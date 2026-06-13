//! 04 — Layout engine — types.zig  (reconciled with module 03)
//!
//! This file IS the contract (INV-5.1). The layout engine's only public entry point is
//! `solve`. Match its signature exactly; implement the body per spec.md.
//!
//! RECONCILIATION NOTE: the element + geometry types (Rect, Size, Constraints, Insets,
//! Dimension, TrackSize, Display, FlexDirection, JustifyContent, AlignItems, LayoutNode)
//! are owned by module 03 (the ElementStore physically stores LayoutNode, and module 03
//! may not depend on a higher-numbered module — INV-3.4 build order). This module IMPORTS
//! them and re-exports for convenience. Do NOT redefine them here.

const std = @import("std");
const store = @import("../03_element_store/types.zig");

// Re-exports (convenience; canonical definitions live in module 03).
pub const ElementId = store.ElementId;
pub const ElementStore = store.ElementStore;
pub const Rect = store.Rect;
pub const Size = store.Size;
pub const Constraints = store.Constraints;
pub const Insets = store.Insets;
pub const Dimension = store.Dimension;
pub const TrackSize = store.TrackSize;
pub const Display = store.Display;
pub const FlexDirection = store.FlexDirection;
pub const JustifyContent = store.JustifyContent;
pub const AlignItems = store.AlignItems;
pub const AlignSelf = store.AlignSelf;
pub const MarginValue = store.MarginValue;
pub const Margin = store.Margin;
pub const LayoutNode = store.LayoutNode;
pub const Position = store.Position;
pub const Direction = store.Direction;

// ---------------------------------------------------------------------------
// Public API — the single entry point (INV-5.1)
// ---------------------------------------------------------------------------

/// Compute the layout of the subtree rooted at `root`, filling every reachable node's
/// `computed` rectangle. Deterministic: identical inputs produce byte-identical outputs.
///
/// `scratch` is a caller-owned reusable buffer (typically arena-backed). solve() must NOT
/// allocate per-node; it may only use `scratch`. See spec.md "Performance intent".
///
/// `dpi_scale` is the HiDPI display scale factor from the primary monitor (default 1.0).
/// All explicit px values (width, height, padding, margin, gap, insets) are multiplied by
/// `dpi_scale` and rounded to the nearest integer pixel so the layout engine operates in
/// physical pixels.
///
/// Children are resolved via `store.childrenOf(id)` (module 03).
pub fn solve(
    s: *ElementStore,
    root: ElementId,
    available: Constraints,
    scratch: []u8,
    dpi_scale: f32,
) void {
    _ = scratch; // scratch is available if needed for iterative traversal
    _ = solveNode(s, root, available, 0.0, 0.0, dpi_scale);
}

// ---------------------------------------------------------------------------
// Internal implementation
// ---------------------------------------------------------------------------

/// Resolve a Dimension value to a concrete pixel size.
/// parent_size is the available parent content-box size on this axis.
/// constraint_min / constraint_max clamp the result.
fn resolveDimension(dim: Dimension, parent_size: f32, constraint_min: f32, constraint_max: f32, dpi_scale: f32) f32 {
    const raw: f32 = switch (dim) {
        .px => |v| @round(v * dpi_scale),
        .percent => |v| parent_size * (v / 100.0),
        .auto => 0.0,
    };
    return std.math.clamp(raw, constraint_min, constraint_max);
}

/// Resolve a node's own width given available constraints and parent content width.
fn resolveWidth(node: *const LayoutNode, avail: Constraints, parent_w: f32, dpi_scale: f32) f32 {
    const v = resolveDimension(node.width, parent_w, avail.min_w, avail.max_w, dpi_scale);
    return std.math.clamp(v, node.min_size.w, node.max_size.w);
}

/// Resolve a node's own height given available constraints and parent content height.
fn resolveHeight(node: *const LayoutNode, avail: Constraints, parent_h: f32, dpi_scale: f32) f32 {
    const v = resolveDimension(node.height, parent_h, avail.min_h, avail.max_h, dpi_scale);
    return std.math.clamp(v, node.min_size.h, node.max_size.h);
}

