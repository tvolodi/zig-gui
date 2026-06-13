# RB2 — M11-03: Right-click event routing

> Roadmap item: M11-03  
> Depends on: M7-14 (context menu — R7D)  
> Read `00_constitution.md` before this file.

## Purpose

Expose a generic `on_right_click` callback on any element, independent of the context-menu
registry introduced by R7D. R7D routes right-clicks to the `ContextMenuManager` when the
hit element has a registered context menu. This requirement adds a lower-level hook that
fires for every right-click on any element that registered one, regardless of whether a
context menu is also registered. The two mechanisms are orthogonal: an element may have
both `on_right_click` and a context menu, neither, or only one.

## What to build

### `on_right_click` callback per element in `Scene`

Add a new parallel array to `Scene`:

In [07.types.zig](../specs/07.types.zig) and `src/07/types.zig`:

```zig
pub const Scene = struct {
    // ...existing fields...

    /// Per-element right-click callbacks.
    /// null = element has no right-click handler.
    _right_click: std.ArrayListUnmanaged(?CallbackFn) = .empty,

    /// Register a right-click callback for element `idx`.
    pub fn setRightClick(self: *Scene, idx: u32, cb: CallbackFn) void

    /// Clear the right-click callback for element `idx`.
    pub fn clearRightClick(self: *Scene, idx: u32) void

    /// Return the right-click callback for element `idx`, or null if none.
    pub fn rightClickOf(self: *const Scene, idx: u32) ?CallbackFn
};
```

`CallbackFn` is the existing type (`*const fn () void`) already used for button
`on_click` callbacks (R31). Registration is programmatic — no markup attribute.

### Input handling in `dispatchEvents` (app.zig)

The existing R7D path handles right-click for context menus. Extend it to also fire
`on_right_click` callbacks:

```zig
if (ev == .mouse_button and ev.mouse_button.button == .right
    and ev.mouse_button.action == .press) {
    const mouse_x = ev.mouse_button.x;
    const mouse_y = ev.mouse_button.y;

    // Hit-test topmost element under cursor (reverse DFS, same as R7D).
    const hit = hitTest(&self.scene, mouse_x, mouse_y);

    // Fire on_right_click callback (M11-03) — independent of context menu.
    if (hit != NONE) {
        if (self.scene.rightClickOf(hit)) |cb| {
            self.scene._queued_callbacks.append(self.gpa, cb) catch {};
        }
    }

    // Context menu (R7D) — existing path unchanged.
    if (hit != NONE and self.scene.contextMenuIdxOf(hit) != 0xFF) {
        self.context_menu_manager.openAt(...);
    } else if (hit == NONE or self.scene.contextMenuIdxOf(hit) == 0xFF) {
        if (self.context_menu_manager.menu.visible) {
            self.context_menu_manager.dismiss(&self.overlay);
        }
    }
}
```

The `on_right_click` callback is queued via `_queued_callbacks` and fired at frame-end
by `scene.fireQueuedCallbacks()`, identical to `on_click` (INV-3.3).

### `reset()` and `instantiate` housekeeping

- `Scene.reset()` must append a `null` entry to `_right_click` alongside all other
  parallel arrays when elements are added. Follow the same resize-and-zero pattern used
  by `_drag` and `_drop` (RB1) and other optional arrays.
- `instantiateNode` does NOT read a `on_right_click=` markup attribute — registration
  is programmatic only.

### Module location

```
src/07/types.zig         — _right_click parallel array, setRightClick, clearRightClick,
                           rightClickOf
docs/specs/07.types.zig  — same
src/app/app.zig          — dispatchEvents right-click extension
docs/requirements/RB2_right_click_routing.md
```

## Public API

```zig
// Scene
pub fn setRightClick(self: *Scene, idx: u32, cb: CallbackFn) void
pub fn clearRightClick(self: *Scene, idx: u32) void
pub fn rightClickOf(self: *const Scene, idx: u32) ?CallbackFn
```

## Behavioral contract

| Situation | Behavior |
|---|---|
| Right-click on element with `on_right_click` registered | Callback queued; fires at frame-end |
| Right-click on element with both `on_right_click` and context menu | Both fire: callback queued AND context menu opens |
| Right-click on element with only context menu (no `on_right_click`) | Context menu opens; no extra callback |
| Right-click on element with neither | No callback; context menu dismissed if open |
| Right-click on empty space | No callback; context menu dismissed if open |

The `on_right_click` callback always fires before the context-menu path evaluates (order
guaranteed by sequential dispatch code).

## Non-goals (DO NOT implement — INV-5.4)

- **No `on_right_click=` markup attribute** — programmatic registration only.
- **No right-click position passed to callback** — `CallbackFn` is `*const fn() void`;
  apps that need position should read it from mouse state in the callback.
- **No right-click on drag source** — right-click during active drag is undefined
  (left button is held); handle it as cancel in RB1 if it arises.
- **No separate `on_right_release` event** — press only.
- **No "consumed" flag** — both `on_right_click` and context menu always fire if present.

## Acceptance criteria

1. Unit tests in `src/07/07_test.zig` (or `src/app/right_click_test.zig`) cover:
   - `setRightClick` stores callback; `rightClickOf` returns it.
   - `clearRightClick` restores `null`.
   - `rightClickOf` on an element with no registration returns `null`.

2. Integration tests (in `src/app/right_click_test.zig` or similar) cover:
   - Simulating a right-click mouse event on an element with `on_right_click` registered
     enqueues the callback in `_queued_callbacks`.
   - Simulating a right-click on an element with both `on_right_click` and a context menu
     enqueues the callback AND would open the context menu (both paths activate).
   - Simulating a right-click on an element with no registration enqueues nothing.

3. `zig build` passes with no regressions in R7D context-menu tests.

4. Checklist fully ticked.

## Open questions

None. The interaction with R7D context menus is explicitly non-exclusive: both fire.
