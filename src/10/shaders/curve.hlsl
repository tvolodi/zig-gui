// curve.hlsl — DX12 curve/polyline shader stub (M22-01 / RJ3)
//
// RM0 (charts polyline/curve rendering) is deferred. This stub satisfies
// the parity requirement (mode 8 exists in the shader vocabulary) without
// implementing actual curve rendering.
//
// Compile:
//   dxc -T vs_6_0 -E VSMain -Fo curve.vert.dxil curve.hlsl
//   dxc -T ps_6_0 -E PSMain -Fo curve.frag.dxil curve.hlsl

cbuffer PushConstants : register(b0) {
    float4x4 ortho;
    float4   clipRect;
    float4   clipRadii;
    uint     clipEnabled;
    uint3    _pad;
};

struct VSInput {
    float2 pos    : POSITION;
    float2 uv     : TEXCOORD0;
    float4 color  : COLOR0;
    float4 colorB : COLOR1;
    uint   mode   : BLENDINDICES;
};

struct PSInput {
    float4 pos   : SV_POSITION;
    float2 uv    : TEXCOORD0;
    float4 color : COLOR0;
};

PSInput VSMain(VSInput v) {
    PSInput o;
    o.pos   = mul(ortho, float4(v.pos, 0.0f, 1.0f));
    o.uv    = v.uv;
    o.color = v.color;
    return o;
}

// Stub pixel shader — magenta until RM0 is implemented.
float4 PSMain(PSInput p) : SV_TARGET {
    return float4(1.0f, 0.0f, 1.0f, 1.0f);
}
