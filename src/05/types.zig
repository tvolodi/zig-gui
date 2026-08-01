//! 05 — Theme — src/05/types.zig
//!
//! Contract (INV-5.1). The struct shapes (Color, Palette, Tokens, ComputedStyle) and all
//! public signatures are the contract — match them exactly. `Color.hex` and `Palette.default`
//! are implemented here (they are data/definitions); `Tokens.light/dark`, the component-style
//! builders, and `Theme.build` are implemented per spec.md. Do not change signatures.
//!
//! Depends on std and module 03 (for Insets). 03 < 05 in the corrected build order (see
//! spec.md "Build-order correction"), so this import is legal.
//!
//! (AGENT AMENDMENT 2026-06-14: SR-03 — moved canonical impl from docs/specs/05.types.zig
//!  to src/05/types.zig per INV-5.7; src/ is now the sole compilation source.)

const std = @import("std");
const store = @import("../03/types.zig");

pub const Insets = store.Insets;

/// RN16 — Standard transition/enter-exit animation duration, in frames.
/// Derived from AI-Qadam's own CSS (`transition: all 150ms var(--ease-out)`) at an assumed
/// 60fps display refresh rate: 150ms * 60/1000 = 9 frames. Named here (not scattered as a
/// magic number) so both module 05's mirrored spec and module 07's live `Scene` wiring agree
/// on the same value. See `docs/AGENT_GUIDE.md` §14.7 for the full rationale.
pub const TRANSITION_DURATION_FRAMES: u32 = 9;

// ---------------------------------------------------------------------------
// Layer 0 — Color
// ---------------------------------------------------------------------------

pub const Color = struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8 = 255,

    /// Construct from 0xRRGGBB (opaque).
    pub fn hex(rgb: u24) Color {
        return .{
            .r = @intCast((rgb >> 16) & 0xFF),
            .g = @intCast((rgb >> 8) & 0xFF),
            .b = @intCast(rgb & 0xFF),
            .a = 255,
        };
    }
};

pub const transparent = Color{ .r = 0, .g = 0, .b = 0, .a = 0 };

pub const Mode = enum { light, dark };

// ---------------------------------------------------------------------------
// Layer 1 — Palette (raw values). Only this layer varies between brand themes.
// ---------------------------------------------------------------------------

