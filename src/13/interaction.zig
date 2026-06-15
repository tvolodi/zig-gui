//! Chart interactivity — M26-04
//! Hit-testing via Scale.invert; hover/select signal wiring.
const std = @import("std");
const chart_mod = @import("chart.zig");
const axes_mod = @import("axes.zig");
const types01 = @import("../01/types.zig");
const Vec2 = types01.Vec2;

pub const HitResult = struct {
    series_idx: u32,
    datum_idx: u32,
    value: f64,
    pixel: Vec2,
};

/// Hit-test a mouse position against a chart's data.
/// Returns the nearest datum within `snap_px` pixels, or null if none within range.
pub fn hitTest(
    chart: *const chart_mod.Chart,
    frame: *const axes_mod.ChartFrame,
    mouse: Vec2,
    snap_px: f32,
) ?HitResult {
    const pr = frame.plot_rect;
    // Check if mouse is in the plot rect
    if (mouse.x < pr.x or mouse.x > pr.x + pr.w or
        mouse.y < pr.y or mouse.y > pr.y + pr.h) return null;

    var best_dist: f32 = snap_px;
    var best: ?HitResult = null;

    for (chart.series, 0..) |series, si| {
        if (!series.visible) continue;
        for (series.values, 0..) |v, di| {
            const xi = @as(f64, @floatFromInt(di));
            const px = frame.x.map(xi);
            const py = pr.y + pr.h - (frame.y.map(v) - pr.y);
            const dx = mouse.x - px;
            const dy = mouse.y - py;
            const dist = @sqrt(dx * dx + dy * dy);
            if (dist < best_dist) {
                best_dist = dist;
                best = .{
                    .series_idx = @intCast(si),
                    .datum_idx = @intCast(di),
                    .value = v,
                    .pixel = .{ .x = px, .y = py },
                };
            }
        }
    }
    return best;
}
