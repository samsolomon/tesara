#include <metal_stdlib>
using namespace metal;

// Shared uniforms for both pipelines
struct EditorUniforms {
    float4x4 projectionMatrix;
    float2 viewportSize;
    float2 scrollOffset;
};

// MARK: - Rectangle Pipeline

struct RectInstance {
    float2 position [[attribute(0)]];
    float2 size     [[attribute(1)]];
    uchar4 color    [[attribute(2)]];
};

struct RectVertexOut {
    float4 position [[position]];
    float4 color;
};

vertex RectVertexOut rect_vertex(
    uint vertexID [[vertex_id]],
    uint instanceID [[instance_id]],
    const device RectInstance* instances [[buffer(0)]],
    constant EditorUniforms& uniforms [[buffer(1)]]
) {
    const float2 corners[] = {
        float2(0, 0), float2(1, 0), float2(0, 1),
        float2(1, 0), float2(1, 1), float2(0, 1)
    };

    RectInstance inst = instances[instanceID];
    float2 corner = corners[vertexID];
    float2 worldPos = inst.position + corner * inst.size - uniforms.scrollOffset;

    RectVertexOut out;
    out.position = uniforms.projectionMatrix * float4(worldPos, 0.0, 1.0);
    out.color = float4(inst.color) / 255.0;
    return out;
}

fragment float4 rect_fragment(RectVertexOut in [[stage_in]]) {
    return in.color;
}

// MARK: - Glyph Pipeline

struct GlyphInstance {
    ushort2 atlasPos  [[attribute(0)]];
    ushort2 atlasSize [[attribute(1)]];
    float2  screenPos [[attribute(2)]];
    short2  bearings  [[attribute(3)]];
    uchar4  color     [[attribute(4)]];
};

struct GlyphVertexOut {
    float4 position [[position]];
    float2 texCoord;
    float4 color;
};

vertex GlyphVertexOut glyph_vertex(
    uint vertexID [[vertex_id]],
    uint instanceID [[instance_id]],
    const device GlyphInstance* instances [[buffer(0)]],
    constant EditorUniforms& uniforms [[buffer(1)]],
    constant float2& atlasSize [[buffer(2)]]
) {
    const float2 corners[] = {
        float2(0, 0), float2(1, 0), float2(0, 1),
        float2(1, 0), float2(1, 1), float2(0, 1)
    };

    GlyphInstance inst = instances[instanceID];
    float2 corner = corners[vertexID];

    float2 glyphSize = float2(inst.atlasSize);
    float2 worldPos = inst.screenPos + float2(inst.bearings.x, -inst.bearings.y) + corner * glyphSize - uniforms.scrollOffset;

    float2 texOrigin = float2(inst.atlasPos) / atlasSize;
    float2 texSize = glyphSize / atlasSize;

    GlyphVertexOut out;
    out.position = uniforms.projectionMatrix * float4(worldPos, 0.0, 1.0);
    out.texCoord = texOrigin + corner * texSize;
    out.color = float4(inst.color) / 255.0;
    return out;
}

fragment float4 glyph_fragment(
    GlyphVertexOut in [[stage_in]],
    texture2d<float> atlas [[texture(0)]]
) {
    constexpr sampler linearSampler(mag_filter::linear, min_filter::linear);
    float alpha = atlas.sample(linearSampler, in.texCoord).r;
    return float4(in.color.rgb, in.color.a * alpha);
}

// MARK: - Color Glyph Pipeline (for emoji)

fragment float4 color_glyph_fragment(
    GlyphVertexOut in [[stage_in]],
    texture2d<float> colorAtlas [[texture(0)]]
) {
    constexpr sampler linearSampler(mag_filter::linear, min_filter::linear);
    return colorAtlas.sample(linearSampler, in.texCoord);
}