pub const Palette = struct {
    // gray scale (light → dark)
    gray_50: Color,
    gray_100: Color,
    gray_200: Color,
    gray_400: Color,
    gray_600: Color,
    gray_800: Color,
    gray_900: Color,

    // RN15 — additive stop (2026-08-01, AAP §8): AI-Qadam's distinct dark-mode "card"
    // surface (#171717), separate from the muted/border stop (gray_800, #262626). See
    // Tokens.dark() amendment note below for why this was added.
    gray_850: Color = Color.hex(0x171717),

    // accent ramp
    accent_200: Color,
    accent_400: Color,
    accent_600: Color,

    // RAI — teal accent palette stop (added 2026-08-01 under AAP §8 for the
    // AI-Qadam visual analog; additive only, no invariant change).
    teal_400: Color,

    // status
    ok_400: Color,
    warn_400: Color,
    err_400: Color,
    info_400: Color,

    white: Color,
    black: Color,

    // base spacing unit (px); scale steps are multiples of this
    base: f32 = 4,

    /// A working default palette, derived from AI-Qadam's actual tokens.css/components.css
    /// (OKLCH source values converted to sRGB hex). AI-Qadam is dark-first; dark-mode stops
    /// are treated as primary. Implemented here because it is data, not logic.
    /// (AGENT AMENDMENT 2026-08-01: RN14 visual-analog task — replaced the zinc-based RN12
    /// default with AI-Qadam-derived hex stops. See docs/specs/AMENDMENTS_LOG.md.)
    pub fn default() Palette {
        return .{
            // gray scale — 7 stops carry both light- and dark-mode AI-Qadam surface/text/
            // border values (Tokens.light/dark select which role each stop plays).
            // Light: bg #FFFFFF, card #FCFCFC, muted #F5F5F5, border #E5E5E5,
            //        muted-fg #737373, fg #0A0A0A.
            // Dark:  bg #0A0A0A, card #171717, muted/border #262626, muted-fg #A1A1A1,
            //        fg #FAFAFA.
            .gray_50 = Color.hex(0xFAFAFA), // light background (~white) / dark foreground
            .gray_100 = Color.hex(0xF5F5F5), // light muted
            .gray_200 = Color.hex(0xE5E5E5), // light border
            .gray_400 = Color.hex(0x737373), // light muted-foreground
            .gray_600 = Color.hex(0xA1A1A1), // dark muted-foreground
            .gray_800 = Color.hex(0x262626), // dark muted / dark border
            .gray_850 = Color.hex(0x171717), // dark card surface (RN15 — distinct from border)
            .gray_900 = Color.hex(0x0A0A0A), // dark background / light foreground

            .accent_200 = Color.hex(0x5FC4C0), // lighter teal tint — dark-mode hover state
            .accent_400 = Color.hex(0x39B3AF), // AI-Qadam primary teal (dark mode)
            .accent_600 = Color.hex(0x008D89), // AI-Qadam primary teal (light mode, darker)

            .teal_400 = Color.hex(0x39B3AF), // RAI — AI-Qadam primary teal accent (repointed)

            .ok_400 = Color.hex(0x00D391), // AI-Qadam success (dark)
            .warn_400 = Color.hex(0xFFAB00), // AI-Qadam warning (dark)
            .err_400 = Color.hex(0xFF6468), // AI-Qadam destructive (dark)
            .info_400 = Color.hex(0x2563EB), // blue-600 (no AI-Qadam info token — unchanged)

            .white = Color.hex(0xFFFFFF),
            .black = Color.hex(0x000000),
            .base = 4,
        };
    }

    /// R95 — A high-contrast palette meeting WCAG 2.1 AA requirements for all semantic token roles.
    pub fn highContrast() Palette {
        return .{
            .gray_50 = Color.hex(0xFFFFFF),
            .gray_100 = Color.hex(0xF0F0F0),
            .gray_200 = Color.hex(0x767676),
            .gray_400 = Color.hex(0x595959),
            .gray_600 = Color.hex(0x3A3A3A),
            .gray_800 = Color.hex(0x1A1A1A),
            .gray_900 = Color.hex(0x000000),

            .accent_200 = Color.hex(0x4A90D9),
            .accent_400 = Color.hex(0x0055CC),
            .accent_600 = Color.hex(0x003D99),

            .teal_400 = Color.hex(0x4DD0C0),

            .ok_400 = Color.hex(0x1A6B00),
            .warn_400 = Color.hex(0x7A4F00),
            .err_400 = Color.hex(0xCC0000),
            .info_400 = Color.hex(0x0055BB),

            .white = Color.hex(0xFFFFFF),
            .black = Color.hex(0x000000),
            .base = 4,
        };
    }

    /// R95 — High-contrast dark palette — white text on near-black background.
    pub fn highContrastDark() Palette {
        return .{
            .gray_50 = Color.hex(0xFFFFFF),
            .gray_100 = Color.hex(0xE8E8E8),
            .gray_200 = Color.hex(0xC8C8C8),
            .gray_400 = Color.hex(0x9E9E9E),
            .gray_600 = Color.hex(0x3A3A3A),
            .gray_800 = Color.hex(0x1A1A1A),
            .gray_900 = Color.hex(0x000000),

            .accent_200 = Color.hex(0xFFE066),
            .accent_400 = Color.hex(0xFFCC00),
            .accent_600 = Color.hex(0xCC9900),

            .teal_400 = Color.hex(0x66E0CC),

            .ok_400 = Color.hex(0x66DD00),
            .warn_400 = Color.hex(0xFFAA00),
            .err_400 = Color.hex(0xFF5555),
            .info_400 = Color.hex(0x55AAFF),

            .white = Color.hex(0xFFFFFF),
            .black = Color.hex(0x000000),
            .base = 4,
        };
    }
};

// ---------------------------------------------------------------------------
// Layer 2 — Semantic tokens (roles). Built from a palette + mode.
// ---------------------------------------------------------------------------

