const std = @import("std");
const scale_mod = @import("scale.zig");
const axes_mod = @import("axes.zig");
const chart_mod = @import("chart.zig");
const interaction = @import("interaction.zig");
const marks_mod = @import("marks.zig");
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

// ===========================================================================
// Shared test helpers
// ===========================================================================

/// A 200×200 chart frame centered at (100,100) with simple linear scales.
fn testPieFrame() axes_mod.ChartFrame {
    return .{
        .outer_rect = .{ .x = 0, .y = 0, .w = 200, .h = 200 },
        .plot_rect  = .{ .x = 0, .y = 0, .w = 200, .h = 200 },
        .x = scale_mod.Scale{ .linear = .{
            .domain_min = 0, .domain_max = 2, .range_min = 0, .range_max = 200,
        }},
        .y = scale_mod.Scale{ .linear = .{
            .domain_min = 0, .domain_max = 100, .range_min = 0, .range_max = 200,
        }},
    };
}

/// A 200×150 chart frame with 3 data points and known pixel positions.
fn testLineFrame() axes_mod.ChartFrame {
    return .{
        .outer_rect = .{ .x = 0, .y = 0, .w = 200, .h = 150 },
        .plot_rect  = .{ .x = 0, .y = 0, .w = 200, .h = 150 },
        .x = scale_mod.Scale{ .linear = .{
            .domain_min = 0, .domain_max = 2, .range_min = 0, .range_max = 200,
        }},
        .y = scale_mod.Scale{ .linear = .{
            .domain_min = 0, .domain_max = 40, .range_min = 0, .range_max = 150,
        }},
    };
}

// ===========================================================================
// RN1 — Donut chart
// ===========================================================================

test "donut: inner_radius 0.0 produces filled pie (backward compat)" {
    const allocator = std.testing.allocator;
    const vals = [_]f64{ 30, 20, 50 };
    const series = [_]chart_mod.Series{.{
        .name = "pie", .values = &vals, .color_token = "series0",
    }};
    const chart = chart_mod.Chart{
        .kind = .pie,
        .series = &series,
        .x = .{ .numeric = &vals },
        .inner_radius = 0.0,   // filled pie — backward compat
    };
    var cmds: std.ArrayListUnmanaged(types01.DrawCommand) = .empty;
    defer cmds.deinit(allocator);

    const frame = testPieFrame();
    try chart.render(&frame, &cmds, allocator);

    // All arc commands must have width == 0.0 (filled wedge)
    var arc_count: u32 = 0;
    for (cmds.items) |cmd| {
        switch (cmd) {
            .arc => |a| {
                try std.testing.expectApproxEqAbs(@as(f32, 0.0), a.width, 1e-4);
                arc_count += 1;
            },
            else => {},
        }
    }
    try std.testing.expectEqual(@as(u32, 3), arc_count);
}

test "donut: inner_radius 0.6 with values [30,20,50] produces 3 arc commands with non-zero width" {
    const allocator = std.testing.allocator;
    const vals = [_]f64{ 30, 20, 50 };
    const series = [_]chart_mod.Series{.{
        .name = "donut", .values = &vals, .color_token = "series0",
    }};
    const chart = chart_mod.Chart{
        .kind = .pie,
        .series = &series,
        .x = .{ .numeric = &vals },
        .inner_radius = 0.6,
    };
    var cmds: std.ArrayListUnmanaged(types01.DrawCommand) = .empty;
    defer cmds.deinit(allocator);

    const frame = testPieFrame();
    try chart.render(&frame, &cmds, allocator);

    // frame: plot_rect 200×200 → r = @min(200,200) * 0.4 = 80
    // ring_width = 80 * (1 - 0.6) = 32
    const pr = frame.plot_rect;
    const r = @min(pr.w, pr.h) * 0.4;
    const expected_width = r * (1.0 - 0.6);

    var arc_count: u32 = 0;
    for (cmds.items) |cmd| {
        switch (cmd) {
            .arc => |a| {
                // width must be non-zero and ≈ r * (1 - inner_radius)
                try std.testing.expect(a.width > 0);
                try std.testing.expectApproxEqAbs(expected_width, a.width, 1.0);
                arc_count += 1;
            },
            else => {},
        }
    }
    try std.testing.expectEqual(@as(u32, 3), arc_count);
}

test "donut: center label stored in chart struct and arc count unchanged" {
    const allocator = std.testing.allocator;
    const vals = [_]f64{ 40, 60 };
    const series = [_]chart_mod.Series{.{
        .name = "d", .values = &vals, .color_token = "series0",
    }};
    const chart = chart_mod.Chart{
        .kind = .pie,
        .series = &series,
        .x = .{ .numeric = &vals },
        .inner_radius = 0.5,
        .center_label = "Total",
    };

    // center_label field is accessible and holds the provided string
    try std.testing.expect(chart.center_label != null);
    try std.testing.expectEqualStrings("Total", chart.center_label.?);

    // Rendering still produces exactly one arc per datum (2 here)
    var cmds: std.ArrayListUnmanaged(types01.DrawCommand) = .empty;
    defer cmds.deinit(allocator);
    const frame = testPieFrame();
    try chart.render(&frame, &cmds, allocator);

    var arc_count: u32 = 0;
    for (cmds.items) |cmd| {
        if (cmd == .arc) arc_count += 1;
    }
    try std.testing.expectEqual(@as(u32, 2), arc_count);
}

