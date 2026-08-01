//! Input class strings — AI-Qadam visual-analog Input appearance (RN14, 2026-08-01).
//!
//! Ground truth (AI-Qadam components.css): height 40px (h-10), padding 0 12px (px-3),
//! border-radius 8px (rounded-md), border 1px.
//!
//! RN16 (2026-08-01): `base` opts into `transition-colors` so the border-color change on
//! hover/focus eases over ~150ms instead of snapping — matches AI-Qadam's own
//! `transition: all 150ms var(--ease-out)`.

/// Standard input field.
pub const base  = "w-full h-10 border bg-raised rounded-md px-3 transition-colors";
/// Label above an input.
pub const label = "text-sm font-bold";
/// Helper/description text below an input.
pub const hint  = "text-xs text-muted mt-1";
