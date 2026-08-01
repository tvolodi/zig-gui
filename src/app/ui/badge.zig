//! Badge class strings — AI-Qadam visual-analog pill labels (RN14, 2026-08-01).
//!
//! Ground truth (AI-Qadam components.css): height 22px, padding 0 8px (px-2), font-size 12px
//! (text-xs), font-weight 500 (font-medium — approximated, see src/06/types.zig comment),
//! border-radius 6px (rounded-sm — matches exactly), border 1px.
//! Height: 22px is not expressible on the 4px scale and module 06 has no `h-[Npx]` arbitrary
//! syntax; nearest scale step is h-6 (24px) — accepted 2px discrepancy per Validator handoff.
//!
//! Usage:
//!   const a = [1]Attr{.{ .name = "text", .value = .{ .literal = "Delivered" } }};
//!   const n = NodeDesc{ .tag = "Card", .classes = badge.ok, .attrs = &a };

const base = "rounded-sm px-2 h-6 text-xs font-medium border";

/// Filled teal (accent) background — primary/default badge.
pub const default   = base ++ " bg-accent";
/// Raised background — secondary/subtle badge.
pub const secondary = base ++ " bg-raised text-body";
/// Canvas background with border — outline badge.
pub const outline   = base ++ " bg-canvas text-body";
/// Success status badge (caller sets text_color = tokens.ok post-instantiation).
pub const ok        = base ++ " bg-raised";
/// Warning status badge (caller sets text_color = tokens.warn post-instantiation).
pub const warn      = base ++ " bg-raised";
/// Error status badge (caller sets text_color = tokens.err post-instantiation).
pub const err       = base ++ " bg-raised";