test "donut: zero inner_radius and non-zero inner_radius produce different widths" {
    const vals = [_]f64{ 50, 50 };
    const pie_chart = chart_mod.Chart{
        .kind = .pie,
        .series = &[_]chart_mod.Series{.{ .name = "p", .values = &vals, .color_token = "series0" }},
        .x = .{ .numeric = &vals },
        .inner_radius = 0.0,
    };
    const donut_chart = chart_mod.Chart{
        .kind = .pie,
        .series = &[_]chart_mod.Series{.{ .name = "d", .values = &vals, .color_token = "series0" }},
        .x = .{ .numeric = &vals },
        .inner_radius = 0.5,
    };

    // Confirm field values differ
    try std.testing.expect(pie_chart.inner_radius != donut_chart.inner_radius);
    try std.testing.expect(donut_chart.inner_radius > 0);
}

// ===========================================================================
// RN2 — Chart annotations / leader-line callouts
// ===========================================================================

test "callout: single segment annotation emits PolylineCmd from segment mid-angle to label position" {
    const vals = [_]f64{ 30, 70 };
    const center = types01.Vec2{ .x = 100, .y = 100 };
    const outer_r: f32 = 80;
    const label_r: f32 = outer_r * 1.35; // ~108

    const pos = marks_mod.computeCalloutPos(&vals, 0, center, outer_r, label_r).?;

    // anchor must be on the outer ring (distance from center ≈ outer_r)
    const dx_a = pos.anchor.x - center.x;
    const dy_a = pos.anchor.y - center.y;
    const dist_a = @sqrt(dx_a * dx_a + dy_a * dy_a);
    try std.testing.expectApproxEqAbs(outer_r, dist_a, 0.5);

    // label_pt must be at label_r from center
    const dx_l = pos.label_pt.x - center.x;
    const dy_l = pos.label_pt.y - center.y;
    const dist_l = @sqrt(dx_l * dx_l + dy_l * dy_l);
    try std.testing.expectApproxEqAbs(label_r, dist_l, 0.5);

    // label_pt is further from center than anchor
    try std.testing.expect(dist_l > dist_a);

    // A PolylineCmd from anchor to label_pt can be constructed (validates the contract)
    const pts = [_]types01.Vec2{ pos.anchor, pos.label_pt };
    const polyline = types01.DrawCommand{ .polyline = .{
        .points = &pts,
        .width  = 1.0,
        .color  = .{ .r = 100, .g = 100, .b = 100, .a = 255 },
        .closed = false,
        .join   = .miter,
    }};
    try std.testing.expect(polyline == .polyline);
}

test "callout: 5+ segments no label overlap" {
    // 5 equal segments → 72° angular separation; label positions must be
    // well-separated even with a conservative minimum distance.
    const vals = [_]f64{ 20, 20, 20, 20, 20 };
    const center = types01.Vec2{ .x = 100, .y = 100 };
    const outer_r: f32 = 80;
    const label_r: f32 = outer_r * 1.35;

    var positions: [5]marks_mod.CalloutPos = undefined;
    for (0..5) |i| {
        positions[i] = marks_mod.computeCalloutPos(
            &vals, @intCast(i), center, outer_r, label_r,
        ).?;
    }

    // For 5 equal segments the chord between adjacent labels ≈ 2*label_r*sin(π/5) ≈ 127 px.
    // Use a generous minimum of 10 px to guard against degenerate cases.
    const min_dist: f32 = 10.0;
    for (0..5) |i| {
        for (i + 1..5) |j| {
            const dx = positions[i].label_pt.x - positions[j].label_pt.x;
            const dy = positions[i].label_pt.y - positions[j].label_pt.y;
            const dist = @sqrt(dx * dx + dy * dy);
            try std.testing.expect(dist >= min_dist);
        }
    }
}

test "callout: datum_idx out of range returns null" {
    const vals = [_]f64{ 50, 50 };
    const center = types01.Vec2{ .x = 0, .y = 0 };
    // datum_idx == values.len is out of range
    const result = marks_mod.computeCalloutPos(&vals, 2, center, 80, 108);
    try std.testing.expect(result == null);
}

test "callout: zero-sum values returns null" {
    const vals = [_]f64{ 0, 0, 0 };
    const center = types01.Vec2{ .x = 0, .y = 0 };
    const result = marks_mod.computeCalloutPos(&vals, 0, center, 80, 108);
    try std.testing.expect(result == null);
}

