//! R90 — DebugOverlay unit tests.
//! Tests init/toggle/isEnabled state machine and the disabled-path early return.
//! No GPU, no GLFW required. Run via: zig build test-debug-overlay

const std = @import("std");
const testing = std.testing;
const overlay_mod = @import("debug_overlay.zig");
const mod02 = @import("../02/types.zig");
const mod05 = @import("../05/types.zig");
const mod07 = @import("../07/types.zig");

const DebugOverlay = overlay_mod.DebugOverlay;
/// Sentinel value for "no element hovered".
const NONE: u32 = std.math.maxInt(u32);

// ---------------------------------------------------------------------------
// 1. init() — default state
// ---------------------------------------------------------------------------

test "init: overlay starts disabled" {
    const o = DebugOverlay.init();
    try testing.expect(!o.enabled);
}

test "init: hovered_idx starts as NONE sentinel" {
    const o = DebugOverlay.init();
    try testing.expectEqual(NONE, o.hovered_idx);
}

// ---------------------------------------------------------------------------
// 2. toggle() — state machine transitions
// ---------------------------------------------------------------------------

test "toggle: disabled becomes enabled" {
    var o = DebugOverlay.init();
    o.toggle();
    try testing.expect(o.enabled);
}

test "toggle: enabled becomes disabled" {
    var o = DebugOverlay.init();
    o.toggle(); // → enabled
    o.toggle(); // → disabled
    try testing.expect(!o.enabled);
}

test "toggle: three toggles restores enabled" {
    var o = DebugOverlay.init();
    o.toggle();
    o.toggle();
    o.toggle();
    try testing.expect(o.enabled);
}

test "toggle: four toggles restores disabled" {
    var o = DebugOverlay.init();
    o.toggle();
    o.toggle();
    o.toggle();
    o.toggle();
    try testing.expect(!o.enabled);
}

// ---------------------------------------------------------------------------
// 3. isEnabled() — reflects .enabled field
// ---------------------------------------------------------------------------

test "isEnabled: returns false after init" {
    const o = DebugOverlay.init();
    try testing.expect(!o.isEnabled());
}

test "isEnabled: returns true after single toggle" {
    var o = DebugOverlay.init();
    o.toggle();
    try testing.expect(o.isEnabled());
}

test "isEnabled: mirrors .enabled field before and after toggle" {
    var o = DebugOverlay.init();
    try testing.expectEqual(o.enabled, o.isEnabled());
    o.toggle();
    try testing.expectEqual(o.enabled, o.isEnabled());
    o.toggle();
    try testing.expectEqual(o.enabled, o.isEnabled());
}

// ---------------------------------------------------------------------------
// 4. buildDebugDrawList — disabled early return (no GPU required).
//    Font and atlas pointers are NEVER dereferenced because !enabled returns
//    before touching them.
// ---------------------------------------------------------------------------

test "buildDebugDrawList: returns empty slice when disabled" {
    const o = DebugOverlay.init(); // disabled by default
    var scene = mod07.Scene.init(testing.allocator);
    defer scene.deinit();

    const tokens = mod05.Tokens.light(mod05.Palette.default());
    // Undefined — safe because the disabled path returns before accessing them.
    var font: mod02.Font = undefined;
    var atlas: mod02.GlyphAtlas = undefined;

    const cmds = try o.buildDebugDrawList(testing.allocator, &scene, tokens, &font, &atlas);
    try testing.expectEqual(@as(usize, 0), cmds.len);
}

test "buildDebugDrawList: repeated disabled calls produce empty slices without leaking" {
    var o = DebugOverlay.init(); // disabled
    var scene = mod07.Scene.init(testing.allocator);
    defer scene.deinit();

    const tokens = mod05.Tokens.light(mod05.Palette.default());
    var font: mod02.Font = undefined;
    var atlas: mod02.GlyphAtlas = undefined;

    for (0..8) |_| {
        const cmds = try o.buildDebugDrawList(testing.allocator, &scene, tokens, &font, &atlas);
        try testing.expectEqual(@as(usize, 0), cmds.len);
    }
}

test "buildDebugDrawList: high-contrast tokens still return empty when disabled" {
    const o = DebugOverlay.init(); // disabled
    var scene = mod07.Scene.init(testing.allocator);
    defer scene.deinit();

    const tokens = mod05.Tokens.light(mod05.Palette.highContrast());
    var font: mod02.Font = undefined;
    var atlas: mod02.GlyphAtlas = undefined;

    const cmds = try o.buildDebugDrawList(testing.allocator, &scene, tokens, &font, &atlas);
    try testing.expectEqual(@as(usize, 0), cmds.len);
}

// ---------------------------------------------------------------------------
// 5. updateHover — empty scene always yields NONE
// ---------------------------------------------------------------------------

test "updateHover: empty scene keeps NONE after call" {
    var o = DebugOverlay.init();
    var scene = mod07.Scene.init(testing.allocator);
    defer scene.deinit();

    o.updateHover(&scene, 100.0, 200.0);
    try testing.expectEqual(NONE, o.hovered_idx);
}

test "updateHover: coordinate (0, 0) on empty scene keeps NONE" {
    var o = DebugOverlay.init();
    var scene = mod07.Scene.init(testing.allocator);
    defer scene.deinit();

    o.updateHover(&scene, 0.0, 0.0);
    try testing.expectEqual(NONE, o.hovered_idx);
}

test "updateHover: large coordinates on empty scene keep NONE" {
    var o = DebugOverlay.init();
    var scene = mod07.Scene.init(testing.allocator);
    defer scene.deinit();

    o.updateHover(&scene, 99999.0, 99999.0);
    try testing.expectEqual(NONE, o.hovered_idx);
}

test "updateHover: multiple calls on empty scene keep NONE" {
    var o = DebugOverlay.init();
    var scene = mod07.Scene.init(testing.allocator);
    defer scene.deinit();

    o.updateHover(&scene, 0.0, 0.0);
    o.updateHover(&scene, 50.0, 100.0);
    o.updateHover(&scene, 1920.0, 1080.0);
    try testing.expectEqual(NONE, o.hovered_idx);
}
