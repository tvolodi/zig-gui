//! CPU tessellation for chart primitives — M26-01
const std = @import("std");
const types01 = @import("../01/types.zig");
const Vec2 = types01.Vec2;

/// Expand a polyline into a triangle strip (for rendering as a PolylineCmd).
/// Returns a slice of vertices suitable for a FilledPathCmd (the tessellated stroke).
pub fn tessellatePolyline(
    allocator: std.mem.Allocator,
    points: []const Vec2,
    width: f32,
    closed: bool,
) ![]Vec2 {
    if (points.len < 2) return &[_]Vec2{};
    const half_w = width * 0.5;
    // For each segment, emit 2 verts (left + right offset by half_w perpendicular)
    var verts: std.ArrayListUnmanaged(Vec2) = .empty;
    try verts.ensureTotalCapacity(allocator, points.len * 2);
    for (0..points.len) |i| {
        const p = points[i];
        const next = if (i + 1 < points.len) points[i + 1] else if (closed) points[0] else points[i];
        const prev = if (i > 0) points[i - 1] else if (closed) points[points.len - 1] else points[i];
        _ = prev;
        // Direction of this segment
        const dx = next.x - p.x;
        const dy = next.y - p.y;
        const len = @sqrt(dx * dx + dy * dy);
        if (len < 0.001) continue;
        const nx = -dy / len;  // normal (perpendicular)
        const ny =  dx / len;
        try verts.append(allocator, .{ .x = p.x + nx * half_w, .y = p.y + ny * half_w });
        try verts.append(allocator, .{ .x = p.x - nx * half_w, .y = p.y - ny * half_w });
    }
    // Cap the last pair
    if (!closed and points.len >= 2) {
        const p = points[points.len - 1];
        const prev = points[points.len - 2];
        const dx = p.x - prev.x;
        const dy = p.y - prev.y;
        const len = @sqrt(dx * dx + dy * dy);
        if (len > 0.001) {
            const nx = -dy / len;
            const ny =  dx / len;
            try verts.append(allocator, .{ .x = p.x + nx * half_w, .y = p.y + ny * half_w });
            try verts.append(allocator, .{ .x = p.x - nx * half_w, .y = p.y - ny * half_w });
        }
    }
    return verts.toOwnedSlice(allocator);
}

/// Triangulate a simple convex polygon (fan from first vertex).
/// Returns (vertices, indices) as owned slices.
pub fn triangulateConvex(
    allocator: std.mem.Allocator,
    points: []const Vec2,
) !struct { verts: []Vec2, indices: []u16 } {
    if (points.len < 3) return .{ .verts = &[_]Vec2{}, .indices = &[_]u16{} };
    const verts = try allocator.dupe(Vec2, points);
    const tri_count = points.len - 2;
    const indices = try allocator.alloc(u16, tri_count * 3);
    for (0..tri_count) |i| {
        indices[i * 3 + 0] = 0;
        indices[i * 3 + 1] = @intCast(i + 1);
        indices[i * 3 + 2] = @intCast(i + 2);
    }
    return .{ .verts = verts, .indices = indices };
}

/// Generate an arc (or wedge) as a polyline of points.
/// Used to build ArcCmd / FilledPathCmd from arc parameters.
pub fn arcToPoints(
    allocator: std.mem.Allocator,
    center: Vec2,
    radius: f32,
    start_rad: f32,
    end_rad: f32,
    segments: u32,
) ![]Vec2 {
    const seg = @max(segments, 3);
    const points = try allocator.alloc(Vec2, seg + 1);
    for (0..seg + 1) |i| {
        const t = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(seg));
        const angle = start_rad + t * (end_rad - start_rad);
        points[i] = .{
            .x = center.x + radius * @cos(angle),
            .y = center.y + radius * @sin(angle),
        };
    }
    return points;
}
