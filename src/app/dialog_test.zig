//! R75 — Modal dialog manager unit tests.
//! Tests DialogManager state transitions without GPU, GLFW, or rendering.

const std = @import("std");
const testing = std.testing;
const dialog_mod = @import("dialog.zig");
const mod07 = @import("../07/types.zig");

pub const DialogManager = dialog_mod.DialogManager;
pub const Scene = mod07.Scene;
pub const NONE: u32 = std.math.maxInt(u32);

fn testTokens() @import("../05/types.zig").Tokens {
    const theme = @import("../05/types.zig");
    return theme.Tokens.light(theme.Palette.default());
}

/// Build a minimal DialogManager without an OverlayLayer.
fn newDialog() DialogManager {
    return DialogManager{};
}

// ---------------------------------------------------------------------------
// open / close / isOpen
// ---------------------------------------------------------------------------

test "open: isOpen() returns true" {
    var d = newDialog();
    var scene = Scene.init(testing.allocator);
    defer scene.deinit();

    try testing.expect(!d.isOpen());
    d.open(NONE, &scene);
    try testing.expect(d.isOpen());
}

test "close: isOpen() returns false" {
    var d = newDialog();
    var scene = Scene.init(testing.allocator);
    defer scene.deinit();

    d.open(NONE, &scene);
    d.close(&scene);
    try testing.expect(!d.isOpen());
}

test "open then close: visible round-trips" {
    var d = newDialog();
    var scene = Scene.init(testing.allocator);
    defer scene.deinit();

    d.open(NONE, &scene);
    try testing.expect(d.isOpen());
    d.close(&scene);
    try testing.expect(!d.isOpen());
}

// ---------------------------------------------------------------------------
// Double open is idempotent
// ---------------------------------------------------------------------------

test "double open: does not crash and stays open" {
    var d = newDialog();
    var scene = Scene.init(testing.allocator);
    defer scene.deinit();

    d.open(NONE, &scene);
    d.open(NONE, &scene); // should not panic
    try testing.expect(d.isOpen());
}

// ---------------------------------------------------------------------------
// Escape key → close
// ---------------------------------------------------------------------------
// The DialogManager does not have a handleKey method; Escape handling is
// performed by the app event dispatcher which calls close() on Escape.
// We verify that close() reliably collapses the dialog (as the dispatcher would).

test "simulate Escape: calling close() hides dialog" {
    var d = newDialog();
    var scene = Scene.init(testing.allocator);
    defer scene.deinit();

    d.open(NONE, &scene);
    // App dispatcher fires close() on Escape:
    d.close(&scene);
    try testing.expect(!d.isOpen());
}

// ---------------------------------------------------------------------------
// NONE sentinel is the correct unset value
// ---------------------------------------------------------------------------

test "content_idx defaults to NONE sentinel" {
    const d = newDialog();
    try testing.expectEqual(NONE, d.content_idx);
}

test "return_focus_idx defaults to NONE sentinel" {
    const d = newDialog();
    try testing.expectEqual(NONE, d.return_focus_idx);
}

// ---------------------------------------------------------------------------
// Focus restore on close
// ---------------------------------------------------------------------------

test "close: restores focus to return_focus_idx" {
    var scene = Scene.init(testing.allocator);
    defer scene.deinit();

    // Create a focusable element (Button) so scene has a valid index to focus.
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const markup = @import("../06/types.zig");
    const desc = try markup.parse(arena.allocator(), "<Button text=\"Trigger\"/>");
    const btn_id = try scene.instantiate(desc, testTokens());
    const btn_idx = btn_id.index;

    // Focus the button before opening the dialog
    scene.setFocus(btn_idx);
    try testing.expectEqual(btn_idx, scene.getFocus());

    var d = newDialog();
    // Open traps focus on NONE (no content)
    d.open(NONE, &scene);
    // close() restores to original focused element
    d.close(&scene);
    // After close, focused_idx should be restored to btn_idx
    try testing.expectEqual(btn_idx, scene.getFocus());
}

// ---------------------------------------------------------------------------
// open with content_idx sets content_idx field
// ---------------------------------------------------------------------------

test "open: content_idx is stored" {
    var scene = Scene.init(testing.allocator);
    defer scene.deinit();

    var d = newDialog();
    d.open(5, &scene);
    try testing.expectEqual(@as(u32, 5), d.content_idx);
}