pub const Tokens = struct {
    // surfaces
    bg_canvas: Color,
    bg_surface: Color,
    bg_raised: Color,

    // text
    text_body: Color,
    text_muted: Color,
    text_disabled: Color,

    // borders
    border_subtle: Color,
    border_default: Color,
    border_strong: Color,

    // accent / interactive
    accent: Color,
    accent_hover: Color,
    accent_text: Color,

    // RAI — teal accent semantic token (added 2026-08-01 under AAP §8 for the
    // AI-Qadam visual analog). Mirrors the role of `accent` but makes the
    // brand-specific teal available without disturbing the default zinc palette
    // used by other showcase screens.
    accent_teal: Color,

    // semantic status colors
    ok: Color,
    warn: Color,
    err: Color,
    info: Color,

    // spacing scale (strictly increasing)
    sp_xs: f32,
    sp_sm: f32,
    sp_md: f32,
    sp_lg: f32,
    sp_xl: f32,

    // radii (strictly increasing)
    radius_sm: f32,
    radius_md: f32,
    radius_lg: f32,
    // RN14 — additive field (2026-08-01, AAP §8): AI-Qadam's --radius-xl stop (16px),
    // used by Card in the visual-analog task. Wired in both light() and dark() below;
    // does not change any existing signature (INV-5.1).
    radius_xl: f32 = 16,

    // type sizes (strictly increasing)
    text_xs: f32,
    text_sm: f32,
    text_base: f32,
    text_lg: f32,
    text_xl: f32,

    /// Map palette stops to roles for LIGHT mode (see spec.md "Light vs dark mapping").
    /// (AGENT AMENDMENT 2026-08-01: RN14 — remapped role→stop assignments to fit AI-Qadam's
    /// actual (asymmetric) light/dark ramps: background #FFFFFF, muted #F5F5F5,
    /// border #E5E5E5, muted-foreground #737373, foreground #0A0A0A.)
    pub fn light(p: Palette) Tokens {
        return .{
            .bg_canvas = p.gray_50,
            .bg_surface = p.gray_100,
            .bg_raised = p.white,

            .text_body = p.gray_900,
            .text_muted = p.gray_400,
            .text_disabled = p.gray_200,

            .border_subtle = p.gray_100,
            .border_default = p.gray_200,
            .border_strong = p.gray_400,

            .accent = p.accent_400,
            .accent_hover = p.accent_600,
            .accent_text = p.gray_50,

            .accent_teal = p.teal_400,

            .ok = p.ok_400,
            .warn = p.warn_400,
            .err = p.err_400,
            .info = p.info_400,

            .sp_xs = 4,
            .sp_sm = 8,
            .sp_md = 16,
            .sp_lg = 24,
            .sp_xl = 32,

            .radius_sm = 6,
            .radius_md = 8,
            .radius_lg = 12,
            .radius_xl = 16,

            .text_xs = 10,
            .text_sm = 12,
            .text_base = 14,
            .text_lg = 18,
            .text_xl = 24,
        };
    }

    /// Map palette stops to roles for DARK mode. `accent` MUST equal the light-mode accent.
    /// (AGENT AMENDMENT 2026-08-01: RN14 — remapped role→stop assignments to fit AI-Qadam's
    /// actual dark ramp: background #0A0A0A, card/raised & muted/border #262626,
    /// muted-foreground #A1A1A1, foreground #FAFAFA.
    /// SUPERSEDED (AGENT AMENDMENT 2026-08-01, RN15, via AAP §8): the RN14 approximation
    /// above — bg_surface/bg_raised sharing gray_800 (#262626) with border_default — made
    /// Card/Input borders invisible against their own fill (Workflow 2 issue resolution,
    /// Visual Tester finding: sampled border hex == sampled fill hex). AI-Qadam's card
    /// surface (#171717) is genuinely distinct from its border/muted stop (#262626); the
    /// Palette now carries a dedicated `gray_850` stop (#171717) for it (additive field,
    /// no signature change, INV-5.1). bg_surface/bg_raised now map to gray_850 so fill and
    /// border are visually distinct, matching the AI-Qadam source exactly instead of
    /// approximating.
    pub fn dark(p: Palette) Tokens {
        return .{
            .bg_canvas = p.gray_900,
            .bg_surface = p.gray_850,
            .bg_raised = p.gray_850,

            .text_body = p.gray_50,
            .text_muted = p.gray_600,
            .text_disabled = p.gray_400,

            .border_subtle = p.gray_900,
            .border_default = p.gray_800,
            .border_strong = p.gray_600,

            .accent = p.accent_400,
            .accent_hover = p.accent_200,
            .accent_text = p.gray_900,

            .accent_teal = p.teal_400,

            .ok = p.ok_400,
            .warn = p.warn_400,
            .err = p.err_400,
            .info = p.info_400,

            .sp_xs = 4,
            .sp_sm = 8,
            .sp_md = 16,
            .sp_lg = 24,
            .sp_xl = 32,

            .radius_sm = 6,
            .radius_md = 8,
            .radius_lg = 12,
            .radius_xl = 16,

            .text_xs = 10,
            .text_sm = 12,
            .text_base = 14,
            .text_lg = 18,
            .text_xl = 24,
        };
    }

    /// R94 — Return a copy of the tokens with all five type-scale sizes multiplied by `factor`.
    /// factor = 1.0 → no change. factor = 1.5 → 50% larger.
    /// All other tokens (colors, spacing, radii) are unaffected.
    /// The result is clamped: each size is at least 6 px and at most 96 px.
    pub fn scaled(self: Tokens, factor: f32) Tokens {
        var result = self;
        const clamp = std.math.clamp;
        result.text_xs = clamp(self.text_xs * factor, 6, 96);
        result.text_sm = clamp(self.text_sm * factor, 6, 96);
        result.text_base = clamp(self.text_base * factor, 6, 96);
        result.text_lg = clamp(self.text_lg * factor, 6, 96);
        result.text_xl = clamp(self.text_xl * factor, 6, 96);
        return result;
    }
};

