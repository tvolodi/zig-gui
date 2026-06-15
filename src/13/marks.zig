//! Chart mark emission — M26-03
const std = @import("std");
const chart_mod = @import("chart.zig");
const axes_mod = @import("axes.zig");
const tess = @import("tessellate.zig");
const types01 = @import("../01/types.zig");
const Vec2 = types01.Vec2;
const Color09 = types01.Color09;

const Chart = chart_mod.Chart;
const ChartFrame = axes_mod.ChartFrame;
const DrawCmd = types01.DrawCommand;

/// Resolve a color token name to a Color09 (simplified — uses fixed semantic palette).
/// In production this reads from the Tokens struct passed from module 05.
pub fn resolveToken(token: []const u8) Color09 {
    // Fixed token → color mapping for basic palette tokens
    if (std.mem.eql(u8, token, "accent"))   return .{ .r = 99,  .g = 102, .b = 241, .a = 255 };
    if (std.mem.eql(u8, token, "ok"))       return .{ .r = 34,  .g = 197, .b = 94,  .a = 255 };
    if (std.mem.eql(u8, token, "warn"))     return .{ .r = 234, .g = 179, .b = 8,   .a = 255 };
    if (std.mem.eql(u8, token, "err"))      return .{ .r = 239, .g = 68,  .b = 68,  .a = 255 };
    if (std.mem.eql(u8, token, "series0"))  return .{ .r = 99,  .g = 102, .b = 241, .a = 255 };
    if (std.mem.eql(u8, token, "series1"))  return .{ .r = 34,  .g = 197, .b = 94,  .a = 255 };
    if (std.mem.eql(u8, token, "series2"))  return .{ .r = 234, .g = 179, .b = 8,   .a = 255 };
    if (std.mem.eql(u8, token, "series3"))  return .{ .r = 239, .g = 68,  .b = 68,  .a = 255 };
    return .{ .r = 100, .g = 100, .b = 100, .a = 255 };
}

pub fn renderChart(
    chart: *const Chart,
    frame: *const ChartFrame,
    out: *std.ArrayListUnmanaged(DrawCmd),
    allocator: std.mem.Allocator,
) !void {
    for (chart.series) |series| {
        if (!series.visible) continue;
        const color = resolveToken(series.color_token);
        switch (chart.kind) {
            .line    => try renderLine(series, frame, color, out, allocator),
            .area    => try renderArea(series, frame, color, out, allocator),
            .bar     => try renderBar(series, chart, frame, color, out, allocator),
            .scatter => try renderScatter(series, frame, color, out, allocator),
            .pie     => try renderPie(series, chart, frame, color, out, allocator),
        }
    }
}

fn renderLine(
    series: chart_mod.Series,
    frame: *const ChartFrame,
    color: Color09,
    out: *std.ArrayListUnmanaged(DrawCmd),
    allocator: std.mem.Allocator,
) !void {
    if (series.values.len < 2) return;
    const pr = frame.plot_rect;
    const pts = try allocator.alloc(Vec2, series.values.len);
    for (series.values, 0..) |v, i| {
        const xi = @as(f64, @floatFromInt(i));
        pts[i] = .{
            .x = frame.x.map(xi),
            .y = pr.y + pr.h - (frame.y.map(v) - pr.y),
        };
    }
    try out.append(.{ .polyline = .{
        .points = pts,
        .width = 2.0,
        .color = color,
        .closed = false,
        .join = .miter,
    }});
}

