# R90 — M9-01: Debug overlay

> Roadmap item: M9-01  
> Depends on: M1-02 (event delivery), module 09 (renderer)  
> Read `00_constitution.md` before this file.

## Purpose

Provide an in-process debug layer that, when toggled on, draws colored element bounds over
the normal scene and shows the computed rect and applied style of whichever element the
cursor is hovering over. The layer is invisible in production; toggling it must not alter
rendering of the normal scene in any way.

An author debugging layout writes nothing — they press the hotkey and see the element tree
directly on screen.

---

## Motivation

Without visual layout feedback, a misaligned element requires adding temporary background
colors to widgets and recompiling. The debug overlay eliminates that workflow by making
the live layout tree visible at any time during development, with no recompile.

---

## What to build

### 1. `DebugOverlay` struct

```zig
pub const DebugOverlay = struct {
    enabled: bool = false,
    hovered_idx: u32 = NONE,   // NONE = no hover; set by hit-test each frame

    pub fn init() DebugOverlay;
    pub fn toggle(self: *DebugOverlay) void;
    pub fn isEnabled(self: *const DebugOverlay) bool;

    /// Update the hovered element from the current cursor position.
    /// Called once per frame before buildDebugDrawList.
    pub fn updateHover(self: *DebugOverlay, scene: *const Scene, x: f32, y: f32) void;

    /// Produce an overlay draw list.  The returned slice is owned by `alloc`; caller frees it.
    /// Returns an empty slice when !enabled.
    pub fn buildDebugDrawList(
        self: *const DebugOverlay,
        alloc: std.mem.Allocator,
        scene: *const Scene,
        tokens: Tokens,
        font: *Font,
        atlas: *GlyphAtlas,
    ) ![]DrawCommand;
};
```

### 2. Hotkey

`F1` toggles the overlay. The key press is consumed by `App.dispatchEvents` before any
other handler: if `F1` is pressed and the debug overlay is present, toggle and return without
propagating the event further.

`F1` must NOT conflict with any existing key handler. Confirm: no existing handler in
`app.zig` uses `Key.f1`. If a future spec assigns `F1`, the conflict must be surfaced.

### 3. Element bounds drawing

When enabled, `buildDebugDrawList` walks every live element in depth-first pre-order
(same traversal order as `buildDrawList` in module 09) and emits one `border_rect` command
per element:

| Element state | Border color |
|---|---|
| `hovered_idx` matches | `tokens.accent` with `a = 255`, width 2 px |
| focusable element | `tokens.info` with `a = 180`, width 1 px |
| layout container (row/column/card/scrollview) | `tokens.ok` with `a = 140`, width 1 px |
| all other elements | `tokens.warn` with `a = 120`, width 1 px |

All colors reference `Tokens` fields only — no hex literals (INV-4.3).

Zero-size elements (`computed.w == 0 or computed.h == 0`) are skipped (same rule as the
main renderer).

Hidden elements (`scene.isHidden(idx)`) are skipped — the bounds overlay is not drawn for
elements that are not rendered.

### 4. Hover info panel

When `hovered_idx != NONE`, an info panel is drawn in the bottom-left corner of the viewport
(24 px from each edge). The panel consists of:

1. A `filled_rect` background: `tokens.bg_raised` with `a = 230` (semi-opaque, not fully
   blocking the scene behind it).
2. A `border_rect` outline: `tokens.border_default`, width 1 px, radius 4.
3. Lines of glyph commands rendered with the provided `font` and `atlas`, font size 11 px,
   color `tokens.text_body`.

The panel displays (one line per entry, in this order):

```
idx: <element_index>   kind: <WidgetKind tag name>
x: <computed.x>  y: <computed.y>  w: <computed.w>  h: <computed.h>
bg: #RRGGBB  text: #RRGGBB  border: <border_width>px #RRGGBB
radius: <radius>  pad: <top>/<right>/<bottom>/<left>  font: <font_size>px
```

All float values are formatted to one decimal place (e.g. `12.0`). Colors are formatted
as `#RRGGBB` (alpha is not shown). The panel is sized to fit its text content; minimum
width 240 px. If the panel would extend beyond the right edge of the viewport, it is
shifted left; same for the bottom edge.

Text rendering uses `layoutParagraph` (module 02) with a large max-width so lines do not
wrap within the panel.

### 5. Integration into `AppInner`

`AppInner` gains one new field:

```zig
debug_overlay: DebugOverlay = DebugOverlay.init(),
```

