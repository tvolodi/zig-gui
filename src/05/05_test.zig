//! 05 — Theme — unit tests
//!
//! Covers edge cases and boundary conditions NOT already in docs/specs/05.acceptance_test.zig.
//! Run via: zig build test-05-unit

const std = @import("std");
const testing = std.testing;
const Th = @import("../../docs/specs/05.types.zig");

fn luminance(c: Th.Color) f32 {
    return 0.299 * @as(f32, @floatFromInt(c.r)) +
        0.587 * @as(f32, @floatFromInt(c.g)) +
        0.114 * @as(f32, @floatFromInt(c.b));
}

fn eqColor(a: Th.Color, b: Th.Color) bool {
    return a.r == b.r and a.g == b.g and a.b == b.b and a.a == b.a;
}

// ---------------------------------------------------------------------------
// 1. Color.hex — black (0x000000) and white (0xFFFFFF)
// ---------------------------------------------------------------------------
test "Color.hex black and white" {
    const black = Th.Color.hex(0x000000);
    try testing.expectEqual(@as(u8, 0), black.r);
    try testing.expectEqual(@as(u8, 0), black.g);
    try testing.expectEqual(@as(u8, 0), black.b);
    try testing.expectEqual(@as(u8, 255), black.a);

    const white = Th.Color.hex(0xFFFFFF);
    try testing.expectEqual(@as(u8, 255), white.r);
    try testing.expectEqual(@as(u8, 255), white.g);
    try testing.expectEqual(@as(u8, 255), white.b);
    try testing.expectEqual(@as(u8, 255), white.a);
}

// ---------------------------------------------------------------------------
// 2. transparent constant — all four fields are zero
// ---------------------------------------------------------------------------
test "transparent constant all fields zero" {
    try testing.expectEqual(@as(u8, 0), Th.transparent.r);
    try testing.expectEqual(@as(u8, 0), Th.transparent.g);
    try testing.expectEqual(@as(u8, 0), Th.transparent.b);
    try testing.expectEqual(@as(u8, 0), Th.transparent.a);
}

// ---------------------------------------------------------------------------
// 3. Palette.default() is deterministic — calling it twice gives same values
// ---------------------------------------------------------------------------
test "Palette.default is deterministic" {
    const p1 = Th.Palette.default();
    const p2 = Th.Palette.default();
    try testing.expect(eqColor(p1.gray_50, p2.gray_50));
    try testing.expect(eqColor(p1.accent_400, p2.accent_400));
    try testing.expect(eqColor(p1.white, p2.white));
    try testing.expect(eqColor(p1.black, p2.black));
    try testing.expectEqual(p1.base, p2.base);
}

// ---------------------------------------------------------------------------
// 4. Palette.default() accent values — verify exact hex values from spec
// ---------------------------------------------------------------------------
test "Palette.default accent values" {
    const p = Th.Palette.default();

    // accent_200 = 0x5DCAA5
    try testing.expectEqual(@as(u8, 0x5D), p.accent_200.r);
    try testing.expectEqual(@as(u8, 0xCA), p.accent_200.g);
    try testing.expectEqual(@as(u8, 0xA5), p.accent_200.b);

    // accent_400 = 0x1D9E75
    try testing.expectEqual(@as(u8, 0x1D), p.accent_400.r);
    try testing.expectEqual(@as(u8, 0x9E), p.accent_400.g);
    try testing.expectEqual(@as(u8, 0x75), p.accent_400.b);

    // accent_600 = 0x0F6E56
    try testing.expectEqual(@as(u8, 0x0F), p.accent_600.r);
    try testing.expectEqual(@as(u8, 0x6E), p.accent_600.g);
    try testing.expectEqual(@as(u8, 0x56), p.accent_600.b);
}

// ---------------------------------------------------------------------------
// 5. Palette.default() base spacing unit is 4.0
// ---------------------------------------------------------------------------
test "Palette.default base spacing is 4" {
    const p = Th.Palette.default();
    try testing.expectEqual(@as(f32, 4.0), p.base);
}

// ---------------------------------------------------------------------------
// 6. Light mode: bg_raised is brighter than bg_canvas
//    white (bg_raised=255) > gray_50 (bg_canvas≈249)
// ---------------------------------------------------------------------------
test "light mode bg_raised brighter than bg_canvas" {
    const t = Th.Tokens.light(Th.Palette.default());
    try testing.expect(luminance(t.bg_raised) > luminance(t.bg_canvas));
}

