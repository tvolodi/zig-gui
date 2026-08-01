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

/// RN16 (2026-08-01) — Hoverable card: same as `surface`, but background/border ease over
/// ~150ms on hover instead of snapping (`transition-colors`, matches AI-Qadam's own CSS).
/// Note: Card has no built-in ButtonState-style hover tracking of its own — callers that want
/// a genuine hover response must drive `scene.setPseudo(idx, .{ .hover = true/false })`
/// themselves (e.g. from a synthetic test hook or a future pointer-hit-test pass over Cards).
/// This class only makes the transition *possible*; it does not add hover detection.
pub const hoverable = surface ++ " transition-colors";

/// RN16 — Card that fades in when its screen is instantiated (`fade_in`, ~150ms ease-out).
pub const enter_fade = surface ++ " fade-in";
