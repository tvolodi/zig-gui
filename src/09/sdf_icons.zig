//! SDF icon definitions and atlas generation (RD3 — M13-04).
//!
//! Each built-in icon is defined by a set of line segments in normalized 0..1 space.
//! SDF generation computes per-pixel distance to the nearest stroke edge.
//! The result is a single-channel byte array (0=inside, 128=edge, 255=outside).

const std = @import("std");

// ---------------------------------------------------------------------------
// Icon definitions
// ---------------------------------------------------------------------------

pub const SdfIcon = enum(u8) {
    chevron_down,
    chevron_right,
    chevron_up,
    chevron_left,
    check,
    cross,
    search,
    menu,
    more,
    plus,
    minus,
};

/// Line segment in normalized 0..1 coordinate space within a 64×64 cell.
pub const IconSegment = struct {
    x0: f32,
    y0: f32,
    x1: f32,
    y1: f32,
};

pub const IconDef = struct {
    name: []const u8,
    /// Thickness of the stroke relative to the cell size.
    thickness: f32,
    segments: []const IconSegment,
};

pub const ICON_SIZE: u32 = 64;

/// Pre-computed SDF pixel data for each icon in the enum order.
/// Each icon is ICON_SIZE × ICON_SIZE grayscale bytes.
/// Caller must init and deinit the returned slice.
pub fn generateAllIcons(alloc: std.mem.Allocator) ![]u8 {
    const count: u32 = @intCast(std.meta.fields(SdfIcon).len);
    const total_bytes = count * ICON_SIZE * ICON_SIZE;
    const data = try alloc.alloc(u8, total_bytes);
    errdefer alloc.free(data);

    var offset: usize = 0;
    inline for (builtin_icons) |def| {
        const slice = data[offset..][0 .. ICON_SIZE * ICON_SIZE];
        generateSdf(def, slice);
        offset += ICON_SIZE * ICON_SIZE;
    }
    return data;
}

/// Generate SDF bitmap for one icon at ICON_SIZE × ICON_SIZE.
/// Result is packed into `out` which must be ICON_SIZE*ICON_SIZE bytes.
/// Encoding: 0 = deep inside stroke, 128 = edge, 255 = deep outside stroke.
pub fn generateSdf(def: IconDef, out: []u8) void {
    const size_f = @as(f32, @floatFromInt(ICON_SIZE));
    const half_thickness = def.thickness * 0.5;
    // max_dist controls sharpness: larger = softer edges.
    const max_dist: f32 = 0.25;

    var y: u32 = 0;
    while (y < ICON_SIZE) : (y += 1) {
        const ny = (@as(f32, @floatFromInt(y)) + 0.5) / size_f;
        var x: u32 = 0;
        while (x < ICON_SIZE) : (x += 1) {
            const nx = (@as(f32, @floatFromInt(x)) + 0.5) / size_f;

            // Compute minimum distance to all segments minus half thickness.
            // Negative = inside stroke, positive = outside.
            var min_d: f32 = 1e10;
            for (def.segments) |seg| {
                const d = pointToSegmentDist(nx, ny, seg.x0, seg.y0, seg.x1, seg.y1);
                min_d = @min(min_d, d);
            }
            const sdf = min_d - half_thickness;

            // Remap: sdf=0 → 0.5 → 128; clamp to [0, 1].
            const normalized = @max(0.0, @min(1.0, sdf / max_dist + 0.5));
            const byte: u8 = @intFromFloat(@round(normalized * 255.0));
            out[y * ICON_SIZE + x] = byte;
        }
    }
}

/// Euclidean distance from point (px,py) to line segment AB.
fn pointToSegmentDist(px: f32, py: f32, ax: f32, ay: f32, bx: f32, by: f32) f32 {
    const abx = bx - ax;
    const aby = by - ay;
    const len_sq = abx * abx + aby * aby;
    if (len_sq < 0.000001) {
        // Degenerate segment: distance to point.
        const dx = px - ax;
        const dy = py - ay;
        return @sqrt(dx * dx + dy * dy);
    }
    var t = ((px - ax) * abx + (py - ay) * aby) / len_sq;
    t = @max(0.0, @min(1.0, t));
    const proj_x = ax + t * abx;
    const proj_y = ay + t * aby;
    const dx = px - proj_x;
    const dy = py - proj_y;
    return @sqrt(dx * dx + dy * dy);
}

// ---------------------------------------------------------------------------
// Built-in icon paths
// ---------------------------------------------------------------------------