In `App.run` / `App.runWithNav`, after the main draw list and overlay are built but before
`backend.drawFrame`, if the debug overlay is enabled:

```zig
const debug_cmds = app.debug_overlay.buildDebugDrawList(
    app.gpa, &app.scene, app.tokens,
    app.font_family.face(false, false), &app.atlas_cpu,
) catch &[_]DrawCommand{};
defer if (debug_cmds.len > 0) app.gpa.free(debug_cmds);
// Concatenate after overlay_cmds (debug layer is topmost).
```

The debug draw list is concatenated AFTER the normal overlay commands (topmost z-order,
painter's algorithm).

`updateHover` is called once per frame inside `run` using `app.last_cursor_x` and
`app.last_cursor_y`, immediately before `buildDebugDrawList`.

The `F1` hotkey is checked in `dispatchEvents` before the existing key dispatch switch:

```zig
if (key == .f1) {
    self.debug_overlay.toggle();
    self.scene.elements.markAllDirty();
    return;
}
```

### 6. Hover hit-test

`updateHover` iterates the live element list in reverse DFS order (topmost painted element
first, so inner elements take precedence over their containers when they overlap):

```
for each live element in reverse pre-order:
    if hidden: skip
    if computed.w == 0 or computed.h == 0: skip
    if cursor is inside computed rect:
        hovered_idx = idx
        return
hovered_idx = NONE
```

---

## Module location

```
src/app/debug_overlay.zig      — DebugOverlay struct
src/app/debug_overlay_test.zig — acceptance tests (headless)
docs/requirements/R90_debug_overlay.md
```

`src/app/types.zig` re-exports `DebugOverlay`.

---

## Invariant interactions

- **INV-2.3**: `DebugOverlay` emits `DrawCommand` values — the same vocabulary as the
  main renderer. It does NOT know about Vulkan or the GPU.
- **INV-4.3**: All colors reference `Tokens` fields. No hex literals in `debug_overlay.zig`.
- **INV-3.3**: The overlay does NOT mark any element dirty. It reads scene state; it does
  not write it. Toggling calls `markAllDirty()` once to force a repaint.

---

## Glossary addition

Add to `docs/specs/glossary.md`:

```
## DebugOverlay

An opt-in draw layer owned by `AppInner` that, when toggled with F1, draws element bounds
over the scene and shows a hover-info panel with the computed rect and style of the element
under the cursor. Produces a `[]DrawCommand` slice appended after all other draw commands
(topmost z-order). Toggling marks all elements dirty to force an immediate repaint.
Not compiled out in production — it is always present but `!enabled` makes it zero-cost
(empty slice returned). Defined in `src/app/debug_overlay.zig`.

See: R90 (M9-01).
```

---

## Non-goals (DO NOT implement — INV-5.4)

- NO element selection or clicking to pin an element — hover only.
- NO tree-view or hierarchical panel — the info panel shows one hovered element at a time.
- NO export / screenshot of the overlay state.
- NO separate debug window (that is M8-04 territory).
- NO performance counters in this item — that is M9-03.
- NO compilation guard (`comptime debug_build`) — the overlay struct is always present;
  its cost when disabled is one bool check per frame.

---

## Acceptance criteria

The module is done when:

1. `zig build test-debug-overlay` passes all tests in `src/app/debug_overlay_test.zig`.
2. `DebugOverlay.init()` starts with `enabled = false`; `buildDebugDrawList` returns an
   empty slice.
3. After `toggle()`, `isEnabled()` returns `true`; `buildDebugDrawList` returns a non-empty
   slice for a scene with at least one element.
4. `updateHover` sets `hovered_idx` to the topmost element whose rect contains (x, y);
   sets `NONE` when (x, y) is outside all rects.
5. The hover info panel text contains the correct `idx`, `kind`, and computed rect values
   for the hovered element.
6. Zero-size and hidden elements produce no bounds rect in the debug list.
7. F1 toggles the overlay and triggers a full repaint (verified by checking `markAllDirty`
   was called in the test).
8. The checklist for this item is fully ticked.

---

## Edge cases (each has a test)

- Scene with zero live elements — `buildDebugDrawList` returns empty slice even when enabled.
- Two overlapping elements — `updateHover` returns the topmost (last in DFS order) one.
- Cursor outside the window — `updateHover` receives out-of-bounds coordinates; `hovered_idx`
  is set to `NONE` without crashing.
- Toggle called twice — returns to `!enabled`; next `buildDebugDrawList` returns empty.
- Info panel at the bottom-right corner of the viewport — panel shifts left/up to stay
  within bounds.
