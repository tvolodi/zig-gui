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
pub const LayoutNode = store.LayoutNode;

// ---------------------------------------------------------------------------
// Public API — the single entry point (INV-5.1)
// ---------------------------------------------------------------------------

/// Compute the layout of the subtree rooted at `root`, filling every reachable node's
/// `computed` rectangle. Deterministic: identical inputs produce byte-identical outputs.
///
/// `scratch` is a caller-owned reusable buffer (typically arena-backed). solve() must NOT
/// allocate per-node; it may only use `scratch`. See spec.md "Performance intent".
///
/// Children are resolved via `store.childrenOf(id)` (module 03).
pub fn solve(
    s: *ElementStore,
    root: ElementId,
    available: Constraints,
    scratch: []u8,
) void {
    _ = s;
    _ = root;
    _ = available;
    _ = scratch;
    @compileError("not implemented — implement per spec.md; do not change this signature");
}