/// Recursively compute the layout of node `id`, placing it at (origin_x, origin_y).
/// Returns the computed Size for the node.
///
/// Depth bound: each stack frame is ~200 bytes. On Windows/Linux the default thread
/// stack is 1–8 MB, giving a safe recursion depth of 4000–40 000 levels — well above
/// the spec's required minimum of 64. The practical UI tree depth is far below 64.
fn solveNode(
    s: *ElementStore,
    id: ElementId,
    avail: Constraints,
    origin_x: f32,
    origin_y: f32,
    dpi_scale: f32,
) Size {
    // R51: display = .none → zero rect, skip children entirely.
    if (s.get(id).display == .none) {
        s.get(id).computed = Rect{ .x = origin_x, .y = origin_y, .w = 0, .h = 0 };
        return Size{ .w = 0, .h = 0 };
    }

    // Resolve node's own size
    const node_w = resolveWidth(s.get(id), avail, avail.max_w, dpi_scale);
    const node_h_raw = resolveHeight(s.get(id), avail, avail.max_h, dpi_scale);
    // For block elements with height=auto (resolves to 0), use measured height as
    // the intrinsic size so Text/Button nodes get their natural content height.
    const node_h_pre_ar = blk: {
        const disp_check = s.get(id).display;
        if (disp_check == .block and node_h_raw == 0) {
            if (s.get(id).measured) |m| break :blk m.h;
        }
        break :blk node_h_raw;
    };

    // Clamp to non-negative and enforce parent's minimum constraints.
    // avail.min_w/min_h come from the parent (e.g. stretch in block/flex) and must be honoured.
    const w = @max(avail.min_w, node_w);

    // M12 RC3 — aspect ratio: if aspect_ratio > 0 and height is .auto, derive height from width.
    // Only applies when the explicit height field is .auto (resolves to 0).
    const h_pre_clamp: f32 = if (s.get(id).aspect_ratio > 0 and s.get(id).height == .auto)
        w / s.get(id).aspect_ratio
    else
        node_h_pre_ar;
    const h = @max(avail.min_h, h_pre_clamp);

    // Determine display type and lay out children
    const disp = s.get(id).display;
    const result: Size = switch (disp) {
        .block => solveBlock(s, id, w, h, origin_x, origin_y, avail, dpi_scale),
        .flex => solveFlex(s, id, w, h, origin_x, origin_y, avail, dpi_scale),
        .grid => solveGrid(s, id, w, h, origin_x, origin_y, avail, dpi_scale),
        .none => unreachable, // handled above
    };

    // Write computed rect for this node
    s.get(id).computed = Rect{
        .x = origin_x,
        .y = origin_y,
        .w = result.w,
        .h = result.h,
    };

    return result;
}

// ---------------------------------------------------------------------------
// Block layout: children stacked vertically, full width
// ---------------------------------------------------------------------------

/// Resolve a MarginValue to a concrete pixel amount (auto → 0 here; auto is handled specially).
fn resolveMarginPx(mv: MarginValue, dpi_scale: f32) f32 {
    return switch (mv) {
        .zero => 0.0,
        .px => |v| @round(v * dpi_scale),
        .auto => 0.0,
    };
}

fn solveBlock(
    s: *ElementStore,
    id: ElementId,
    container_w: f32,
    container_h: f32,
    origin_x: f32,
    origin_y: f32,
    avail: Constraints,
    dpi_scale: f32,
) Size {
    _ = avail;
    const padding_raw = s.get(id).padding;
    const padding = Insets{
        .top = @round(padding_raw.top * dpi_scale),
        .right = @round(padding_raw.right * dpi_scale),
        .bottom = @round(padding_raw.bottom * dpi_scale),
        .left = @round(padding_raw.left * dpi_scale),
    };
    const content_w = @max(0.0, container_w - padding.left - padding.right);

    var cursor_y: f32 = origin_y + padding.top;
    var total_content_h: f32 = 0.0;

    // First pass: normal-flow children only (skip absolute).
    var it = s.childrenOf(id);
    while (it.next()) |child_id| {
        // M12 RC0: skip absolutely-positioned children in normal flow.
        if (s.get(child_id).position == .absolute) continue;

        const content_h = @max(0.0, container_h - padding.top - padding.bottom);
        const child = s.get(child_id);
        const child_margin = child.margin;

        // R51: margin.px — subtract from available width
        const margin_left_px = resolveMarginPx(child_margin.left, dpi_scale);
        const margin_right_px = resolveMarginPx(child_margin.right, dpi_scale);
        const margin_top_px = resolveMarginPx(child_margin.top, dpi_scale);
        const margin_bottom_px = resolveMarginPx(child_margin.bottom, dpi_scale);

        // Available width for the child after its own margins
        const child_content_w = @max(0.0, content_w - margin_left_px - margin_right_px);

        // For overflow:hidden containers (ScrollView) children may grow taller than the
        // viewport — the clip happens at render time, not layout time. Let height be free.
        const is_scroll = s.get(id).overflow == .hidden;
        const child_avail = Constraints{
            .min_w = child_content_w,
            .max_w = child_content_w,
            .min_h = if (is_scroll) 0.0 else content_h,
            .max_h = if (is_scroll) std.math.inf(f32) else if (content_h > 0) content_h else std.math.inf(f32),
        };

        // Determine x offset: mx-auto centers the child
        const child_offset_x = blk: {
            if (child_margin.left == .auto and child_margin.right == .auto) {
                // mx-auto: resolve child width first without placing
                const cw = resolveWidth(s.get(child_id), child_avail, child_content_w, dpi_scale);
                break :blk (content_w - cw) / 2.0;
            } else {
                break :blk margin_left_px;
            }
        };

        const child_size = solveNode(
            s, child_id, child_avail,
            origin_x + padding.left + child_offset_x,
            cursor_y + margin_top_px,
            dpi_scale,
        );
        cursor_y += child_size.h + margin_top_px + margin_bottom_px;
        total_content_h += child_size.h + margin_top_px + margin_bottom_px;
    }

    // Height: if declared, use it; otherwise content-driven
    const actual_h = if (container_h > 0) container_h else total_content_h + padding.top + padding.bottom;

    // Write container rect before second pass so absolute children can read it.
    s.get(id).computed = Rect{ .x = origin_x, .y = origin_y, .w = container_w, .h = actual_h };

    // M12 RC0: Second pass — place absolutely-positioned children.
    placeAbsoluteChildren(s, id, origin_x, origin_y, container_w, actual_h, dpi_scale);

    return Size{ .w = container_w, .h = actual_h };
}

