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
const m05 = @import("../../docs/specs/05.types.zig");
const markup_mod = @import("../06/types.zig");
const m03 = @import("../03/types.zig");

const BindingSet = binding_mod.BindingSet;
const Scene = m07.Scene;
const ElementId = m07.ElementId;
const Signal = signal_mod.Signal;
const Tokens = m07.Tokens;

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

fn testTokens() Tokens {
    return m05.Tokens.light(m05.Palette.default());
}

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
    bindings.refresh(&scene, testTokens());

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

    bindings.refresh(&scene, testTokens());

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
    bindings.refresh(&scene, testTokens());

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

// ===========================================================================
// R52 — bindCond: Signal(bool) → element hidden state
// ===========================================================================

// NOTE: Calling bindCond with a non-Signal(bool) field should cause a compile
// error. Verify manually by changing the type of `visible` below to, e.g.,
// Signal(u32) and observing the @compileError from bindCond.

const CondState = struct {
    visible: Signal(bool),
};

/// Build a minimal Scene with one element that has a _hidden slot.
/// Uses Scene.instantiate so all parallel arrays (including _hidden) are populated.
fn makeSceneWithElement(gpa: std.mem.Allocator) !struct { scene: Scene, id: m07.ElementId, arena: std.heap.ArenaAllocator } {
    var arena = std.heap.ArenaAllocator.init(gpa);
    const desc = try markup_mod.parse(arena.allocator(), "<Text text=\"x\"/>");
    var scene = Scene.init(gpa);
    const id = try scene.instantiate(desc, testTokens());
    return .{ .scene = scene, .id = id, .arena = arena };
}

test "R52: bindCond with Signal(bool)=true → element visible after refresh" {
    const gpa = std.testing.allocator;
    var ctx = try makeSceneWithElement(gpa);
    defer ctx.scene.deinit();
    defer ctx.arena.deinit();

    var state = CondState{
        .visible = Signal(bool).init(gpa, true, &ctx.scene.elements.dirty),
    };
    defer state.visible.deinit();

    var bindings = BindingSet.init();
    defer bindings.deinit(gpa);

    try bindings.bindCond(CondState, "visible", &state, ctx.id.index, gpa);
    bindings.refresh(&ctx.scene, testTokens());

    try std.testing.expect(!ctx.scene.isHidden(ctx.id.index));
}

test "R52: Signal(bool).set(false) → after refresh element is hidden" {
    const gpa = std.testing.allocator;
    var ctx = try makeSceneWithElement(gpa);
    defer ctx.scene.deinit();
    defer ctx.arena.deinit();

    var state = CondState{
        .visible = Signal(bool).init(gpa, true, &ctx.scene.elements.dirty),
    };
    defer state.visible.deinit();

    var bindings = BindingSet.init();
    defer bindings.deinit(gpa);

    try bindings.bindCond(CondState, "visible", &state, ctx.id.index, gpa);
    bindings.refresh(&ctx.scene, testTokens());
    try std.testing.expect(!ctx.scene.isHidden(ctx.id.index));

    // Now hide it
    state.visible.set(false);
    bindings.refresh(&ctx.scene, testTokens());
    try std.testing.expect(ctx.scene.isHidden(ctx.id.index));
    // display should be .none
    try std.testing.expectEqual(m03.Display.none, ctx.scene.elements.layout.items[ctx.id.index].display);
}

test "R52: Signal(bool).set(true) → after refresh element is visible and display restored" {
    const gpa = std.testing.allocator;
    var ctx = try makeSceneWithElement(gpa);
    defer ctx.scene.deinit();
    defer ctx.arena.deinit();

    var state = CondState{
        .visible = Signal(bool).init(gpa, true, &ctx.scene.elements.dirty),
    };
    defer state.visible.deinit();

    var bindings = BindingSet.init();
    defer bindings.deinit(gpa);

    try bindings.bindCond(CondState, "visible", &state, ctx.id.index, gpa);

    // Hide first
    state.visible.set(false);
    bindings.refresh(&ctx.scene, testTokens());
    try std.testing.expect(ctx.scene.isHidden(ctx.id.index));

    // Show again
    state.visible.set(true);
    bindings.refresh(&ctx.scene, testTokens());
    try std.testing.expect(!ctx.scene.isHidden(ctx.id.index));
    // display should NOT be .none anymore
    try std.testing.expect(ctx.scene.elements.layout.items[ctx.id.index].display != m03.Display.none);
}

