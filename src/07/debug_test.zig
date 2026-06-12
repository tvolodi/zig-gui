//! R91 — Scene dump unit tests.
//! Tests that debugPrint / debugPrintStats do not crash on empty and non-empty scenes.
//! Output goes to stderr; content correctness is verified manually.
//! No GPU required. Run via: zig build test-scene-dump

const std = @import("std");
const testing = std.testing;
const scene_mod = @import("types.zig"); // wired to mod07

const Scene = scene_mod.Scene;
const LayoutNode = scene_mod.LayoutNode;

// ---------------------------------------------------------------------------
// 1. Scene.debugPrint — must not crash (output to stderr)
// ---------------------------------------------------------------------------

test "debugPrint: empty scene does not crash" {
    var scene = Scene.init(testing.allocator);
    defer scene.deinit();

    scene.debugPrint();
}

test "debugPrint: scene with one root element does not crash" {
    var scene = Scene.init(testing.allocator);
    defer scene.deinit();

    _ = try scene.elements.addRoot(LayoutNode{});
    scene.debugPrint();
}

test "debugPrint: scene with multiple root elements does not crash" {
    var scene = Scene.init(testing.allocator);
    defer scene.deinit();

    _ = try scene.elements.addRoot(LayoutNode{});
    _ = try scene.elements.addRoot(LayoutNode{});
    _ = try scene.elements.addRoot(LayoutNode{});
    scene.debugPrint();
}

test "debugPrint: scene with parent and child does not crash" {
    var scene = Scene.init(testing.allocator);
    defer scene.deinit();

    const root = try scene.elements.addRoot(LayoutNode{});
    _ = try scene.elements.addChild(root, LayoutNode{});
    scene.debugPrint();
}

// ---------------------------------------------------------------------------
// 2. Scene.debugPrintStats — must not crash
// ---------------------------------------------------------------------------

test "debugPrintStats: empty scene does not crash" {
    var scene = Scene.init(testing.allocator);
    defer scene.deinit();

    scene.debugPrintStats();
}

test "debugPrintStats: scene with one element does not crash" {
    var scene = Scene.init(testing.allocator);
    defer scene.deinit();

    _ = try scene.elements.addRoot(LayoutNode{});
    scene.debugPrintStats();
}

test "debugPrintStats: scene with multiple elements does not crash" {
    var scene = Scene.init(testing.allocator);
    defer scene.deinit();

    const root = try scene.elements.addRoot(LayoutNode{});
    _ = try scene.elements.addChild(root, LayoutNode{});
    _ = try scene.elements.addChild(root, LayoutNode{});
    scene.debugPrintStats();
}

// ---------------------------------------------------------------------------
// 3. Idempotence — calling twice on same scene must not crash
// ---------------------------------------------------------------------------

test "debugPrint: calling twice does not crash" {
    var scene = Scene.init(testing.allocator);
    defer scene.deinit();

    scene.debugPrint();
    scene.debugPrint();
}

test "debugPrintStats: calling twice does not crash" {
    var scene = Scene.init(testing.allocator);
    defer scene.deinit();

    scene.debugPrintStats();
    scene.debugPrintStats();
}
