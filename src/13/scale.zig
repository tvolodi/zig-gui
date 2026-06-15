//! Chart scales — M26-02
const std = @import("std");

pub const Tick = struct {
    value: f64,
    label: []const u8,  // formatted label (caller owns if heap-allocated)
};

pub const Scale = union(enum) {
    linear: struct { domain_min: f64, domain_max: f64, range_min: f32, range_max: f32 },
    log:    struct { domain_min: f64, domain_max: f64, range_min: f32, range_max: f32 },
    band:   struct { categories: []const []const u8, range_min: f32, range_max: f32, padding: f32 },
    time:   struct { t_min: i64, t_max: i64, range_min: f32, range_max: f32 },

    pub fn map(self: Scale, value: f64) f32 {
        return switch (self) {
            .linear => |s| blk: {
                const span = s.domain_max - s.domain_min;
                if (@abs(span) < 1e-10) break :blk s.range_min;
                const t = @as(f32, @floatCast((value - s.domain_min) / span));
                break :blk s.range_min + t * (s.range_max - s.range_min);
            },
            .log => |s| blk: {
                if (value <= 0 or s.domain_min <= 0 or s.domain_max <= 0) break :blk s.range_min;
                const log_min = @log(s.domain_min);
                const log_max = @log(s.domain_max);
                const span = log_max - log_min;
                if (@abs(span) < 1e-10) break :blk s.range_min;
                const t = @as(f32, @floatCast((@log(value) - log_min) / span));
                break :blk s.range_min + t * (s.range_max - s.range_min);
            },
            .band => |s| blk: {
                if (s.categories.len == 0) break :blk s.range_min;
                const n = @as(f32, @floatFromInt(s.categories.len));
                const band_w = (s.range_max - s.range_min) / n;
                const idx = @as(f32, @floatCast(value));
                break :blk s.range_min + idx * band_w + band_w * (0.5 + s.padding * 0.5);
            },
            .time => |s| blk: {
                const span = s.t_max - s.t_min;
                if (span == 0) break :blk s.range_min;
                const t = @as(f32, @floatCast((value - @as(f64, @floatFromInt(s.t_min))) / @as(f64, @floatFromInt(span))));
                break :blk s.range_min + t * (s.range_max - s.range_min);
            },
        };
    }

    pub fn invert(self: Scale, pixel: f32) f64 {
        return switch (self) {
            .linear => |s| blk: {
                const range_span = s.range_max - s.range_min;
                if (@abs(range_span) < 1e-6) break :blk s.domain_min;
                const t = @as(f64, @floatCast((pixel - s.range_min) / range_span));
                break :blk s.domain_min + t * (s.domain_max - s.domain_min);
            },
            .log => |s| blk: {
                const range_span = s.range_max - s.range_min;
                if (@abs(range_span) < 1e-6) break :blk s.domain_min;
                const t = @as(f64, @floatCast((pixel - s.range_min) / range_span));
                const log_min = @log(s.domain_min);
                const log_max = @log(s.domain_max);
                break :blk @exp(log_min + t * (log_max - log_min));
            },
            .band => |s| blk: {
                if (s.categories.len == 0) break :blk 0;
                const n = @as(f32, @floatFromInt(s.categories.len));
                const band_w = (s.range_max - s.range_min) / n;
                break :blk @as(f64, @floatCast((pixel - s.range_min) / band_w));
            },
            .time => |s| blk: {
                const range_span = s.range_max - s.range_min;
                if (@abs(range_span) < 1e-6) break :blk @as(f64, @floatFromInt(s.t_min));
                const t = @as(f64, @floatCast((pixel - s.range_min) / range_span));
                break :blk @as(f64, @floatFromInt(s.t_min)) + t * @as(f64, @floatFromInt(s.t_max - s.t_min));
            },
        };
    }

    /// Generate "nice" tick values for the scale.
    pub fn ticks(self: Scale, target_count: u32, allocator: std.mem.Allocator) ![]Tick {
        return switch (self) {
            .linear => |s| linearTicks(s.domain_min, s.domain_max, target_count, allocator),
            .log    => |s| logTicks(s.domain_min, s.domain_max, target_count, allocator),
            .band   => |s| bandTicks(s.categories, allocator),
            .time   => |s| timeTicks(s.t_min, s.t_max, target_count, allocator),
        };
    }
};

fn niceStep(rough_step: f64) f64 {
    const exp = @floor(@log10(rough_step));
    const frac = rough_step / std.math.pow(f64, 10.0, exp);
    const nice_frac: f64 = if (frac < 1.5) 1.0
        else if (frac < 3.0) 2.0
        else if (frac < 7.0) 5.0
        else 10.0;
    return nice_frac * std.math.pow(f64, 10.0, exp);
}

fn linearTicks(domain_min: f64, domain_max: f64, target_count: u32, allocator: std.mem.Allocator) ![]Tick {
    if (target_count == 0) return &[_]Tick{};
    const rough_step = (domain_max - domain_min) / @as(f64, @floatFromInt(target_count));
    const step = niceStep(@abs(rough_step));
    if (step < 1e-15) return &[_]Tick{};
    const start = @ceil(domain_min / step) * step;
    var values: std.ArrayListUnmanaged(Tick) = .empty;
    var v = start;
    while (v <= domain_max + step * 0.01) : (v += step) {
        const label = try std.fmt.allocPrint(allocator, "{d:.4}", .{v});
        try values.append(allocator, .{ .value = v, .label = label });
        if (values.items.len > 100) break; // safety
    }
    return values.toOwnedSlice(allocator);
}

fn logTicks(domain_min: f64, domain_max: f64, target_count: u32, allocator: std.mem.Allocator) ![]Tick {
    _ = target_count;
    var values: std.ArrayListUnmanaged(Tick) = .empty;
    var magnitude = @ceil(@log10(domain_min));
    while (std.math.pow(f64, 10.0, magnitude) <= domain_max) : (magnitude += 1.0) {
        const v = std.math.pow(f64, 10.0, magnitude);
        const label = try std.fmt.allocPrint(allocator, "10^{d:.0}", .{magnitude});
        try values.append(allocator, .{ .value = v, .label = label });
        if (values.items.len > 20) break;
    }
    return values.toOwnedSlice(allocator);
}

fn bandTicks(categories: []const []const u8, allocator: std.mem.Allocator) ![]Tick {
    const result = try allocator.alloc(Tick, categories.len);
    for (categories, 0..) |cat, i| {
        result[i] = .{ .value = @floatFromInt(i), .label = cat };
    }
    return result;
}

fn timeTicks(t_min: i64, t_max: i64, target_count: u32, allocator: std.mem.Allocator) ![]Tick {
    _ = target_count;
    const span_s = t_max - t_min;
    // Simple: divide into at most 6 steps
    const steps: i64 = 6;
    const step = @divTrunc(span_s, steps);
    var values: std.ArrayListUnmanaged(Tick) = .empty;
    var t: i64 = t_min;
    while (t <= t_max) : (t += if (step > 0) step else 1) {
        const label = try std.fmt.allocPrint(allocator, "t={d}", .{t});
        try values.append(allocator, .{ .value = @floatFromInt(t), .label = label });
        if (values.items.len > 20) break;
        if (step <= 0) break;
    }
    return values.toOwnedSlice(allocator);
}
