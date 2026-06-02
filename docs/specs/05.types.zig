//! 05 — Theme — types.zig
//!
//! Contract (INV-5.1). The struct shapes (Color, Palette, Tokens, ComputedStyle) and all
//! public signatures are the contract — match them exactly. `Color.hex` and `Palette.default`
//! are implemented here (they are data/definitions); `Tokens.light/dark`, the component-style
//! builders, and `Theme.build` are stubbed — implement per spec.md. Do not change signatures.
//!
//! Depends on std and module 03 (for Insets). 03 < 05 in the corrected build order (see
//! spec.md "Build-order correction"), so this import is legal.

const std = @import("std");
const store = @import("../03_element_store/types.zig");

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
    text_sm: f32,
    text_base: f32,
    text_lg: f32,

    /// Map palette stops to roles for LIGHT mode (see spec.md "Light vs dark mapping").
    pub fn light(p: Palette) Tokens {
        _ = p;
        @compileError("not implemented — implement per spec.md; do not change this signature");
    }

    /// Map palette stops to roles for DARK mode. `accent` MUST equal the light-mode accent.
    pub fn dark(p: Palette) Tokens {
        _ = p;
        @compileError("not implemented — implement per spec.md; do not change this signature");
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
};

/// Component-style builders. Each derives ENTIRELY from tokens (INV-4.3) — no palette values,
/// no hex literals. Stubbed; implement per spec.md.

pub fn buttonPrimary(t: Tokens) ComputedStyle {
    _ = t;
    @compileError("not implemented — implement per spec.md; do not change this signature");
}

pub fn buttonGhost(t: Tokens) ComputedStyle {
    _ = t;
    @compileError("not implemented — implement per spec.md; do not change this signature");
}

pub fn inputDefault(t: Tokens) ComputedStyle {
    _ = t;
    @compileError("not implemented — implement per spec.md; do not change this signature");
}

pub fn cardSurface(t: Tokens) ComputedStyle {
    _ = t;
    @compileError("not implemented — implement per spec.md; do not change this signature");
}

// ---------------------------------------------------------------------------
// Theme — the resolved bundle. Swapping theme = rebuild from palette + mode.
// ---------------------------------------------------------------------------

pub const Theme = struct {
    tokens: Tokens,

    pub fn build(palette: Palette, mode: Mode) Theme {
        _ = palette;
        _ = mode;
        @compileError("not implemented — implement per spec.md; do not change this signature");
    }
};
