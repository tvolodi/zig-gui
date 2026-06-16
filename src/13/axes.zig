//! Chart axes and frame — M26-02
const std = @import("std");
const scale_mod = @import("scale.zig");
const Scale = scale_mod.Scale;
const types01 = @import("../01/types.zig");

pub const Rect09 = types01.Rect09;
pub const Vec2 = types01.Vec2;
pub const Color09 = types01.Color09;

pub const ChartFrame = struct {
    plot_rect: Rect09,    // inner drawing area (frame minus axis gutters)
    outer_rect: Rect09,   // full widget rect
    x: Scale,
    y: Scale,
};

pub const AxisOptions = struct {
    show_x: bool = true,
    show_y: bool = true,
    show_grid: bool = true,
    x_tick_count: u32 = 5,
    y_tick_count: u32 = 5,
    axis_color: Color09 = .{ .r = 150, .g = 150, .b = 150, .a = 255 },
    grid_color: Color09 = .{ .r = 220, .g = 220, .b = 220, .a = 180 },
    label_color: Color09 = .{ .r = 80, .g = 80, .b = 80, .a = 255 },
    tick_len: f32 = 4.0,
    gutter_left: f32 = 40.0,
    gutter_bottom: f32 = 24.0,
};

/// Compute a ChartFrame from a widget rect and scales, applying axis gutters.
pub fn makeFrame(outer: Rect09, x: Scale, y: Scale, opts: AxisOptions) ChartFrame {
    return .{
        .outer_rect = outer,
        .plot_rect = .{
            .x = outer.x + opts.gutter_left,
            .y = outer.y,
            .w = outer.w - opts.gutter_left,
            .h = outer.h - opts.gutter_bottom,
        },
        .x = x,
        .y = y,
    };
}

pub const DrawCmd = types01.DrawCommand;

/// Emit axis lines, ticks, gridlines, and labels into a draw list.
/// Uses polyline commands for axis lines and gridlines.
pub fn drawAxes(
    frame: *const ChartFrame,
    opts: AxisOptions,
    out: *std.ArrayListUnmanaged(DrawCmd),
    allocator: std.mem.Allocator,
) !void {
    const pr = frame.plot_rect;

    if (opts.show_y) {
        // Y axis line
        const y_pts = try allocator.dupe(Vec2, &.{
            .{ .x = pr.x, .y = pr.y },
            .{ .x = pr.x, .y = pr.y + pr.h },
        });
        try out.append(allocator, .{ .polyline = .{
            .points = y_pts,
            .width = 1.0,
            .color = opts.axis_color,
            .closed = false,
            .join = .miter,
        }});

        // Y ticks + gridlines
        const y_ticks = try frame.y.ticks(opts.y_tick_count, allocator);
        defer {
            for (y_ticks) |tick| allocator.free(tick.label);
            allocator.free(y_ticks);
        }
        for (y_ticks) |tick| {
            const py = frame.y.map(tick.value);
            if (py < pr.y or py > pr.y + pr.h) continue;
            // Tick mark
            const tick_pts = try allocator.dupe(Vec2, &.{
                .{ .x = pr.x - opts.tick_len, .y = py },
                .{ .x = pr.x, .y = py },
            });
            try out.append(allocator, .{ .polyline = .{
                .points = tick_pts, .width = 1.0, .color = opts.axis_color,
                .closed = false, .join = .miter,
            }});
            // Gridline
            if (opts.show_grid) {
                const grid_pts = try allocator.dupe(Vec2, &.{
                    .{ .x = pr.x, .y = py },
                    .{ .x = pr.x + pr.w, .y = py },
                });
                try out.append(allocator, .{ .polyline = .{
                    .points = grid_pts, .width = 1.0, .color = opts.grid_color,
                    .closed = false, .join = .miter,
                }});
            }
        }
    }

    if (opts.show_x) {
        // X axis line
        const x_pts = try allocator.dupe(Vec2, &.{
            .{ .x = pr.x, .y = pr.y + pr.h },
            .{ .x = pr.x + pr.w, .y = pr.y + pr.h },
        });
        try out.append(allocator, .{ .polyline = .{
            .points = x_pts, .width = 1.0, .color = opts.axis_color,
            .closed = false, .join = .miter,
        }});

        // X ticks + gridlines
        const x_ticks = try frame.x.ticks(opts.x_tick_count, allocator);
        defer {
            for (x_ticks) |tick| allocator.free(tick.label);
            allocator.free(x_ticks);
        }
        for (x_ticks) |tick| {
            const px = frame.x.map(tick.value);
            if (px < pr.x or px > pr.x + pr.w) continue;
            const tick_pts = try allocator.dupe(Vec2, &.{
                .{ .x = px, .y = pr.y + pr.h },
                .{ .x = px, .y = pr.y + pr.h + opts.tick_len },
            });
            try out.append(allocator, .{ .polyline = .{
                .points = tick_pts, .width = 1.0, .color = opts.axis_color,
                .closed = false, .join = .miter,
            }});
            if (opts.show_grid) {
                const grid_pts = try allocator.dupe(Vec2, &.{
                    .{ .x = px, .y = pr.y },
                    .{ .x = px, .y = pr.y + pr.h },
                });
                try out.append(allocator, .{ .polyline = .{
                    .points = grid_pts, .width = 1.0, .color = opts.grid_color,
                    .closed = false, .join = .miter,
                }});
            }
        }
    }
}
