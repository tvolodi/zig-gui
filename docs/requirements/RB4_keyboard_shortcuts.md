# RB4 — M11-05: Keyboard shortcuts / accelerators

> Roadmap item: M11-05  
> Depends on: M1-02 (event delivery)  
> Read `00_constitution.md` before this file.

## Purpose

Allow the application to register global key combinations (e.g. `Ctrl+S`, `Ctrl+Z`) that
fire a `CallbackFn` regardless of which element is focused. Shortcuts are registered on
`AppInner` via `registerShortcut` / `unregisterShortcut`. The shortcut table is checked in
`dispatchEvents` before the focused-element path, so a global shortcut always wins.

## What to build

### `Shortcut` and shortcut table on `AppInner`

Add to `src/app/app.zig`:

```zig
/// A key combination that triggers a global callback.
pub const Shortcut = struct {
    key:  Key,
    mods: Modifiers,
    cb:   CallbackFn,
};

pub const MAX_SHORTCUTS: usize = 64;

/// Shortcut table stored inline on AppInner (no heap allocation needed for ≤64 entries).
/// Slots are filled from index 0; empty slots have cb = null (distinguished by sentinel).
pub const ShortcutTable = struct {
    entries: [MAX_SHORTCUTS]Shortcut = [_]Shortcut{.{ .key = .other, .mods = .{}, .cb = &noop }} ** MAX_SHORTCUTS,
    count:   usize = 0,

    fn noop() void {}

    /// Register a shortcut. Returns error.TooManyShortcuts if the table is full.
    /// If the same key+mods combination is already registered, the old callback is replaced.
    pub fn register(self: *ShortcutTable, key: Key, mods: Modifiers, cb: CallbackFn) !void

    /// Remove the shortcut for key+mods. No-op if not registered.
    pub fn unregister(self: *ShortcutTable, key: Key, mods: Modifiers) void

    /// Return the callback for key+mods, or null if not registered.
    pub fn lookup(self: *const ShortcutTable, key: Key, mods: Modifiers) ?CallbackFn
};
```

`ShortcutTable` is a value type stored directly on `AppInner`:

```zig
// AppInner gains:
shortcuts: ShortcutTable = .{},
```

The public-facing methods on `App` delegate to `inner.shortcuts`:

```zig
pub fn registerShortcut(self: *App, key: Key, mods: Modifiers, cb: CallbackFn) !void
pub fn unregisterShortcut(self: *App, key: Key, mods: Modifiers) void
```

`registerShortcut` and `unregisterShortcut` are the only two new public methods on `App`.

### Matching in `dispatchEvents` (app.zig)

Check the shortcut table for every `key` press event, **before** the focused-element path:

```zig
if (ev == .key and ev.key.action == .press) {
    if (self.shortcuts.lookup(ev.key.key, ev.key.mods)) |cb| {
        // Queue via _queued_callbacks (INV-3.3).
        self.scene._queued_callbacks.append(self.gpa, cb) catch {};
        // Do NOT fall through to focused-element handling for this event.
        // (The shortcut consumes the key press.)
        continue;  // or equivalent early-exit for this event
    }
}
// ...existing focused-element key handling...
```

A matched shortcut consumes the event: the focused-element key handler does not also
see it. This prevents, for example, `Ctrl+Z` from both triggering an undo shortcut and
inserting a character into a text input.

### Modifier matching rules

Two `Modifiers` values match when ALL four booleans are equal. The app must set exactly
the modifiers it intends — there is no "ignore extra modifiers" fuzzy matching.

Example: `Ctrl+S` requires `mods = .{ .ctrl = true }`. Pressing `Ctrl+Shift+S` does NOT
match this registration; the app would need a separate entry for `Ctrl+Shift+S` if desired.

### Error type

```zig
pub const ShortcutError = error{ TooManyShortcuts };
```

`register` returns `ShortcutError!void`. If the table is full (64 entries), the call
returns `error.TooManyShortcuts`; the app is responsible for handling or ignoring the
error.

### Module location

```
src/app/app.zig          — Shortcut, ShortcutTable, AppInner.shortcuts field,
                           App.registerShortcut, App.unregisterShortcut,
                           dispatchEvents shortcut-check path
docs/requirements/RB4_keyboard_shortcuts.md
```

No changes to `docs/specs/07.types.zig` or module 01 — shortcuts are purely an app-layer
concern.

## Public API

```zig
// App
pub fn registerShortcut(self: *App, key: Key, mods: Modifiers, cb: CallbackFn) !void
pub fn unregisterShortcut(self: *App, key: Key, mods: Modifiers) void

// Shortcut types (exported from src/app/app.zig or src/app/types.zig)
pub const Shortcut = struct { key: Key, mods: Modifiers, cb: CallbackFn }
pub const ShortcutError = error{ TooManyShortcuts }
pub const MAX_SHORTCUTS: usize = 64
```

## Behavioral contract

| Situation | Behavior |
|---|---|
| Key press matches a registered shortcut | Callback queued; event NOT passed to focused element |
| Key press does not match any shortcut | Passed to focused element as usual |
| Same key+mods registered twice | Second call replaces the first callback |
| Table full (64 entries), new registration | Returns `error.TooManyShortcuts` |
| `unregisterShortcut` on unregistered combo | No-op |
| Key release of a shortcut key | NOT dispatched to shortcut table (press only) |
| Shortcut fires while text input is focused | Input does NOT receive the key press |

## Non-goals (DO NOT implement — INV-5.4)

- **No per-screen shortcut scoping** — shortcuts are global for the lifetime of the app;
  callers re-register on screen transitions if scoping is needed.
- **No priority ordering** — first matching entry wins (search order: 0 → count-1).
- **No sequence shortcuts** — single key combination only (no `Ctrl+K, Ctrl+S` chords).
- **No shortcut display in menus** — R7D context menus already declared this a non-goal.
- **No `key release` shortcuts** — press events only.
- **No dynamic shortcut names / descriptions** — `CallbackFn` is opaque.
- **No built-in shortcuts** — the framework registers no shortcuts by default; the app
  registers all of them.

## Acceptance criteria

1. Unit tests in `src/app/shortcut_test.zig` cover:
   - `register` stores the entry; `lookup` returns the callback.
   - `register` with duplicate key+mods replaces the old callback.
   - `unregister` removes the entry; subsequent `lookup` returns `null`.
   - `unregister` on a non-existent combo is a no-op.
   - Registering 64 shortcuts succeeds; registering a 65th returns
     `error.TooManyShortcuts`.
   - Modifier matching is exact: `Ctrl+S` does not match `Ctrl+Shift+S`.

2. Integration tests (in `src/app/shortcut_test.zig` or `src/app/app_test.zig`) cover:
   - A `key` press event for a registered shortcut enqueues the callback in
     `_queued_callbacks` and does NOT reach the focused-element handler.
   - A `key` press event for an unregistered combo reaches the focused-element handler.

3. `zig build` passes with no regressions in existing keyboard-navigation tests.

4. Checklist fully ticked.

## Open questions

None. 64-entry fixed table is sufficient for a single-owner desktop app.
