#version 450

layout(location = 0) in vec2 fragUV;
layout(location = 1) in vec4 fragColor;
layout(location = 2) flat in uint fragMode;

layout(binding = 0) uniform sampler2D atlasTexture;

layout(location = 0) out vec4 outColor;

void main() {
    if (fragMode == 1u) {
        // Glyph: red channel is alpha mask (stb_truetype single-channel atlas).
        float alpha = texture(atlasTexture, fragUV).r;
        outColor = vec4(fragColor.rgb, fragColor.a * alpha);
    } else {
        outColor = fragColor;
    }
}