/// Build circle segments as a heap-allocated slice. Caller owns the memory.
/// Used at runtime by SdfAtlas.init() — not in static comptime data.
pub fn circleSegments(alloc: std.mem.Allocator, cx: f32, cy: f32, r: f32) ![]IconSegment {
    const tmp = [8]struct { x: f32, y: f32 }{
        .{ .x = cx + r, .y = cy },
        .{ .x = cx + r * 0.707, .y = cy + r * 0.707 },
        .{ .x = cx, .y = cy + r },
        .{ .x = cx - r * 0.707, .y = cy + r * 0.707 },
        .{ .x = cx - r, .y = cy },
        .{ .x = cx - r * 0.707, .y = cy - r * 0.707 },
        .{ .x = cx, .y = cy - r },
        .{ .x = cx + r * 0.707, .y = cy - r * 0.707 },
    };
    const segs = try alloc.alloc(IconSegment, 8);
    for (0..8) |i| {
        const j = (i + 1) % 8;
        segs[i] = .{ .x0 = tmp[i].x, .y0 = tmp[i].y, .x1 = tmp[j].x, .y1 = tmp[j].y };
    }
    return segs;
}

pub const builtin_icons = [_]IconDef{
    // chevron-down: V pointing down
    .{
        .name = "chevron-down",
        .thickness = 0.12,
        .segments = &[_]IconSegment{
            .{ .x0 = 0.20, .y0 = 0.30, .x1 = 0.50, .y1 = 0.70 },
            .{ .x0 = 0.50, .y0 = 0.70, .x1 = 0.80, .y1 = 0.30 },
        },
    },
    // chevron-right: > pointing right
    .{
        .name = "chevron-right",
        .thickness = 0.12,
        .segments = &[_]IconSegment{
            .{ .x0 = 0.30, .y0 = 0.20, .x1 = 0.70, .y1 = 0.50 },
            .{ .x0 = 0.70, .y0 = 0.50, .x1 = 0.30, .y1 = 0.80 },
        },
    },
    // chevron-up: ^ pointing up
    .{
        .name = "chevron-up",
        .thickness = 0.12,
        .segments = &[_]IconSegment{
            .{ .x0 = 0.20, .y0 = 0.70, .x1 = 0.50, .y1 = 0.30 },
            .{ .x0 = 0.50, .y0 = 0.30, .x1 = 0.80, .y1 = 0.70 },
        },
    },
    // chevron-left: < pointing left
    .{
        .name = "chevron-left",
        .thickness = 0.12,
        .segments = &[_]IconSegment{
            .{ .x0 = 0.70, .y0 = 0.20, .x1 = 0.30, .y1 = 0.50 },
            .{ .x0 = 0.30, .y0 = 0.50, .x1 = 0.70, .y1 = 0.80 },
        },
    },
    // check: checkmark ✓
    .{
        .name = "check",
        .thickness = 0.13,
        .segments = &[_]IconSegment{
            .{ .x0 = 0.80, .y0 = 0.22, .x1 = 0.38, .y1 = 0.62 },
            .{ .x0 = 0.38, .y0 = 0.62, .x1 = 0.15, .y1 = 0.42 },
        },
    },
    // cross: X
    .{
        .name = "cross",
        .thickness = 0.12,
        .segments = &[_]IconSegment{
            .{ .x0 = 0.22, .y0 = 0.22, .x1 = 0.78, .y1 = 0.78 },
            .{ .x0 = 0.78, .y0 = 0.22, .x1 = 0.22, .y1 = 0.78 },
        },
    },
    // search: magnifying glass (circle + handle)
    // Circle at (0.38, 0.38) radius 0.23 approximated with 8 segments.
    .{
        .name = "search",
        .thickness = 0.10,
        .segments = &[_]IconSegment{
            // Circle: 8 segments connecting 8 points around center (0.38, 0.38), r=0.23
            .{ .x0 = 0.610, .y0 = 0.380, .x1 = 0.543, .y1 = 0.543 }, // 0 -> pi/4
            .{ .x0 = 0.543, .y0 = 0.543, .x1 = 0.380, .y1 = 0.610 }, // pi/4 -> pi/2
            .{ .x0 = 0.380, .y0 = 0.610, .x1 = 0.217, .y1 = 0.543 }, // pi/2 -> 3pi/4
            .{ .x0 = 0.217, .y0 = 0.543, .x1 = 0.150, .y1 = 0.380 }, // 3pi/4 -> pi
            .{ .x0 = 0.150, .y0 = 0.380, .x1 = 0.217, .y1 = 0.217 }, // pi -> 5pi/4
            .{ .x0 = 0.217, .y0 = 0.217, .x1 = 0.380, .y1 = 0.150 }, // 5pi/4 -> 3pi/2
            .{ .x0 = 0.380, .y0 = 0.150, .x1 = 0.543, .y1 = 0.217 }, // 3pi/2 -> 7pi/4
            .{ .x0 = 0.543, .y0 = 0.217, .x1 = 0.610, .y1 = 0.380 }, // 7pi/4 -> 2pi

            // Handle: from bottom-right of circle to corner
            .{ .x0 = 0.56, .y0 = 0.56, .x1 = 0.85, .y1 = 0.85 },
        },
    },
    // menu: three horizontal lines (hamburger)
    .{
        .name = "menu",
        .thickness = 0.10,
        .segments = &[_]IconSegment{
            .{ .x0 = 0.15, .y0 = 0.24, .x1 = 0.85, .y1 = 0.24 },
            .{ .x0 = 0.15, .y0 = 0.50, .x1 = 0.85, .y1 = 0.50 },
            .{ .x0 = 0.15, .y0 = 0.76, .x1 = 0.85, .y1 = 0.76 },
        },
    },
    // more: three dots (vertical short segments = circles via stroke thickness)
    .{
        .name = "more",
        .thickness = 0.15,
        .segments = &[_]IconSegment{
            .{ .x0 = 0.20, .y0 = 0.48, .x1 = 0.20, .y1 = 0.52 },
            .{ .x0 = 0.50, .y0 = 0.48, .x1 = 0.50, .y1 = 0.52 },
            .{ .x0 = 0.80, .y0 = 0.48, .x1 = 0.80, .y1 = 0.52 },
        },
    },
    // plus
    .{
        .name = "plus",
        .thickness = 0.13,
        .segments = &[_]IconSegment{
            .{ .x0 = 0.20, .y0 = 0.50, .x1 = 0.80, .y1 = 0.50 },
            .{ .x0 = 0.50, .y0 = 0.20, .x1 = 0.50, .y1 = 0.80 },
        },
    },
    // minus
    .{
        .name = "minus",
        .thickness = 0.13,
        .segments = &[_]IconSegment{
            .{ .x0 = 0.22, .y0 = 0.50, .x1 = 0.78, .y1 = 0.50 },
        },
    },
};

