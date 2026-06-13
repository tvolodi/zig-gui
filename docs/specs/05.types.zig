//! 05 — Theme — types.zig
//!
//! Contract (INV-5.1). The struct shapes (Color, Palette, Tokens, ComputedStyle) and all
//! public signatures are the contract — match them exactly. `Color.hex` and `Palette.default`
//! are implemented here (they are data/definitions); `Tokens.light/dark`, the component-style
//! builders, and `Theme.build` are implemented per spec.md. Do not change signatures.
//!
//! Depends on std and module 03 (for Insets). 03 < 05 in the corrected build order (see
//! spec.md "Build-order correction"), so this import is legal.

const std = @import("std");
const store = @import("./03.types.zig");

pub const Insets = store.Insets;

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

    // accent ramp
    accent_200: Color,
    accent_400: Color,
    accent_600: Color,

    // status
    ok_400: Color,
    warn_400: Color,
    err_400: Color,
    info_400: Color,

    white: Color,
    black: Color,

    // base spacing unit (px); scale steps are multiples of this
    base: f32 = 4,

    /// A working default palette (gray + teal accent + status), so there is a usable theme
    /// out of the box. Implemented here because it is data, not logic.
    pub fn default() Palette {
        return .{
            .gray_50 = Color.hex(0xF9F9F8),
            .gray_100 = Color.hex(0xF1EFE8),
            .gray_200 = Color.hex(0xD3D1C7),
            .gray_400 = Color.hex(0x888780),
            .gray_600 = Color.hex(0x5F5E5A),
            .gray_800 = Color.hex(0x3A3A38),
            .gray_900 = Color.hex(0x2C2C2A),

            .accent_200 = Color.hex(0x5DCAA5),
            .accent_400 = Color.hex(0x1D9E75),
            .accent_600 = Color.hex(0x0F6E56),

            .ok_400 = Color.hex(0x639922),
            .warn_400 = Color.hex(0xBA7517),
            .err_400 = Color.hex(0xE24B4A),
            .info_400 = Color.hex(0x378ADD),

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

    // type sizes (strictly increasing)
    text_xs: f32,
    text_sm: f32,
    text_base: f32,
    text_lg: f32,
    text_xl: f32,

    /// Map palette stops to roles for LIGHT mode (see spec.md "Light vs dark mapping").
    pub fn light(p: Palette) Tokens {
        return .{
            .bg_canvas = p.gray_50,
            .bg_surface = p.gray_100,
            .bg_raised = p.white,

            .text_body = p.gray_900,
            .text_muted = p.gray_600,
            .text_disabled = p.gray_400,

            .border_subtle = p.gray_100,
            .border_default = p.gray_200,
            .border_strong = p.gray_400,

            .accent = p.accent_400,
            .accent_hover = p.accent_600,
            .accent_text = p.white,

            .ok = p.ok_400,
            .warn = p.warn_400,
            .err = p.err_400,
            .info = p.info_400,

            .sp_xs = 4,
            .sp_sm = 8,
            .sp_md = 16,
            .sp_lg = 24,
            .sp_xl = 32,

            .radius_sm = 4,
            .radius_md = 8,
            .radius_lg = 16,

            .text_xs = 10,
            .text_sm = 12,
            .text_base = 14,
            .text_lg = 18,
            .text_xl = 24,
        };
    }

    /// Map palette stops to roles for DARK mode. `accent` MUST equal the light-mode accent.
    pub fn dark(p: Palette) Tokens {
        return .{
            .bg_canvas = p.gray_900,
            .bg_surface = p.gray_800,
            .bg_raised = p.gray_600,

            .text_body = p.gray_50,
            .text_muted = p.gray_200,
            .text_disabled = p.gray_400,

            .border_subtle = p.gray_800,
            .border_default = p.gray_600,
            .border_strong = p.gray_400,

            .accent = p.accent_400,
            .accent_hover = p.accent_200,
            .accent_text = p.white,

            .ok = p.ok_400,
            .warn = p.warn_400,
            .err = p.err_400,
            .info = p.info_400,

            .sp_xs = 4,
            .sp_sm = 8,
            .sp_md = 16,
            .sp_lg = 24,
            .sp_xl = 32,

            .radius_sm = 4,
            .radius_md = 8,
            .radius_lg = 16,

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
