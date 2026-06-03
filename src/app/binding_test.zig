//! Unit tests for BindingSet and TextBinding (R23 / M2-04).
//!
//! No GPU, no GLFW. All tests use std.testing.allocator for leak detection.
//! Tests cover the binding lifecycle: bindText, dirty propagation, refresh,
//! multi-binding, and deinit.
//!
//! NOTE: Passing a non-Signal field to bindText produces a compile error.
//! Verify manually by changing the field type in the State struct and observing
//! the @compileError emitted by bindText — no runtime test is possible for this.

const std = @import("std");
const binding_mod = @import("binding.zig");
const m07 = @import("../07/types.zig");
const signal_mod = @import("signal.zig");

const BindingSet = binding_mod.BindingSet;
const Scene = m07.Scene;
const ElementId = m07.ElementId;
const Signal = signal_mod.Signal;

// ---------------------------------------------------------------------------
// Helper: build a minimal Scene with `n` elements, each with a text slot.
//
// Uses ElementStore.addRoot() to allocate elements (which populates the
// dirty bitset) and manually appends null entries to _text so that
// Scene.setText(idx, ...) is safe to call for each index.
//
// NOTE: _kind and _style are left empty; Scene.deinit() handles them safely
// because ArrayListUnmanaged.deinit on an empty list is a no-op.
// ---------------------------------------------------------------------------

fn makeScene(gpa: std.mem.Allocator, n: u32) !Scene {
    var scene = Scene.init(gpa);
    var i: u32 = 0;
    while (i < n) : (i += 1) {
        _ = try scene.elements.addRoot(.{});
        // Extend the _text parallel array so setText(i, ...) is valid.
        try scene._text.append(scene.gpa, null);
    }
    return scene;
}

// ---------------------------------------------------------------------------
// Application state struct — used across multiple tests.
// ---------------------------------------------------------------------------

const State = struct {
    greeting: Signal([]const u8),
};

// ===========================================================================
// Tests
// ===========================================================================

test "bindText: signal.set marks element_idx dirty in the ElementStore dirty bitset" {
    const gpa = std.testing.allocator;

    var scene = try makeScene(gpa, 1);
    defer scene.deinit();

    var state = State{
        .greeting = Signal([]const u8).init(gpa, "hello", &scene.elements.dirty),
    };
    defer state.greeting.deinit();

    var bindings = BindingSet.init();
    defer bindings.deinit(gpa);

    try bindings.bindText(State, "greeting", &state, 0, gpa);

    // addRoot already marked element 0 dirty; clear it so we can observe
    // the effect of signal.set() in isolation.
    scene.elements.dirty.unset(0);
    try std.testing.expect(!scene.elements.dirty.isSet(0));

    state.greeting.set("world");

    // After set(), the dirty bitset must have bit 0 set (R20 / R23 AC).
    try std.testing.expect(scene.elements.dirty.isSet(0));
}

test "bindText + refresh: element text slot equals signal value after refresh" {
    const gpa = std.testing.allocator;

    var scene = try makeScene(gpa, 1);
    defer scene.deinit();

    var state = State{
        .greeting = Signal([]const u8).init(gpa, "initial", &scene.elements.dirty),
    };
    defer state.greeting.deinit();

    var bindings = BindingSet.init();
    defer bindings.deinit(gpa);

    try bindings.bindText(State, "greeting", &state, 0, gpa);

    state.greeting.set("updated");
    bindings.refresh(&scene);

    const id = ElementId{ .index = 0, .gen = scene.elements.gen.items[0] };
    const txt = scene.textOf(id);
    try std.testing.expect(txt != null);
    try std.testing.expectEqualStrings("updated", txt.?);
}

test "BindingSet.deinit: no memory leaks" {
    const gpa = std.testing.allocator;

    var scene = try makeScene(gpa, 1);
    defer scene.deinit();

    var state = State{
        .greeting = Signal([]const u8).init(gpa, "hello", &scene.elements.dirty),
    };
    defer state.greeting.deinit();

    var bindings = BindingSet.init();
    try bindings.bindText(State, "greeting", &state, 0, gpa);
    // deinit must free the internal text ArrayList.
    bindings.deinit(gpa);
    // std.testing.allocator detects any remaining allocation as a leak.
}

test "refresh: multiple bindings all update their respective text slots" {
    const gpa = std.testing.allocator;

    var scene = try makeScene(gpa, 3);
    defer scene.deinit();

    const MultiState = struct {
        a: Signal([]const u8),
        b: Signal([]const u8),
        c: Signal([]const u8),
    };

    var state = MultiState{
        .a = Signal([]const u8).init(gpa, "A_init", &scene.elements.dirty),
        .b = Signal([]const u8).init(gpa, "B_init", &scene.elements.dirty),
        .c = Signal([]const u8).init(gpa, "C_init", &scene.elements.dirty),
    };
    defer state.a.deinit();
    defer state.b.deinit();
    defer state.c.deinit();

    var bindings = BindingSet.init();
    defer bindings.deinit(gpa);

    try bindings.bindText(MultiState, "a", &state, 0, gpa);
    try bindings.bindText(MultiState, "b", &state, 1, gpa);
    try bindings.bindText(MultiState, "c", &state, 2, gpa);

    state.a.set("Alpha");
    state.b.set("Beta");
    state.c.set("Gamma");

    bindings.refresh(&scene);

    const id0 = ElementId{ .index = 0, .gen = scene.elements.gen.items[0] };
    const id1 = ElementId{ .index = 1, .gen = scene.elements.gen.items[1] };
    const id2 = ElementId{ .index = 2, .gen = scene.elements.gen.items[2] };

    try std.testing.expectEqualStrings("Alpha", scene.textOf(id0).?);
    try std.testing.expectEqualStrings("Beta", scene.textOf(id1).?);
    try std.testing.expectEqualStrings("Gamma", scene.textOf(id2).?);
}

test "refresh: calling refresh before any set propagates the initial signal value" {
    const gpa = std.testing.allocator;

    var scene = try makeScene(gpa, 1);
    defer scene.deinit();

    var state = State{
        .greeting = Signal([]const u8).init(gpa, "original", &scene.elements.dirty),
    };
    defer state.greeting.deinit();

    var bindings = BindingSet.init();
    defer bindings.deinit(gpa);

    try bindings.bindText(State, "greeting", &state, 0, gpa);

    // refresh without any intervening set() — must push the initial value.
    bindings.refresh(&scene);

    const id = ElementId{ .index = 0, .gen = scene.elements.gen.items[0] };
    try std.testing.expectEqualStrings("original", scene.textOf(id).?);
}

test "bindText: signal dirty propagation reaches the correct element index" {
    const gpa = std.testing.allocator;

    // Allocate 4 elements; bind the signal to element 3 specifically.
    var scene = try makeScene(gpa, 4);
    defer scene.deinit();

    var state = State{
        .greeting = Signal([]const u8).init(gpa, "x", &scene.elements.dirty),
    };
    defer state.greeting.deinit();

    var bindings = BindingSet.init();
    defer bindings.deinit(gpa);

    try bindings.bindText(State, "greeting", &state, 3, gpa);

    // Clear all dirty bits.
    scene.elements.dirty.unsetAll();

    state.greeting.set("y");

    // Only element 3 should be dirty; 0, 1, 2 should remain clean.
    try std.testing.expect(!scene.elements.dirty.isSet(0));
    try std.testing.expect(!scene.elements.dirty.isSet(1));
    try std.testing.expect(!scene.elements.dirty.isSet(2));
    try std.testing.expect(scene.elements.dirty.isSet(3));
}
