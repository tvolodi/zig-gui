//! R94 — Font-scale unit tests.
//! Tests Tokens.scaled() — the pure function that multiplies type-scale sizes.
//! Covers: identity, doubling, halving, min/max clamping, non-affected fields.
//! No GPU required. Run via: zig build test-font-scale

const std = @import("std");
const testing = std.testing;
const Th = @import("../05/types.zig");

const Palette = Th.Palette;
const Tokens = Th.Tokens;

// Helper: construct a default light tokens base.
fn base() Tokens {
    return Tokens.light(Palette.default());
}

// Default type sizes from spec (Tokens.light defaults).
const DEFAULT_XS: f32 = 10;
const DEFAULT_SM: f32 = 12;
const DEFAULT_BASE: f32 = 14;
const DEFAULT_LG: f32 = 18;
const DEFAULT_XL: f32 = 24;

// ---------------------------------------------------------------------------
// 1. Identity — scaled(1.0) is a no-op
// ---------------------------------------------------------------------------

test "scaled(1.0): text_xs unchanged" {
    try testing.expectApproxEqAbs(DEFAULT_XS, base().scaled(1.0).text_xs, 1e-4);
}

test "scaled(1.0): text_sm unchanged" {
    try testing.expectApproxEqAbs(DEFAULT_SM, base().scaled(1.0).text_sm, 1e-4);
}

test "scaled(1.0): text_base unchanged" {
    try testing.expectApproxEqAbs(DEFAULT_BASE, base().scaled(1.0).text_base, 1e-4);
}

test "scaled(1.0): text_lg unchanged" {
    try testing.expectApproxEqAbs(DEFAULT_LG, base().scaled(1.0).text_lg, 1e-4);
}

test "scaled(1.0): text_xl unchanged" {
    try testing.expectApproxEqAbs(DEFAULT_XL, base().scaled(1.0).text_xl, 1e-4);
}

// ---------------------------------------------------------------------------
// 2. Doubling — scaled(2.0) doubles each type size
// ---------------------------------------------------------------------------

test "scaled(2.0): text_xs doubles" {
    try testing.expectApproxEqAbs(DEFAULT_XS * 2.0, base().scaled(2.0).text_xs, 1e-4);
}

test "scaled(2.0): text_sm doubles" {
    try testing.expectApproxEqAbs(DEFAULT_SM * 2.0, base().scaled(2.0).text_sm, 1e-4);
}

test "scaled(2.0): text_base doubles" {
    try testing.expectApproxEqAbs(DEFAULT_BASE * 2.0, base().scaled(2.0).text_base, 1e-4);
}

test "scaled(2.0): text_lg doubles" {
    try testing.expectApproxEqAbs(DEFAULT_LG * 2.0, base().scaled(2.0).text_lg, 1e-4);
}

test "scaled(2.0): text_xl doubles" {
    try testing.expectApproxEqAbs(DEFAULT_XL * 2.0, base().scaled(2.0).text_xl, 1e-4);
}

// ---------------------------------------------------------------------------
// 3. Halving — scaled(0.5) halves each type size (text_xs=10 → 5 → clamped to 6)
// ---------------------------------------------------------------------------

test "scaled(0.5): text_xs clamped to 6 (10*0.5=5 < min 6)" {
    try testing.expectApproxEqAbs(@as(f32, 6.0), base().scaled(0.5).text_xs, 1e-4);
}

test "scaled(0.5): text_sm halves to 6.0 (12*0.5=6 == min)" {
    try testing.expectApproxEqAbs(@as(f32, 6.0), base().scaled(0.5).text_sm, 1e-4);
}

test "scaled(0.5): text_base halves to 7.0" {
    try testing.expectApproxEqAbs(DEFAULT_BASE * 0.5, base().scaled(0.5).text_base, 1e-4);
}

test "scaled(0.5): text_lg halves to 9.0" {
    try testing.expectApproxEqAbs(DEFAULT_LG * 0.5, base().scaled(0.5).text_lg, 1e-4);
}

test "scaled(0.5): text_xl halves to 12.0" {
    try testing.expectApproxEqAbs(DEFAULT_XL * 0.5, base().scaled(0.5).text_xl, 1e-4);
}

