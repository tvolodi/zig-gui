//! 07 — Components — types.zig
//!
//! Contract (INV-5.1). `WidgetKind`, the `Scene` public method set, and the registry are the
//! contract. `tagToKind` and `defaultLayoutFor` are implemented here (data/wiring);
//! `defaultStyleFor`, `Scene.instantiate`, and `Scene.measurePass` are the real work and are
//! stubbed. Match signatures exactly; implement per spec.md.
//!
//! Imports modules 02/03/05/06 — all lower-numbered (INV-3.4), so legal. Scene owns the
//! ElementStore and the parallel presentation arrays (see spec.md build-order consequence).

const std = @import("std");
const text = @import("../02_text/types.zig");
const store = @import("../03_element_store/types.zig");
const theme = @import("../05_theme/types.zig");
const markup = @import("../06_markup_style/types.zig");

pub const ElementId = store.ElementId;
pub const ElementStore = store.ElementStore;
pub const LayoutNode = store.LayoutNode;
pub const Tokens = theme.Tokens;
pub const ComputedStyle = theme.ComputedStyle;
pub const NodeDesc = markup.NodeDesc;

// ---------------------------------------------------------------------------
// Widget kinds + registry
// ---------------------------------------------------------------------------

pub const WidgetKind = enum { text, button, input, card, row, column, dropdown };

/// Map a markup tag to a widget kind. Unknown tag → null (instantiate turns that into an
/// error). Implemented here to pin the exact tag spellings.
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
/// Implemented here (simple/definitional).
pub fn defaultLayoutFor(kind: WidgetKind) LayoutNode {
    return switch (kind) {
        .row => .{ .display = .flex, .direction = .row },
        .column => .{ .display = .flex, .direction = .column },
        else => .{ .display = .block },
    };
}

/// Per-kind default style, wired to module 05's component builders (button→buttonPrimary,
/// card→cardSurface, input/dropdown→inputDefault, others→empty). Stubbed — implement per
/// spec.md.
pub fn defaultStyleFor(kind: WidgetKind, tokens: Tokens) ComputedStyle {
    _ = kind;
    _ = tokens;
    @compileError("not implemented — implement per spec.md; do not change this signature");
}

// ---------------------------------------------------------------------------
// Scene — owns the ElementStore + parallel presentation arrays (INV-3.1)
// ---------------------------------------------------------------------------

pub const InstantiateError = error{
    UnknownTag,
    OutOfMemory,
};

pub const Scene = struct {
    // Scene owns the store. Element creation/removal funnels through Scene so the parallel
    // arrays stay index-aligned with the store's layout[] (spec.md "ownership rule").
    elements: ElementStore,

    // Parallel presentation arrays, indexed by ElementId.index (same index space as the
    // store). Implementation-defined backing (ArrayListUnmanaged etc.).
    _kind: std.ArrayListUnmanaged(WidgetKind) = .{},
    _style: std.ArrayListUnmanaged(ComputedStyle) = .{},
    _text: std.ArrayListUnmanaged(?[]const u8) = .{},

    gpa: std.mem.Allocator,

    pub fn init(gpa: std.mem.Allocator) Scene {
        _ = gpa;
        @compileError("not implemented — implement per spec.md; do not change this signature");
    }

    pub fn deinit(self: *Scene) void {
        _ = self;
        @compileError("not implemented — implement per spec.md; do not change this signature");
    }

    pub fn reset(self: *Scene) void {
        _ = self;
        @compileError("not implemented — implement per spec.md; do not change this signature");
    }

    /// Build the descriptor subtree into the store + presentation arrays (no font). Resolves
    /// classes layered over per-kind defaults (spec.md "merge rule"). Returns the root id.
    /// Unknown tag → InstantiateError.UnknownTag.
    pub fn instantiate(self: *Scene, desc: NodeDesc, tokens: Tokens) InstantiateError!ElementId {
        _ = self;
        _ = desc;
        _ = tokens;
        @compileError("not implemented — implement per spec.md; do not change this signature");
    }

    /// Measure every text-bearing element and fill its LayoutNode.measured, ensuring glyphs
    /// are in the atlas. Font-dependent; run after instantiate, before layout.
    pub fn measurePass(self: *Scene, font: *text.Font, atlas: *text.GlyphAtlas) text.FontError!void {
        _ = self;
        _ = font;
        _ = atlas;
        @compileError("not implemented — implement per spec.md; do not change this signature");
    }

    // --- accessors ---

    pub fn store(self: *Scene) *ElementStore {
        _ = self;
        @compileError("not implemented — implement per spec.md; do not change this signature");
    }

    pub fn kindOf(self: *Scene, id: ElementId) WidgetKind {
        _ = self;
        _ = id;
        @compileError("not implemented — implement per spec.md; do not change this signature");
    }

    pub fn styleOf(self: *Scene, id: ElementId) *ComputedStyle {
        _ = self;
        _ = id;
        @compileError("not implemented — implement per spec.md; do not change this signature");
    }

    pub fn textOf(self: *Scene, id: ElementId) ?[]const u8 {
        _ = self;
        _ = id;
        @compileError("not implemented — implement per spec.md; do not change this signature");
    }

    pub fn count(self: *Scene) u32 {
        _ = self;
        @compileError("not implemented — implement per spec.md; do not change this signature");
    }
};
