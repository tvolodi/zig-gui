//! Chart component — M26-03 / M27 RN1 RN2 RN7
const std = @import("std");
const scale_mod = @import("scale.zig");
const axes_mod = @import("axes.zig");
const marks_mod = @import("marks.zig");
const types01 = @import("../01/types.zig");

pub const ChartKind = enum { line, bar, area, scatter, pie };
pub const Scale = scale_mod.Scale;
pub const ChartFrame = axes_mod.ChartFrame;

pub const XData = union(enum) {
    categories: []const []const u8,
    numeric: []const f64,
    time: []const i64,
};

pub const Series = struct {
    name: []const u8,
    values: []const f64,
    color_token: []const u8,  // semantic palette token — NOT a raw color (INV-4.3)
    visible: bool = true,
    hovered_datum: ?u32 = null,
    selected_datum: ?u32 = null,
};

/// RN2 — Annotation callout bound to a datum index.
/// For pie charts: datum_idx is the segment (value) index in the primary series.
/// Rendered as a PolylineCmd leader line from the segment outer edge to an outboard
/// label box (filled_rect background at the computed anchor point).
pub const Callout = struct {
    datum_idx: u32,
    label: []const u8,
};

/// RN7 — Crosshair / reference guide shown when any series has a hovered datum.
/// Rendered as alternating short PolylineCmd segments (dashed vertical line).
/// No draw-command vocabulary change — uses existing PolylineCmd (INV-2.1-v2).
pub const CrosshairOptions = struct {
    /// Enable crosshair rendering.
    enabled: bool = false,
    /// Semantic color token for the crosshair line (INV-4.3).
    color_token: []const u8 = "axis",
    /// Length of each visible dash segment in pixels.
    dash_len: f32 = 6.0,
    /// Length of each gap between dashes in pixels.
    gap_len: f32 = 4.0,
    /// Stroke width of the crosshair line.
    width: f32 = 1.0,
};

pub const Chart = struct {
    kind: ChartKind,
    series: []const Series,
    x: XData,
    /// RN1 — Donut inner radius as a fraction of outer radius.
    /// 0.0 = filled pie (backward compat); range (0, 1) = ring/donut.
    inner_radius: f32 = 0.0,
    /// RN1 — Optional label slot for the donut hole center.
    /// When set and inner_radius > 0, renderPie emits an aa_filled_circle background;
    /// the caller renders the actual glyphs (same pattern as drawLegend / INV-4.3).
    center_label: ?[]const u8 = null,
    /// RN2 — annotation callouts; for pie charts each entry emits one leader line.
    callouts: []const Callout = &.{},
    /// RN7 — optional crosshair guide (ignored when .enabled = false).
    crosshair: CrosshairOptions = .{},

    pub fn render(
        self: *const Chart,
        frame: *const ChartFrame,
        out: *std.ArrayListUnmanaged(types01.DrawCommand),
        allocator: std.mem.Allocator,
    ) !void {
        return marks_mod.renderChart(self, frame, out, allocator);
    }
};
