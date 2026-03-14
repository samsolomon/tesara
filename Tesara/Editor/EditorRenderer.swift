import Metal
import QuartzCore
import simd

/// GPU renderer for the editor: draws colored rectangles, text glyphs, and color emoji via instanced quads.
final class EditorRenderer {

    // MARK: - Instance Types (matched to Metal structs)

    struct GlyphInstance {
        var atlasPos: SIMD2<UInt16>
        var atlasSize: SIMD2<UInt16>
        var screenPos: SIMD2<Float>
        var bearings: SIMD2<Int16>
        var color: SIMD4<UInt8>
    }

    struct RectInstance {
        var position: SIMD2<Float>
        var size: SIMD2<Float>
        var color: SIMD4<UInt8>
        var cornerRadius: Float = 0
        var glowRadius: Float = 0
        var glowOpacity: Float = 0
    }

    private struct Uniforms {
        var projectionMatrix: simd_float4x4
        var viewportSize: SIMD2<Float>
        var scrollOffset: SIMD2<Float>
    }

    // MARK: - Metal State

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let rectPipeline: MTLRenderPipelineState
    private let glyphPipeline: MTLRenderPipelineState
    private let colorGlyphPipeline: MTLRenderPipelineState

    // Double-buffered
    private let maxInstances = 65536
    private var rectBuffers: [MTLBuffer]
    private var glyphBuffers: [MTLBuffer]
    private var colorGlyphBuffers: [MTLBuffer]
    private var uniformBuffers: [MTLBuffer]
    private var overlayRectBuffers: [MTLBuffer]
    private var bufferIndex = 0
    private let frameSemaphore = DispatchSemaphore(value: 2)

    // Atlas textures
    private var atlasTexture: MTLTexture?
    private var lastAtlasModified: UInt64 = 0
    private var lastAtlasSize: Int = 0

    private var colorAtlasTexture: MTLTexture?
    private var lastColorAtlasModified: UInt64 = 0
    private var lastColorAtlasSize: Int = 0

    init?(device: MTLDevice) {
        self.device = device

        guard let queue = device.makeCommandQueue() else { return nil }
        self.commandQueue = queue

        guard let library = device.makeDefaultLibrary() else { return nil }

        // Build rect pipeline
        guard let rectVertexFn = library.makeFunction(name: "rect_vertex"),
              let rectFragmentFn = library.makeFunction(name: "rect_fragment") else { return nil }

        let rectDesc = MTLRenderPipelineDescriptor()
        rectDesc.vertexFunction = rectVertexFn
        rectDesc.fragmentFunction = rectFragmentFn
        rectDesc.colorAttachments[0].pixelFormat = .bgra8Unorm
        rectDesc.colorAttachments[0].isBlendingEnabled = true
        rectDesc.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        rectDesc.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        rectDesc.colorAttachments[0].sourceAlphaBlendFactor = .one
        rectDesc.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha

        // Build glyph pipeline
        guard let glyphVertexFn = library.makeFunction(name: "glyph_vertex"),
              let glyphFragmentFn = library.makeFunction(name: "glyph_fragment") else { return nil }

        let glyphDesc = MTLRenderPipelineDescriptor()
        glyphDesc.vertexFunction = glyphVertexFn
        glyphDesc.fragmentFunction = glyphFragmentFn
        glyphDesc.colorAttachments[0].pixelFormat = .bgra8Unorm
        glyphDesc.colorAttachments[0].isBlendingEnabled = true
        glyphDesc.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        glyphDesc.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        glyphDesc.colorAttachments[0].sourceAlphaBlendFactor = .one
        glyphDesc.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha

        // Build color glyph pipeline (for emoji)
        guard let colorGlyphFragmentFn = library.makeFunction(name: "color_glyph_fragment") else { return nil }

        let colorGlyphDesc = MTLRenderPipelineDescriptor()
        colorGlyphDesc.vertexFunction = glyphVertexFn  // reuse glyph vertex shader
        colorGlyphDesc.fragmentFunction = colorGlyphFragmentFn
        colorGlyphDesc.colorAttachments[0].pixelFormat = .bgra8Unorm
        colorGlyphDesc.colorAttachments[0].isBlendingEnabled = true
        colorGlyphDesc.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        colorGlyphDesc.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        colorGlyphDesc.colorAttachments[0].sourceAlphaBlendFactor = .one
        colorGlyphDesc.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha

        do {
            self.rectPipeline = try device.makeRenderPipelineState(descriptor: rectDesc)
            self.glyphPipeline = try device.makeRenderPipelineState(descriptor: glyphDesc)
            self.colorGlyphPipeline = try device.makeRenderPipelineState(descriptor: colorGlyphDesc)
        } catch {
            return nil
        }

        // Allocate double-buffered vertex/uniform buffers
        let rectStride = MemoryLayout<RectInstance>.stride
        let glyphStride = MemoryLayout<GlyphInstance>.stride
        let uniformSize = MemoryLayout<Uniforms>.stride
        let maxInst = 65536

        guard let rb0 = device.makeBuffer(length: rectStride * maxInst, options: .storageModeShared),
              let rb1 = device.makeBuffer(length: rectStride * maxInst, options: .storageModeShared),
              let gb0 = device.makeBuffer(length: glyphStride * maxInst, options: .storageModeShared),
              let gb1 = device.makeBuffer(length: glyphStride * maxInst, options: .storageModeShared),
              let cgb0 = device.makeBuffer(length: glyphStride * maxInst, options: .storageModeShared),
              let cgb1 = device.makeBuffer(length: glyphStride * maxInst, options: .storageModeShared),
              let ub0 = device.makeBuffer(length: uniformSize * 2, options: .storageModeShared),
              let ub1 = device.makeBuffer(length: uniformSize * 2, options: .storageModeShared),
              let orb0 = device.makeBuffer(length: rectStride * 16, options: .storageModeShared),
              let orb1 = device.makeBuffer(length: rectStride * 16, options: .storageModeShared) else { return nil }

        self.rectBuffers = [rb0, rb1]
        self.glyphBuffers = [gb0, gb1]
        self.colorGlyphBuffers = [cgb0, cgb1]
        self.uniformBuffers = [ub0, ub1]
        self.overlayRectBuffers = [orb0, orb1]
    }

