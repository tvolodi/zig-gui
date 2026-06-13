//! 05 — Theme — src/05/types.zig
//!
//! Re-exports the canonical implementation from docs/specs/05.types.zig.
//! The implementation lives in docs/specs/05.types.zig so the acceptance
//! test in docs/specs/ can resolve its imports correctly via build.zig.

const spec = @import("../../docs/specs/05.types.zig");
pub const Insets = spec.Insets;
pub const Color = spec.Color;
pub const Mode = spec.Mode;
pub const Palette = spec.Palette;
pub const Tokens = spec.Tokens;
pub const ComputedStyle = spec.ComputedStyle;
pub const TransitionState = spec.TransitionState;
pub const EnterExitState = spec.EnterExitState;
pub const PseudoOverride = spec.PseudoOverride;
pub const PseudoStyleSet = spec.PseudoStyleSet;
pub const Theme = spec.Theme;
pub const buttonPseudo = spec.buttonPseudo;
pub const inputPseudo = spec.inputPseudo;
pub const dropdownPseudo = spec.dropdownPseudo;
pub const checkboxPseudo = spec.checkboxPseudo;
pub const buttonPrimary = spec.buttonPrimary;
pub const buttonGhost = spec.buttonGhost;
pub const inputDefault = spec.inputDefault;
pub const cardSurface = spec.cardSurface;