// ===========================================================================
// R53 — bindList: Signal([]T) → children of container element
// ===========================================================================

const Item = struct { label: []const u8 };

/// A minimal item instantiation function for bindList tests.
fn instantiateItem(
    scene: *Scene,
    container_id: m07.ElementId,
    item: *const Item,
    toks: Tokens,
) !void {
    _ = toks;
    _ = item;
    // We just add a minimal Text node as the child.
    // Use a scratch allocator so the NodeDesc slice lives long enough for instantiateUnder.
    var scratch_buf: [256]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&scratch_buf);
    const desc = try markup_mod.parse(fba.allocator(), "<Text text=\"item\"/>");
    _ = try scene.instantiateUnder(container_id, desc, Tokens.light(m05.Palette.default()));
}

/// Build a container Scene using instantiate for a "<Column/>" root.
fn makeContainerScene(gpa: std.mem.Allocator) !struct { scene: Scene, container_id: m07.ElementId, arena: std.heap.ArenaAllocator } {
    var arena = std.heap.ArenaAllocator.init(gpa);
    const desc = try markup_mod.parse(arena.allocator(), "<Column/>");
    var scene = Scene.init(gpa);
    const container_id = try scene.instantiate(desc, testTokens());
    return .{ .scene = scene, .container_id = container_id, .arena = arena };
}

const ListState = struct {
    items: Signal([]Item),
};

test "R53: bindList with 3-item slice produces 3 children after refresh" {
    const gpa = std.testing.allocator;
    var ctx = try makeContainerScene(gpa);
    defer ctx.scene.deinit();
    defer ctx.arena.deinit();

    var items_data = [_]Item{
        .{ .label = "a" },
        .{ .label = "b" },
        .{ .label = "c" },
    };
    var state = ListState{
        .items = Signal([]Item).init(gpa, &items_data, &ctx.scene.elements.dirty),
    };
    defer state.items.deinit();

    var bindings = BindingSet.init();
    defer bindings.deinit(gpa);

    const empty_template = m07.NodeDesc{ .tag = "Text" };
    try bindings.bindList(Item, "items", &state, ctx.container_id.index, empty_template, instantiateItem, gpa);

    bindings.refresh(&ctx.scene, testTokens());

    // Count children
    var it = ctx.scene.elements.childrenOf(ctx.container_id);
    var child_count: u32 = 0;
    while (it.next()) |_| child_count += 1;
    try std.testing.expectEqual(@as(u32, 3), child_count);
}

test "R53: empty slice produces 0 children after refresh" {
    const gpa = std.testing.allocator;
    var ctx = try makeContainerScene(gpa);
    defer ctx.scene.deinit();
    defer ctx.arena.deinit();

    var items_data = [_]Item{};
    var state = ListState{
        .items = Signal([]Item).init(gpa, &items_data, &ctx.scene.elements.dirty),
    };
    defer state.items.deinit();

    var bindings = BindingSet.init();
    defer bindings.deinit(gpa);

    const empty_template = m07.NodeDesc{ .tag = "Text" };
    try bindings.bindList(Item, "items", &state, ctx.container_id.index, empty_template, instantiateItem, gpa);

    bindings.refresh(&ctx.scene, testTokens());

    var it = ctx.scene.elements.childrenOf(ctx.container_id);
    var child_count: u32 = 0;
    while (it.next()) |_| child_count += 1;
    try std.testing.expectEqual(@as(u32, 0), child_count);
}

