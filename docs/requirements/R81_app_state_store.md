# R81 — M8-02: Application state store

> Roadmap item: M8-02  
> Depends on: M2-01 (Signal type)  
> Read `00_constitution.md` before this file.

## Purpose

Provide a top-level signal tree — the `AppState` — that survives screen transitions and is
accessible from any `ScreenFn` without passing it through every intermediate layer. This is
the single source of truth for data that spans multiple screens (current user, selected item,
filter state, etc.).

An application author writes:

```zig
const MyState = struct {
    username: Signal([]const u8),
    is_logged_in: Signal(bool),
    item_count: Signal(u32),
};

var state = try AppState(MyState).init(gpa, .{
    .username     = Signal([]const u8).init(""),
    .is_logged_in = Signal(bool).init(false),
    .item_count   = Signal(u32).init(0),
});
defer state.deinit();

// In a ScreenFn:
state.get().is_logged_in.set(true);
```

---

## Motivation

Today the only way to share state between screens is to thread raw pointers through `ctx`
arguments. This works for one or two fields but does not scale. `AppState` wraps a
user-defined struct and makes its signals accessible by any screen in the application.

---

## What to build

### 1. `AppState(T)` — comptime-parametric state container

`AppState(T)` is a comptime-generic struct where `T` is a user-defined struct whose fields
are all `Signal(X)` types. The framework provides no reflection magic on field names; the
author accesses signals directly through the `get()` pointer.

```zig
pub fn AppState(comptime T: type) type {
    return struct {
        gpa: std.mem.Allocator,
        inner: T,

        const Self = @This();

        /// Initialise from a value-initialised T.
        pub fn init(gpa: std.mem.Allocator, initial: T) !Self;

        /// Deinit all signals in T (calls .deinit() on each Signal field via comptime field walk).
        pub fn deinit(self: *Self) void;

        /// Return a mutable pointer to the inner state struct.
        pub fn get(self: *Self) *T;
    };
}
```

`deinit` uses a comptime field walk (`std.meta.fields(T)`) to call `.deinit()` on each
field. It asserts at comptime that every field of `T` responds to `.deinit()` so that the
error surfaces at the call site, not inside the generic.

### 2. Comptime validation

`AppState(T)` does NOT require that every field is a `Signal`. It simply calls `deinit()` on
every field that has one. Fields without a `deinit` method are left alone. This keeps the
author free to embed plain scalars or other types in the state struct without restriction.

### 3. Passing state to screens

The recommended pattern is to embed `*AppState(T)` in the `ctx` argument to `Navigator.push`.
The framework does NOT inject state automatically. This avoids any hidden global state or
thread-local trickery and keeps the data flow explicit (INV-3.3: no hidden change paths).

```zig
// In main:
const ctx = .{ .state = &my_state, .extra = some_value };
try nav.push("profile", &ctx, &scene, tokens, app);

// In the ScreenFn:
const c: *MyCtx = @ptrCast(@alignCast(ctx));
const username_val = c.state.get().username.get();
```

### 4. Global state helper (optional convenience)

For applications that want a truly global singleton, a thin comptime wrapper is provided.
This is an opt-in pattern, not a default:

```zig
/// Thread-local global state pointer (single-threaded; no mutex needed per INV-1.2 / INV-2.1).
/// Call AppState.setGlobal / AppState.getGlobal only from the main thread.
pub fn AppState(comptime T: type) type {
    return struct {
        // ... (as above) ...

        var _global: ?*Self = null;

        pub fn setGlobal(self: *Self) void {
            _global = self;
        }

        pub fn getGlobal() ?*Self {
            return _global;
        }
    };
}
```

`setGlobal` / `getGlobal` are NOT thread-safe. This is acceptable because the whole framework
runs on one thread (INV-2.1 / GLFW single-thread requirement).

---

## Module location

```
src/app/app_state.zig          — AppState(T) implementation
src/app/app_state_test.zig     — acceptance tests (fully headless)
docs/requirements/R81_app_state_store.md
```

`src/app/types.zig` must re-export the `AppState` function.

---

## Invariant interactions

- **INV-3.3**: `AppState` signals follow the same dirty-bitset mechanism as all other
  signals. `Signal.set()` marks subscribed element indices dirty. No new change-propagation
  path is introduced.
- **INV-5.5**: The term **AppState** is added to `glossary.md` (see below).
- **INV-1.1**: No plugin system, no configurable slots. Hardcoded generic struct pattern.

---

## Glossary addition

Add to `docs/specs/glossary.md`:

```
## AppState(T)

A comptime-generic container wrapping a user-defined struct `T` whose fields are `Signal`
instances (or any type with a `deinit` method). Owned by the application entry point and
shared across screens via the `ctx` argument to `Navigator.push`. Provides `get()` returning
`*T` for direct signal access. Optionally exposed as a thread-local singleton via
`setGlobal` / `getGlobal`. Defined in `src/app/app_state.zig`.

See: R81 (M8-02).
```

---

## Non-goals (DO NOT implement — INV-5.4)

- NO automatic injection of state into `ScreenFn` — threading it through `ctx` is explicit
  and intentional.
- NO observable/reactive subscriptions between AppState fields — signals already handle this.
- NO serialisation of AppState to disk — that is M8-03 (`PersistentSettings`).
- NO multi-threaded access — all state mutation happens on the main thread.
- NO schema / shape validation of the state struct beyond the comptime field walk.

---

## Acceptance criteria

The module is done when:

1. `zig build test-app-state` runs `src/app/app_state_test.zig` and all tests pass.
2. `AppState(T).init` compiles and runs for a struct with three `Signal` fields.
3. `deinit` calls `.deinit()` on each `Signal` field; no leaks detected by `std.testing.allocator`.
4. `get()` returns a mutable pointer; mutations via `signal.set()` are reflected in subsequent `signal.get()` calls.
5. `setGlobal` / `getGlobal` round-trip correctly; `getGlobal` returns `null` before `setGlobal` is called.
6. A struct with a non-Signal field (e.g. a plain `u32`) compiles without error and the field is unmodified by `deinit`.
7. The checklist for this item is fully ticked.

---

## Edge cases (each has a test)

- `T = struct {}` (empty state struct) — `init` and `deinit` are no-ops; no crash.
- Signal with zero subscribers — `set()` does not crash.
- `getGlobal()` before `setGlobal()` → returns `null`.
- Two calls to `setGlobal` — second overwrites first without leaking.
