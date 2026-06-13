# RB0 — M11-01: Mouse cursor shapes

> Roadmap item: M11-01  
> Depends on: M1-02 (event delivery)  
> Read `00_constitution.md` before this file.

## Purpose

Change the OS cursor icon based on which element the mouse is hovering. GLFW exposes
`glfwCreateStandardCursor` and `glfwSetCursor` for this purpose. The framework selects
the cursor shape by inspecting the hovered element's widget kind and an optional
`cursor` attribute. This requires no new reactivity mechanism — cursor shape is set
imperatively in the event-dispatch path, once per frame after hit-testing (INV-3.3).

## What to build

### `CursorShape` enum in module 01

Add to [01.types.zig](../specs/01.types.zig) (and `src/01/types.zig`):

```zig
/// OS cursor shapes available via glfwCreateStandardCursor.
pub const CursorShape = enum {
    arrow,       // GLFW_ARROW_CURSOR
    text_beam,   // GLFW_IBEAM_CURSOR
    crosshair,   // GLFW_CROSSHAIR_CURSOR
    hand,        // GLFW_POINTING_HAND_CURSOR
    resize_ew,   // GLFW_RESIZE_EW_CURSOR   (horizontal resize)
    resize_ns,   // GLFW_RESIZE_NS_CURSOR   (vertical resize)
    resize_all,  // GLFW_RESIZE_ALL_CURSOR  (move/drag)
    not_allowed, // GLFW_NOT_ALLOWED_CURSOR
};
```

### `Platform.setCursor` in module 01

Extend `Platform` in [01.types.zig](../specs/01.types.zig) and `src/01/types.zig`:

```zig
pub const Platform = struct {
    // ...existing fields...

    /// Change the OS cursor displayed over the GLFW window.
    /// Cursor objects are created on first use and cached for the window's lifetime.
    /// Calling with the same shape as the current shape is a no-op.
    pub fn setCursor(self: *Platform, shape: CursorShape) void
};
```

Implementation detail in `src/01/types.zig`:
- At `Platform.init` time allocate a `[8]*c.GLFWcursor` cache array, initialised to `null`.
- `setCursor` lazily calls `glfwCreateStandardCursor` for the requested shape (mapping
  `CursorShape` to the corresponding `GLFW_*_CURSOR` constant), caches it, then calls
  `glfwSetCursor(self.window, cursor)`.
- At `Platform.deinit` destroy all non-null cursors with `glfwDestroyCursor`.
- The mapping from enum to GLFW constant must be a `comptime` switch (no runtime string
  comparisons).

### Default cursor shape per widget kind

Add a helper to `src/app/app.zig` (not a public type — internal to the dispatch path):

```zig
fn defaultCursorFor(kind: WidgetKind, disabled: bool) CursorShape {
    if (disabled) return .not_allowed;
    return switch (kind) {
        .button, .checkbox, .radio, .dropdown,
        .slider, .tabs, .accordion, .date_picker => .hand,
        .input, .textarea                         => .text_beam,
        else                                      => .arrow,
    };
}
```

### `cursor` markup attribute

Support an optional `cursor="<shape>"` attribute on any element. The markup resolver
maps the string to `CursorShape` at parse/instantiate time and stores it in a new
parallel array in `Scene`:

In [07.types.zig](../specs/07.types.zig) and `src/07/types.zig`:

```zig
pub const Scene = struct {
    // ...existing fields...

    /// Optional cursor shape override per element.
    /// null = use defaultCursorFor(kind, disabled).
    _cursor: std.ArrayListUnmanaged(?CursorShape) = .empty,

    /// Return the cursor override for element `idx`, or null if none was set.
    pub fn cursorOf(self: *const Scene, idx: u32) ?CursorShape
};
```

`instantiateNode` reads the `cursor=` attribute and sets `_cursor.items[idx]` if present.
Valid attribute values: `"arrow"`, `"text"`, `"crosshair"`, `"hand"`, `"resize-ew"`,
`"resize-ns"`, `"resize-all"`, `"not-allowed"`. Unknown values are silently ignored
(cursor remains null).

### Cursor update in `dispatchEvents` (app.zig)

After the existing hit-test in `dispatchEvents`, once the hovered element index is known:

```zig
// After resolving hovered_idx:
const shape: CursorShape = blk: {
    if (hovered_idx == NONE) break :blk .arrow;
    if (scene.cursorOf(hovered_idx)) |override| break :blk override;
    const disabled = scene._pseudo.items[hovered_idx].disabled;
    break :blk defaultCursorFor(scene.kindOf(hovered_idx), disabled);
};
platform.setCursor(shape);
```

The cursor is set every frame (idempotent: GLFW call is a no-op when the cursor object
is already set). No dirty-bit mechanism is needed for cursor shape.

### Module location

```
src/01/types.zig         — CursorShape enum, Platform.setCursor, cursor cache
docs/specs/01.types.zig  — CursorShape enum, Platform.setCursor signature
src/07/types.zig         — Scene._cursor parallel array, cursorOf accessor
docs/specs/07.types.zig  — _cursor field, cursorOf
src/app/app.zig          — defaultCursorFor helper, setCursor call in dispatchEvents
docs/requirements/RB0_mouse_cursor_shapes.md
```

## Public API

```zig
// Module 01
pub const CursorShape = enum { arrow, text_beam, crosshair, hand,
                               resize_ew, resize_ns, resize_all, not_allowed };
pub fn setCursor(self: *Platform, shape: CursorShape) void

// Module 07 — Scene
pub fn cursorOf(self: *const Scene, idx: u32) ?CursorShape
```

## Behavioral contract

| Situation | Cursor shown |
|---|---|
| No element under cursor | `arrow` |
| Button, checkbox, radio, dropdown, slider, tabs, accordion, date_picker | `hand` |
| Input, textarea | `text_beam` |
| Any element with `cursor="hand"` attribute | `hand` |
| Any element with `disabled` pseudo-state | `not_allowed` |
| Any element with `cursor=` override | override wins over default |

## Non-goals (DO NOT implement — INV-5.4)

- **No custom image cursors** — standard OS cursors only (GLFW standard set).
- **No animated cursors** — static shapes only.
- **No cursor per scroll container drag** — scroll drag is a future enhancement.
- **No cursor API exposed to screen callbacks** — `setCursor` is called by the app
  dispatch loop only, not by user code.
- **No per-platform cursor image packs** — GLFW's cross-platform standard set only.

## Acceptance criteria

1. Unit tests in `src/01/01_test.zig` (or `src/01/cursor_test.zig`) cover:
   - `CursorShape` enum values map to the correct GLFW constants in `setCursor`.
   - Calling `setCursor` twice with the same shape calls `glfwSetCursor` each time
     (GLFW handles the no-op at the OS level; the wrapper does not need to deduplicate).
   - `Platform.deinit` does not crash when no cursors were ever created.

2. Unit tests in `src/07/07_test.zig` (or added to existing test) cover:
   - After instantiate, element with no `cursor=` attribute returns `null` from `cursorOf`.
   - Element with `cursor="hand"` returns `.hand`.
   - Element with `cursor="text"` returns `.text_beam`.
   - Unknown `cursor=` value leaves the slot `null`.

3. Integration behavior (verified via `zig build visual-check` + manual inspection):
   - Hovering an `<Input>` shows the I-beam cursor.
   - Hovering a `<Button>` shows the hand cursor.
   - Hovering a disabled button shows the not-allowed cursor.
   - Moving off all elements reverts to the arrow cursor.

4. Checklist fully ticked.

## Open questions

None. Standard GLFW cursor set covers all required shapes. No custom images needed.