/// M12 RC0 — Place all direct children with position == .absolute within their containing block.
/// The containing block is `(cb_x, cb_y, cb_w, cb_h)` (the parent's computed rect).
fn placeAbsoluteChildren(
    s: *ElementStore,
    id: ElementId,
    cb_x: f32,
    cb_y: f32,
    cb_w: f32,
    cb_h: f32,
    dpi_scale: f32,
) void {
    var it = s.childrenOf(id);
    while (it.next()) |child_id| {
        if (s.get(child_id).position != .absolute) continue;

        const child = s.get(child_id);

        // Resolve insets (.auto → 0 as unset).  Multiply px values by dpi_scale.
        const inset_left:   f32 = switch (child.inset_left)   { .px => |v| @round(v * dpi_scale), else => 0 };
        const inset_right:  f32 = switch (child.inset_right)  { .px => |v| @round(v * dpi_scale), else => 0 };
        const inset_top:    f32 = switch (child.inset_top)    { .px => |v| @round(v * dpi_scale), else => 0 };
        const inset_bottom: f32 = switch (child.inset_bottom) { .px => |v| @round(v * dpi_scale), else => 0 };

        const left_set  = child.inset_left  != .auto;
        const right_set = child.inset_right != .auto;
        const top_set   = child.inset_top   != .auto;
        const bottom_set = child.inset_bottom != .auto;

        // Resolve width
        const child_w: f32 = switch (child.width) {
            .px => |v| @round(v * dpi_scale),
            .percent => |v| cb_w * (v / 100.0),
            .auto => if (left_set and right_set)
                @max(0.0, cb_w - inset_left - inset_right)
            else if (child.measured) |m| m.w
            else 0.0,
        };

        // Resolve height
        const child_h: f32 = switch (child.height) {
            .px => |v| @round(v * dpi_scale),
            .percent => |v| cb_h * (v / 100.0),
            .auto => if (top_set and bottom_set)
                @max(0.0, cb_h - inset_top - inset_bottom)
            else if (child.measured) |m| m.h
            else 0.0,
        };

        // Position: inset_right places right edge N px from containing block right.
        const child_x: f32 = if (left_set)
            cb_x + inset_left
        else if (right_set)
            cb_x + cb_w - inset_right - child_w
        else
            cb_x;

        const child_y: f32 = if (top_set)
            cb_y + inset_top
        else if (bottom_set)
            cb_y + cb_h - inset_bottom - child_h
        else
            cb_y;

        const child_avail = Constraints{
            .min_w = child_w,
            .max_w = child_w,
            .min_h = child_h,
            .max_h = child_h,
        };

        _ = solveNode(s, child_id, child_avail, child_x, child_y, dpi_scale);
    }
}

// ---------------------------------------------------------------------------
// Flex layout
// ---------------------------------------------------------------------------

/// Maximum children we support in a flex container (scratch-budget safe for 4096 bytes)
const MAX_FLEX_CHILDREN = 128;

/// Per-child data computed during flex layout
const FlexChildData = struct {
    id: ElementId,
    base_size: f32, // main-axis base size after flex_basis resolution
    final_size: f32, // main-axis final size after grow/shrink
    cross_size: f32, // cross-axis size
};

