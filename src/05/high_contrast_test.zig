//! R95 — High-contrast accessibility palette unit tests.
//! Tests that Palette.highContrast() and Palette.highContrastDark() return
//! the exact values specified in the R95 requirement.
//! No GPU required. Run via: zig build test-high-contrast

const std = @import("std");
const testing = std.testing;
const Th = @import("../../docs/specs/05.types.zig");

const Palette = Th.Palette;
const Tokens = Th.Tokens;
const Theme = Th.Theme;
const Color = Th.Color;

// Helper: compare two colors for equality.
fn colorEq(a: Color, b: Color) bool {
    return a.r == b.r and a.g == b.g and a.b == b.b and a.a == b.a;
}

// ---------------------------------------------------------------------------
// 1. Palette.highContrast() — specific hardcoded values from spec
// ---------------------------------------------------------------------------

test "highContrast: gray_50 is pure white (0xFFFFFF)" {
    const p = Palette.highContrast();
    try testing.expect(colorEq(p.gray_50, Color.hex(0xFFFFFF)));
}

test "highContrast: gray_900 is pure black (0x000000)" {
    const p = Palette.highContrast();
    try testing.expect(colorEq(p.gray_900, Color.hex(0x000000)));
}

test "highContrast: accent_400 is deep blue (0x0055CC)" {
    const p = Palette.highContrast();
    try testing.expect(colorEq(p.accent_400, Color.hex(0x0055CC)));
}

test "highContrast: ok_400 is dark green (0x1A6B00)" {
    const p = Palette.highContrast();
    try testing.expect(colorEq(p.ok_400, Color.hex(0x1A6B00)));
}

test "highContrast: warn_400 is dark amber (0x7A4F00)" {
    const p = Palette.highContrast();
    try testing.expect(colorEq(p.warn_400, Color.hex(0x7A4F00)));
}

test "highContrast: err_400 is dark red (0xCC0000)" {
    const p = Palette.highContrast();
    try testing.expect(colorEq(p.err_400, Color.hex(0xCC0000)));
}

test "highContrast: info_400 is deep navy blue (0x0055BB)" {
    const p = Palette.highContrast();
    try testing.expect(colorEq(p.info_400, Color.hex(0x0055BB)));
}

test "highContrast: base spacing is 4" {
    const p = Palette.highContrast();
    try testing.expectEqual(@as(f32, 4.0), p.base);
}

// ---------------------------------------------------------------------------
// 2. Palette.highContrastDark() — specific hardcoded values from spec
// ---------------------------------------------------------------------------

test "highContrastDark: gray_50 is pure white (0xFFFFFF)" {
    const p = Palette.highContrastDark();
    try testing.expect(colorEq(p.gray_50, Color.hex(0xFFFFFF)));
}

test "highContrastDark: gray_900 is pure black (0x000000)" {
    const p = Palette.highContrastDark();
    try testing.expect(colorEq(p.gray_900, Color.hex(0x000000)));
}

test "highContrastDark: accent_400 is bright yellow (0xFFCC00)" {
    const p = Palette.highContrastDark();
    try testing.expect(colorEq(p.accent_400, Color.hex(0xFFCC00)));
}

test "highContrastDark: ok_400 is bright green (0x66DD00)" {
    const p = Palette.highContrastDark();
    try testing.expect(colorEq(p.ok_400, Color.hex(0x66DD00)));
}

test "highContrastDark: warn_400 is bright orange (0xFFAA00)" {
    const p = Palette.highContrastDark();
    try testing.expect(colorEq(p.warn_400, Color.hex(0xFFAA00)));
}

test "highContrastDark: err_400 is bright red (0xFF5555)" {
    const p = Palette.highContrastDark();
    try testing.expect(colorEq(p.err_400, Color.hex(0xFF5555)));
}

test "highContrastDark: info_400 is sky blue (0x55AAFF)" {
    const p = Palette.highContrastDark();
    try testing.expect(colorEq(p.info_400, Color.hex(0x55AAFF)));
}

test "highContrastDark: base spacing is 4" {
    const p = Palette.highContrastDark();
    try testing.expectEqual(@as(f32, 4.0), p.base);
}

