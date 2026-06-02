//! 07 — Components — src/07/types.zig
//!
//! Full implementation of module 07 (Components). Turns a NodeDesc tree (from module 06
//! parser) into a live element tree in the ElementStore. Owns parallel presentation arrays
//! (_kind, _style, _text) index-aligned with the store's layout[].
//!
//! Imports:
//!   02 — text (Font, GlyphAtlas, layoutParagraph)
//!   03 — element store (ElementStore, ElementId, LayoutNode)
//!   05 — theme (Tokens, ComputedStyle, buttonPrimary, etc.)
//!   06 — markup (NodeDesc, resolveClasses, Resolved)

const std = @import("std");
const text = @import("../02/types.zig");
const store_mod = @import("../03/types.zig");
const theme = @import("../05/types.zig");
const markup = @import("../06/types.zig");

// ---------------------------------------------------------------------------
// Re-exports used by the acceptance test
// ---------------------------------------------------------------------------

pub const ElementId = store_mod.ElementId;
pub const ElementStore = store_mod.ElementStore;
pub const LayoutNode = store_mod.LayoutNode;
pub const Tokens = theme.Tokens;
pub const ComputedStyle = theme.ComputedStyle;
pub const NodeDesc = markup.NodeDesc;

// ---------------------------------------------------------------------------
// Widget kinds + registry
// ---------------------------------------------------------------------------

pub const WidgetKind = enum { text, button, input, card, row, column, dropdown };

/// Map a markup tag to a widget kind. Unknown tag → null.
pub fn tagToKind(tag: []const u8) ?WidgetKind {
    const eql = std.mem.eql;
    if (eql(u8, tag, "Text")) return .text;
    if (eql(u8, tag, "Button")) return .button;
    if (eql(u8, tag, "Input")) return .input;
    if (eql(u8, tag, "Card")) return .card;
    if (eql(u8, tag, "Row")) return .row;
    if (eql(u8, tag, "Column")) return .column;
    if (eql(u8, tag, "Dropdown")) return .dropdown;
    return null;
}

/// Per-kind default layout. Row/Column are flex containers; everything else is block.
pub fn defaultLayoutFor(kind: WidgetKind) LayoutNode {
    return switch (kind) {
        .row => .{ .display = .flex, .direction = .row },
        .column => .{ .display = .flex, .direction = .column },
        else => .{ .display = .block },
    };
}

/// Per-kind default style, wired to module 05's component builders.
pub fn defaultStyleFor(kind: WidgetKind, tokens: Tokens) ComputedStyle {
    return switch (kind) {
        .button => theme.buttonPrimary(tokens),
        .card => theme.cardSurface(tokens),
        .input, .dropdown => theme.inputDefault(tokens),
        .text, .row, .column => ComputedStyle{},
    };
}

// ---------------------------------------------------------------------------
// Color equality helper
// ---------------------------------------------------------------------------

fn colorEq(a: theme.Color, b: theme.Color) bool {
    return a.r == b.r and a.g == b.g and a.b == b.b and a.a == b.a;
}

// ---------------------------------------------------------------------------
// Dimension equality helper (tagged union)
// ---------------------------------------------------------------------------

fn dimensionEq(a: store_mod.Dimension, b: store_mod.Dimension) bool {
    return std.meta.eql(a, b);
}

// ---------------------------------------------------------------------------
// Scene — owns the ElementStore + parallel presentation arrays
// ---------------------------------------------------------------------------

pub const InstantiateError = error{
    UnknownTag,
    OutOfMemory,
};