    // MARK: - Render

    func render(
        to drawable: CAMetalDrawable,
        viewport: CGSize,
        scale: CGFloat,
        scrollOffset: CGPoint,
        rects: [RectInstance],
        glyphs: [GlyphInstance],
        colorGlyphs: [GlyphInstance],
        backgroundColor: SIMD4<Float>,
        atlas: GlyphAtlas,
        colorAtlas: GlyphAtlas,
        overlayRects: [RectInstance]
    ) {
        frameSemaphore.wait()

        let idx = bufferIndex
        bufferIndex = (bufferIndex + 1) % 2

        // Update uniforms
        let scaledWidth = Float(viewport.width * scale)
        let scaledHeight = Float(viewport.height * scale)
        var uniforms = Uniforms(
            projectionMatrix: orthographicProjection(width: scaledWidth, height: scaledHeight),
            viewportSize: SIMD2<Float>(scaledWidth, scaledHeight),
            scrollOffset: SIMD2<Float>(Float(scrollOffset.x * scale), Float(scrollOffset.y * scale))
        )
        memcpy(uniformBuffers[idx].contents(), &uniforms, MemoryLayout<Uniforms>.stride)

        // Overlay uniforms (zero scroll) at offset
        var overlayUniforms = Uniforms(
            projectionMatrix: orthographicProjection(width: scaledWidth, height: scaledHeight),
            viewportSize: SIMD2<Float>(scaledWidth, scaledHeight),
            scrollOffset: SIMD2<Float>(0, 0)
        )
        memcpy(uniformBuffers[idx].contents().advanced(by: MemoryLayout<Uniforms>.stride), &overlayUniforms, MemoryLayout<Uniforms>.stride)

        // Copy rect instances
        let rectCount = min(rects.count, maxInstances)
        if rectCount > 0 {
            _ = rects.withUnsafeBufferPointer { ptr in
                memcpy(rectBuffers[idx].contents(), ptr.baseAddress!, rectCount * MemoryLayout<RectInstance>.stride)
            }
        }

        // Copy glyph instances
        let glyphCount = min(glyphs.count, maxInstances)
        if glyphCount > 0 {
            _ = glyphs.withUnsafeBufferPointer { ptr in
                memcpy(glyphBuffers[idx].contents(), ptr.baseAddress!, glyphCount * MemoryLayout<GlyphInstance>.stride)
            }
        }

        // Copy color glyph instances
        let colorGlyphCount = min(colorGlyphs.count, maxInstances)
        if colorGlyphCount > 0 {
            _ = colorGlyphs.withUnsafeBufferPointer { ptr in
                memcpy(colorGlyphBuffers[idx].contents(), ptr.baseAddress!, colorGlyphCount * MemoryLayout<GlyphInstance>.stride)
            }
        }

        // Copy overlay rect instances
        let overlayCount = min(overlayRects.count, 16)
        if overlayCount > 0 {
            _ = overlayRects.withUnsafeBufferPointer { ptr in
                memcpy(overlayRectBuffers[idx].contents(), ptr.baseAddress!, overlayCount * MemoryLayout<RectInstance>.stride)
            }
        }

        // Update atlas textures if changed
        updateAtlasTexture(atlas: atlas)
        updateColorAtlasTexture(atlas: colorAtlas)

        // Build command buffer
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            frameSemaphore.signal()
            return
        }