test "generateSdf produces valid range for chevron-down" {
    var out: [64 * 64]u8 = undefined;
    generateSdf(builtin_icons[0], &out);

    // Verify: edge pixels should have values near 128.
    var edge_found = false;
    // Check a ring around the expected stroke positions.
    for (out) |b| {
        if (b >= 110 and b <= 150) {
            edge_found = true;
            break;
        }
    }
    try std.testing.expect(edge_found);

    // Verify: center of the V (0.5, 0.7) should be inside the stroke (< 128).
    const cy: u32 = @intFromFloat(0.70 * 64.0);
    const cx: u32 = @intFromFloat(0.50 * 64.0);
    const center_val = out[cy * 64 + cx];
    try std.testing.expect(center_val < 128);
}

test "generateSdf produces valid range for cross" {
    var out: [64 * 64]u8 = undefined;
    generateSdf(builtin_icons[5], &out); // cross

    // Center (0.5, 0.5) is where the two lines cross — should be inside stroke (< 128).
    const center_val = out[32 * 64 + 32];
    try std.testing.expect(center_val < 128);

    // Far corner (0, 0) should be outside stroke (> 128).
    const corner_val = out[4 * 64 + 4];
    try std.testing.expect(corner_val > 128);
}

test "builtin icons count matches enum" {
    try std.testing.expectEqual(builtin_icons.len, @typeInfo(SdfIcon).@"enum".fields.len);
}

test "generateAllIcons produces correct total size" {
    const data = try generateAllIcons(std.testing.allocator);
    defer std.testing.allocator.free(data);
    try std.testing.expectEqual(@as(usize, 11 * 64 * 64), data.len);
}

test "pointToSegmentDist" {
    // Point on segment.
    try std.testing.expect(@abs(pointToSegmentDist(0.5, 0.5, 0.0, 0.5, 1.0, 0.5)) < 0.0001);

    // Point perpendicularly offset by 0.1 from midpoint.
    try std.testing.expect(@abs(pointToSegmentDist(0.5, 0.6, 0.0, 0.5, 1.0, 0.5) - 0.1) < 0.0001);

    // Point at endpoint.
    try std.testing.expect(@abs(pointToSegmentDist(0.0, 0.0, 0.0, 0.0, 1.0, 0.0)) < 0.0001);

    // Degenerate segment (zero length).
    try std.testing.expect(@abs(pointToSegmentDist(0.3, 0.4, 0.5, 0.5, 0.5, 0.5) - @sqrt(0.04 + 0.01)) < 0.0001);
}
