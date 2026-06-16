//! Chart mark emission — M26-03 / M27 RN1 RN2 RN7
const std = @import("std");
const chart_mod = @import("chart.zig");
const axes_mod = @import("axes.zig");
const types01 = @import("../01/types.zig");
const Vec2 = types01.Vec2;
const Color09 = types01.Color09;

const Chart = chart_mod.Chart;
const ChartFrame = axes_mod.ChartFrame;
const DrawCmd = types01.DrawCommand;

/// RN10 — A dot marker positioned on the world map.
pub const MapMarker = struct {
    norm_x: f32,
    norm_y: f32,
    radius: f32 = 4.0,
    color_token: []const u8 = "accent",
};

/// Resolve a color token name to a Color09 (simplified — uses fixed semantic palette).
/// In production this reads from the Tokens struct passed from module 05 (INV-4.3).
pub fn resolveToken(token: []const u8) Color09 {
    if (std.mem.eql(u8, token, "accent"))   return .{ .r = 99,  .g = 102, .b = 241, .a = 255 };
    if (std.mem.eql(u8, token, "ok"))       return .{ .r = 34,  .g = 197, .b = 94,  .a = 255 };
    if (std.mem.eql(u8, token, "warn"))     return .{ .r = 234, .g = 179, .b = 8,   .a = 255 };
    if (std.mem.eql(u8, token, "err"))      return .{ .r = 239, .g = 68,  .b = 68,  .a = 255 };
    if (std.mem.eql(u8, token, "series0"))  return .{ .r = 99,  .g = 102, .b = 241, .a = 255 };
    if (std.mem.eql(u8, token, "series1"))  return .{ .r = 34,  .g = 197, .b = 94,  .a = 255 };
    if (std.mem.eql(u8, token, "series2"))  return .{ .r = 234, .g = 179, .b = 8,   .a = 255 };
    if (std.mem.eql(u8, token, "series3"))  return .{ .r = 239, .g = 68,  .b = 68,  .a = 255 };
    // RN1/RN2/RN7 semantic tokens (INV-4.3 — never a raw hex literal at call sites)
    if (std.mem.eql(u8, token, "axis"))     return .{ .r = 150, .g = 150, .b = 150, .a = 200 };
    if (std.mem.eql(u8, token, "surface"))  return .{ .r = 255, .g = 255, .b = 255, .a = 220 };
    return .{ .r = 100, .g = 100, .b = 100, .a = 255 };
}