        let passDesc = MTLRenderPassDescriptor()
        passDesc.colorAttachments[0].texture = drawable.texture
        passDesc.colorAttachments[0].loadAction = .clear
        passDesc.colorAttachments[0].storeAction = .store
        passDesc.colorAttachments[0].clearColor = MTLClearColor(
            red: Double(backgroundColor.x),
            green: Double(backgroundColor.y),
            blue: Double(backgroundColor.z),
            alpha: Double(backgroundColor.w)
        )

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDesc) else {
            frameSemaphore.signal()
            return
        }

        // Draw rects (selection, cursor)
        if rectCount > 0 {
            encoder.setRenderPipelineState(rectPipeline)
            encoder.setVertexBuffer(rectBuffers[idx], offset: 0, index: 0)
            encoder.setVertexBuffer(uniformBuffers[idx], offset: 0, index: 1)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: rectCount)
        }

        // Draw monochrome glyphs
        if glyphCount > 0, let atlasTexture {
            encoder.setRenderPipelineState(glyphPipeline)
            encoder.setVertexBuffer(glyphBuffers[idx], offset: 0, index: 0)
            encoder.setVertexBuffer(uniformBuffers[idx], offset: 0, index: 1)

            var atlasSizeVec = SIMD2<Float>(Float(atlas.size), Float(atlas.size))
            encoder.setVertexBytes(&atlasSizeVec, length: MemoryLayout<SIMD2<Float>>.stride, index: 2)

            encoder.setFragmentTexture(atlasTexture, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: glyphCount)
        }

        // Draw color glyphs (emoji)
        if colorGlyphCount > 0, let colorAtlasTexture {
            encoder.setRenderPipelineState(colorGlyphPipeline)
            encoder.setVertexBuffer(colorGlyphBuffers[idx], offset: 0, index: 0)
            encoder.setVertexBuffer(uniformBuffers[idx], offset: 0, index: 1)

            var colorAtlasSizeVec = SIMD2<Float>(Float(colorAtlas.size), Float(colorAtlas.size))
            encoder.setVertexBytes(&colorAtlasSizeVec, length: MemoryLayout<SIMD2<Float>>.stride, index: 2)

            encoder.setFragmentTexture(colorAtlasTexture, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: colorGlyphCount)
        }

        // Draw overlay rects (scrollbar) — with zero scroll offset
        if overlayCount > 0 {
            encoder.setRenderPipelineState(rectPipeline)
            encoder.setVertexBuffer(overlayRectBuffers[idx], offset: 0, index: 0)
            encoder.setVertexBuffer(uniformBuffers[idx], offset: MemoryLayout<Uniforms>.stride, index: 1)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: overlayCount)
        }

        encoder.endEncoding()

        commandBuffer.addCompletedHandler { [weak self] _ in
            self?.frameSemaphore.signal()
        }

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    // MARK: - Atlas Texture

    private func updateAtlasTexture(atlas: GlyphAtlas) {
        let needsRecreate = atlasTexture == nil || atlas.size != lastAtlasSize
        let needsUpdate = atlas.modifiedCount != lastAtlasModified

        if needsRecreate {
            let desc = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .r8Unorm,
                width: atlas.size,
                height: atlas.size,
                mipmapped: false
            )
            desc.usage = [.shaderRead]
            atlasTexture = device.makeTexture(descriptor: desc)
            lastAtlasSize = atlas.size
        }

        if needsRecreate || needsUpdate, let atlasTexture {
            atlas.textureData.withUnsafeBufferPointer { ptr in
                atlasTexture.replace(
                    region: MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0),
                                     size: MTLSize(width: atlas.size, height: atlas.size, depth: 1)),
                    mipmapLevel: 0,
                    withBytes: ptr.baseAddress!,
                    bytesPerRow: atlas.size
                )
            }
            lastAtlasModified = atlas.modifiedCount
        }
    }

    private func updateColorAtlasTexture(atlas: GlyphAtlas) {
        let needsRecreate = colorAtlasTexture == nil || atlas.size != lastColorAtlasSize
        let needsUpdate = atlas.modifiedCount != lastColorAtlasModified

        if needsRecreate {
            let desc = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .rgba8Unorm,
                width: atlas.size,
                height: atlas.size,
                mipmapped: false
            )
            desc.usage = [.shaderRead]
            colorAtlasTexture = device.makeTexture(descriptor: desc)
            lastColorAtlasSize = atlas.size
        }

        if needsRecreate || needsUpdate, let colorAtlasTexture {
            atlas.textureData.withUnsafeBufferPointer { ptr in
                colorAtlasTexture.replace(
                    region: MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0),
                                     size: MTLSize(width: atlas.size, height: atlas.size, depth: 1)),
                    mipmapLevel: 0,
                    withBytes: ptr.baseAddress!,
                    bytesPerRow: atlas.size * 4
                )
            }
            lastColorAtlasModified = atlas.modifiedCount
        }
    }

    // MARK: - Projection

    private func orthographicProjection(width: Float, height: Float) -> simd_float4x4 {
        // Maps (0,0)-(width,height) to clip space, with Y flipped (top-left origin)
        return simd_float4x4(columns: (
            SIMD4<Float>(2.0 / width, 0, 0, 0),
            SIMD4<Float>(0, -2.0 / height, 0, 0),
            SIMD4<Float>(0, 0, 1, 0),
            SIMD4<Float>(-1, 1, 0, 1)
        ))
    }
}
