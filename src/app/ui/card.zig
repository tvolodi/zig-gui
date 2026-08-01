//! Card class strings — AI-Qadam visual-analog Card variants (RN14, 2026-08-01).
//!
//! Ground truth (AI-Qadam components.css): border-radius 12px (rounded-lg, now repointed to
//! radius_lg=12 in src/05/types.zig), padding 24px (p-6), border 1px, two-layer soft shadow
//! (approximated via the existing `shadow` class — shadow_blur/offset/color fields — per
//! Validator: true multi-layer CSS shadows are out of scope for this task).

/// Standard card surface with shadow and padding.
pub const surface  = "p-6 shadow border bg-raised rounded-lg";
/// Card without padding (children provide their own).
pub const bare     = "shadow border bg-raised rounded-lg";
/// Subtle card — surface background, no shadow.
pub const subtle   = "p-6 bg-surface rounded-lg";
/// Card header — bold text inside a card.
pub const header   = "font-bold text-lg mb-2";
/// Card description — muted text below header.
pub const desc     = "text-sm text-muted mb-4";
