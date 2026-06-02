//! 05 — Theme — acceptance_test.zig
//!
//! THIS FILE IS THE SPECIFICATION OF CORRECT BEHAVIOR (INV-5.3). DO NOT EDIT IT TO MAKE AN
//! IMPLEMENTATION PASS. If a test seems wrong, STOP and surface it to the human.
//!
//! All tests are pure (no GPU, no font, no I/O). Run with: `zig test acceptance_test.zig`.
//! "Done" for module 05 == every test passes AND checklist.md is fully ticked.

const std = @import("std");
const testing = std.testing;
const Th = @import("types.zig");

fn luminance(c: Th.Color) f32 {
    return 0.299 * @as(f32, @floatFromInt(c.r)) +
        0.587 * @as(f32, @floatFromInt(c.g)) +
        0.114 * @as(f32, @floatFromInt(c.b));
}

fn eqColor(a: Th.Color, b: Th.Color) bool {
    return a.r == b.r and a.g == b.g and a.b == b.b and a.a == b.a;
}

// ---------------------------------------------------------------------------
// 1. Color.hex splits 0xRRGGBB correctly and is opaque.
// ---------------------------------------------------------------------------
test "Color.hex" {
    const c = Th.Color.hex(0x1D9E75);
    try testing.expectEqual(@as(u8, 0x1D), c.r);
    try testing.expectEqual(@as(u8, 0x9E), c.g);
    try testing.expectEqual(@as(u8, 0x75), c.b);
    try testing.expectEqual(@as(u8, 255), c.a);
    try testing.expectEqual(@as(u8, 0), Th.transparent.a);
}

// ---------------------------------------------------------------------------
// 2. Default palette has a real gray ramp (light end brighter than dark end).
// ---------------------------------------------------------------------------
test "default palette gray ramp ordered" {
    const p = Th.Palette.default();
    try testing.expect(luminance(p.gray_50) > luminance(p.gray_900));
    try testing.expect(luminance(p.gray_50) > luminance(p.gray_400));
    try testing.expect(luminance(p.gray_400) > luminance(p.gray_900));
}

// ---------------------------------------------------------------------------
// 3. Light mode: canvas is light, body text is dark (high contrast).
// ---------------------------------------------------------------------------
test "light mode contrast" {
    const t = Th.Tokens.light(Th.Palette.default());
    try testing.expect(luminance(t.bg_canvas) > luminance(t.text_body));
    try testing.expect(luminance(t.bg_canvas) > 180); // genuinely light
}

// ---------------------------------------------------------------------------
// 4. Dark mode: canvas is dark, body text is light (inverted vs light mode).
// ---------------------------------------------------------------------------
test "dark mode inverts surfaces" {
    const p = Th.Palette.default();
    const lt = Th.Tokens.light(p);
    const dk = Th.Tokens.dark(p);
    try testing.expect(luminance(dk.bg_canvas) < luminance(dk.text_body));
    try testing.expect(luminance(dk.bg_canvas) < luminance(lt.bg_canvas));
    try testing.expect(luminance(dk.text_body) > luminance(lt.text_body));
}

// ---------------------------------------------------------------------------
// 5. Accent role is identical across modes; only accent_hover/accent_text shift.
// ---------------------------------------------------------------------------
test "accent stable across modes" {
    const p = Th.Palette.default();
    const lt = Th.Tokens.light(p);
    const dk = Th.Tokens.dark(p);
    try testing.expect(eqColor(lt.accent, dk.accent));
    // accent must equal the palette's accent_400 (the canonical accent stop).
    try testing.expect(eqColor(lt.accent, p.accent_400));
}

// ---------------------------------------------------------------------------
// 6. Spacing scale and radii are strictly increasing.
// ---------------------------------------------------------------------------
test "scales are monotonic" {
    const t = Th.Tokens.light(Th.Palette.default());
    try testing.expect(t.sp_xs < t.sp_sm);
    try testing.expect(t.sp_sm < t.sp_md);
    try testing.expect(t.sp_md < t.sp_lg);
    try testing.expect(t.sp_lg < t.sp_xl);

    try testing.expect(t.radius_sm < t.radius_md);
    try testing.expect(t.radius_md < t.radius_lg);

    try testing.expect(t.text_sm < t.text_base);
    try testing.expect(t.text_base < t.text_lg);
}

// ---------------------------------------------------------------------------
// 7. INV-4.3: component styles reference TOKENS, not palette values or hex literals.
// ---------------------------------------------------------------------------
test "component styles trace to tokens" {
    const t = Th.Tokens.light(Th.Palette.default());

    const primary = Th.buttonPrimary(t);
    try testing.expect(eqColor(primary.background, t.accent));
    try testing.expect(eqColor(primary.text_color, t.accent_text));

    const ghost = Th.buttonGhost(t);
    try testing.expect(eqColor(ghost.background, Th.transparent));
    try testing.expect(eqColor(ghost.border_color, t.border_default));
    try testing.expect(eqColor(ghost.text_color, t.text_body));

    const input = Th.inputDefault(t);
    try testing.expect(eqColor(input.border_color, t.border_default));

    const card = Th.cardSurface(t);
    try testing.expect(eqColor(card.background, t.bg_surface));
}

// ---------------------------------------------------------------------------
// 8. Component styles pull spacing/radius from tokens too (not magic numbers).
// ---------------------------------------------------------------------------
test "component styles use token spacing and radius" {
    const t = Th.Tokens.light(Th.Palette.default());
    const primary = Th.buttonPrimary(t);
    // radius is one of the token radii (sm/md/lg), not an arbitrary value.
    try testing.expect(primary.radius == t.radius_sm or
        primary.radius == t.radius_md or
        primary.radius == t.radius_lg);
    // horizontal padding is a token spacing step.
    const ph = primary.padding.left;
    try testing.expect(ph == t.sp_sm or ph == t.sp_md or ph == t.sp_lg);
}

// ---------------------------------------------------------------------------
// 9. Theme.build wires the right token set for the mode.
// ---------------------------------------------------------------------------
test "Theme.build selects mode tokens" {
    const p = Th.Palette.default();
    const light_theme = Th.Theme.build(p, .light);
    const dark_theme = Th.Theme.build(p, .dark);

    try testing.expect(eqColor(light_theme.tokens.bg_canvas, Th.Tokens.light(p).bg_canvas));
    try testing.expect(eqColor(dark_theme.tokens.bg_canvas, Th.Tokens.dark(p).bg_canvas));
    // Swapping mode changes the canvas but not the accent.
    try testing.expect(!eqColor(light_theme.tokens.bg_canvas, dark_theme.tokens.bg_canvas));
    try testing.expect(eqColor(light_theme.tokens.accent, dark_theme.tokens.accent));
}
