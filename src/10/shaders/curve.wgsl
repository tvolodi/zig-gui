// curve.wgsl — Curve/chart primitive shader for WebGPU (M23-01 / RJ4)
//
// Mode 8 parity stub — deferred to M26 (RM0 charts).
// Returns magenta to distinguish from the quad shader's mode 8 stub path.

@fragment
fn fs_main_curve(@builtin(position) pos: vec4<f32>) -> @location(0) vec4<f32> {
    _ = pos;
    return vec4<f32>(1.0, 0.0, 1.0, 1.0); // magenta stub
}
