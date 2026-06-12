//! R91 — Scene dump implementation.
//! Free functions called from Scene.debugPrint / Scene.debugPrintStats forwarding methods.
//! No heap allocation — uses a fixed 256-byte stack buffer per line written to stderr.

const std = @import("std");
const scene_mod = @import("types.zig");

const Scene = scene_mod.Scene;
const NONE: u32 = std.math.maxInt(u32);

/// Write a human-readable, indented element tree to stderr.
pub fn debugPrintScene(scene: *const Scene) void {
    const s = &scene.elements;
    const total = s.gen.items.len;
    if (total == 0) return;

    // Walk depth-first pre-order using a stack.  We track depth by following parent pointers.
    for (0..total) |i| {
        const idx = @as(u32, @intCast(i));
        const id = scene_mod.ElementId{ .index = idx, .gen = s.gen.items[idx] };
        if (!s.isValid(id)) continue;

        // Compute depth by walking parent chain.
        var depth: u32 = 0;
        var cur_id = id;
        while (s.parentOf(cur_id)) |par| {
            depth += 1;
            cur_id = par;
        }

        printElement(scene, idx, depth);
    }
}

/// Print one-line summary: live/total/dirty/focused.
pub fn debugPrintSceneStats(scene: *const Scene) void {
    const s = &scene.elements;
    const total = s.gen.items.len;

    // Count live elements.
    var live: u32 = 0;
    for (0..total) |i| {
        const idx = @as(u32, @intCast(i));
        const id = scene_mod.ElementId{ .index = idx, .gen = s.gen.items[idx] };
        if (s.isValid(id)) live += 1;
    }

    // Count dirty elements.
    var dirty_count: u32 = 0;
    if (s.dirty.bit_length > 0) {
        var bi: u32 = 0;
        while (bi < s.dirty.bit_length) : (bi += 1) {
            if (s.dirty.isSet(bi)) dirty_count += 1;
        }
    }

    const focused = scene.focused_idx;

    var buf: [256]u8 = undefined;
    const line = if (focused == NONE)
        std.fmt.bufPrint(&buf, "Scene: {d} live / {d} total elements, {d} dirty, focused=none\n", .{
            live, total, dirty_count,
        }) catch return
    else
        std.fmt.bufPrint(&buf, "Scene: {d} live / {d} total elements, {d} dirty, focused={d}\n", .{
            live, total, dirty_count, focused,
        }) catch return;

    std.debug.print("{s}", .{line});
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

fn printElement(scene: *const Scene, idx: u32, depth: u32) void {
    var buf: [256]u8 = undefined;
    var pos: usize = 0;

    // Indent: 2 spaces per depth level.
    const indent_spaces = depth * 2;
    var si: u32 = 0;
    while (si < indent_spaces and pos < buf.len - 1) : (si += 1) {
        buf[pos] = ' ';
        pos += 1;
    }

    // [<idx>]
    const idx_str = std.fmt.bufPrint(buf[pos..], "[{d}] ", .{idx}) catch return;
    pos += idx_str.len;
    if (pos >= buf.len - 4) {
        truncateAndFlush(&buf, pos);
        return;
    }

    // kind name
    const kind = if (idx < scene._kind.items.len) scene._kind.items[idx] else return;
    const kind_name = @tagName(kind);
    if (pos + kind_name.len + 1 < buf.len) {
        @memcpy(buf[pos..][0..kind_name.len], kind_name);
        pos += kind_name.len;
        buf[pos] = ' ';
        pos += 1;
    }
    if (pos >= buf.len - 4) {
        truncateAndFlush(&buf, pos);
        return;
    }

    // text_summary (only for .text elements)
    if (kind == .text) {
        if (idx < scene._text.items.len) {
            if (scene._text.items[idx]) |text_val| {
                buf[pos] = '"';
                pos += 1;
                const max_chars: usize = 24;
                const truncated = text_val.len > max_chars;
                const copy_len = @min(text_val.len, max_chars);
                if (pos + copy_len + 5 < buf.len) {
                    @memcpy(buf[pos..][0..copy_len], text_val[0..copy_len]);
                    pos += copy_len;
                    if (truncated) {
                        const ellip = "...";
                        @memcpy(buf[pos..][0..3], ellip);
                        pos += 3;
                    }
                    buf[pos] = '"';
                    pos += 1;
                    buf[pos] = ' ';
                    pos += 1;
                }
            }
        }
    }
    if (pos >= buf.len - 4) {
        truncateAndFlush(&buf, pos);
        return;
    }

    // Computed rect (x/y/w/h)
    if (idx < scene.elements.layout.items.len) {
        const rect = scene.elements.layout.items[idx].computed;
        const rect_str = std.fmt.bufPrint(buf[pos..], "x={d:.1} y={d:.1} w={d:.1} h={d:.1}  ", .{
            rect.x, rect.y, rect.w, rect.h,
        }) catch blk: {
            break :blk buf[pos..pos];
        };
        pos += rect_str.len;
    }
    if (pos >= buf.len - 4) {
        truncateAndFlush(&buf, pos);
        return;
    }

    // Style summary
    if (idx < scene._style.items.len) {
        const style = scene._style.items[idx];
        if (style.background.a > 0) {
            const s = std.fmt.bufPrint(buf[pos..], "bg=#{x:0>2}{x:0>2}{x:0>2} ", .{
                style.background.r, style.background.g, style.background.b,
            }) catch blk: {
                break :blk buf[pos..pos];
            };
            pos += s.len;
        }
        if (pos < buf.len - 4 and style.text_color.a > 0) {
            const s = std.fmt.bufPrint(buf[pos..], "text=#{x:0>2}{x:0>2}{x:0>2} ", .{
                style.text_color.r, style.text_color.g, style.text_color.b,
            }) catch blk: {
                break :blk buf[pos..pos];
            };
            pos += s.len;
        }
        if (pos < buf.len - 4 and style.border_width > 0) {
            const s = std.fmt.bufPrint(buf[pos..], "border={d:.0}px #{x:0>2}{x:0>2}{x:0>2} ", .{
                style.border_width,
                style.border_color.r,
                style.border_color.g,
                style.border_color.b,
            }) catch blk: {
                break :blk buf[pos..pos];
            };
            pos += s.len;
        }
        if (pos < buf.len - 4 and style.radius > 0) {
            const s = std.fmt.bufPrint(buf[pos..], "radius={d:.0} ", .{style.radius}) catch blk: {
                break :blk buf[pos..pos];
            };
            pos += s.len;
        }
        if (pos < buf.len - 4) {
            const s = std.fmt.bufPrint(buf[pos..], "font={d:.0}px ", .{style.font_size}) catch blk: {
                break :blk buf[pos..pos];
            };
            pos += s.len;
        }
    }
    if (pos >= buf.len - 4) {
        truncateAndFlush(&buf, pos);
        return;
    }

    // Flags
    const s = &scene.elements;
    const id = scene_mod.ElementId{ .index = idx, .gen = s.gen.items[idx] };
    _ = id;
    const is_dirty = if (idx < s.dirty.bit_length) s.dirty.isSet(idx) else false;
    const is_focused = (scene.focused_idx == idx);
    const is_hidden = scene.isHidden(idx);

    if (is_dirty and pos + 8 < buf.len) {
        const sl = "(dirty) ";
        @memcpy(buf[pos..][0..sl.len], sl);
        pos += sl.len;
    }
    if (is_focused and pos + 10 < buf.len) {
        const sl = "(focused) ";
        @memcpy(buf[pos..][0..sl.len], sl);
        pos += sl.len;
    }
    if (is_hidden and pos + 9 < buf.len) {
        const sl = "(hidden) ";
        @memcpy(buf[pos..][0..sl.len], sl);
        pos += sl.len;
    }

    if (pos < buf.len - 1) {
        buf[pos] = '\n';
        pos += 1;
    }

    std.debug.print("{s}", .{buf[0..pos]});
}

fn truncateAndFlush(buf: *[256]u8, pos: usize) void {
    const end = @min(pos, 253);
    buf[end] = '.';
    buf[end + 1] = '.';
    buf[end + 2] = '.';
    std.debug.print("{s}", .{buf[0 .. end + 3]});
}
