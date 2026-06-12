//! R93 — Theme live-swap unit tests.
//! Tests the pure Theme/Palette/Mode API: light vs dark token differences,
//! Theme.build with same palette, Mode enum values.
//! AppInner.setTheme and .toggleTheme require GPU context — see comments below.
//! No GPU required. Run via: zig build test-theme-swap

const std = @import("std");
const testing = std.testing;
const Th = @import("../05/types.zig");

const Palette = Th.Palette;
const Tokens = Th.Tokens;
const Theme = Th.Theme;
const Mode = Th.Mode;

// ---------------------------------------------------------------------------
// 1. Mode enum
// ---------------------------------------------------------------------------

test "Mode enum has .light variant" {
    const m: Mode = .light;
    try testing.expect(m == .light);
}

test "Mode enum has .dark variant" {
    const m: Mode = .dark;
    try testing.expect(m == .dark);
}

test "Mode enum: light and dark are distinct" {
    try testing.expect(Mode.light != Mode.dark);
}

// ---------------------------------------------------------------------------
// 2. Theme.build — light vs dark produce different bg_canvas
// ---------------------------------------------------------------------------

test "Theme.build: light mode bg_canvas equals palette gray_50" {
    const p = Palette.default();
    const theme = Theme.build(p, .light);
    try testing.expectEqual(p.gray_50.r, theme.tokens.bg_canvas.r);
    try testing.expectEqual(p.gray_50.g, theme.tokens.bg_canvas.g);
    try testing.expectEqual(p.gray_50.b, theme.tokens.bg_canvas.b);
}

test "Theme.build: dark mode bg_canvas equals palette gray_900" {
    const p = Palette.default();
    const theme = Theme.build(p, .dark);
    try testing.expectEqual(p.gray_900.r, theme.tokens.bg_canvas.r);
    try testing.expectEqual(p.gray_900.g, theme.tokens.bg_canvas.g);
    try testing.expectEqual(p.gray_900.b, theme.tokens.bg_canvas.b);
}

test "Theme.build: light and dark bg_canvas differ for default palette" {
    const p = Palette.default();
    const light = Theme.build(p, .light);
    const dark = Theme.build(p, .dark);
    // gray_50 != gray_900 for the default palette
    try testing.expect(
        light.tokens.bg_canvas.r != dark.tokens.bg_canvas.r or
            light.tokens.bg_canvas.g != dark.tokens.bg_canvas.g or
            light.tokens.bg_canvas.b != dark.tokens.bg_canvas.b,
    );
}

// ---------------------------------------------------------------------------
// 3. Light mode — specific token roles from spec
// ---------------------------------------------------------------------------

test "light mode: text_body equals gray_900" {
    const p = Palette.default();
    const t = Theme.build(p, .light).tokens;
    try testing.expectEqual(p.gray_900.r, t.text_body.r);
    try testing.expectEqual(p.gray_900.g, t.text_body.g);
    try testing.expectEqual(p.gray_900.b, t.text_body.b);
}

test "light mode: accent equals palette accent_400" {
    const p = Palette.default();
    const t = Theme.build(p, .light).tokens;
    try testing.expectEqual(p.accent_400.r, t.accent.r);
    try testing.expectEqual(p.accent_400.g, t.accent.g);
    try testing.expectEqual(p.accent_400.b, t.accent.b);
}

// ---------------------------------------------------------------------------
// 4. Dark mode — specific token roles from spec
// ---------------------------------------------------------------------------

test "dark mode: text_body equals gray_50" {
    const p = Palette.default();
    const t = Theme.build(p, .dark).tokens;
    try testing.expectEqual(p.gray_50.r, t.text_body.r);
    try testing.expectEqual(p.gray_50.g, t.text_body.g);
    try testing.expectEqual(p.gray_50.b, t.text_body.b);
}

test "dark mode: accent equals palette accent_400 (same as light)" {
    const p = Palette.default();
    const light_accent = Theme.build(p, .light).tokens.accent;
    const dark_accent = Theme.build(p, .dark).tokens.accent;
    try testing.expectEqual(light_accent.r, dark_accent.r);
    try testing.expectEqual(light_accent.g, dark_accent.g);
    try testing.expectEqual(light_accent.b, dark_accent.b);
}

// ---------------------------------------------------------------------------
// 5. Theme.build with non-default palette
// ---------------------------------------------------------------------------

test "Theme.build: high-contrast light — bg_canvas is pure white" {
    const hc_theme = Theme.build(Palette.highContrast(), .light);
    try testing.expectEqual(@as(u8, 255), hc_theme.tokens.bg_canvas.r);
    try testing.expectEqual(@as(u8, 255), hc_theme.tokens.bg_canvas.g);
    try testing.expectEqual(@as(u8, 255), hc_theme.tokens.bg_canvas.b);
}

test "Theme.build: high-contrast dark — bg_canvas is pure black" {
    const hc_dark_theme = Theme.build(Palette.highContrastDark(), .dark);
    try testing.expectEqual(@as(u8, 0), hc_dark_theme.tokens.bg_canvas.r);
    try testing.expectEqual(@as(u8, 0), hc_dark_theme.tokens.bg_canvas.g);
    try testing.expectEqual(@as(u8, 0), hc_dark_theme.tokens.bg_canvas.b);
}

// ---------------------------------------------------------------------------
// 6. Spacing and radii are mode-independent (same for light and dark)
// ---------------------------------------------------------------------------

test "spacing tokens are identical in light and dark modes" {
    const p = Palette.default();
    const light = Theme.build(p, .light).tokens;
    const dark = Theme.build(p, .dark).tokens;
    try testing.expectEqual(light.sp_xs, dark.sp_xs);
    try testing.expectEqual(light.sp_sm, dark.sp_sm);
    try testing.expectEqual(light.sp_md, dark.sp_md);
    try testing.expectEqual(light.sp_lg, dark.sp_lg);
    try testing.expectEqual(light.sp_xl, dark.sp_xl);
}

test "radius tokens are identical in light and dark modes" {
    const p = Palette.default();
    const light = Theme.build(p, .light).tokens;
    const dark = Theme.build(p, .dark).tokens;
    try testing.expectEqual(light.radius_sm, dark.radius_sm);
    try testing.expectEqual(light.radius_md, dark.radius_md);
    try testing.expectEqual(light.radius_lg, dark.radius_lg);
}

// ---------------------------------------------------------------------------
// NOTE: AppInner.setTheme and AppInner.toggleTheme require a live GPU context
// (VulkanBackend, GLFW window, full renderer pipeline). They cannot be unit-tested
// headlessly. Verify manually or in integration tests with GPU.
// ---------------------------------------------------------------------------
