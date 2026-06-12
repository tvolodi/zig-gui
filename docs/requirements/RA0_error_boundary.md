# RA0 — M10-01: Error boundary / recovery

> Roadmap item: M10-01  
> Depends on: M8-01 (Screen / navigation model — Navigator, ScreenFn)  
> Read `00_constitution.md` before this file.

## Purpose

Catch panics or returned errors from `ScreenFn` callbacks and display a built-in fallback
screen instead of crashing the process. Production GUI applications must not crash to a
console stack trace when a screen builder fails; they must stay alive and give the user
actionable feedback.

---

## Motivation

`Navigator.push` calls `ScreenFn`, which may `return error.Foo` or trigger a `@panic`.
Today, either case terminates the process. Production hardening requires the framework to
catch these failures, log the error, and render a minimal "Something went wrong" screen so
the user can navigate back or restart gracefully.

---

## What to build

### 1. `ErrorBoundary` struct — `src/app/error_boundary.zig`

```zig
pub const ErrorBoundary = struct {
    /// Last error captured by `call`. Null when no error has been captured.
    last_error: ?anyerror = null,
    /// Last error message captured. Null when no error has been captured.
    last_message: [256]u8 = undefined,
    last_message_len: usize = 0,

    /// Call `screen_fn` with the given arguments, catching any returned error.
    /// Panics are NOT caught (see Non-goals).
    /// Returns `true` if the call succeeded; `false` if it returned an error.
    pub fn call(
        self: *ErrorBoundary,
        screen_fn: ScreenFn,
        scene: *Scene,
        tokens: Tokens,
        app: *AppInner,
        ctx: ?*anyopaque,
    ) bool;

    /// Returns the last captured error, or null if none.
    pub fn lastError(self: *const ErrorBoundary) ?anyerror;

    /// Returns a slice into `last_message` describing the last error, or "" if none.
    pub fn lastMessage(self: *const ErrorBoundary) []const u8;

    /// Clear the captured error state.
    pub fn clear(self: *ErrorBoundary) void;
};
```

`call` wraps the `ScreenFn` invocation in an `if (screen_fn(...)) |_| {} else |err| { ... }`
catch block. It stores `err` in `last_error` and formats a message into `last_message` using
`std.fmt.bufPrint`. It then returns `false`.

### 2. Fallback screen — `src/app/error_boundary.zig`

```zig
/// Build a minimal fallback scene that shows the error message.
/// Called by Navigator when `call` returns false.
/// Does NOT use markup parsing — builds the scene programmatically via Scene API.
pub fn buildFallbackScreen(
    boundary: *const ErrorBoundary,
    scene: *Scene,
    tokens: Tokens,
) void;
```

`buildFallbackScreen` creates a minimal element tree:
- A root `column` element filling the viewport.
- A `text` element with content `"Something went wrong"` styled with `tokens.err` color.
- A `text` element showing `boundary.lastMessage()` styled with `tokens.text_secondary`.

It does NOT use `markup_mod.parse` — builds the tree directly via `Scene.instantiate` /
`Scene.addChild`-level APIs so there is no parser dependency in error handling.

### 3. `Navigator` integration

Modify `Navigator.push`, `Navigator.pop`, and `Navigator.replace` in
`src/app/navigator.zig` to accept an optional `*ErrorBoundary`:

```zig
pub fn pushWithBoundary(
    self: *Navigator,
    name: []const u8,
    ctx: ?*anyopaque,
    scene: *Scene,
    tokens: Tokens,
    app: *AppInner,
    boundary: *ErrorBoundary,
) !void;
```

When `boundary.call(...)` returns `false`, `pushWithBoundary`:
1. Calls `scene.reset()`.
2. Calls `boundary.buildFallbackScreen(scene, tokens)`.
3. Does NOT push a new entry to `nav.stack` (the failed screen never becomes current).
4. Returns normally (does not propagate the original error — it was captured in `boundary`).

The original `push` / `pop` / `replace` remain unchanged (backward-compatible).

### 4. `AppInner` integration

`AppInner` gains an optional field:

```zig
error_boundary: ?ErrorBoundary = null,
```

When `error_boundary` is non-null, `runWithNav` uses `pushWithBoundary` instead of `push`
for each deferred navigation event.

The `AppOptions` struct gains:

```zig
/// Enable error boundary. When true, ScreenFn errors display a fallback screen.
enable_error_boundary: bool = false,
```

`AppInner.init` initialises `error_boundary` to `.{}` when `opts.enable_error_boundary` is true.

---

## Module location

```
src/app/error_boundary.zig       — ErrorBoundary + buildFallbackScreen
src/app/error_boundary_test.zig  — unit tests (headless)
docs/requirements/RA0_error_boundary.md
```

`src/app/types.zig` must re-export `ErrorBoundary`.

---

## Invariant interactions

- **INV-5.6**: No new dependencies. Error capture uses Zig's standard `anyerror` catch.
- **INV-3.1**: `buildFallbackScreen` does not allocate per-widget heap objects; it uses
  Scene's existing arena-backed APIs.
- **INV-5.4**: Panic recovery is explicitly a non-goal (see below).
- **INV-1.1**: `enable_error_boundary` defaults to `false` — no new default behavior.

---

## Glossary addition

Add to `docs/specs/glossary.md`:

```
## ErrorBoundary

A struct that wraps a `ScreenFn` call in a Zig error-catch block. When the screen function
returns an error, `ErrorBoundary.call` stores the error and returns `false`; the Navigator
then displays a built-in fallback screen. Does NOT catch panics. Defined in
`src/app/error_boundary.zig`. See: RA0 (M10-01).
```

---

## Non-goals (DO NOT implement — INV-5.4)

- NO panic recovery. Zig provides no safe panic interception at user level. Panics terminate
  the process. Only `anyerror` returns from `ScreenFn` are caught.
- NO per-error-code recovery strategies. All errors show the same fallback screen.
- NO retry button in the fallback screen (the user can navigate Back via the Nav stack).
- NO automatic restart or self-healing.
- NO wrapping of `buildDrawList` or layout solver — only `ScreenFn` invocations are guarded.
- NO error boundary for event callbacks (`on_click` etc.) — that is a separate, later scope.

---

## Acceptance criteria

The module is done when:

1. `zig build test-error-boundary` runs `src/app/error_boundary_test.zig` and all tests pass.
2. `boundary.call(failing_fn, ...)` returns `false` and `boundary.lastError()` returns the error.
3. `boundary.call(passing_fn, ...)` returns `true` and `boundary.lastError()` returns null.
4. `boundary.clear()` resets `last_error` to null.
5. `buildFallbackScreen` builds a scene with at least two text elements (title + message).
6. `pushWithBoundary` on a failing `ScreenFn` leaves the nav stack depth unchanged and
   renders the fallback screen.
7. `enable_error_boundary = false` (default) produces zero overhead — no `ErrorBoundary` is
   allocated and `push` behaves identically to before this requirement.
8. No memory leaks (tested with `std.testing.allocator`).

---

## Edge cases (each has a test)

- `ScreenFn` returns `error.OutOfMemory` → `lastError()` == `error.OutOfMemory`.
- `ScreenFn` returns `error.SomeCustomError` → `lastMessage()` contains "SomeCustomError".
- `buildFallbackScreen` called with an empty message → renders title only, no crash.
- `boundary.call` called twice in a row (second overwrites first) → `lastError` reflects second call.
- `clear()` after a captured error → subsequent `lastError()` returns null.
