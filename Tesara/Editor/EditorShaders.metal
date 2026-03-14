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
    float2 position     [[attribute(0)]];
    float2 size         [[attribute(1)]];
    uchar4 color        [[attribute(2)]];
    float  cornerRadius [[attribute(3)]];
    float  glowRadius   [[attribute(4)]];
    float  glowOpacity  [[attribute(5)]];
};

struct RectVertexOut {
    float4 position [[position]];
    float4 color;
    float2 localPos;
    float2 rectSize;
    float2 innerSize;
    float  cornerRadius;
    float  glowRadius;
    float  glowOpacity;
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

    // When glow is enabled, expand the quad outward to make room for the halo
    float2 pad = float2(inst.glowRadius);
    float2 expandedSize = inst.size + pad * 2.0;
    float2 origin = inst.position - pad;
    float2 worldPos = origin + corner * expandedSize - uniforms.scrollOffset;

    RectVertexOut out;
    out.position = uniforms.projectionMatrix * float4(worldPos, 0.0, 1.0);
    out.color = float4(inst.color) / 255.0;
    out.localPos = corner * expandedSize;
    out.rectSize = expandedSize;
    out.innerSize = inst.size;
    out.cornerRadius = inst.cornerRadius;
    out.glowRadius = inst.glowRadius;
    out.glowOpacity = inst.glowOpacity;
    return out;
}

fragment float4 rect_fragment(RectVertexOut in [[stage_in]]) {
    // Fast path: no corner radius and no glow — plain rect
    if (in.cornerRadius <= 0.0 && in.glowRadius <= 0.0) {
        return in.color;
    }

    // Compute SDF to the inner rect (centered within the possibly-expanded quad)
    float2 innerHalf = in.innerSize * 0.5;
    float2 center = in.rectSize * 0.5;
    float r = min(in.cornerRadius, min(innerHalf.x, innerHalf.y));
    float2 p = abs(in.localPos - center) - (innerHalf - r);
    float dist = length(max(p, 0.0)) - r;

    // Solid interior with anti-aliased edge
    float solidAlpha = 1.0 - smoothstep(-0.5, 0.5, dist);

    // Glow exterior: exponential falloff from cursor edge
    float glowAlpha = 0.0;
    if (in.glowRadius > 0.0 && dist > 0.0) {
        glowAlpha = in.glowOpacity * exp(-dist * 2.5 / in.glowRadius);
    }

    float finalAlpha = max(solidAlpha, glowAlpha);
    return float4(in.color.rgb, in.color.a * finalAlpha);
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