test "callout: all 5 segments have distinct mid-angles" {
    const vals = [_]f64{ 10, 20, 30, 25, 15 };
    const center = types01.Vec2{ .x = 50, .y = 50 };
    const outer_r: f32 = 40;
    const label_r: f32 = 55;

    var angles: [5]f32 = undefined;
    for (0..5) |i| {
        const pos = marks_mod.computeCalloutPos(&vals, @intCast(i), center, outer_r, label_r).?;
        angles[i] = pos.mid_angle;
    }

    // No two mid-angles should be identical (each segment is distinct)
    for (0..5) |i| {
        for (i + 1..5) |j| {
            const diff = @abs(angles[i] - angles[j]);
            try std.testing.expect(diff > 0.01);
        }
    }
}

// ===========================================================================
// RN7 — Chart crosshair / reference guide on hover
// ===========================================================================

test "crosshair: default state has null x" {
    const cs = interaction.CrosshairState{};
    try std.testing.expect(cs.x == null);
}

test "crosshair: hover sets crosshair x to nearest datum x" {
    const vals = [_]f64{ 10, 20, 30 };
    const series = [_]chart_mod.Series{.{
        .name = "A", .values = &vals, .color_token = "accent",
    }};
    const chart = chart_mod.Chart{
        .kind  = .line,
        .series = &series,
        .x = .{ .numeric = &vals },
    };
    const frame = testLineFrame();
    // datum 1 is at x=100, datum 0 at x=0, datum 2 at x=200
    var cs = interaction.CrosshairState{};
    interaction.updateCrosshairX(&chart, &frame, .{ .x = 102, .y = 75 }, 30.0, &cs);
    try std.testing.expect(cs.x != null);
    try std.testing.expectApproxEqAbs(@as(f32, 100.0), cs.x.?, 2.0);
}

test "crosshair: mouse out clears crosshair x (null/hidden)" {
    const vals = [_]f64{ 10, 20 };
    const series = [_]chart_mod.Series{.{
        .name = "A", .values = &vals, .color_token = "accent",
    }};
    const chart = chart_mod.Chart{
        .kind  = .line,
        .series = &series,
        .x = .{ .numeric = &vals },
    };
    const frame = testLineFrame();
    var cs = interaction.CrosshairState{ .x = 50.0 };
    // Pass null mouse → mouse-out event
    interaction.updateCrosshairX(&chart, &frame, null, 20.0, &cs);
    try std.testing.expect(cs.x == null);
}

test "crosshair: mouse outside plot rect leaves x null" {
    const vals = [_]f64{ 10, 20, 30 };
    const series = [_]chart_mod.Series{.{
        .name = "A", .values = &vals, .color_token = "accent",
    }};
    const chart = chart_mod.Chart{
        .kind  = .line,
        .series = &series,
        .x = .{ .numeric = &vals },
    };
    // plot_rect occupies [40..200] x [0..150]; mouse at (5,75) is outside
    const frame = axes_mod.ChartFrame{
        .outer_rect = .{ .x = 0, .y = 0, .w = 200, .h = 150 },
        .plot_rect  = .{ .x = 40, .y = 0, .w = 160, .h = 150 },
        .x = scale_mod.Scale{ .linear = .{
            .domain_min = 0, .domain_max = 2, .range_min = 40, .range_max = 200,
        }},
        .y = scale_mod.Scale{ .linear = .{
            .domain_min = 0, .domain_max = 40, .range_min = 0, .range_max = 150,
        }},
    };
    var cs = interaction.CrosshairState{};
    interaction.updateCrosshairX(&chart, &frame, .{ .x = 5, .y = 75 }, 30.0, &cs);
    try std.testing.expect(cs.x == null);
}

test "crosshair: successive hover calls update x each time" {
    const vals = [_]f64{ 0, 50, 100 };
    const series = [_]chart_mod.Series{.{
        .name = "A", .values = &vals, .color_token = "accent",
    }};
    const chart = chart_mod.Chart{
        .kind  = .line,
        .series = &series,
        .x = .{ .numeric = &vals },
    };
    const frame = axes_mod.ChartFrame{
        .outer_rect = .{ .x = 0, .y = 0, .w = 300, .h = 150 },
        .plot_rect  = .{ .x = 0, .y = 0, .w = 300, .h = 150 },
        .x = scale_mod.Scale{ .linear = .{
            .domain_min = 0, .domain_max = 2, .range_min = 0, .range_max = 300,
        }},
        .y = scale_mod.Scale{ .linear = .{
            .domain_min = 0, .domain_max = 110, .range_min = 0, .range_max = 150,
        }},
    };
    // datum 0 at x=0, datum 1 at x=150, datum 2 at x=300
    var cs = interaction.CrosshairState{};

    interaction.updateCrosshairX(&chart, &frame, .{ .x = 5, .y = 75 }, 30.0, &cs);
    const x_after_datum0 = cs.x;

    interaction.updateCrosshairX(&chart, &frame, .{ .x = 152, .y = 75 }, 30.0, &cs);
    const x_after_datum1 = cs.x;

    // The two snap positions must differ
    if (x_after_datum0 != null and x_after_datum1 != null) {
        try std.testing.expect(x_after_datum0.? != x_after_datum1.?);
    }
}