fn solveFlex(
    s: *ElementStore,
    id: ElementId,
    container_w: f32,
    container_h: f32,
    origin_x: f32,
    origin_y: f32,
    avail: Constraints,
    dpi_scale: f32,
) Size {
    _ = avail;
    const node = s.get(id);
    const padding_raw = node.padding;
    const padding = Insets{
        .top = @round(padding_raw.top * dpi_scale),
        .right = @round(padding_raw.right * dpi_scale),
        .bottom = @round(padding_raw.bottom * dpi_scale),
        .left = @round(padding_raw.left * dpi_scale),
    };
    const direction = node.direction;
    const gap = @round(node.gap * dpi_scale);
    const justify = node.justify_content;
    const align_items_val = node.align_items;
    const do_wrap = node.flex_wrap and direction == .row; // RC2: wrap only for row direction

    // Content box dimensions
    const content_w = @max(0.0, container_w - padding.left - padding.right);
    const content_h = @max(0.0, container_h - padding.top - padding.bottom);

    // Main and cross dimensions depend on direction
    const main_size: f32 = if (direction == .row) content_w else content_h;
    const cross_size: f32 = if (direction == .row) content_h else content_w;

    // --- Phase 1: collect children and compute base sizes ---
    // We use a fixed-size stack array (no heap allocation)
    var children_buf: [MAX_FLEX_CHILDREN]FlexChildData = undefined;
    var n: usize = 0;

    {
        var it = s.childrenOf(id);
        while (it.next()) |child_id| {
            if (n >= MAX_FLEX_CHILDREN) break;
            // M12 RC0: skip absolutely-positioned children in normal flex flow.
            if (s.get(child_id).position == .absolute) continue;
            const child = s.get(child_id);
            const flex_basis = child.flex_basis;

            // Resolve flex_basis on main axis
            var base: f32 = switch (flex_basis) {
                .px => |v| @round(v * dpi_scale),
                .percent => |v| main_size * (v / 100.0),
                .auto => blk: {
                    // Fall back to declared width (row) or height (column).
                    // When the declared dimension is also auto, use measured intrinsic size.
                    const dim = if (direction == .row) child.width else child.height;
                    break :blk switch (dim) {
                        .px => |v| @round(v * dpi_scale),
                        .percent => |v| main_size * (v / 100.0),
                        .auto => if (child.measured) |m|
                            if (direction == .row)
                                m.w + @round(child.padding.left * dpi_scale) + @round(child.padding.right * dpi_scale)
                            else
                                m.h + @round(child.padding.top * dpi_scale) + @round(child.padding.bottom * dpi_scale)
                        else
                            0.0,
                    };
                },
            };

            // Clamp to child min/max on main axis
            const child_min_main = if (direction == .row) child.min_size.w else child.min_size.h;
            const child_max_main = if (direction == .row) child.max_size.w else child.max_size.h;
            base = std.math.clamp(base, child_min_main, child_max_main);

            // Resolve cross-axis size
            var cross: f32 = if (direction == .row) blk: {
                // For row, cross is height
                break :blk switch (child.height) {
                    .px => |v| @round(v * dpi_scale),
                    .percent => |v| cross_size * (v / 100.0),
                    .auto => if (child.measured) |m| m.h else 0.0,
                };
            } else blk: {
                // For column, cross is width
                break :blk switch (child.width) {
                    .px => |v| @round(v * dpi_scale),
                    .percent => |v| cross_size * (v / 100.0),
                    .auto => if (child.measured) |m| m.w else 0.0,
                };
            };

            // R51: align_self overrides parent's align_items for this child
            const effective_align: AlignItems = switch (child.align_self) {
                .auto => align_items_val,
                .start => .start,
                .center => .center,
                .end => .end,
                .stretch => .stretch,
            };

            // stretch alignment overrides cross size to fill container.
            // Only applies when the container has a definite (non-zero) cross size;
            // when cross_size == 0 the container is auto-sized and we must preserve
            // the child's intrinsic size so max_child_cross can drive auto-height.
            if (effective_align == .stretch and cross_size > 0) {
                cross = cross_size;
            }

            // Clamp cross to child min/max
            const child_min_cross = if (direction == .row) child.min_size.h else child.min_size.w;
            const child_max_cross = if (direction == .row) child.max_size.h else child.max_size.w;
            cross = std.math.clamp(cross, child_min_cross, child_max_cross);

            children_buf[n] = FlexChildData{
                .id = child_id,
                .base_size = base,
                .final_size = base,
                .cross_size = cross,
            };
            n += 1;
        }
    }

    const children = children_buf[0..n];

    // --- Phase 2: distribute free space ---
    if (n > 0) {
        // Total base sizes + gaps
        var total_base: f32 = 0.0;
        for (children) |c| total_base += c.base_size;
        const gap_total: f32 = gap * @as(f32, @floatFromInt(n - 1));
        const free_space = main_size - total_base - gap_total;

        if (free_space > 0.0) {
            // Distribute to growing children
            var total_grow: f32 = 0.0;
            for (children) |c| {
                total_grow += s.get(c.id).flex_grow;
            }
            if (total_grow > 0.0) {
                for (children) |*c| {
                    const fg = s.get(c.id).flex_grow;
                    if (fg > 0.0) {
                        const child = s.get(c.id);
                        const child_max_main = if (direction == .row) child.max_size.w else child.max_size.h;
                        const extra = (fg / total_grow) * free_space;
                        c.final_size = @min(c.base_size + extra, child_max_main);
                    }
                }
            }
        } else if (free_space < 0.0) {
            // Shrink children that allow it
            var total_shrink_weighted: f32 = 0.0;
            for (children) |c| {
                const fs = s.get(c.id).flex_shrink;
                total_shrink_weighted += fs * c.base_size;
            }
            if (total_shrink_weighted > 0.0) {
                const overflow = -free_space;
                for (children) |*c| {
                    const child = s.get(c.id);
                    const fs = child.flex_shrink;
                    if (fs > 0.0) {
                        const weight = fs * c.base_size;
                        const shrink_amount = (weight / total_shrink_weighted) * overflow;
                        const child_min_main = if (direction == .row) child.min_size.w else child.min_size.h;
                        c.final_size = @max(c.base_size - shrink_amount, child_min_main);
                    }
                }
            }
        }
    }

    // --- Phase 3: place children ---

    // M12 RC2: flex-wrap path (row direction only).
    if (do_wrap) {
        const actual_size = solveFlexWrap(s, id, children, n, container_w, container_h, origin_x, origin_y, padding, gap, align_items_val, justify, main_size, cross_size, dpi_scale);
        // Write container rect before absolute second pass.
        s.get(id).computed = Rect{ .x = origin_x, .y = origin_y, .w = actual_size.w, .h = actual_size.h };
        placeAbsoluteChildren(s, id, origin_x, origin_y, actual_size.w, actual_size.h, dpi_scale);
        return actual_size;
    }

    // M15-04: RTL layout direction (row flex containers only).
    const is_rtl_row = direction == .row and s.get(id).layout_direction == .rtl;

    // Compute remaining free space after final sizes
    var total_final: f32 = 0.0;
    for (children) |c| total_final += c.final_size;
    const gap_total_final: f32 = if (n > 1) gap * @as(f32, @floatFromInt(n - 1)) else 0.0;
    const remaining = main_size - total_final - gap_total_final;

    // Compute start offset and inter-child spacing based on justify_content.
    // For RTL row, flex-start and flex-end are mirrored.
    var main_offset: f32 = 0.0;
    var inter_gap: f32 = gap;
    const effective_justify: JustifyContent = if (is_rtl_row) switch (justify) {
        .start => .end,
        .end => .start,
        else => justify,
    } else justify;

    switch (effective_justify) {
        .start => {
            main_offset = 0.0;
            inter_gap = gap;
        },
        .center => {
            main_offset = @max(0.0, remaining) / 2.0;
            inter_gap = gap;
        },
        .end => {
            main_offset = @max(0.0, remaining);
            inter_gap = gap;
        },
        .space_between => {
            main_offset = 0.0;
            inter_gap = if (n > 1) @max(0.0, remaining) / @as(f32, @floatFromInt(n - 1)) else 0.0;
        },
        .space_around => {
            const per_item = if (n > 0) @max(0.0, remaining) / @as(f32, @floatFromInt(n)) else 0.0;
            main_offset = per_item / 2.0;
            inter_gap = per_item;
        },
    }

    // Place each child using cumulative position tracking (no drift)
    // We track the cumulative edge position in f32 and round at each step.
    var cursor_main_f32: f32 = if (is_rtl_row)
        // RTL row: start from the right edge and go left
        origin_x + padding.left + main_size - main_offset
    else if (direction == .row)
        origin_x + padding.left + main_offset
    else
        origin_y + padding.top + main_offset;
    var max_child_cross: f32 = 0.0;
    var total_main_extent: f32 = 0.0;

    for (children) |*c| {
        // M15-04 RTL: child is placed to the LEFT of the current right-edge cursor
        const child_main_pos = if (is_rtl_row)
            @round(cursor_main_f32 - c.final_size)
        else
            @round(cursor_main_f32);

        // R51: use child's align_self if not .auto, else parent's align_items
        const child_node = s.get(c.id);
        const effective_child_align: AlignItems = blk: {
            break :blk switch (child_node.align_self) {
                .auto => align_items_val,
                .start => .start,
                .center => .center,
                .end => .end,
                .stretch => .stretch,
            };
        };

        // Determine cross position based on effective alignment
        const child_cross: f32 = c.cross_size;
        const cross_pos: f32 = switch (effective_child_align) {
            .start => if (direction == .row) origin_y + padding.top else origin_x + padding.left,
            .center => blk: {
                const offset = (cross_size - child_cross) / 2.0;
                break :blk if (direction == .row)
                    origin_y + padding.top + offset
                else
                    origin_x + padding.left + offset;
            },
            .end => blk: {
                break :blk if (direction == .row)
                    origin_y + padding.top + cross_size - child_cross
                else
                    origin_x + padding.left + cross_size - child_cross;
            },
            .stretch => if (direction == .row) origin_y + padding.top else origin_x + padding.left,
        };

        const child_x = if (direction == .row) child_main_pos else cross_pos;
        const child_y = if (direction == .row) cross_pos else child_main_pos;

        // For the child's own size resolution, build constraints.
        // Stretch constrains to cross_size only when the container has a definite
        // (non-zero) cross size; with cross_size == 0 (auto container) the child
        // must be free to report its intrinsic size.
        const stretch_definite = effective_child_align == .stretch and cross_size > 0;
        const child_avail: Constraints = if (direction == .row)
            Constraints{
                .min_w = c.final_size,
                .max_w = c.final_size,
                .min_h = if (stretch_definite) cross_size else 0.0,
                .max_h = if (stretch_definite) cross_size else std.math.inf(f32),
            }
        else
            Constraints{
                .min_h = c.final_size,
                .max_h = c.final_size,
                .min_w = if (stretch_definite) cross_size else 0.0,
                .max_w = if (stretch_definite) cross_size else std.math.inf(f32),
            };

        // Recurse into child (lay out its subtree)
        const child_size = solveNode(s, c.id, child_avail, child_x, child_y, dpi_scale);

        // Track actual cross-axis extent for auto-sized containers.
        const child_cross_actual = if (direction == .row) child_size.h else child_size.w;
        if (child_cross_actual > max_child_cross) max_child_cross = child_cross_actual;

        // Advance cursor: use the larger of planned final_size and actual solved size.
        // This handles containers whose height was 0 during phase 1 (e.g. flex rows
        // with no explicit height) but expanded after solving their own children.
        const child_main_actual = if (direction == .row) child_size.w else child_size.h;
        const effective_advance = @max(c.final_size, child_main_actual);
        total_main_extent += effective_advance;
        // M15-04 RTL: cursor moves LEFT (subtract) instead of RIGHT (add)
        if (is_rtl_row) {
            cursor_main_f32 -= effective_advance + inter_gap;
        } else {
            cursor_main_f32 += effective_advance + inter_gap;
        }
    }
    // Subtract trailing inter_gap that was added after the last child.
    const children_main_size = if (n > 0)
        total_main_extent + @as(f32, @floatFromInt(n - 1)) * inter_gap
    else
        0.0;

    // Derive auto sizes from children on each axis.
    const actual_h: f32 = if (container_h > 0)
        container_h
    else if (direction == .column)
        children_main_size + padding.top + padding.bottom
    else
        max_child_cross + padding.top + padding.bottom;
    const actual_w: f32 = if (container_w > 0)
        container_w
    else if (direction == .row)
        children_main_size + padding.left + padding.right
    else
        max_child_cross + padding.left + padding.right;

    // Write container rect before absolute second pass.
    s.get(id).computed = Rect{ .x = origin_x, .y = origin_y, .w = actual_w, .h = actual_h };
    placeAbsoluteChildren(s, id, origin_x, origin_y, actual_w, actual_h, dpi_scale);

    return Size{ .w = actual_w, .h = actual_h };
}