// ---------------------------------------------------------------------------
// 4. Minimum clamp — very small factor clamps all sizes to 6
// ---------------------------------------------------------------------------

test "scaled(0.001): all sizes clamp to 6" {
    const s = base().scaled(0.001);
    try testing.expectApproxEqAbs(@as(f32, 6.0), s.text_xs, 1e-4);
    try testing.expectApproxEqAbs(@as(f32, 6.0), s.text_sm, 1e-4);
    try testing.expectApproxEqAbs(@as(f32, 6.0), s.text_base, 1e-4);
    try testing.expectApproxEqAbs(@as(f32, 6.0), s.text_lg, 1e-4);
    try testing.expectApproxEqAbs(@as(f32, 6.0), s.text_xl, 1e-4);
}

// ---------------------------------------------------------------------------
// 5. Maximum clamp — very large factor clamps all sizes to 96
// ---------------------------------------------------------------------------

test "scaled(100.0): all sizes clamp to 96" {
    const s = base().scaled(100.0);
    try testing.expectApproxEqAbs(@as(f32, 96.0), s.text_xs, 1e-4);
    try testing.expectApproxEqAbs(@as(f32, 96.0), s.text_sm, 1e-4);
    try testing.expectApproxEqAbs(@as(f32, 96.0), s.text_base, 1e-4);
    try testing.expectApproxEqAbs(@as(f32, 96.0), s.text_lg, 1e-4);
    try testing.expectApproxEqAbs(@as(f32, 96.0), s.text_xl, 1e-4);
}

// ---------------------------------------------------------------------------
// 6. Non-affected tokens — colors, spacing, radii must not change
// ---------------------------------------------------------------------------

test "scaled(2.0): colors are unaffected" {
    const b = base();
    const s = b.scaled(2.0);
    // bg_canvas
    try testing.expectEqual(b.bg_canvas.r, s.bg_canvas.r);
    try testing.expectEqual(b.bg_canvas.g, s.bg_canvas.g);
    try testing.expectEqual(b.bg_canvas.b, s.bg_canvas.b);
    // accent
    try testing.expectEqual(b.accent.r, s.accent.r);
    try testing.expectEqual(b.accent.g, s.accent.g);
    try testing.expectEqual(b.accent.b, s.accent.b);
    // err
    try testing.expectEqual(b.err.r, s.err.r);
    try testing.expectEqual(b.err.g, s.err.g);
    try testing.expectEqual(b.err.b, s.err.b);
}

test "scaled(2.0): spacing tokens are unaffected" {
    const b = base();
    const s = b.scaled(2.0);
    try testing.expectEqual(b.sp_xs, s.sp_xs);
    try testing.expectEqual(b.sp_sm, s.sp_sm);
    try testing.expectEqual(b.sp_md, s.sp_md);
    try testing.expectEqual(b.sp_lg, s.sp_lg);
    try testing.expectEqual(b.sp_xl, s.sp_xl);
}

test "scaled(2.0): radius tokens are unaffected" {
    const b = base();
    const s = b.scaled(2.0);
    try testing.expectEqual(b.radius_sm, s.radius_sm);
    try testing.expectEqual(b.radius_md, s.radius_md);
    try testing.expectEqual(b.radius_lg, s.radius_lg);
}

// ---------------------------------------------------------------------------
// 7. Boundary — scale factor of exactly 4.0 (max recommended per spec R94)
// ---------------------------------------------------------------------------

test "scaled(4.0): text_base is 56.0 (within 96 cap)" {
    try testing.expectApproxEqAbs(DEFAULT_BASE * 4.0, base().scaled(4.0).text_base, 1e-4);
}

test "scaled(4.0): text_xl is 96.0 (24*4=96 == max)" {
    try testing.expectApproxEqAbs(@as(f32, 96.0), base().scaled(4.0).text_xl, 1e-4);
}

// ---------------------------------------------------------------------------
// NOTE: AppInner.setFontScale() (which clamps factor to [0.5, 4.0] and calls
// rebuildStyles + markAllDirty) requires a live GPU context. Verify manually.
// ---------------------------------------------------------------------------