fn renderArea(
    series: chart_mod.Series,
    frame: *const ChartFrame,
    color: Color09,
    out: *std.ArrayListUnmanaged(DrawCmd),
    allocator: std.mem.Allocator,
) !void {
    if (series.values.len < 2) return;
    const pr = frame.plot_rect;
    const n = series.values.len;
    // vertices: top line + bottom baseline (reverse order)
    const verts = try allocator.alloc(Vec2, n * 2);
    for (series.values, 0..) |v, i| {
        const xi = @as(f64, @floatFromInt(i));
        const px = frame.x.map(xi);
        const py = pr.y + pr.h - (frame.y.map(v) - pr.y);
        const baseline = pr.y + pr.h;
        verts[i] = .{ .x = px, .y = py };
        verts[n * 2 - 1 - i] = .{ .x = px, .y = baseline };
    }
    // Triangulate as fan
    const fan = try tess.triangulateConvex(allocator, verts);
    var fill_color = color;
    fill_color.a = 120;
    try out.append(.{ .filled_path = .{
        .vertices = fan.verts,
        .indices = fan.indices,
        .color = fill_color,
    }});
    // Top line
    const top_pts = try allocator.dupe(Vec2, verts[0..n]);
    try out.append(.{ .polyline = .{
        .points = top_pts, .width = 2.0, .color = color,
        .closed = false, .join = .miter,
    }});
}

fn renderBar(
    series: chart_mod.Series,
    chart: *const Chart,
    frame: *const ChartFrame,
    color: Color09,
    out: *std.ArrayListUnmanaged(DrawCmd),
    allocator: std.mem.Allocator,
) !void {
    const pr = frame.plot_rect;
    const n = series.values.len;
    if (n == 0) return;
    const bar_w = @max(pr.w / @as(f32, @floatFromInt(n)) - 4.0, 2.0);
    const baseline = pr.y + pr.h;
    for (series.values, 0..) |v, i| {
        const xi = @as(f64, @floatFromInt(i));
        const cx = frame.x.map(xi);
        const top_y = frame.y.map(v);
        const bar_h = baseline - top_y;
        _ = chart;
        const rect = types01.Rect09{
            .x = cx - bar_w * 0.5,
            .y = top_y,
            .w = bar_w,
            .h = bar_h,
        };
        try out.append(allocator, .{ .filled_rect = .{ .rect = rect, .color = color } });
    }
}

fn renderScatter(
    series: chart_mod.Series,
    frame: *const ChartFrame,
    color: Color09,
    out: *std.ArrayListUnmanaged(DrawCmd),
    allocator: std.mem.Allocator,
) !void {
    const pr = frame.plot_rect;
    for (series.values, 0..) |v, i| {
        const xi = @as(f64, @floatFromInt(i));
        const cx = frame.x.map(xi);
        const cy = pr.y + pr.h - (frame.y.map(v) - pr.y);
        const r: f32 = if (series.hovered_datum != null and series.hovered_datum.? == i) 6.0 else 4.0;
        try out.append(allocator, .{ .arc = .{
            .center = .{ .x = cx, .y = cy },
            .radius = r,
            .start_rad = 0.0,
            .end_rad = std.math.tau,
            .width = 0.0,
            .color = color,
        }});
    }
}

fn renderPie(
    series: chart_mod.Series,
    chart: *const Chart,
    frame: *const ChartFrame,
    color: Color09,
    out: *std.ArrayListUnmanaged(DrawCmd),
    allocator: std.mem.Allocator,
) !void {
    _ = chart;
    const pr = frame.plot_rect;
    const cx = pr.x + pr.w * 0.5;
    const cy = pr.y + pr.h * 0.5;
    const r = @min(pr.w, pr.h) * 0.4;

    // Sum all values for proportion
    var total: f64 = 0;
    for (series.values) |v| total += @abs(v);
    if (total < 1e-10) return;

    var angle: f32 = -std.math.pi * 0.5; // start at top
    for (series.values, 0..) |v, i| {
        const sweep = @as(f32, @floatCast((v / total) * std.math.tau));
        // Slightly vary color per wedge (simplistic)
        var wedge_color = color;
        const shade: u8 = @intCast(@min(255, @as(i32, color.r) + @as(i32, @intCast(i)) * 20));
        wedge_color.r = shade;
        try out.append(allocator, .{ .arc = .{
            .center = .{ .x = cx, .y = cy },
            .radius = r,
            .start_rad = angle,
            .end_rad = angle + sweep,
            .width = 0.0,
            .color = wedge_color,
        }});
        angle += sweep;
    }
}