// ---------------------------------------------------------------------------
// M12 RC2 — Flex-wrap layout (row direction only)
// ---------------------------------------------------------------------------

/// Maximum lines we support in a wrapping flex container.
const MAX_FLEX_LINES = 32;

/// Solve a wrapping row flex container. Breaks children into lines, sizes each line
/// independently, and stacks lines vertically.
fn solveFlexWrap(
    s: *ElementStore,
    id: ElementId,
    children: []FlexChildData,
    n: usize,
    container_w: f32,
    container_h: f32,
    origin_x: f32,
    origin_y: f32,
    padding: store.Insets,
    gap: f32,
    align_items_val: AlignItems,
    justify: JustifyContent,
    main_size: f32,
    cross_size: f32,
    dpi_scale: f32,
) Size {
    _ = id;         // container id not needed; children addressed by their own ids
    _ = cross_size; // row wrap: cross is height; handled via lines
    _ = justify;    // per-line justify uses default start for now

    // --- Line-breaking pass ---
    // Each "line" is a slice [line_start, line_end) of children[].
    const MAX_LINE_STARTS = MAX_FLEX_LINES + 1;
    var line_starts: [MAX_LINE_STARTS]usize = undefined;
    var line_count: usize = 0;
    line_starts[0] = 0;

    var line_width: f32 = 0;
    var i: usize = 0;
    while (i < n) : (i += 1) {
        const child_base = children[i].base_size;
        const needed = if (line_width == 0) child_base else line_width + gap + child_base;
        if (needed > main_size and line_width > 0 and line_count + 1 < MAX_FLEX_LINES) {
            // Break: start a new line.
            line_count += 1;
            line_starts[line_count] = i;
            line_width = child_base;
        } else {
            line_width = needed;
        }
    }
    // Close last line.
    line_count += 1;
    line_starts[line_count] = n;

    // --- Place each line ---
    var cursor_y: f32 = origin_y + padding.top;
    var max_line_w: f32 = 0;
    var total_cross: f32 = 0;

    var li: usize = 0;
    while (li < line_count) : (li += 1) {
        const ls = line_starts[li];
        const le = line_starts[li + 1];
        const line_n = le - ls;
        if (line_n == 0) continue;

        // Compute per-line free space and apply flex-grow within this line.
        var line_base_total: f32 = 0;
        for (children[ls..le]) |c| line_base_total += c.base_size;
        const line_gap_total: f32 = if (line_n > 1) gap * @as(f32, @floatFromInt(line_n - 1)) else 0.0;
        const line_free = main_size - line_base_total - line_gap_total;

        // Apply flex_grow within line.
        var total_grow: f32 = 0;
        for (children[ls..le]) |c| total_grow += s.get(c.id).flex_grow;
        if (line_free > 0 and total_grow > 0) {
            for (children[ls..le]) |*c| {
                const fg = s.get(c.id).flex_grow;
                if (fg > 0) {
                    const child = s.get(c.id);
                    const child_max = child.max_size.w;
                    c.final_size = @min(c.base_size + (fg / total_grow) * line_free, child_max);
                }
            }
        } else {
            for (children[ls..le]) |*c| c.final_size = c.base_size;
        }

        // Find line cross height (max of all children on this line).
        var line_cross: f32 = 0;
        for (children[ls..le]) |c| {
            if (c.cross_size > line_cross) line_cross = c.cross_size;
        }

        // Place children on this line.
        var cursor_x: f32 = origin_x + padding.left;
        for (children[ls..le]) |*c| {
            const child_node = s.get(c.id);
            const effective_align: AlignItems = switch (child_node.align_self) {
                .auto => align_items_val,
                .start => .start,
                .center => .center,
                .end => .end,
                .stretch => .stretch,
            };
            const child_cross_sz = if (effective_align == .stretch) line_cross else c.cross_size;
            const child_y_offset: f32 = switch (effective_align) {
                .start, .stretch => 0,
                .center => (line_cross - c.cross_size) / 2.0,
                .end => line_cross - c.cross_size,
            };
            const child_avail = Constraints{
                .min_w = c.final_size,
                .max_w = c.final_size,
                .min_h = if (effective_align == .stretch) child_cross_sz else 0.0,
                .max_h = if (effective_align == .stretch) child_cross_sz else std.math.inf(f32),
            };
            _ = solveNode(s, c.id, child_avail, cursor_x, cursor_y + child_y_offset, dpi_scale);
            cursor_x += c.final_size + gap;
        }

        const line_actual_w = cursor_x - gap - origin_x - padding.left;
        if (line_actual_w > max_line_w) max_line_w = line_actual_w;
        cursor_y += line_cross + gap;
        total_cross += line_cross + gap;
    }
    // Remove trailing gap.
    if (line_count > 0 and total_cross >= gap) total_cross -= gap;
    if (line_count > 0) cursor_y -= gap;

    const actual_w = if (container_w > 0) container_w else max_line_w + padding.left + padding.right;
    const actual_h = if (container_h > 0) container_h else total_cross + padding.top + padding.bottom;

    return Size{ .w = actual_w, .h = actual_h };
}

