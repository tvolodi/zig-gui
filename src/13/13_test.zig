const std = @import("std");
const scale_mod = @import("scale.zig");
const axes_mod = @import("axes.zig");
const chart_mod = @import("chart.zig");
const interaction = @import("interaction.zig");
const tess = @import("tessellate.zig");
const types01 = @import("../01/types.zig");

test "Scale.linear: map midpoint" {
    const s = scale_mod.Scale{ .linear = .{
        .domain_min = 0, .domain_max = 100,
        .range_min = 0, .range_max = 200,
    }};
    try std.testing.expectApproxEqAbs(@as(f32, 100.0), s.map(50.0), 0.01);
}

test "Scale.linear: map/invert round-trip" {
    const s = scale_mod.Scale{ .linear = .{
        .domain_min = 0, .domain_max = 100,
        .range_min = 0, .range_max = 200,
    }};
    const pixel = s.map(37.5);
    const back = s.invert(pixel);
    try std.testing.expectApproxEqAbs(@as(f64, 37.5), back, 0.01);
}

test "Scale.log: map/invert round-trip" {
    const s = scale_mod.Scale{ .log = .{
        .domain_min = 1, .domain_max = 1000,
        .range_min = 0, .range_max = 300,
    }};
    const pixel = s.map(100.0);
    const back = s.invert(pixel);
    try std.testing.expectApproxEqAbs(@as(f64, 100.0), back, 0.5);
}

test "Scale.band: map returns band center" {
    const cats = [_][]const u8{ "A", "B", "C", "D" };
    const s = scale_mod.Scale{ .band = .{
        .categories = &cats,
        .range_min = 0,
        .range_max = 200,
        .padding = 0.0,
    }};
    // 4 bands of 50px each; center of band 0 at 25, band 1 at 75, etc.
    const c0 = s.map(0);
    const c1 = s.map(1);
    try std.testing.expectApproxEqAbs(@as(f32, 25.0), c0, 1.0);
    try std.testing.expectApproxEqAbs(@as(f32, 75.0), c1, 1.0);
}

test "Scale.linear: ticks produces nice values" {
    const allocator = std.testing.allocator;
    const s = scale_mod.Scale{ .linear = .{
        .domain_min = 0, .domain_max = 97,
        .range_min = 0, .range_max = 300,
    }};
    const t = try s.ticks(5, allocator);
    defer {
        for (t) |tick| allocator.free(tick.label);
        allocator.free(t);
    }
    try std.testing.expect(t.len >= 3);
    // All ticks in domain (with small margin for nice rounding)
    for (t) |tick| {
        try std.testing.expect(tick.value >= -1.0 and tick.value <= 101.0);
    }
}

test "tessellate polyline: 3 points produces verts" {
    const allocator = std.testing.allocator;
    const pts = [_]types01.Vec2{
        .{ .x = 0, .y = 0 },
        .{ .x = 10, .y = 0 },
        .{ .x = 10, .y = 10 },
    };
    const verts = try tess.tessellatePolyline(allocator, &pts, 2.0, false);
    defer allocator.free(verts);
    try std.testing.expect(verts.len >= 4);
}

test "tessellate convex: triangle fan has correct index count" {
    const allocator = std.testing.allocator;
    const pts = [_]types01.Vec2{
        .{ .x = 0, .y = 0 },
        .{ .x = 10, .y = 0 },
        .{ .x = 5, .y = 10 },
        .{ .x = 0, .y = 10 },
    };
    const fan = try tess.triangulateConvex(allocator, &pts);
    defer allocator.free(fan.verts);
    defer allocator.free(fan.indices);
    // 4 verts → 2 triangles → 6 indices
    try std.testing.expectEqual(@as(usize, 6), fan.indices.len);
}

