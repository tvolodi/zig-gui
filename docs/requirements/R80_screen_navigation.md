# R80 — M8-01: Screen / navigation model

> Roadmap item: M8-01  
> Depends on: M1-01 (App main loop)  
> Read `00_constitution.md` before this file.

## Purpose

Give the application a stack-based navigation model so that multiple named screens can be
pushed and popped without tearing down the GPU device or font atlas. An application author
writes:

```zig
var nav = Navigator.init(gpa);
defer nav.deinit();

nav.register("home",     HomeScreen.build);
nav.register("settings", SettingsScreen.build);

try nav.push("home");
app.run(&nav);           // Nav drives scene resets on each push/pop
```

After this item ships, the framework supports multi-screen apps with a Back button, deep-link
push to any registered screen, and a clean API for passing arguments between screens.

---

## Motivation

`App.run` currently owns exactly one `Scene`. Building a multi-screen app today requires the
author to manually call `scene.reset()`, re-instantiate the tree, and re-register bindings —
and there is no mechanism to track history. Milestone 8 makes this a first-class framework
concern.

---

## What to build

### 1. `ScreenFn` — the screen builder type

```zig
/// A function that (re-)builds a scene for one named screen.
/// Called by Navigator.push / Navigator.pop after scene.reset().
/// `ctx` is an opaque pointer to the per-screen argument struct.
pub const ScreenFn = *const fn (
    scene: *Scene,
    tokens: Tokens,
    app: *AppInner,
    ctx: ?*anyopaque,
) anyerror!void;
```

A `ScreenFn` is NOT a closure. It is a plain function pointer. Per-screen state is threaded
through `ctx`. INV-3.1 applies: no per-screen heap objects are created by the framework; the
screen function may allocate into the arena via `scene`'s allocator.

### 2. `ScreenEntry` — registered screen descriptor

```zig
pub const ScreenEntry = struct {
    name: []const u8,   // owned slice (duped from the string literal at register time)
    build: ScreenFn,
};
```

### 3. `NavEntry` — one entry in the history stack

```zig
pub const NavEntry = struct {
    screen_idx: u32,    // index into Navigator.screens
    ctx: ?*anyopaque,   // caller-owned argument pointer; may be null
};
```

The `ctx` pointer is NOT owned or freed by `Navigator`. Ownership stays with the caller.

### 4. `Navigator` struct

```zig
pub const Navigator = struct {
    gpa: std.mem.Allocator,
    screens: std.ArrayListUnmanaged(ScreenEntry),
    stack: std.ArrayListUnmanaged(NavEntry),

    pub fn init(gpa: std.mem.Allocator) Navigator;
    pub fn deinit(self: *Navigator) void;

    /// Register a named screen. Names must be unique — calling register
    /// with a duplicate name is a programming error (asserts in debug).
    pub fn register(self: *Navigator, name: []const u8, build: ScreenFn) !void;

    /// Push a new screen. Resets the scene, calls the screen's ScreenFn, and
    /// re-registers bindings via AppInner.rebind_fn (if set).
    pub fn push(
        self: *Navigator,
        name: []const u8,
        ctx: ?*anyopaque,
        scene: *Scene,
        tokens: Tokens,
        app: *AppInner,
    ) !void;

    /// Pop the current screen. Restores the previous screen (calls its ScreenFn again).
    /// Returns error.EmptyStack if the stack has only one entry.
    pub fn pop(
        self: *Navigator,
        scene: *Scene,
        tokens: Tokens,
        app: *AppInner,
    ) !void;

    /// Replace the current top of stack without adding a history entry.
    /// Equivalent to pop() + push() but does not error on a single-entry stack.
    pub fn replace(
        self: *Navigator,
        name: []const u8,
        ctx: ?*anyopaque,
        scene: *Scene,
        tokens: Tokens,
        app: *AppInner,
    ) !void;

    /// Return the name of the current screen, or null if the stack is empty.
    pub fn currentName(self: *const Navigator) ?[]const u8;

    /// Return the stack depth (number of entries).
    pub fn depth(self: *const Navigator) usize;
};
```

