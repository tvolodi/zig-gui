# RA4 — M10-05: Window state persistence

> Roadmap item: M10-05  
> Depends on: M8-03 (PersistentSettings — R82)  
> Read `00_constitution.md` before this file.

## Purpose

Automatically save and restore window position, size, and maximised state via
`PersistentSettings` so that the application remembers its window layout across restarts.
An application author opts in with a single flag; the framework handles all save/restore
logic transparently.

---

## Motivation

Without window state persistence, the window always opens at the default position and size.
Users who resize and reposition the window lose that preference on every relaunch. This is
the minimum expected behavior for a desktop application.

---

## What to build

### 1. `WindowStateManager` — `src/app/window_state.zig`

```zig
const std = @import("std");

pub const SavedWindowState = struct {
    x: i32,
    y: i32,
    width: u32,
    height: u32,
    maximised: bool,
};

pub const WindowStateManager = struct {
    settings: *PersistentSettings,    // borrowed — NOT owned
    key_prefix: [32]u8,               // e.g. "win_" → keys: win_x, win_y, win_w, win_h, win_max
    key_prefix_len: usize,

    /// Wrap an existing PersistentSettings. `key_prefix` namespaces the keys
    /// (e.g. "win_" produces "win_x", "win_y", "win_w", "win_h", "win_max").
    pub fn init(settings: *PersistentSettings, key_prefix: []const u8) WindowStateManager;

    /// Load saved state. Returns null if no saved state exists for this prefix.
    pub fn load(self: *const WindowStateManager) ?SavedWindowState;

    /// Save the given state to settings (marks settings dirty; does NOT flush).
    pub fn save(self: *WindowStateManager, state: SavedWindowState) !void;

    /// Clear all saved keys for this prefix (marks settings dirty).
    pub fn clear(self: *WindowStateManager) void;
};
```

Key names are constructed as `"{prefix}x"`, `"{prefix}y"`, `"{prefix}w"`, `"{prefix}h"`,
`"{prefix}max"`. All five keys must be present for `load` to return a non-null value; if
any is missing, `load` returns null (incomplete state is treated as absent).

### 2. Platform helpers — `src/app/window_state.zig`

```zig
/// Read current window position and size from GLFW via the Platform handle.
/// `platform` is `*mod01.Platform`. Returns the current window state.
pub fn readFromPlatform(platform: *Platform) SavedWindowState;

/// Apply a saved state to the GLFW window.
/// Calls glfwSetWindowPos, glfwSetWindowSize, and (if maximised) glfwMaximizeWindow.
/// Must be called before the first frame (during AppInner.init / runWithNav start).
pub fn applyToPlatform(state: SavedWindowState, platform: *Platform) void;
```

`readFromPlatform` uses:
- `glfwGetWindowPos` → `x`, `y`
- `glfwGetWindowSize` → `width`, `height`
- `glfwGetWindowAttrib(win, GLFW_MAXIMIZED)` → `maximised`

`applyToPlatform` uses:
- `glfwSetWindowPos(x, y)` — skipped when maximised (maximised window ignores position)
- `glfwSetWindowSize(width, height)` — skipped when maximised
- `glfwMaximizeWindow(win)` — called when `state.maximised`

### 3. `AppOptions` addition

```zig
/// Enable automatic window state persistence.
/// When true, AppInner.init restores the saved window state (if any) from
/// persistent_settings (which must also be provided). AppInner.deinit saves and
/// flushes the final window state.
persist_window_state: bool = false,

/// Prefix for window state keys in PersistentSettings. Default "win_".
/// Must be ≤ 28 bytes (prefix + 3-char key suffix ≤ 31-byte PersistentSettings key limit).
window_state_key_prefix: []const u8 = "win_",
```

### 4. `AppInner` integration

`AppInner` gains:

```zig
window_state_mgr: ?WindowStateManager = null,
```

**On `AppInner.init`** (when `opts.persist_window_state` and `opts.persistent_settings != null`):
1. Construct `WindowStateManager.init(settings, opts.window_state_key_prefix)`.
2. Call `window_state_mgr.?.load()`.
3. If non-null, call `applyToPlatform(state, &platform)` before `beginFrame`.