// ---------------------------------------------------------------------------
// Layer 3 — Resolved per-element style (also the output type of the module-06 resolver).
// ---------------------------------------------------------------------------

pub const ComputedStyle = struct {
    background: Color = transparent,
    text_color: Color = transparent,
    border_color: Color = transparent,
    border_width: f32 = 0,
    radius: f32 = 0,
    padding: Insets = .{},
    gap: f32 = 0,
    font_size: f32 = 14,
    truncate: bool = false,
    opacity: f32 = 1.0,
    shadow_blur: f32 = 0,
    shadow_offset_x: f32 = 0,
    shadow_offset_y: f32 = 4,
    shadow_color: Color = .{ .r = 0, .g = 0, .b = 0, .a = 64 },
    /// R60 — bold/italic font variant flags.
    font_bold: bool = false,
    font_italic: bool = false,
    /// M13-01 RD0 — gradient direction (0=none, 1=right, 2=bottom, 3=bottom_right).
    gradient_direction: u32 = 0,

    /// M14-02 — Transition property flags.
    transition_opacity: bool = false,
    transition_background: bool = false,
    transition_colors: bool = false,
    /// Transition duration in frames. 0 = no transition.
    transition_duration: u32 = 0,
    /// M14-03 — Enter/exit animation flags.
    animate_in: bool = false,
    animate_out: bool = false,
    fade_in: bool = false,
    fade_out: bool = false,
    slide_in_from_top: bool = false,
    slide_in_from_bottom: bool = false,
    slide_out_to_top: bool = false,
    slide_out_to_bottom: bool = false,
};

/// M14-02 — Per-element transition state for style animations.
pub const TransitionState = struct {
    active_opacity: bool = false,
    opacity_timeline_idx: u32 = 0xFFFFFFFF,
    from_opacity: f32 = 1.0,
    to_opacity: f32 = 1.0,

    active_background: bool = false,
    background_timeline_idx: u32 = 0xFFFFFFFF,
    from_background: Color = .{ .r = 0, .g = 0, .b = 0, .a = 0 },
    to_background: Color = .{ .r = 0, .g = 0, .b = 0, .a = 0 },

    /// RN16 — border_color transition (additive, INV-5.1). Mirrors the background pair
    /// above; module 07's Scene is the live implementation (see that file for the actual
    /// AnimTimeline wiring — this module-05 copy stays a shape-only spec mirror).
    active_border: bool = false,
    border_timeline_idx: u32 = 0xFFFFFFFF,
    from_border: Color = .{ .r = 0, .g = 0, .b = 0, .a = 0 },
    to_border: Color = .{ .r = 0, .g = 0, .b = 0, .a = 0 },
};

/// M14-03 — Per-element state for enter/exit animations.
pub const EnterExitState = struct {
    entering: bool = false,
    exiting: bool = false,
    enter_timeline_idx: u32 = 0xFFFFFFFF,
    exit_timeline_idx: u32 = 0xFFFFFFFF,
    pending_hidden: bool = false,
};

// ---------------------------------------------------------------------------
// R40 — Pseudo-state styling types
// ---------------------------------------------------------------------------

/// Style deltas applied when a widget is in a given pseudo-state.
/// Only fields that differ from the base style need to be set;
/// a null field means "inherit from base".
pub const PseudoOverride = struct {
    background: ?Color = null,
    text_color: ?Color = null,
    border_color: ?Color = null,
    border_width: ?f32 = null,
    radius: ?f32 = null,
};

/// All pseudo-state overrides for one widget kind (button, input, etc.).
/// Built entirely from tokens (INV-4.3).
pub const PseudoStyleSet = struct {
    hover: PseudoOverride = .{},
    focus: PseudoOverride = .{},
    active: PseudoOverride = .{},
    disabled: PseudoOverride = .{},
};

