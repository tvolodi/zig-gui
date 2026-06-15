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

/// RN7 — Per-chart crosshair state. `x` is the pixel x of the snapped vertical
/// guide, or null when the crosshair is hidden (mouse outside plot or no datum found).
pub const CrosshairState = struct {
    x: ?f32 = null,
};

/// RN7 — Update `state.x` from a mouse position.
/// Snaps to the nearest datum's pixel x within `snap_px` distance.
/// Pass `mouse = null` (mouse-out event) to hide the crosshair.
pub fn updateCrosshairX(
    chart: *const chart_mod.Chart,
    frame: *const axes_mod.ChartFrame,
    mouse: ?Vec2,
    snap_px: f32,
    state: *CrosshairState,
) void {
    const m = mouse orelse {
        state.x = null;
        return;
    };
    const hit = hitTest(chart, frame, m, snap_px);
    state.x = if (hit) |h| h.pixel.x else null;
}

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
