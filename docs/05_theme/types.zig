//! 05 — Theme — shim for docs/specs/06.types.zig and docs/specs/07.acceptance_test.zig.
//!
//! This file re-exports docs/specs/05.types.zig so that spec files under docs/
//! can import theme types without going outside their module path boundary.
//!
//! IMPORTANT: This file is used in TWO contexts:
//!   1. Build-script context (build.zig evaluation): imported as a plain file.
//!      In this context, ../specs/05.types.zig is a plain file import (no module conflict).
//!   2. Module compilation context: the importing module (e.g. mod06) has
//!      addImport("../05_theme/types.zig", mod05) registered, so this file is NEVER
//!      loaded — the named module mod05 is used instead.
//!
//! Do NOT import this file from src/ files (they should use mod05 directly).

const inner = @import("../specs/05.types.zig");

pub const Color = inner.Color;
pub const transparent = inner.transparent;
pub const Mode = inner.Mode;
pub const Palette = inner.Palette;
pub const Tokens = inner.Tokens;
pub const ComputedStyle = inner.ComputedStyle;
pub const TransitionState = inner.TransitionState;
pub const EnterExitState = inner.EnterExitState;
pub const PseudoOverride = inner.PseudoOverride;
pub const PseudoStyleSet = inner.PseudoStyleSet;
pub const Theme = inner.Theme;
pub const buttonPseudo = inner.buttonPseudo;
pub const inputPseudo = inner.inputPseudo;
pub const dropdownPseudo = inner.dropdownPseudo;
pub const checkboxPseudo = inner.checkboxPseudo;
pub const buttonPrimary = inner.buttonPrimary;
pub const buttonGhost = inner.buttonGhost;
pub const inputDefault = inner.inputDefault;
pub const cardSurface = inner.cardSurface;
