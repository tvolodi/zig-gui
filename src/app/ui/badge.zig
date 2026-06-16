//! Badge class strings — semantic pill labels (shadcn Badge variants).
//!
//! Usage:
//!   const a = [1]Attr{.{ .name = "text", .value = .{ .literal = "Delivered" } }};
//!   const n = NodeDesc{ .tag = "Card", .classes = badge.ok, .attrs = &a };

/// Zinc-900 background — primary/default badge (inverted).
pub const default   = "rounded-full px-2 text-xs font-bold bg-accent";
/// Zinc-100 background — secondary/subtle badge.
pub const secondary = "rounded-full px-2 text-xs bg-raised text-body";
/// White background with border — outline badge.
pub const outline   = "rounded-full px-2 text-xs border bg-canvas text-body";
/// Success status badge (caller sets text_color = tokens.ok post-instantiation).
pub const ok        = "rounded-full px-2 text-xs font-bold bg-raised";
/// Warning status badge (caller sets text_color = tokens.warn post-instantiation).
pub const warn      = "rounded-full px-2 text-xs font-bold bg-raised";
/// Error status badge (caller sets text_color = tokens.err post-instantiation).
pub const err       = "rounded-full px-2 text-xs font-bold bg-raised";