// ---------------------------------------------------------------------------
// Grid layout
// ---------------------------------------------------------------------------

fn solveGrid(
    s: *ElementStore,
    id: ElementId,
    container_w: f32,
    container_h: f32,
    origin_x: f32,
    origin_y: f32,
    avail: Constraints,
    dpi_scale: f32,
) Size {
    _ = avail;
    const node = s.get(id);
    const padding_raw = node.padding;
    const padding = Insets{
        .top = @round(padding_raw.top * dpi_scale),
        .right = @round(padding_raw.right * dpi_scale),
        .bottom = @round(padding_raw.bottom * dpi_scale),
        .left = @round(padding_raw.left * dpi_scale),
    };
    const gap = @round(node.gap * dpi_scale);
    const cols = node.grid_template_columns;
    const rows = node.grid_template_rows;

    const content_w = @max(0.0, container_w - padding.left - padding.right);
    const content_h = @max(0.0, container_h - padding.top - padding.bottom);

    const n_cols = cols.len;
    const n_rows = rows.len;

    // --- Resolve column track widths ---
    // Use stack arrays (max 64 tracks is fine for 4096 scratch budget)
    const MAX_TRACKS = 64;
    var col_widths_buf: [MAX_TRACKS]f32 = undefined;
    var col_starts_buf: [MAX_TRACKS]f32 = undefined;
    var row_heights_buf: [MAX_TRACKS]f32 = undefined;
    var row_starts_buf: [MAX_TRACKS]f32 = undefined;

    const nc = @min(n_cols, MAX_TRACKS);
    const nr = @min(n_rows, MAX_TRACKS);

    resolveTrackSizes(cols[0..nc], content_w, gap, col_widths_buf[0..nc], dpi_scale);
    resolveTrackStarts(col_widths_buf[0..nc], gap, col_starts_buf[0..nc]);

    resolveTrackSizes(rows[0..nr], content_h, gap, row_heights_buf[0..nr], dpi_scale);
    resolveTrackStarts(row_heights_buf[0..nr], gap, row_starts_buf[0..nr]);

    // --- Auto-place children row-major ---
    var col_cursor: usize = 0;
    var row_cursor: usize = 0;

    var it = s.childrenOf(id);
    while (it.next()) |child_id| {
        const child = s.get(child_id);
        const col_span: usize = @intCast(child.col_span);
        const row_span: usize = @intCast(child.row_span);

        // Wrap to next row if needed
        if (nc > 0 and col_cursor + col_span > nc) {
            col_cursor = 0;
            row_cursor += 1;
        }

        // Compute child rect
        var child_x = origin_x + padding.left;
        var child_y = origin_y + padding.top;
        var child_w: f32 = 0.0;
        var child_h: f32 = 0.0;

        if (nc > 0 and col_cursor < nc) {
            child_x += col_starts_buf[col_cursor];
            // Sum widths of spanned columns
            child_w = 0.0;
            var sc: usize = 0;
            while (sc < col_span and col_cursor + sc < nc) : (sc += 1) {
                child_w += col_widths_buf[col_cursor + sc];
            }
            // Add gaps between spanned columns
            if (col_span > 1) {
                child_w += gap * @as(f32, @floatFromInt(col_span - 1));
            }
        }

        if (nr > 0 and row_cursor < nr) {
            child_y += row_starts_buf[row_cursor];
            // Sum heights of spanned rows
            child_h = 0.0;
            var sr: usize = 0;
            while (sr < row_span and row_cursor + sr < nr) : (sr += 1) {
                child_h += row_heights_buf[row_cursor + sr];
            }
            // Add gaps between spanned rows
            if (row_span > 1) {
                child_h += gap * @as(f32, @floatFromInt(row_span - 1));
            }
        }

        const child_avail = Constraints{
            .min_w = child_w,
            .max_w = child_w,
            .min_h = child_h,
            .max_h = child_h,
        };

        _ = solveNode(s, child_id, child_avail, child_x, child_y, dpi_scale);

        // Advance column cursor
        col_cursor += col_span;
        if (nc > 0 and col_cursor >= nc) {
            col_cursor = 0;
            row_cursor += 1;
        }
    }

    return Size{ .w = container_w, .h = container_h };
}