// ---------------------------------------------------------------------------
// 7. Dark mode: all three surface tokens are darker than light bg_canvas
// ---------------------------------------------------------------------------
test "dark mode surfaces darker than light bg_canvas" {
    const p = Th.Palette.default();
    const lt = Th.Tokens.light(p);
    const dk = Th.Tokens.dark(p);
    const light_canvas_lum = luminance(lt.bg_canvas);
    try testing.expect(luminance(dk.bg_canvas) < light_canvas_lum);
    try testing.expect(luminance(dk.bg_surface) < light_canvas_lum);
    try testing.expect(luminance(dk.bg_raised) < light_canvas_lum);
}

// ---------------------------------------------------------------------------
// 8. accent_hover: light mode uses darker stop, dark mode uses lighter stop
//    => light accent_hover luminance < dark accent_hover luminance
// ---------------------------------------------------------------------------
test "accent_hover differs between modes" {
    const p = Th.Palette.default();
    const lt = Th.Tokens.light(p);
    const dk = Th.Tokens.dark(p);
    // Light uses accent_600 (darker), dark uses accent_200 (lighter)
    try testing.expect(luminance(lt.accent_hover) < luminance(dk.accent_hover));
}

// ---------------------------------------------------------------------------
// 9. buttonPrimary border_color is transparent
// ---------------------------------------------------------------------------
test "buttonPrimary border is transparent" {
    const t = Th.Tokens.light(Th.Palette.default());
    const primary = Th.buttonPrimary(t);
    try testing.expect(eqColor(primary.border_color, Th.transparent));
}

// ---------------------------------------------------------------------------
// 10. cardSurface gap is non-zero
// ---------------------------------------------------------------------------
test "cardSurface gap is non-zero" {
    const t = Th.Tokens.light(Th.Palette.default());
    const card = Th.cardSurface(t);
    try testing.expect(card.gap > 0);
}

// ---------------------------------------------------------------------------
// 11. inputDefault radius < cardSurface radius (radius_sm < radius_lg)
// ---------------------------------------------------------------------------
test "inputDefault radius smaller than cardSurface radius" {
    const t = Th.Tokens.light(Th.Palette.default());
    const input = Th.inputDefault(t);
    const card = Th.cardSurface(t);
    try testing.expect(input.radius < card.radius);
}

// ---------------------------------------------------------------------------
// 12. Theme.build with dark mode: tokens match Tokens.dark() directly
// ---------------------------------------------------------------------------
test "Theme.build dark mode selects dark tokens" {
    const p = Th.Palette.default();
    const dark_theme = Th.Theme.build(p, .dark);
    const direct_dark = Th.Tokens.dark(p);
    try testing.expect(eqColor(dark_theme.tokens.bg_canvas, direct_dark.bg_canvas));
    try testing.expect(eqColor(dark_theme.tokens.bg_surface, direct_dark.bg_surface));
    try testing.expect(eqColor(dark_theme.tokens.bg_raised, direct_dark.bg_raised));
    try testing.expect(eqColor(dark_theme.tokens.accent, direct_dark.accent));
    try testing.expect(eqColor(dark_theme.tokens.accent_hover, direct_dark.accent_hover));
}

// ---------------------------------------------------------------------------
// 13. ComputedStyle defaults — zero-value struct has expected defaults
// ---------------------------------------------------------------------------
test "ComputedStyle defaults" {
    const cs = Th.ComputedStyle{};
    try testing.expect(eqColor(cs.background, Th.transparent));
    try testing.expectEqual(@as(f32, 14), cs.font_size);
    try testing.expectEqual(@as(f32, 0), cs.border_width);
    try testing.expectEqual(@as(f32, 0), cs.gap);
    try testing.expectEqual(@as(f32, 0), cs.radius);
}

// ===========================================================================
// M14-02 — ComputedStyle transition defaults
// ===========================================================================

test "ComputedStyle transition fields default to false/0" {
    const cs = Th.ComputedStyle{};
    try testing.expect(!cs.transition_opacity);
    try testing.expect(!cs.transition_background);
    try testing.expect(!cs.transition_colors);
    try testing.expectEqual(@as(u32, 0), cs.transition_duration);
}

// ===========================================================================
// M14-03 — ComputedStyle enter/exit defaults
// ===========================================================================

test "ComputedStyle enter/exit fields default to false" {
    const cs = Th.ComputedStyle{};
    try testing.expect(!cs.animate_in);
    try testing.expect(!cs.animate_out);
    try testing.expect(!cs.fade_in);
    try testing.expect(!cs.fade_out);
    try testing.expect(!cs.slide_in_from_top);
    try testing.expect(!cs.slide_in_from_bottom);
    try testing.expect(!cs.slide_out_to_top);
    try testing.expect(!cs.slide_out_to_bottom);
}
