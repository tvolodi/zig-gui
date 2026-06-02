#version 450

layout(location = 0) in vec2 inPos;
layout(location = 1) in vec2 inUV;
layout(location = 2) in vec4 inColor;
layout(location = 3) in uint inMode;

layout(push_constant) uniform PushConstants {
    mat4 ortho;
} pc;

layout(location = 0) out vec2 fragUV;
layout(location = 1) out vec4 fragColor;
layout(location = 2) flat out uint fragMode;

void main() {
    gl_Position = pc.ortho * vec4(inPos, 0.0, 1.0);
    fragUV = inUV;
    fragColor = inColor;
    fragMode = inMode;
}
