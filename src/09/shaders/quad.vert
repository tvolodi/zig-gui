#version 450

layout(location = 0) in vec2 inPos;
layout(location = 1) in vec2 inUV;
layout(location = 2) in vec4 inColor;
layout(location = 3) in vec4 inColorB;
layout(location = 4) in uint inMode;

layout(push_constant) uniform PushConstants {
    mat4 ortho;        // offset 0,  size 64 (vertex)
    vec4 clipRect;     // offset 64, size 16 (fragment, RD1)
    vec4 clipRadii;    // offset 80, size 16 (fragment, RD1)
    uint clipEnabled;  // offset 96, size 4  (fragment, RD1)
} pc;

layout(location = 0) out vec2 fragUV;
layout(location = 1) out vec4 fragColor;
layout(location = 2) out vec4 fragColorB;
layout(location = 3) flat out uint fragMode;

void main() {
    gl_Position = pc.ortho * vec4(inPos, 0.0, 1.0);
    fragUV = inUV;
    fragColor = inColor;
    fragColorB = inColorB;
    fragMode = inMode;
}
