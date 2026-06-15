//! Chart legend — M26-04
//! Legend is a row of swatch + series-name pairs using existing draw commands.
const std = @import("std");
const chart_mod = @import("chart.zig");
const marks_mod = @import("marks.zig");
const types01 = @import("../01/types.zig");

pub const LegendOptions = struct {
    x: f32,
    y: f32,
    swatch_size: f32 = 12.0,
    row_height: f32 = 18.0,
    label_color: types01.Color09 = .{ .r = 60, .g = 60, .b = 60, .a = 255 },
};

/// Emit legend swatches (filled rects) for a chart's series.
/// Labels require glyph commands — emitting filled swatches only here.
pub fn drawLegend(
    chart: *const chart_mod.Chart,
    opts: LegendOptions,
    out: *std.ArrayListUnmanaged(types01.DrawCommand),
    allocator: std.mem.Allocator,
) !void {
    for (chart.series, 0..) |series, i| {
        const color = marks_mod.resolveToken(series.color_token);
        const y = opts.y + @as(f32, @floatFromInt(i)) * opts.row_height;
        const swatch_rect = types01.Rect09{
            .x = opts.x,
            .y = y,
            .w = opts.swatch_size,
            .h = opts.swatch_size,
        };
        try out.append(allocator, .{ .filled_rect = .{ .rect = swatch_rect, .color = color } });
    }
}
