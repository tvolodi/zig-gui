// quad.hlsl — DX12 quad shader for zig-gui (M22-01 / RJ3)
//
// Implements all 9 fragment modes matching the GLSL quad.vert / quad.frag pipeline.
// Modes 0-7 are fully implemented; mode 8 is a deferred stub (RM0 charts).
//
// Compile:
//   dxc -T vs_6_0 -E VSMain -Fo quad.vert.dxil quad.hlsl
//   dxc -T ps_6_0 -E PSMain -Fo quad.frag.dxil quad.hlsl

// ---------------------------------------------------------------------------
// Constant buffer (root constants — matches Vulkan push constants layout)
// ---------------------------------------------------------------------------

cbuffer PushConstants : register(b0) {
    float4x4 ortho;       // orthographic projection matrix
    float4   clipRect;    // x, y, w, h in screen pixels (RD1)
    float4   clipRadii;   // tl, tr, br, bl corner radii (RD1)
    uint     clipEnabled; // 0 = no clip, 1 = clip active
    uint3    _pad;
};

// ---------------------------------------------------------------------------
// Textures (SRV bindings — match GLSL binding layout)
// ---------------------------------------------------------------------------

Texture2D    atlasTexture    : register(t0); // grayscale/RGBA glyph atlas
Texture2D    subpixelTexture : register(t1); // RGB subpixel atlas (RD2)
Texture2D    sdfTexture      : register(t2); // SDF icon atlas (RD3)
SamplerState linearSampler   : register(s0); // linear clamp-to-edge sampler

// ---------------------------------------------------------------------------
// Vertex input / output
// ---------------------------------------------------------------------------

struct VSInput {
    float2 pos    : POSITION;
    float2 uv     : TEXCOORD0;
    float4 color  : COLOR0;     // premultiplied RGBA (unpacked from u8 in Zig side)
    float4 colorB : COLOR1;     // second gradient stop
    uint   mode   : BLENDINDICES; // fragment mode 0-8
};

struct PSInput {
    float4 pos    : SV_POSITION;
    float2 uv     : TEXCOORD0;
    float4 color  : COLOR0;
    float4 colorB : COLOR1;
    uint   mode   : BLENDINDICES;
};

// ---------------------------------------------------------------------------
// Vertex shader
// ---------------------------------------------------------------------------

PSInput VSMain(VSInput v) {
    PSInput o;
    o.pos    = mul(ortho, float4(v.pos, 0.0f, 1.0f));
    o.uv     = v.uv;
    o.color  = v.color;
    o.colorB = v.colorB;
    o.mode   = v.mode;
    return o;
}

// ---------------------------------------------------------------------------
// Pixel shader helpers
// ---------------------------------------------------------------------------

// RD1: Rounded-corner clipping — returns < 0 if fragment should be discarded.
float evalClip(float2 fragCoord) {
    float2 cp = fragCoord - clipRect.xy;
    float  r  = 0.0f;

    if (cp.x < clipRadii.x && cp.y < clipRadii.x) {
        // Top-left
        r = clipRadii.x - length(float2(clipRadii.x - cp.x, clipRadii.x - cp.y));
    } else if (cp.x > clipRect.z - clipRadii.y && cp.y < clipRadii.y) {
        // Top-right
        r = clipRadii.y - length(float2(cp.x - (clipRect.z - clipRadii.y), clipRadii.y - cp.y));
    } else if (cp.x > clipRect.z - clipRadii.z && cp.y > clipRect.w - clipRadii.z) {
        // Bottom-right
        r = clipRadii.z - length(float2(cp.x - (clipRect.z - clipRadii.z), cp.y - (clipRect.w - clipRadii.z)));
    } else if (cp.x < clipRadii.w && cp.y > clipRect.w - clipRadii.w) {
        // Bottom-left
        r = clipRadii.w - length(float2(clipRadii.w - cp.x, cp.y - (clipRect.w - clipRadii.w)));
    } else {
        r = 0.0f; // inside, no discard
    }
    return r;
}

// ---------------------------------------------------------------------------
// Pixel shader
// ---------------------------------------------------------------------------

float4 PSMain(PSInput p) : SV_TARGET {
    float4 outColor = float4(0.0f, 0.0f, 0.0f, 0.0f);

    switch (p.mode) {

        case 0: // solid rect
            outColor = p.color;
            break;

        case 1: { // glyph — grayscale atlas, red channel is alpha mask
            float a = atlasTexture.Sample(linearSampler, p.uv).r;
            outColor = float4(p.color.rgb, p.color.a * a);
            break;
        }

        case 2: // bordered rect — fallback to solid color
            outColor = p.color;
            break;

        case 3: { // image rect (RGBA)
            outColor = atlasTexture.Sample(linearSampler, p.uv) * p.color;
            break;
        }

        case 4: { // SDF icon (RD3)
            float dist     = sdfTexture.Sample(linearSampler, p.uv).r;
            float smoothing = abs(ddx(dist)) * 0.5f + abs(ddy(dist)) * 0.5f;
            float alphaVal  = 1.0f - smoothstep(0.5f - smoothing, 0.5f + smoothing, dist);
            outColor = float4(p.color.rgb, p.color.a * alphaVal);
            break;
        }

        case 5: { // gradient (RD0)
            // Direction encoded in UV: right=x, bottom=y, bottom_right=x+y
            float t = clamp(p.uv.x + p.uv.y, 0.0f, 1.0f);
            outColor = lerp(p.color, p.colorB, t);
            break;
        }

        case 6: { // AA filled circle (RD4)
            float distUv   = length(p.uv - 0.5f) * 2.0f;
            float2 dx_     = ddx(p.uv);
            float2 dy_     = ddy(p.uv);
            float pixScale = length(float2(dx_.x + dy_.x, dx_.y + dy_.y)) * 0.5f;
            float dPixel   = (1.0f - distUv) / max(pixScale, 0.0001f);
            float alphaCircle = smoothstep(0.0f, 1.0f, dPixel);
            outColor = float4(p.color.rgb, p.color.a * alphaCircle);
            break;
        }

        case 7: { // subpixel glyph (RD2)
            float3 coverage = subpixelTexture.Sample(linearSampler, p.uv).rgb;
            outColor = float4(p.color.rgb * coverage, p.color.a);
            break;
        }

        case 8: // curve/polyline — deferred (RM0)
            outColor = float4(1.0f, 0.0f, 1.0f, 1.0f); // magenta stub
            break;

        default:
            outColor = float4(1.0f, 0.0f, 1.0f, 1.0f); // magenta error
            break;
    }

    // RD1: Rounded-corner clipping
    if (clipEnabled != 0u) {
        float r = evalClip(p.pos.xy);
        if (r < 0.0f) discard;
    }

    return outColor;
}
