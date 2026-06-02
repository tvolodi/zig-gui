#version 450

// Hardcoded triangle (spike-only proof of shader path — INV-2.3 deferred).
const vec2 kPositions[3] = vec2[](
    vec2( 0.0, -0.5),
    vec2( 0.5,  0.5),
    vec2(-0.5,  0.5)
);

const vec3 kColors[3] = vec3[](
    vec3(1.0, 0.0, 0.0),
    vec3(0.0, 1.0, 0.0),
    vec3(0.0, 0.0, 1.0)
);

layout(location = 0) out vec3 fragColor;

void main() {
    gl_Position = vec4(kPositions[gl_VertexIndex], 0.0, 1.0);
    fragColor   = kColors[gl_VertexIndex];
}