pub fn buttonPseudo(t: Tokens) PseudoStyleSet {
    return .{
        .hover = .{ .background = t.accent_hover },
        .focus = .{ .border_color = Color.hex(0x0066FF), .border_width = 2 },
        .active = .{ .background = t.accent_hover },
        .disabled = .{ .background = t.bg_surface, .text_color = t.text_disabled },
    };
}

pub fn inputPseudo(t: Tokens) PseudoStyleSet {
    return .{
        .hover = .{ .border_color = t.border_strong },
        .focus = .{ .border_color = Color.hex(0x0066FF), .border_width = 2 },
        .active = .{},
        .disabled = .{ .background = t.bg_canvas, .text_color = t.text_disabled },
    };
}

pub fn dropdownPseudo(t: Tokens) PseudoStyleSet {
    return .{
        .hover = .{ .border_color = t.border_strong },
        .focus = .{ .border_color = Color.hex(0x0066FF), .border_width = 2 },
        .active = .{},
        .disabled = .{ .background = t.bg_canvas, .text_color = t.text_disabled },
    };
}

pub fn checkboxPseudo(t: Tokens) PseudoStyleSet {
    return .{
        .hover = .{ .border_color = t.border_strong },
        .focus = .{ .border_color = Color.hex(0x0066FF), .border_width = 2 },
        .active = .{},
        .disabled = .{ .text_color = t.text_disabled },
    };
}

/// RN16 — Hover overrides for the `ui.Card.hoverable` variant. Card has no focus/active
/// concept (not a focusable widget — see `docs/AGENT_GUIDE.md` §14.7); only hover lightens the
/// surface and strengthens the border, matching AI-Qadam's `.card:hover` treatment.
pub fn cardPseudo(t: Tokens) PseudoStyleSet {
    return .{
        .hover = .{ .background = t.bg_raised, .border_color = t.border_strong },
        .focus = .{},
        .active = .{},
        .disabled = .{},
    };
}

/// Component-style builders. Each derives ENTIRELY from tokens (INV-4.3) — no palette values,
/// no hex literals.
pub fn buttonPrimary(t: Tokens) ComputedStyle {
    return .{
        .background = t.accent,
        .text_color = t.accent_text,
        .border_color = transparent,
        .border_width = 0,
        .radius = t.radius_md,
        .padding = .{ .top = t.sp_sm, .bottom = t.sp_sm, .left = t.sp_md, .right = t.sp_md },
        .gap = 0,
        .font_size = t.text_base,
    };
}

pub fn buttonGhost(t: Tokens) ComputedStyle {
    return .{
        .background = transparent,
        .text_color = t.text_body,
        .border_color = t.border_default,
        .border_width = 1,
        .radius = t.radius_md,
        .padding = .{ .top = t.sp_sm, .bottom = t.sp_sm, .left = t.sp_md, .right = t.sp_md },
        .gap = 0,
        .font_size = t.text_base,
    };
}

pub fn inputDefault(t: Tokens) ComputedStyle {
    return .{
        .background = t.bg_surface,
        .text_color = t.text_body,
        .border_color = t.border_default,
        .border_width = 1,
        .radius = t.radius_sm,
        .padding = .{ .top = t.sp_sm, .bottom = t.sp_sm, .left = t.sp_sm, .right = t.sp_sm },
        .gap = 0,
        .font_size = t.text_base,
    };
}

pub fn cardSurface(t: Tokens) ComputedStyle {
    return .{
        .background = t.bg_surface,
        .text_color = t.text_body,
        .border_color = t.border_subtle,
        .border_width = 1,
        .radius = t.radius_lg,
        .padding = .{ .top = t.sp_md, .bottom = t.sp_md, .left = t.sp_md, .right = t.sp_md },
        .gap = t.sp_md,
        .font_size = t.text_base,
    };
}

// ---------------------------------------------------------------------------
// Theme — the resolved bundle. Swapping theme = rebuild from palette + mode.
// ---------------------------------------------------------------------------

pub const Theme = struct {
    tokens: Tokens,
    palette: Palette,
    mode: Mode,

    pub fn build(palette: Palette, mode: Mode) Theme {
        return .{
            .tokens = switch (mode) {
                .light => Tokens.light(palette),
                .dark => Tokens.dark(palette),
            },
            .palette = palette,
            .mode = mode,
        };
    }

    /// R95 — Convenience constant: light high-contrast theme.
    pub const hc_light = Theme.build(Palette.highContrast(), .light);
    /// R95 — Convenience constant: dark high-contrast theme.
    pub const hc_dark = Theme.build(Palette.highContrastDark(), .dark);
};