test "R53: new slice replaces old children on refresh" {
    const gpa = std.testing.allocator;
    var ctx = try makeContainerScene(gpa);
    defer ctx.scene.deinit();
    defer ctx.arena.deinit();

    var items_a = [_]Item{ .{ .label = "a" }, .{ .label = "b" } };
    var items_b = [_]Item{ .{ .label = "x" }, .{ .label = "y" }, .{ .label = "z" } };

    var state = ListState{
        .items = Signal([]Item).init(gpa, &items_a, &ctx.scene.elements.dirty),
    };
    defer state.items.deinit();

    var bindings = BindingSet.init();
    defer bindings.deinit(gpa);

    const empty_template = m07.NodeDesc{ .tag = "Text" };
    try bindings.bindList(Item, "items", &state, ctx.container_id.index, empty_template, instantiateItem, gpa);

    bindings.refresh(&ctx.scene, testTokens());

    {
        var it = ctx.scene.elements.childrenOf(ctx.container_id);
        var n: u32 = 0;
        while (it.next()) |_| n += 1;
        try std.testing.expectEqual(@as(u32, 2), n);
    }

    // Update signal to 3 items
    state.items.set(&items_b);
    bindings.refresh(&ctx.scene, testTokens());

    {
        var it = ctx.scene.elements.childrenOf(ctx.container_id);
        var n: u32 = 0;
        while (it.next()) |_| n += 1;
        try std.testing.expectEqual(@as(u32, 3), n);
    }
}

// ===========================================================================
// R56 — FileWatcher lifecycle tests
// ===========================================================================

const FileWatcher = @import("file_watcher.zig").FileWatcher;

test "R56: FileWatcher.init and deinit with no files — no leaks" {
    const gpa = std.testing.allocator;
    var watcher = FileWatcher.init(gpa);
    watcher.deinit();
    // std.testing.allocator catches leaks at the end of the test
}

test "R56: FileWatcher.addFile stores the path" {
    const gpa = std.testing.allocator;
    var watcher = FileWatcher.init(gpa);
    defer watcher.deinit();

    const test_path = "src/screens/example.ui";
    try watcher.addFile(test_path);
    try std.testing.expectEqual(@as(usize, 1), watcher.entries.items.len);
    try std.testing.expectEqualStrings(test_path, watcher.entries.items[0].path[0..test_path.len]);
}

test "R56: FileWatcher.poll on non-existent file does not crash" {
    const gpa = std.testing.allocator;
    var watcher = FileWatcher.init(gpa);
    defer watcher.deinit();

    // Add a path that definitely does not exist
    try watcher.addFile("__nonexistent_file_12345__.ui");
    // poll() should stat silently fail and not add to changed list
    watcher.poll();
    const changed = watcher.drainChanged();
    try std.testing.expectEqual(@as(usize, 0), changed.len);
}

test "R56: FileWatcher.drainChanged after poll with no changes returns empty slice" {
    const gpa = std.testing.allocator;
    var watcher = FileWatcher.init(gpa);
    defer watcher.deinit();

    // No files watched; poll returns empty
    watcher.poll();
    const changed = watcher.drainChanged();
    try std.testing.expectEqual(@as(usize, 0), changed.len);
}

test "R56: FileWatcher.deinit with multiple files frees all paths" {
    const gpa = std.testing.allocator;
    var watcher = FileWatcher.init(gpa);

    try watcher.addFile("file1.ui");
    try watcher.addFile("file2.ui");
    try watcher.addFile("file3.ui");
    // deinit must free all paths; leak detector will catch any failures
    watcher.deinit();
}

// NOTE: The following acceptance criteria for R56 require manual testing:
//   - `zig build run-dev` runs the app with the -Dhot-reload flag (no main.zig yet)
//   - Editing a .ui file while run-dev is active triggers re-parse and re-instantiation
//   - The window reflects changes without restart
//   - `rebind_fn` field on AppInner triggers UI refresh after file reload
// These cannot be automated as unit tests (interactive/visual requirement).
