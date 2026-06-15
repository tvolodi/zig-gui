//! Chart component — M26-03
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

pub const Chart = struct {
    kind: ChartKind,
    series: []const Series,
    x: XData,

    pub fn render(
        self: *const Chart,
        frame: *const ChartFrame,
        out: *std.ArrayListUnmanaged(types01.DrawCommand),
        allocator: std.mem.Allocator,
    ) !void {
        return marks_mod.renderChart(self, frame, out, allocator);
    }
};