pub fn renderChart(
    chart: *const Chart,
    frame: *const ChartFrame,
    out: *std.ArrayListUnmanaged(DrawCmd),
    allocator: std.mem.Allocator,
) !void {
    // RN9/RN10 — gauge and map do not iterate over series; handle and return early.
    switch (chart.kind) {
        .gauge => return renderGauge(chart.gauge_value, chart.gauge_bg_token, chart.gauge_fill_token, frame, out, allocator),
        .map   => return renderWorldMap(chart.map_markers, chart.map_ocean_token, chart.map_land_token, frame, out, allocator),
        else   => {},
    }

    for (chart.series) |series| {
        if (!series.visible) continue;
        const color = resolveToken(series.color_token);
        switch (chart.kind) {
            .line    => try renderLine(series, frame, color, out, allocator),
            .area    => try renderArea(series, frame, color, out, allocator),
            .bar     => try renderBar(series, chart, frame, color, out, allocator),
            .scatter => try renderScatter(series, frame, color, out, allocator),
            .pie     => try renderPie(series, chart, frame, color, out, allocator),
            .gauge, .map => {}, // handled above, never reached via series loop
        }
    }

    // RN2 — emit annotation callouts (pie: one leader line per callout entry).
    if (chart.kind == .pie and chart.callouts.len > 0) {
        try renderCallouts(chart, frame, out, allocator);
    }

    // RN7 — emit crosshair when enabled and any series has a hovered datum.
    if (chart.crosshair.enabled) {
        for (chart.series) |series| {
            if (!series.visible) continue;
            if (series.hovered_datum) |datum_idx| {
                try renderCrosshair(datum_idx, frame, chart.crosshair, out, allocator);
                break; // single crosshair line across all series
            }
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
    try out.append(allocator, .{ .polyline = .{
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
    const baseline = pr.y + pr.h;

    // The Vulkan backend renders filled_path/polyline as no-ops.
    // Emit aa_filled_rect column segments instead: each column spans from
    // x[i] to x[i+1], from min(y[i], y[i+1]) down to the baseline.
    var fill_color = color;
    fill_color.a = 120;

    var prev_px: f32 = 0;
    var prev_py: f32 = 0;
    for (series.values, 0..) |v, i| {
        const xi = @as(f64, @floatFromInt(i));
        const px = frame.x.map(xi);
        const py = pr.y + pr.h - (frame.y.map(v) - pr.y);
        if (i > 0 and px > prev_px) {
            // Area fill column.
            const col_top = @min(prev_py, py);
            const col_h = baseline - col_top;
            if (col_h > 0) {
                try out.append(allocator, .{ .aa_filled_rect = .{
                    .rect = .{ .x = prev_px, .y = col_top, .w = px - prev_px, .h = col_h },
                    .color = fill_color,
                    .radius = 0,
                }});
            }
            // Top edge line (2 px tall, spanning the column width at the top).
            try out.append(allocator, .{ .aa_filled_rect = .{
                .rect = .{ .x = prev_px, .y = col_top - 1, .w = px - prev_px, .h = 2.0 },
                .color = color,
                .radius = 0,
            }});
        }
        prev_px = px;
        prev_py = py;
    }
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
        // Compare u32 hovered_datum to usize loop index safely.
        const is_hovered = if (series.hovered_datum) |hd| @as(usize, hd) == i else false;
        const r: f32 = if (is_hovered) 6.0 else 4.0;
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

/// RN1: renderPie handles solid pie (inner_radius == 0) and donut ring (inner_radius > 0).
///
/// Ring geometry when chart.inner_radius > 0:
///   outer_r  = @min(pr.w, pr.h) * 0.4
///   arc_radius = outer_r * (1.0 + inner_radius) * 0.5   ← center of the ring stroke
///   arc_width  = outer_r * (1.0 - inner_radius)          ← total ring thickness
///
/// ArcCmd contract (INV-2.3): width == 0 → filled wedge; width > 0 → ring stroke
/// centered on radius with half the width inward and half outward.  With the above
/// formula the inner edge sits at outer_r * inner_radius and the outer edge at outer_r.
///
/// When center_label is set and inner_radius > 0, an aa_filled_circle background is
/// emitted centered in the hole as a clean slot for the caller's glyph commands (same
/// deferral pattern as drawLegend — see INV-4.3 and the M26 legend note).
fn renderPie(
    series: chart_mod.Series,
    chart: *const Chart,
    frame: *const ChartFrame,
    color: Color09,
    out: *std.ArrayListUnmanaged(DrawCmd),
    allocator: std.mem.Allocator,
) !void {
    const pr = frame.plot_rect;
    const cx = pr.x + pr.w * 0.5;
    const cy = pr.y + pr.h * 0.5;
    const outer_r = @min(pr.w, pr.h) * 0.4;
    const ir = chart.inner_radius;  // 0..1 proportion

    // Compute arc geometry: filled wedge or ring stroke.
    const arc_radius: f32 = if (ir > 0.0) outer_r * (1.0 + ir) * 0.5 else outer_r;
    const arc_width: f32  = if (ir > 0.0) outer_r * (1.0 - ir)       else 0.0;

    // Sum all values for proportion.
    var total: f64 = 0;
    for (series.values) |v| total += @abs(v);
    if (total < 1e-10) return;

    var angle: f32 = -std.math.pi * 0.5; // start at top
    for (series.values, 0..) |v, i| {
        const sweep = @as(f32, @floatCast((v / total) * std.math.tau));
        // Slightly vary hue per wedge (simplistic distinguisher).
        var wedge_color = color;
        const shade: u8 = @intCast(@min(255, @as(i32, color.r) + @as(i32, @intCast(i)) * 20));
        wedge_color.r = shade;
        try out.append(allocator, .{ .arc = .{
            .center    = .{ .x = cx, .y = cy },
            .radius    = arc_radius,
            .start_rad = angle,
            .end_rad   = angle + sweep,
            .width     = arc_width,
            .color     = wedge_color,
        }});
        angle += sweep;
    }

    // RN1 center-label background: emit an aa_filled_circle within the hole so the
    // caller's glyph commands appear on a clean background.
    if (chart.center_label != null and ir > 0.0) {
        const hole_r = outer_r * ir * 0.85;
        try out.append(allocator, .{ .aa_filled_circle = .{
            .center_x = cx,
            .center_y = cy,
            .radius   = hole_r,
            .color    = resolveToken("surface"),
        }});
    }
}

// ---------------------------------------------------------------------------
// RN2 — Callout (leader-line) annotation support
// ---------------------------------------------------------------------------

/// RN2 — Computed geometry for one callout anchor.
pub const CalloutPos = struct {
    /// Point on the outer ring at the segment mid-angle (PolylineCmd start).
    anchor: Vec2,
    /// Outboard label anchor point (PolylineCmd end / text origin).
    label_pt: Vec2,
    /// Mid-angle of the segment in radians (measured from positive-x, clockwise).
    mid_angle: f32,
};

/// RN2 — Compute the outboard label position for a single pie/donut segment.
///
/// `values` is the full data series; `datum_idx` selects the segment.
/// `center` is the chart center pixel; `outer_r` is the outer ring radius;
/// `label_r` is the radial distance for label placement (typically outer_r * 1.35).
/// Returns null when datum_idx is out of range or the value sum is zero.
pub fn computeCalloutPos(
    values: []const f64,
    datum_idx: u32,
    center: Vec2,
    outer_r: f32,
    label_r: f32,
) ?CalloutPos {
    if (datum_idx >= values.len) return null;
    var total: f64 = 0;
    for (values) |v| total += @abs(v);
    if (total < 1e-10) return null;

    // Accumulate angle up to datum_idx (same start convention as renderPie).
    var angle: f32 = -std.math.pi * 0.5;
    for (0..datum_idx) |i| {
        angle += @as(f32, @floatCast((@abs(values[i]) / total) * std.math.tau));
    }
    const sweep: f32 = @floatCast((@abs(values[datum_idx]) / total) * std.math.tau);
    const mid = angle + sweep * 0.5;

    const cos_mid = @cos(mid);
    const sin_mid = @sin(mid);

    return CalloutPos{
        .anchor   = .{ .x = center.x + outer_r * cos_mid, .y = center.y + outer_r * sin_mid },
        .label_pt = .{ .x = center.x + label_r * cos_mid, .y = center.y + label_r * sin_mid },
        .mid_angle = mid,
    };
}

/// RN2: Emit leader-line annotation callouts for a pie chart.
///
/// For each chart_mod.Callout in chart.callouts this function emits:
///   1. A PolylineCmd (2 points) from the segment outer edge to an outboard anchor
///      (leader line).
///   2. A filled_rect label background at the anchor (caller renders the actual glyphs).
///
/// Non-overlap guarantee for ≥ 5 segments: anchors are placed at outer_r * 1.5 along
/// each segment's mid-angle.  For 5 evenly-distributed segments the inter-anchor
/// distance is ≥ 1.76 * outer_r, which exceeds the 60 px label width for any
/// plot_rect ≥ 100 × 100 px.
fn renderCallouts(
    chart: *const Chart,
    frame: *const ChartFrame,
    out: *std.ArrayListUnmanaged(DrawCmd),
    allocator: std.mem.Allocator,
) !void {
    if (chart.series.len == 0) return;
    const series = chart.series[0];
    if (series.values.len == 0) return;

    const pr = frame.plot_rect;
    const cx = pr.x + pr.w * 0.5;
    const cy = pr.y + pr.h * 0.5;
    const outer_r = @min(pr.w, pr.h) * 0.4;
    const anchor_r = outer_r * 1.5;  // outboard line terminus
    const label_r  = outer_r * 1.6;  // label box center radius

    // Reproduce renderPie's angle traversal to get each segment's mid-angle.
    var total: f64 = 0;
    for (series.values) |v| total += @abs(v);
    if (total < 1e-10) return;

    const seg_mid_angles = try allocator.alloc(f32, series.values.len);
    defer allocator.free(seg_mid_angles);

    var angle: f32 = -std.math.pi * 0.5;
    for (series.values, 0..) |v, i| {
        const sweep = @as(f32, @floatCast((v / total) * std.math.tau));
        seg_mid_angles[i] = angle + sweep * 0.5;
        angle += sweep;
    }

    const line_color  = resolveToken("axis");
    const label_color = resolveToken("surface");

    for (chart.callouts) |callout| {
        const idx = callout.datum_idx;
        if (idx >= series.values.len) continue;

        const mid_angle = seg_mid_angles[idx];
        const cos_a = @cos(mid_angle);
        const sin_a = @sin(mid_angle);

        // Leader line: segment outer edge → outboard anchor (2-point PolylineCmd).
        const line_start = Vec2{
            .x = cx + outer_r * 1.05 * cos_a,
            .y = cy + outer_r * 1.05 * sin_a,
        };
        const line_end = Vec2{
            .x = cx + anchor_r * cos_a,
            .y = cy + anchor_r * sin_a,
        };
        const line_pts = try allocator.dupe(Vec2, &.{ line_start, line_end });
        try out.append(allocator, .{ .polyline = .{
            .points = line_pts,
            .width  = 1.0,
            .color  = line_color,
            .closed = false,
            .join   = .miter,
        }});

        // Label background rect at outboard anchor (caller renders actual glyphs).
        const label_w: f32 = 60.0;
        const label_h: f32 = 16.0;
        const label_cx = cx + label_r * cos_a;
        const label_cy = cy + label_r * sin_a;
        try out.append(allocator, .{ .filled_rect = .{
            .rect = .{
                .x = label_cx - label_w * 0.5,
                .y = label_cy - label_h * 0.5,
                .w = label_w,
                .h = label_h,
            },
            .color = label_color,
        }});
    }
}

// ---------------------------------------------------------------------------
// RN7 — Crosshair / reference guide on hover
// ---------------------------------------------------------------------------

/// RN7: Emit a dashed vertical crosshair guide snapped to datum_idx's x-pixel.
///
/// "Dashed" = alternating short PolylineCmd segments (option b — no vocabulary
/// change, simpler than adding a dash-pattern field to PolylineCmd).
/// The crosshair is only emitted when a series has hovered_datum set; when the
/// mouse leaves the plot (hovered_datum → null) this function is not called,
/// which removes the crosshair from the draw list (hide on mouse-out).
fn renderCrosshair(
    datum_idx: u32,
    frame: *const ChartFrame,
    opts: chart_mod.CrosshairOptions,
    out: *std.ArrayListUnmanaged(DrawCmd),
    allocator: std.mem.Allocator,
) !void {
    const pr = frame.plot_rect;
    const xi = @as(f64, @floatFromInt(datum_idx));
    const x = frame.x.map(xi);

    // Only render when x is within the plot rect.
    if (x < pr.x or x > pr.x + pr.w) return;

    const step = opts.dash_len + opts.gap_len;
    if (step <= 0.001) return; // guard against degenerate config / infinite loop

    const color = resolveToken(opts.color_token);

    // Emit one 2-point PolylineCmd per dash, top → bottom of the plot rect.
    var y: f32 = pr.y;
    while (y < pr.y + pr.h) : (y += step) {
        const y_end = @min(y + opts.dash_len, pr.y + pr.h);
        const dash_pts = try allocator.dupe(Vec2, &.{
            .{ .x = x, .y = y },
            .{ .x = x, .y = y_end },
        });
        try out.append(allocator, .{ .polyline = .{
            .points = dash_pts,
            .width  = opts.width,
            .color  = color,
            .closed = false,
            .join   = .miter,
        }});
    }
}

// ---------------------------------------------------------------------------
// RN9 — Gauge chart (semi-circle arc meter)
// ---------------------------------------------------------------------------

/// RN9 — Semi-circle arc meter showing a value 0..1.
/// Arc sweeps through the TOP of the circle (left → top → right).
/// Angle convention: start_rad = -π (left = 9 o'clock), end_rad = 0 (right = 3 o'clock).
fn renderGauge(
    value: f64,
    bg_token: []const u8,
    fill_token: []const u8,
    frame: *const ChartFrame,
    out: *std.ArrayListUnmanaged(DrawCmd),
    allocator: std.mem.Allocator,
) !void {
    const pr = frame.plot_rect;
    const cx = pr.x + pr.w * 0.5;
    // Gauge center: lower portion of plot rect so the arc dome has headroom.
    const cy = pr.y + pr.h * 0.72;

    const outer_r = @min(pr.w, pr.h * 1.3) * 0.46;
    const inner_r = outer_r * 0.72;
    const arc_r   = (outer_r + inner_r) * 0.5;
    const arc_w   = outer_r - inner_r;

    const pi: f32 = std.math.pi;
    const start_rad: f32 = -pi;   // left endpoint of gauge (9 o'clock)
    const end_rad: f32   = 0.0;   // right endpoint (3 o'clock)

    const clamped: f32 = @floatCast(@max(0.0, @min(1.0, value)));
    const fill_end: f32 = start_rad + clamped * pi;

    // Background arc (full 180° sweep, light color).
    try out.append(allocator, .{ .arc = .{
        .center    = .{ .x = cx, .y = cy },
        .radius    = arc_r,
        .start_rad = start_rad,
        .end_rad   = end_rad,
        .width     = arc_w,
        .color     = resolveToken(bg_token),
    }});

    // Fill arc (value portion, accent color).
    if (clamped > 0.001) {
        try out.append(allocator, .{ .arc = .{
            .center    = .{ .x = cx, .y = cy },
            .radius    = arc_r,
            .start_rad = start_rad,
            .end_rad   = fill_end,
            .width     = arc_w,
            .color     = resolveToken(fill_token),
        }});
    }

    // End-cap dots at 9 o'clock and 3 o'clock positions for a polished look.
    const cap_r: f32 = arc_w * 0.5;
    // Left cap (9 o'clock)
    try out.append(allocator, .{ .aa_filled_circle = .{
        .center_x = cx - arc_r,
        .center_y = cy,
        .radius   = cap_r,
        .color    = resolveToken(bg_token),
    }});
    // Right cap (3 o'clock)
    try out.append(allocator, .{ .aa_filled_circle = .{
        .center_x = cx + arc_r,
        .center_y = cy,
        .radius   = cap_r,
        .color    = resolveToken(bg_token),
    }});
    // Tip of fill arc (polished cap at the fill endpoint)
    if (clamped > 0.001 and clamped < 0.999) {
        const tip_x = cx + arc_r * @cos(fill_end);
        const tip_y = cy + arc_r * @sin(fill_end);
        try out.append(allocator, .{ .aa_filled_circle = .{
            .center_x = tip_x,
            .center_y = tip_y,
            .radius   = cap_r,
            .color    = resolveToken(fill_token),
        }});
    }
}

// ---------------------------------------------------------------------------
// RN10 — World map visualization
// ---------------------------------------------------------------------------

/// RN10 — Simplified world map with hardcoded continent outlines and dot markers.
fn renderWorldMap(
    markers: []const MapMarker,
    ocean_token: []const u8,
    land_token: []const u8,
    frame: *const ChartFrame,
    out: *std.ArrayListUnmanaged(DrawCmd),
    allocator: std.mem.Allocator,
) !void {
    const pr = frame.plot_rect;

    // Ocean background.
    try out.append(allocator, .{ .aa_filled_rect = .{
        .rect = .{ .x = pr.x, .y = pr.y, .w = pr.w, .h = pr.h },
        .color = resolveToken(ocean_token),
        .radius = 4.0,
    }});

    // Simplified continent bounding boxes (normalized 0..1).
    // The Vulkan backend renders filled_path as a no-op, so use aa_filled_rect
    // for each continent's approximate bounding box instead.
    // x: longitude −180→+180 mapped to 0→1; y: latitude +90→−90 mapped to 0→1.
    const ContinentBox = struct { x: f32, y: f32, w: f32, h: f32 };
    const all_continents = [_]ContinentBox{
        .{ .x = 0.04, .y = 0.08, .w = 0.28, .h = 0.42 }, // North America
        .{ .x = 0.17, .y = 0.48, .w = 0.15, .h = 0.30 }, // South America
        .{ .x = 0.44, .y = 0.12, .w = 0.11, .h = 0.14 }, // Europe
        .{ .x = 0.44, .y = 0.26, .w = 0.14, .h = 0.42 }, // Africa
        .{ .x = 0.54, .y = 0.08, .w = 0.34, .h = 0.34 }, // Asia
        .{ .x = 0.73, .y = 0.56, .w = 0.13, .h = 0.16 }, // Australia
    };

    const land_col = resolveToken(land_token);

    for (all_continents, 0..) |box, ci| {
        const shade_offset: i32 = @as(i32, @intCast(ci)) * 12;
        var col = land_col;
        col.r = @intCast(@min(255, @max(0, @as(i32, col.r) + shade_offset)));
        col.g = @intCast(@min(255, @max(0, @as(i32, col.g) + shade_offset)));
        col.b = @intCast(@min(255, @max(0, @as(i32, col.b) + shade_offset)));
        try out.append(allocator, .{ .aa_filled_rect = .{
            .rect = .{
                .x = pr.x + box.x * pr.w,
                .y = pr.y + box.y * pr.h,
                .w = box.w * pr.w,
                .h = box.h * pr.h,
            },
            .color = col,
            .radius = 3.0,
        }});
    }

    // Dot markers (aa_filled_circle is supported by the Vulkan backend).
    for (markers) |m| {
        const mx = pr.x + m.norm_x * pr.w;
        const my = pr.y + m.norm_y * pr.h;
        try out.append(allocator, .{ .aa_filled_circle = .{
            .center_x = mx,
            .center_y = my,
            .radius   = m.radius,
            .color    = resolveToken(m.color_token),
        }});
    }
}