pub const Scene = struct {
    elements: ElementStore,

    _kind: std.ArrayListUnmanaged(WidgetKind) = .empty,
    _style: std.ArrayListUnmanaged(ComputedStyle) = .empty,
    _text: std.ArrayListUnmanaged(?[]const u8) = .empty,

    gpa: std.mem.Allocator,

    pub fn init(gpa: std.mem.Allocator) Scene {
        return Scene{
            .gpa = gpa,
            .elements = ElementStore.init(gpa),
        };
    }

    pub fn deinit(self: *Scene) void {
        self._kind.deinit(self.gpa);
        self._style.deinit(self.gpa);
        self._text.deinit(self.gpa);
        self.elements.deinit();
    }

    pub fn reset(self: *Scene) void {
        self._kind.clearRetainingCapacity();
        self._style.clearRetainingCapacity();
        self._text.clearRetainingCapacity();
        self.elements.reset();
    }

    /// Build the descriptor subtree into the store + presentation arrays (no font).
    /// Returns the root id. Unknown tag → InstantiateError.UnknownTag.
    pub fn instantiate(self: *Scene, desc: NodeDesc, tokens: Tokens) InstantiateError!ElementId {
        return self.instantiateNode(desc, tokens, null);
    }

    /// Measure every text-bearing element and fill its LayoutNode.measured.
    pub fn measurePass(self: *Scene, font: *text.Font, atlas: *text.GlyphAtlas) text.FontError!void {
        for (self._text.items, 0..) |maybe_str, i| {
            const str = maybe_str orelse continue;
            const font_size = self._style.items[i].font_size;
            const para = try text.layoutParagraph(self.gpa, font, atlas, str, font_size, 1e6);
            defer self.gpa.free(para.glyphs);
            self.elements.layout.items[i].measured = .{ .w = para.extent.w, .h = para.extent.h };
        }
    }

    // --- accessors ---

    pub fn store(self: *Scene) *ElementStore {
        return &self.elements;
    }

    pub fn kindOf(self: *Scene, id: ElementId) WidgetKind {
        return self._kind.items[id.index];
    }

    pub fn styleOf(self: *Scene, id: ElementId) *ComputedStyle {
        return &self._style.items[id.index];
    }

    pub fn textOf(self: *Scene, id: ElementId) ?[]const u8 {
        if (id.index >= self._text.items.len) return null;
        return self._text.items[id.index];
    }

    pub fn count(self: *Scene) u32 {
        return self.elements.live;
    }

    // --- private helpers ---

    fn instantiateNode(
        self: *Scene,
        desc: NodeDesc,
        tokens: Tokens,
        parent_id: ?ElementId,
    ) InstantiateError!ElementId {
        const kind = tagToKind(desc.tag) orelse return InstantiateError.UnknownTag;

        // Build merged layout and style using the spec merge rule:
        //   base     = defaultStyleFor/defaultLayoutFor(kind, tokens)
        //   resolved = resolveClasses(node.classes, tokens)
        //   empty    = resolveClasses("", tokens)
        //   final.field = if (resolved.field != empty.field) resolved.field else base.field
        const base_style = defaultStyleFor(kind, tokens);
        const base_layout = defaultLayoutFor(kind);
        const resolved = markup.resolveClasses(desc.classes, tokens);
        const empty = markup.resolveClasses("", tokens);

        // --- Merge style fields ---
        var final_style = base_style;

        if (!colorEq(resolved.style.background, empty.style.background))
            final_style.background = resolved.style.background;
        if (!colorEq(resolved.style.text_color, empty.style.text_color))
            final_style.text_color = resolved.style.text_color;
        if (!colorEq(resolved.style.border_color, empty.style.border_color))
            final_style.border_color = resolved.style.border_color;
        if (resolved.style.border_width != empty.style.border_width)
            final_style.border_width = resolved.style.border_width;
        if (resolved.style.radius != empty.style.radius)
            final_style.radius = resolved.style.radius;
        if (resolved.style.gap != empty.style.gap)
            final_style.gap = resolved.style.gap;
        if (resolved.style.font_size != empty.style.font_size)
            final_style.font_size = resolved.style.font_size;

        // Padding sub-fields
        if (resolved.style.padding.top != empty.style.padding.top)
            final_style.padding.top = resolved.style.padding.top;
        if (resolved.style.padding.right != empty.style.padding.right)
            final_style.padding.right = resolved.style.padding.right;
        if (resolved.style.padding.bottom != empty.style.padding.bottom)
            final_style.padding.bottom = resolved.style.padding.bottom;
        if (resolved.style.padding.left != empty.style.padding.left)
            final_style.padding.left = resolved.style.padding.left;

        // --- Merge layout fields ---
        var final_layout = base_layout;

        if (resolved.layout.display != empty.layout.display)
            final_layout.display = resolved.layout.display;
        if (resolved.layout.direction != empty.layout.direction)
            final_layout.direction = resolved.layout.direction;
        if (resolved.layout.justify_content != empty.layout.justify_content)
            final_layout.justify_content = resolved.layout.justify_content;
        if (resolved.layout.align_items != empty.layout.align_items)
            final_layout.align_items = resolved.layout.align_items;
        if (resolved.layout.gap != empty.layout.gap)
            final_layout.gap = resolved.layout.gap;
        if (resolved.layout.flex_grow != empty.layout.flex_grow)
            final_layout.flex_grow = resolved.layout.flex_grow;
        if (resolved.layout.flex_shrink != empty.layout.flex_shrink)
            final_layout.flex_shrink = resolved.layout.flex_shrink;
        if (!dimensionEq(resolved.layout.flex_basis, empty.layout.flex_basis))
            final_layout.flex_basis = resolved.layout.flex_basis;
        if (!dimensionEq(resolved.layout.width, empty.layout.width))
            final_layout.width = resolved.layout.width;
        if (!dimensionEq(resolved.layout.height, empty.layout.height))
            final_layout.height = resolved.layout.height;
        if (resolved.layout.col_span != empty.layout.col_span)
            final_layout.col_span = resolved.layout.col_span;
        if (resolved.layout.row_span != empty.layout.row_span)
            final_layout.row_span = resolved.layout.row_span;
        // grid_template_columns/rows: compare by length (empty has len 0)
        if (resolved.layout.grid_template_columns.len != empty.layout.grid_template_columns.len)
            final_layout.grid_template_columns = resolved.layout.grid_template_columns;
        if (resolved.layout.grid_template_rows.len != empty.layout.grid_template_rows.len)
            final_layout.grid_template_rows = resolved.layout.grid_template_rows;

        // Sync layout padding from the resolved style (style padding drives layout spacing).
        // Only apply if the layout hasn't been explicitly set via a Tailwind class.
        if (resolved.layout.padding.top == empty.layout.padding.top)
            final_layout.padding.top = final_style.padding.top;
        if (resolved.layout.padding.right == empty.layout.padding.right)
            final_layout.padding.right = final_style.padding.right;
        if (resolved.layout.padding.bottom == empty.layout.padding.bottom)
            final_layout.padding.bottom = final_style.padding.bottom;
        if (resolved.layout.padding.left == empty.layout.padding.left)
            final_layout.padding.left = final_style.padding.left;

        // --- Extract text attr ---
        var text_val: ?[]const u8 = null;
        for (desc.attrs) |attr| {
            if (std.mem.eql(u8, attr.name, "text")) {
                text_val = switch (attr.value) {
                    .literal => |s| s,
                    .bind => |s| s,
                };
            }
        }

        // --- Add element to the store ---
        const id: ElementId = if (parent_id) |pid|
            try self.elements.addChild(pid, final_layout)
        else
            try self.elements.addRoot(final_layout);

        // --- Extend parallel arrays to cover id.index ---
        const needed = id.index + 1;
        try self._kind.ensureTotalCapacity(self.gpa, needed);
        if (self._kind.items.len <= id.index) {
            self._kind.items.len = needed;
        }
        self._kind.items[id.index] = kind;

        try self._style.ensureTotalCapacity(self.gpa, needed);
        if (self._style.items.len <= id.index) {
            self._style.items.len = needed;
        }
        self._style.items[id.index] = final_style;

        try self._text.ensureTotalCapacity(self.gpa, needed);
        if (self._text.items.len <= id.index) {
            self._text.items.len = needed;
        }
        self._text.items[id.index] = text_val;

        // --- Recurse into children ---
        for (desc.children) |child| {
            _ = try self.instantiateNode(child, tokens, id);
        }

        return id;
    }
};
