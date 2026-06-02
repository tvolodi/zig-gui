//! 06 — Markup + style — types.zig
//!
//! Contract (INV-5.1). The descriptor struct shapes (NodeDesc, Attr, AttrValue) and the
//! public signatures are the contract — match them exactly. `parse` and `resolveClasses` are
//! the real work and are stubbed — implement per spec.md; do not change signatures.
//!
//! Depends on std + module 03 (LayoutNode/geometry) + module 05 (Tokens/ComputedStyle).
//! All lower-numbered in the corrected build order, so these imports are legal (INV-3.4).

const std = @import("std");
const store = @import("../03_element_store/types.zig");
const theme = @import("../05_theme/types.zig");

pub const LayoutNode = store.LayoutNode;
pub const Tokens = theme.Tokens;
pub const ComputedStyle = theme.ComputedStyle;

// ---------------------------------------------------------------------------
// Markup descriptor tree (output of parse)
// ---------------------------------------------------------------------------

/// An attribute value is either a literal string or a binding path captured from
/// `{bind path}`. Binding paths are recorded only — never evaluated here (spec non-goal).
pub const AttrValue = union(enum) {
    literal: []const u8,
    bind: []const u8, // e.g. "user.name" from text="{bind user.name}"
};

pub const Attr = struct {
    name: []const u8,
    value: AttrValue,
};

/// A parsed markup node. Slices are owned by the allocator passed to `parse`.
pub const NodeDesc = struct {
    tag: []const u8,
    classes: []const u8 = "", // value of class="..." ("" if absent)
    attrs: []const Attr = &.{}, // every attribute except class
    children: []const NodeDesc = &.{},
};

pub const ParseError = error{
    UnexpectedToken,
    UnclosedTag,
    MismatchedTag,
    MalformedAttribute,
    OutOfMemory,
};

/// Parse `.ui` markup into a descriptor tree rooted at the returned NodeDesc.
/// One function, two uses (spec refinement 1): run at build time by the codegen step to emit
/// baked struct literals, and at app runtime behind `-Dhot-reload` for live editing. Keep it
/// free of constructs that would prevent build-time use.
pub fn parse(allocator: std.mem.Allocator, source: []const u8) ParseError!NodeDesc {
    _ = allocator;
    _ = source;
    @compileError("not implemented — implement per spec.md; do not change this signature");
}

// ---------------------------------------------------------------------------
// Tailwind-subset resolver (classes -> style + layout)
// ---------------------------------------------------------------------------

/// The class string resolved into a style patch and a layout patch. Only class-derived
/// fields are set; everything else is left at struct defaults.
pub const Resolved = struct {
    style: ComputedStyle = .{},
    layout: LayoutNode = .{},
};

/// Resolve a space-separated class string against theme tokens (see spec.md "Tailwind
/// subset"). Order-independent except last-wins on direct conflict. Unknown classes ignored.
/// Spacing/gap/sizing use the fixed n*4 px scale; color/radius/font-size use tokens.
pub fn resolveClasses(classes: []const u8, tokens: Tokens) Resolved {
    _ = classes;
    _ = tokens;
    @compileError("not implemented — implement per spec.md; do not change this signature");
}
