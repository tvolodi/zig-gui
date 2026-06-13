#version 450

layout(location = 0) in vec2 fragUV;
layout(location = 1) in vec4 fragColor;
layout(location = 2) in vec4 fragColorB;
layout(location = 3) flat in uint fragMode;

layout(binding = 0) uniform sampler2D atlasTexture;
layout(binding = 1) uniform sampler2D subpixelTexture;
layout(binding = 2) uniform sampler2D sdfTexture;

layout(push_constant) uniform PushConstants {
    mat4 ortho;        // offset 0,  size 64 (vertex)
    vec4 clipRect;     // offset 64, size 16 — x, y, w, h in screen pixels (RD1)
    vec4 clipRadii;    // offset 80, size 16 — tl, tr, br, bl corner radii (RD1)
    uint clipEnabled;  // offset 96, size 4  — 0 = no clip, 1 = clip active (RD1)
} pc;

layout(location = 0) out vec4 outColor;

void main() {
    // RD1: Rounded-corner clipping — discard fragments outside the rounded rect boundary.
    if (pc.clipEnabled != 0u) {
        vec2 cp = gl_FragCoord.xy - pc.clipRect.xy;
        float r = 0.0;
        if (cp.x < pc.clipRadii.x && cp.y < pc.clipRadii.x) {
            // Top-left corner: distance from (radius, radius)
            r = pc.clipRadii.x - length(vec2(pc.clipRadii.x - cp.x, pc.clipRadii.x - cp.y));
        } else if (cp.x > pc.clipRect.z - pc.clipRadii.y && cp.y < pc.clipRadii.y) {
            // Top-right corner
            r = pc.clipRadii.y - length(vec2(cp.x - (pc.clipRect.z - pc.clipRadii.y), pc.clipRadii.y - cp.y));
        } else if (cp.x > pc.clipRect.z - pc.clipRadii.z && cp.y > pc.clipRect.w - pc.clipRadii.z) {
            // Bottom-right corner
            r = pc.clipRadii.z - length(vec2(cp.x - (pc.clipRect.z - pc.clipRadii.z), cp.y - (pc.clipRect.w - pc.clipRadii.z)));
        } else if (cp.x < pc.clipRadii.w && cp.y > pc.clipRect.w - pc.clipRadii.w) {
            // Bottom-left corner
            r = pc.clipRadii.w - length(vec2(pc.clipRadii.w - cp.x, cp.y - (pc.clipRect.w - pc.clipRadii.w)));
        } else {
            // Not in any corner zone — inside the rect by default, don't discard.
            r = 0.0; // won't trigger discard below
        }
        if (r < 0.0) discard;
    }

    if (fragMode == 1u) {
        // Glyph: red channel is alpha mask (stb_truetype single-channel atlas).
        float alpha = texture(atlasTexture, fragUV).r;
        outColor = vec4(fragColor.rgb, fragColor.a * alpha);
    } else if (fragMode == 2u) {
        // M13-01 RD0 — Gradient: linear interpolation between fragColor and fragColorB.
        // Direction is encoded in the UV: one axis varies 0..1, the unused axis is ~0.
        //   right:        t = fragUV.x (fragUV.y ≈ 0)
        //   bottom:       t = fragUV.y (fragUV.x ≈ 0)
        //   bottom_right: t = fragUV.x + fragUV.y (both vary 0..1)
        float t = clamp(fragUV.x + fragUV.y, 0.0, 1.0);
        outColor = mix(fragColor, fragColorB, t);
    } else if (fragMode == 5u) {
        // M13-05 RD4 — AA filled rect: 1-pixel smooth feather at edges.
        // fragUV.x = 0..1 across rect width, fragUV.y = 0..1 across height.
        // Screen-space derivatives convert UV-space distance to pixel distance.
        vec2 dx = dFdx(fragUV);
        vec2 dy = dFdy(fragUV);
        float d_left   = fragUV.x / length(vec2(dx.x, dy.x));
        float d_right  = (1.0 - fragUV.x) / length(vec2(dx.x, dy.x));
        float d_top    = fragUV.y / length(vec2(dx.y, dy.y));
        float d_bottom = (1.0 - fragUV.y) / length(vec2(dx.y, dy.y));
        float d = min(min(d_left, d_right), min(d_top, d_bottom));
        float alpha_val = smoothstep(0.0, 1.0, d);
        outColor = vec4(fragColor.rgb, fragColor.a * alpha_val);
    } else if (fragMode == 6u) {
        // M13-05 RD4 — AA filled circle: 1-pixel smooth feather at edge.
        // The quad bounds exactly enclose the circle. fragUV=(0.5,0.5) is center.
        // dist_uv: 0 at center, 1.0 at the circle edge.
        float dist_uv = length(fragUV - 0.5) * 2.0;
        // Convert UV-space distance to pixel distance using screen-space derivatives.
        vec2 dx = dFdx(fragUV);
        vec2 dy = dFdy(fragUV);
        float pixel_scale = length(vec2(dx.x + dy.x, dx.y + dy.y)) * 0.5;
        float d_pixel = (1.0 - dist_uv) / pixel_scale;
        float alpha_val = smoothstep(0.0, 1.0, d_pixel);
        outColor = vec4(fragColor.rgb, fragColor.a * alpha_val);
    } else if (fragMode == 3u) {
        // M13-03 RD2 — Subpixel glyph: RGB channels encode subpixel coverage.
        vec3 coverage = texture(subpixelTexture, fragUV).rgb;
        outColor = vec4(fragColor.rgb * coverage, fragColor.a);
    } else if (fragMode == 4u) {
        // M13-04 RD3 — SDF icon: signed distance field in red channel.
        // 0.0 = inside, 0.5 = edge, 1.0 = outside.
        float dist = texture(sdfTexture, fragUV).r;
        float smoothing = fwidth(dist) * 0.5;
        float alpha_val = 1.0 - smoothstep(0.5 - smoothing, 0.5 + smoothing, dist);
        outColor = vec4(fragColor.rgb, fragColor.a * alpha_val);
    } else {
        outColor = fragColor;
    }
}