// ---------------------------------------------------------------------------
// 3. highContrast differs from default palette
// ---------------------------------------------------------------------------

test "highContrast: gray_50 differs from default palette gray_50" {
    const hc = Palette.highContrast();
    const def = Palette.default();
    try testing.expect(!colorEq(hc.gray_50, def.gray_50));
}

test "highContrast: gray_900 differs from default palette gray_900" {
    const hc = Palette.highContrast();
    const def = Palette.default();
    try testing.expect(!colorEq(hc.gray_900, def.gray_900));
}

test "highContrast: accent_400 differs from default accent_400" {
    const hc = Palette.highContrast();
    const def = Palette.default();
    try testing.expect(!colorEq(hc.accent_400, def.accent_400));
}

// ---------------------------------------------------------------------------
// 4. highContrast and highContrastDark are distinct palettes
// ---------------------------------------------------------------------------

test "highContrast and highContrastDark have different accent colors" {
    const hc = Palette.highContrast();
    const hcd = Palette.highContrastDark();
    // Light HC uses deep blue (0x0055CC), dark HC uses bright yellow (0xFFCC00).
    try testing.expect(!colorEq(hc.accent_400, hcd.accent_400));
    // bg_canvas differs: hc_light is white, hc_dark is black.
    try testing.expect(!colorEq(Theme.hc_light.tokens.bg_canvas, Theme.hc_dark.tokens.bg_canvas));
}

// ---------------------------------------------------------------------------
// 5. Theme.hc_light / Theme.hc_dark convenience constants
// ---------------------------------------------------------------------------

test "Theme.hc_light: bg_canvas is pure white" {
    try testing.expectEqual(@as(u8, 255), Theme.hc_light.tokens.bg_canvas.r);
    try testing.expectEqual(@as(u8, 255), Theme.hc_light.tokens.bg_canvas.g);
    try testing.expectEqual(@as(u8, 255), Theme.hc_light.tokens.bg_canvas.b);
}

test "Theme.hc_dark: bg_canvas is pure black" {
    try testing.expectEqual(@as(u8, 0), Theme.hc_dark.tokens.bg_canvas.r);
    try testing.expectEqual(@as(u8, 0), Theme.hc_dark.tokens.bg_canvas.g);
    try testing.expectEqual(@as(u8, 0), Theme.hc_dark.tokens.bg_canvas.b);
}

test "Theme.hc_light: text_body is pure black (gray_900 = 0x000000)" {
    try testing.expectEqual(@as(u8, 0), Theme.hc_light.tokens.text_body.r);
    try testing.expectEqual(@as(u8, 0), Theme.hc_light.tokens.text_body.g);
    try testing.expectEqual(@as(u8, 0), Theme.hc_light.tokens.text_body.b);
}

test "Theme.hc_dark: text_body is pure white (gray_50 = 0xFFFFFF in dark mode)" {
    // In dark mode text_body = palette.gray_50 = 0xFFFFFF for highContrastDark.
    // hcd.gray_50 = 0xFFFFFF (white).
    try testing.expectEqual(@as(u8, 255), Theme.hc_dark.tokens.text_body.r);
    try testing.expectEqual(@as(u8, 255), Theme.hc_dark.tokens.text_body.g);
    try testing.expectEqual(@as(u8, 255), Theme.hc_dark.tokens.text_body.b);
}

test "Theme.hc_light: accent is deep blue (0x0055CC)" {
    const expected = Color.hex(0x0055CC);
    try testing.expectEqual(expected.r, Theme.hc_light.tokens.accent.r);
    try testing.expectEqual(expected.g, Theme.hc_light.tokens.accent.g);
    try testing.expectEqual(expected.b, Theme.hc_light.tokens.accent.b);
}

test "Theme.hc_dark: accent is bright yellow (0xFFCC00)" {
    const expected = Color.hex(0xFFCC00);
    try testing.expectEqual(expected.r, Theme.hc_dark.tokens.accent.r);
    try testing.expectEqual(expected.g, Theme.hc_dark.tokens.accent.g);
    try testing.expectEqual(expected.b, Theme.hc_dark.tokens.accent.b);
}