### 5. `App.run` integration

`App.run` in `src/app/app.zig` must accept an optional `*Navigator` so it can hand off screen
changes that are queued from within event callbacks. The interface stays backward-compatible:

```zig
pub fn run(self: *AppInner) void;           // existing — no nav
pub fn runWithNav(self: *AppInner, nav: *Navigator) void;  // new overload
```

`runWithNav` is identical to `run` except it checks `nav.pending_push` at the top of each
frame (see "Deferred navigation" below).

### 6. Deferred navigation (no re-entrancy)

Screen changes initiated inside a button `on_click` callback must not call `push`/`pop`
directly, because the scene is mid-frame. Instead:

```zig
pub const PendingNav = union(enum) {
    none,
    push: struct { name: []const u8, ctx: ?*anyopaque },
    pop,
    replace: struct { name: []const u8, ctx: ?*anyopaque },
};
```

`Navigator` carries `pending: PendingNav = .none`. `Navigator.requestPush` / `requestPop` /
`requestReplace` set `pending` without touching the scene. At the top of the next frame,
`runWithNav` drains `pending` into the actual `push`/`pop`/`replace` call before the layout
pass.

### 7. Screen transitions

Screen transitions are out of scope for v1 (no animation timeline model exists — see
post-v1 table in `00_constitution.md`). A transition is a comptime non-goal for this item.
The switch between screens is instantaneous: `scene.reset()`, then the new screen's
`ScreenFn` runs.

---

## Module location

```
src/app/navigator.zig          — Navigator, NavEntry, ScreenEntry, PendingNav
src/app/navigator_test.zig     — acceptance tests (headless)
docs/requirements/R80_screen_navigation.md
```

`src/app/types.zig` must re-export `Navigator`, `ScreenFn`, `NavEntry`, and `PendingNav`.

---

## Invariant interactions

- **INV-3.5**: Each `push`/`pop`/`replace` calls `scene.reset()` before calling the new
  `ScreenFn`. The arena is reset; all prior element indices are invalid after the call.
- **INV-3.1**: `Navigator` does not allocate per-screen widget objects on the heap.
  `ScreenEntry.name` is a duped slice owned by `Navigator`; everything else is caller-owned.
- **INV-5.1**: `Navigator`'s public API is defined by `src/app/types.zig`. Match it exactly.

---

## Non-goals (DO NOT implement — INV-5.4)

- NO animated transitions between screens.
- NO URL-style routing (only named string registration).
- NO serialization of the navigation stack to disk (that is M8-03).
- NO multi-window navigation (each window has its own Navigator; that is M8-04).
- NO lifecycle hooks (`onEnter` / `onExit` callbacks per screen) — the `ScreenFn` is the
  entry point; exit is implicit on push/pop.

---

## Acceptance criteria

The module is done when:

1. `zig build test-nav` runs `src/app/navigator_test.zig` and all tests pass.
2. `register` with a duplicate name asserts (debug) or returns `error.DuplicateName` (release).
3. `push` resets the scene, calls `ScreenFn`, marks all elements dirty.
4. `pop` on a single-entry stack returns `error.EmptyStack` without modifying the scene.
5. `replace` on a single-entry stack succeeds (replaces in place).
6. `currentName` returns the correct name after push/pop/replace sequences.
7. `depth` returns the correct stack depth.
8. `requestPush` + `runWithNav` applies the navigation at the start of the next frame.
9. No memory is leaked (test with `std.testing.allocator`).
10. The checklist for this item is fully ticked.

---

## Edge cases (each has a test)

- Push the same screen twice → two entries on the stack with the same `screen_idx`.
- Pop from depth 1 → `error.EmptyStack`, scene unchanged.
- `requestPush` during a frame, then `requestPush` again before the frame ends → second
  request overwrites the first (last-write-wins, single pending slot).
- `ctx` passed to `push` is `null` → `ScreenFn` receives `null`; must not crash.
- Screen name not found in registry → `error.ScreenNotFound` returned from `push`.