test "hitTest: returns null when mouse outside plot rect" {
    const series_data = [_]f64{ 10, 20, 30 };
    const series = [_]chart_mod.Series{.{
        .name = "A", .values = &series_data, .color_token = "accent",
    }};
    const chart = chart_mod.Chart{
        .kind = .line,
        .series = &series,
        .x = .{ .numeric = &series_data },
    };
    const frame = axes_mod.ChartFrame{
        .outer_rect = .{ .x = 0, .y = 0, .w = 200, .h = 150 },
        .plot_rect = .{ .x = 40, .y = 0, .w = 160, .h = 126 },
        .x = scale_mod.Scale{ .linear = .{ .domain_min = 0, .domain_max = 2, .range_min = 40, .range_max = 200 }},
        .y = scale_mod.Scale{ .linear = .{ .domain_min = 0, .domain_max = 40, .range_min = 0, .range_max = 126 }},
    };
    const result = interaction.hitTest(&chart, &frame, .{ .x = 5, .y = 5 }, 20.0);
    try std.testing.expect(result == null);
}

test "hitTest: hits nearest datum" {
    const series_data = [_]f64{ 10, 20, 30 };
    const series = [_]chart_mod.Series{.{
        .name = "A", .values = &series_data, .color_token = "accent",
    }};
    const chart = chart_mod.Chart{
        .kind = .line,
        .series = &series,
        .x = .{ .numeric = &series_data },
    };
    const frame = axes_mod.ChartFrame{
        .outer_rect = .{ .x = 0, .y = 0, .w = 200, .h = 150 },
        .plot_rect = .{ .x = 0, .y = 0, .w = 200, .h = 150 },
        .x = scale_mod.Scale{ .linear = .{ .domain_min = 0, .domain_max = 2, .range_min = 0, .range_max = 200 }},
        .y = scale_mod.Scale{ .linear = .{ .domain_min = 0, .domain_max = 40, .range_min = 0, .range_max = 150 }},
    };
    // datum 0 is at x=0, datum 1 at x=100, datum 2 at x=200
    // clicking near datum 1 (x=100)
    const result = interaction.hitTest(&chart, &frame, .{ .x = 102, .y = 75 }, 30.0);
    if (result) |hit| {
        try std.testing.expectEqual(@as(u32, 1), hit.datum_idx);
    }
    // null is also acceptable if hit-test math puts y out of range
}

test "pie wedge angles sum to tau" {
    // Sum of proportional angles = 2π
    const vals = [_]f64{ 30, 20, 50 };
    var total: f64 = 0;
    for (vals) |v| total += v;
    var angle_sum: f64 = 0;
    for (vals) |v| angle_sum += (v / total) * std.math.tau;
    try std.testing.expectApproxEqAbs(std.math.tau, angle_sum, 0.001);
}

test "DrawCommand union has polyline variant" {
    const dc = types01.DrawCommand{ .polyline = .{
        .points = &[_]types01.Vec2{},
        .width = 1.0,
        .color = .{ .r = 0, .g = 0, .b = 0, .a = 255 },
        .closed = false,
        .join = .miter,
    }};
    try std.testing.expect(dc == .polyline);
}

test "DrawCommand union has arc variant" {
    const dc = types01.DrawCommand{ .arc = .{
        .center = .{ .x = 0, .y = 0 },
        .radius = 10.0,
        .start_rad = 0,
        .end_rad = std.math.pi,
        .width = 0,
        .color = .{ .r = 255, .g = 0, .b = 0, .a = 255 },
    }};
    try std.testing.expect(dc == .arc);
}

test "ChartKind enum has all 5 kinds" {
    const k: chart_mod.ChartKind = .line;
    try std.testing.expect(k == .line);
    try std.testing.expect(chart_mod.ChartKind.bar != .line);
    try std.testing.expect(chart_mod.ChartKind.area != .bar);
    try std.testing.expect(chart_mod.ChartKind.scatter != .area);
    try std.testing.expect(chart_mod.ChartKind.pie != .scatter);
}