**On `AppInner.deinit`** (when `window_state_mgr != null`):
1. Call `readFromPlatform(&platform)` to get the current state.
2. Call `window_state_mgr.?.save(state)` then `settings.flush()`.

### 5. `AppOptions.persistent_settings` field

`AppOptions` gains a reference to an already-constructed `PersistentSettings`:

```zig
/// Optional reference to a PersistentSettings for window-state persistence.
/// The caller owns the PersistentSettings and must keep it alive for the duration of App.run.
persistent_settings: ?*PersistentSettings = null,
```

---

## Module location

```
src/app/window_state.zig       — WindowStateManager, SavedWindowState, readFromPlatform, applyToPlatform
src/app/window_state_test.zig  — unit tests (headless — uses a mock PersistentSettings)
docs/requirements/RA4_window_state_persistence.md
```

`src/app/types.zig` must re-export `WindowStateManager` and `SavedWindowState`.

---

## Invariant interactions

- **INV-5.6**: No new dependencies. All GLFW calls are already in the approved set.
- **INV-1.1**: `persist_window_state = false` (default) produces zero overhead.
- **INV-1.2**: `readFromPlatform` and `applyToPlatform` use GLFW calls that work on both
  Windows and Linux — no platform-specific code paths needed.
- **INV-3.5**: The arena is not involved. Window state is stored in `PersistentSettings`
  (heap-allocated, not arena) — it persists across `scene.reset()`.

---

## Glossary addition

Add to `docs/specs/glossary.md`:

```
## WindowStateManager

A helper struct that reads and writes window position, size, and maximised state to
`PersistentSettings`. Used by `AppInner` when `AppOptions.persist_window_state = true`.
Reads state from GLFW on `deinit`; applies saved state to GLFW on `init`. Defined in
`src/app/window_state.zig`. See: RA4 (M10-05).

## SavedWindowState

A plain struct (`x: i32`, `y: i32`, `width: u32`, `height: u32`, `maximised: bool`)
holding a snapshot of window geometry. Produced by `WindowStateManager.load` and
`readFromPlatform`. See: RA4 (M10-05).
```

---

## Non-goals (DO NOT implement — INV-5.4)

- NO per-monitor DPI-aware state saving. Position and size are stored in screen coordinates
  as returned by GLFW; DPI scaling is not adjusted.
- NO multi-window state tracking. Each window must create its own `WindowStateManager` with
  a distinct prefix.
- NO automatic flush during the frame loop. Flush happens only in `deinit`.
- NO saving minimised state (minimised windows have unreliable geometry from GLFW).
- NO migration if the prefix changes between app versions — old keys are orphaned in the
  settings file.

---

## Acceptance criteria

The module is done when:

1. `zig build test-window-state` runs `src/app/window_state_test.zig` and all tests pass.
2. `WindowStateManager.save` writes five keys with the correct prefix to `PersistentSettings`.
3. `WindowStateManager.load` returns null when any of the five keys is missing.
4. `WindowStateManager.load` returns the correct `SavedWindowState` when all five keys exist.
5. `WindowStateManager.clear` removes all five keys and marks settings dirty.
6. `persist_window_state = false` (default) initialises `window_state_mgr = null`; no
   GLFW calls are made in `deinit` related to window state.
7. No memory leaks (tested with `std.testing.allocator` via mock `PersistentSettings`).

---

## Edge cases (each has a test)

- Only 4 of 5 keys present → `load` returns null.
- `maximised = true` → `save` writes `"true"` for `win_max`; `load` reads it back correctly.
- `width = 0`, `height = 0` (zero-size window edge case) → saved and restored without crash.
- `key_prefix` exactly 28 bytes → key names are at most 31 bytes (within limit).
- `persistent_settings = null` with `persist_window_state = true` → `AppInner.init`
  returns `error.MissingPersistentSettings` (asserts in debug; returns error in release).
