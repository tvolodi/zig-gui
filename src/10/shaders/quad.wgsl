// quad.wgsl — WebGPU quad shader for zig-gui (M23-01 / RJ4)
//
// Implements all 9 fragment modes matching the GLSL / HLSL quad shader pipeline.
// Mode mapping:
//   0: filled_rect / solid rect
//   1: glyph — grayscale atlas, red channel is alpha mask
//   2: border_rect — bordered rect (solid color fallback)
//   3: image_rect — RGBA from atlas
//   4: sdf_icon — SDF icon (RD3)
//   5: gradient_rect (RD0)
//   6: aa_filled_circle (RD4)
//   7: subpixel_glyph — fallback to regular glyph (no subpixel on WebGPU portably)
//   8: curve/polyline stub (RM0, deferred)
//
// Compile: embedded via @embedFile("shaders/quad.wgsl") in webgpu_backend.zig

// ---------------------------------------------------------------------------
// Bind group 0: atlas texture + sampler
// ---------------------------------------------------------------------------

@group(0) @binding(0) var atlas_texture: texture_2d<f32>;
@group(0) @binding(1) var atlas_sampler: sampler;

// ---------------------------------------------------------------------------
// Vertex input / output
// ---------------------------------------------------------------------------

struct VertexInput {
    @location(0) position: vec2<f32>,
    @location(1) uv: vec2<f32>,
    @location(2) color: u32,      // packed RGBA (big-endian: R<<24 | G<<16 | B<<8 | A)
    @location(3) color_b: u32,    // second gradient stop (same packing)
    @location(4) mode: u32,       // fragment mode 0-8
};

struct VertexOutput {
    @builtin(position) clip_position: vec4<f32>,
    @location(0) uv: vec2<f32>,
    @location(1) color: vec4<f32>,
    @location(2) color_b: vec4<f32>,
    @location(3) @interpolate(flat) mode: u32,
};

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn unpack_color(packed: u32) -> vec4<f32> {
    let r = f32((packed >> 24u) & 0xFFu) / 255.0;
    let g = f32((packed >> 16u) & 0xFFu) / 255.0;
    let b = f32((packed >>  8u) & 0xFFu) / 255.0;
    let a = f32( packed        & 0xFFu) / 255.0;
    return vec4<f32>(r, g, b, a);
}

// ---------------------------------------------------------------------------
// Vertex shader
// ---------------------------------------------------------------------------

@vertex
fn vs_main(in: VertexInput) -> VertexOutput {
    var out: VertexOutput;
    // Positions are already in NDC (the Zig side applies ortho projection before
    // writing vertices into the vertex buffer).
    out.clip_position = vec4<f32>(in.position, 0.0, 1.0);
    out.uv     = in.uv;
    out.color  = unpack_color(in.color);
    out.color_b = unpack_color(in.color_b);
    out.mode   = in.mode;
    return out;
}

// ---------------------------------------------------------------------------
// Fragment shader
// ---------------------------------------------------------------------------

@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4<f32> {
    switch in.mode {

        // ---- case 0u: filled_rect / solid rect --------------------------------
        case 0u: {
            return in.color;
        }

        // ---- case 1u: glyph — grayscale atlas, red channel is alpha mask ------
        case 1u: {
            let alpha = textureSample(atlas_texture, atlas_sampler, in.uv).r;
            return vec4<f32>(in.color.rgb, in.color.a * alpha);
        }

        // ---- case 2u: border_rect — solid color (border geometry from Zig) ----
        case 2u: {
            return in.color;
        }

        // ---- case 3u: image_rect — RGBA from atlas ----------------------------
        case 3u: {
            let tex_color = textureSample(atlas_texture, atlas_sampler, in.uv);
            return tex_color * in.color;
        }

        // ---- case 4u: sdf_icon — SDF icon (RD3) -------------------------------
        case 4u: {
            let dist = textureSample(atlas_texture, atlas_sampler, in.uv).r;
            // smoothstep-based SDF rendering with derivative-based smoothing
            let dx = dpdx(in.uv);
            let dy = dpdy(in.uv);
            let smoothing = (abs(dx.x) + abs(dx.y) + abs(dy.x) + abs(dy.y)) * 0.25;
            let alpha = smoothstep(0.5 - smoothing, 0.5 + smoothing, dist) * in.color.a;
            return vec4<f32>(in.color.rgb, alpha);
        }

        // ---- case 5u: gradient_rect (RD0) -------------------------------------
        case 5u: {
            // Direction encoded in UV: right=x, bottom=y, bottom_right=x+y
            let t = clamp(in.uv.x + in.uv.y, 0.0, 1.0);
            return mix(in.color, in.color_b, t);
        }

        // ---- case 6u: aa_filled_circle (RD4) ----------------------------------
        case 6u: {
            let dist_uv   = length(in.uv - vec2<f32>(0.5, 0.5)) * 2.0;
            let dx = dpdx(in.uv);
            let dy = dpdy(in.uv);
            let pix_scale = (abs(dx.x) + abs(dx.y) + abs(dy.x) + abs(dy.y)) * 0.5;
            let d_pixel   = (1.0 - dist_uv) / max(pix_scale, 0.0001);
            let alpha_circle = clamp(d_pixel, 0.0, 1.0) * in.color.a;
            return vec4<f32>(in.color.rgb, alpha_circle);
        }

        // ---- case 7u: subpixel_glyph — fallback to grayscale glyph -----------
        // WebGPU does not support subpixel blending portably; fall back to mode 1.
        case 7u: {
            let alpha = textureSample(atlas_texture, atlas_sampler, in.uv).r;
            return vec4<f32>(in.color.rgb, in.color.a * alpha);
        }

        // ---- case 8u: curve/polyline stub (RM0, deferred) --------------------
        case 8u: {
            return vec4<f32>(1.0, 0.0, 1.0, 1.0); // magenta stub
        }

        // ---- default ----------------------------------------------------------
        default: {
            return vec4<f32>(1.0, 0.0, 1.0, 1.0); // magenta error
        }
    }
}