/// Resolve track sizes (px, fr, auto) into concrete pixel widths.
/// Uses cumulative rounding for fr tracks to avoid drift.
fn resolveTrackSizes(tracks: []const TrackSize, available: f32, gap: f32, out: []f32, dpi_scale: f32) void {
    const n = tracks.len;
    if (n == 0) return;

    // Sum px sizes and count fr units
    var px_sum: f32 = 0.0;
    var fr_total: f32 = 0.0;
    for (tracks) |t| {
        switch (t) {
            .px => |v| px_sum += @round(v * dpi_scale),
            .fr => |v| fr_total += v,
            .auto => {},
        }
    }

    const gap_total: f32 = if (n > 1) gap * @as(f32, @floatFromInt(n - 1)) else 0.0;
    const fr_space = @max(0.0, available - px_sum - gap_total);

    // First pass: assign px and auto tracks
    for (tracks, 0..) |t, i| {
        out[i] = switch (t) {
            .px => |v| @round(v * dpi_scale),
            .fr => 0.0, // placeholder
            .auto => 0.0,
        };
    }

    // Second pass: distribute fr space using cumulative rounding
    if (fr_total > 0.0) {
        // Find fr tracks and distribute with cumulative rounding
        // We need to track "allocated so far" to avoid drift
        var fr_allocated: f32 = 0.0;
        var fr_index: usize = 0;
        var fr_count: usize = 0;
        for (tracks) |t| {
            if (t == .fr) fr_count += 1;
        }

        for (tracks, 0..) |t, i| {
            switch (t) {
                .fr => |v| {
                    fr_index += 1;
                    if (fr_index == fr_count) {
                        // Last fr track gets the remainder to avoid drift
                        out[i] = @round(fr_space - fr_allocated);
                    } else {
                        const share = @round((v / fr_total) * fr_space);
                        out[i] = share;
                        fr_allocated += share;
                    }
                },
                else => {},
            }
        }
    }
}

/// Compute cumulative start positions for tracks.
/// track_starts[i] = sum of track_widths[0..i] + i * gap
fn resolveTrackStarts(widths: []const f32, gap: f32, out: []f32) void {
    var cursor: f32 = 0.0;
    for (widths, 0..) |w, i| {
        out[i] = @round(cursor);
        cursor += w + gap;
    }
}
