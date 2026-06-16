//! Card class strings — shadcn Card variants.

/// Standard card surface with shadow and padding.
pub const surface  = "p-4 shadow bg-raised rounded-lg";
/// Card without padding (children provide their own).
pub const bare     = "shadow bg-raised rounded-lg";
/// Subtle card — surface background, no shadow.
pub const subtle   = "p-4 bg-surface rounded-lg";
/// Card header — bold text inside a card.
pub const header   = "font-bold text-lg mb-2";
/// Card description — muted text below header.
pub const desc     = "text-sm text-muted mb-4";
