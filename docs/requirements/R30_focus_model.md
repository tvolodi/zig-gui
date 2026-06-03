# R30 — M3-01: Focus model

> Roadmap item: M3-01  
> Depends on: M1-02 (event delivery), M2-02 (dirty scan), module 03 (element store)  
> Read `00_constitution.md` before this file.

## Purpose

Establish a single-focused-element model that persists across frames. The focused element
is highlighted with a visual focus ring. Tab and Shift+Tab navigate forward/backward through
focusable elements (those with `WidgetKind` of `button`, `input`, or `dropdown`). The focused
element index is owned by `Scene` and marks affected elements dirty when it changes, enabling
the renderer to apply focus styling (M4-01).

## What to build

### Focus state storage in `Scene`

Extend [07.types.zig](../specs/07.types.zig) `Scene` struct:

```zig
pub const Scene = struct {
    // ...existing fields...
    
    /// Current focused element index. u32 (not wrapped in ElementId struct).
    /// Set to std.math.maxInt(u32) to represent "no focus".
    /// When this value changes, all focusable elements are marked dirty
    /// so the renderer can update focus styling.
    focused_idx: u32 = std.math.maxInt(u32),
    
    /// Cached list of all focusable element indices (button, input, dropdown).
    /// Rebuilt at the end of instantiate(). Used for Tab/Shift+Tab navigation.
    /// Stored as ArrayListUnmanaged(u32); cleared on reset().
    focusable_indices: std.ArrayListUnmanaged(u32) = .empty,
    
    /// Set focus to `idx`, mark affected elements dirty, and return the index
    /// of the element that actually received focus (may differ in future if
    /// the target is disabled, but for now it matches `idx`).
    /// If `idx` is std.math.maxInt(u32), clears focus.
    pub fn setFocus(self: *Scene, idx: u32) void
    
    /// Return the currently focused element index, or std.math.maxInt(u32) if none.
    pub fn getFocus(self: *Scene) u32
    
    /// Return true if `idx` is in `focusable_indices`.
    pub fn isFocusable(self: *Scene, idx: u32) bool
    
    /// Navigate focus forward by 1 position in focusable_indices.
    /// Wraps around from last to first. If no element is focused, focuses the first.
    pub fn focusNext(self: *Scene) void
    
    /// Navigate focus backward by 1 position in focusable_indices.
    /// Wraps around from first to last. If no element is focused, focuses the last.
    pub fn focusPrev(self: *Scene) void
};
```

### Integration into `App` frame loop

In `src/app/app.zig` `App.run()` method, after polling events, handle Tab and Shift+Tab:

```zig
while (!platform.shouldClose()) {
    platform.pollEvents()
    
    // NEW: Tab/Shift+Tab navigation
    if (event_queue.hasKey(Key.Tab, Action.press)) {
        if (events.modifiersContain(Modifiers.shift)) {
            scene.focusPrev()
        } else {
            scene.focusNext()
        }
    }
    
    // ... rest of frame loop ...
}
```

### Focus ring rendering

The focus ring is drawn in `src/app/renderer.zig` `buildDrawList()`. For each element whose
index equals `scene.focused_idx`:

- Draw a thin bordered rect (outline, not filled) around the element's computed layout rect
  (from `RenderObject.rect`).
- Border width: 2 px.
- Border color: resolved from token `focus-ring` (to be added to M5-02 token set, but use
  a hardcoded bright color like `#0066ff` for now).
- Focus ring sits on top of the element (z-index managed by draw order in `buildDrawList`).

### Focusable element discovery

When `Scene.instantiate()` completes, or when elements are added to an already-instantiated
scene, rebuild `focusable_indices`:

```zig
// In Scene.instantiate(), after all elements are instantiated:
self.focusable_indices.clearRetainingCapacity()
var idx: u32 = 0
while (idx < self.count()) : (idx += 1) {
    const kind = self.kindOf(idx)
    if (kind == .button or kind == .input or kind == .dropdown) {
        try self.focusable_indices.append(self.elements.allocator(), idx)
    }
}
```

### Behavioral contract

| Event | Behavior |
|---|---|
| `Key.Tab` pressed (no shift) | Call `scene.focusNext()` |
| `Key.Tab` pressed (with shift) | Call `scene.focusPrev()` |
| Element created (button, input, dropdown) | Element is automatically in `focusable_indices` after instantiate |
| `setFocus(idx)` called | Old focused element and new focused element both marked dirty; `focused_idx` updated |
| Frame renders | Focused element drawn with focus ring overlay |

### Module location

```
src/app/types.zig                 — Scene extension (types only)
docs/specs/07.spec.md             — Scene.setFocus/getFocus/focusable_indices
docs/specs/07.types.zig           — Scene struct extension
docs/requirements/R30_focus_model.md
```

Rendering changes touch:
```
src/app/renderer.zig              — buildDrawList focus ring drawing
```

Event handling touches:
```
src/app/app.zig                   — App.run() Tab/Shift+Tab dispatch
```

## Public API

New `Scene` methods:

```zig
pub fn setFocus(self: *Scene, idx: u32) void
pub fn getFocus(self: *Scene) u32
pub fn isFocusable(self: *Scene, idx: u32) bool
pub fn focusNext(self: *Scene) void
pub fn focusPrev(self: *Scene) void
```

New `Scene` field:

```zig
focused_idx: u32
focusable_indices: std.ArrayListUnmanaged(u32)
```

## Non-goals (DO NOT implement — INV-5.4)

- **No focus style overrides** — focus ring appearance is hardcoded; token-driven styling is M4-01.
- **No focus trapping** — focus does not wrap to a specific start/end element; Tab wraps to first, Shift+Tab wraps to last.
- **No focus restoration** — closing and reopening a screen does not restore previous focus.
- **No disabled-element skip** — all focusable elements are reachable; disabling an element is M4-01.
- **No accessibility tree** — no screen-reader announcements (INV-1.4).
- **No custom focus strategies** — the built-in button/input/dropdown focus order is fixed; no customization.
- **No focus event callbacks** — focus is internal state; application code does not register focus listeners (INV-3.3).

## Acceptance criteria

1. `zig build test-scene` runs `docs/specs/07.acceptance_test.zig`. New test cases must cover:
   - After instantiate, `focusable_indices` contains all buttons, inputs, and dropdowns in the scene.
   - `setFocus(idx)` updates `focused_idx` and both old and new elements are marked dirty.
   - `getFocus()` returns the currently focused element index.
   - `focusNext()` and `focusPrev()` navigate the list and wrap around.
   - Focus can be cleared by calling `setFocus(std.math.maxInt(u32))`.
   - An empty scene (no focusable elements) handles `focusNext()` and `focusPrev()` without crashing.

2. Renderer correctly draws the focus ring:
   - Running the app and pressing Tab shows the focus ring moving between buttons/inputs.
   - The ring is a 2px border, visible on all focusable elements.

3. Event handling integrates:
   - Pressing Tab advances focus.
   - Pressing Shift+Tab goes backward.
   - Focus wraps correctly.

4. No allocations per-frame in focus navigation (only per-scene in instantiate).

5. Checklist fully ticked.

## Open questions

None. The focus model is scoped: one focused element per scene, no disabled-element logic,
no accessibility tree integration.
