# R42 — M4-03: Clipping / overflow-hidden

> Roadmap item: M4-03  
> Depends on: module 09 (renderer/buildDrawList), M3-06 (scroll container)  
> Read `00_constitution.md` before this file.

## Purpose

Clip child draw commands to their scroll container's bounds. The renderer emits a
`set_scissor` draw command before a clipped subtree and a `restore_scissor` command after.
The GPU pipeline translates these into `vkCmdSetScissor` calls with no shader changes. All
other elements continue to render with a full-viewport scissor.

## What to build

### Two new draw command kinds

Extend [09.types.zig](../specs/09.types.zig) `DrawCommand`:

```zig
pub const DrawCommand = union(enum) {
    filled_rect:     FilledRect,
    border_rect:     BorderRect,
    glyph:           GlyphCmd,
    set_scissor:     ScissorRect,  // NEW
    restore_scissor: void,         // NEW
};

/// Integer pixel rect used for scissor. Origin top-left, exclusive right/bottom.
pub const ScissorRect = struct {
    x: i32,
    y: i32,
    w: u32,
    h: u32,
};
```

`restore_scissor` carries no data (it resets to the full-viewport scissor that was active
before the matching `set_scissor`). The payload is `void` so the tagged union stays compact.

### Scissor stack in `VulkanBackend.drawFrame`

The draw-command executor in `VulkanBackend.drawFrame` maintains a small scissor stack
(max depth 8 — sufficient for v1 since nested scrollviews are a non-goal).

```zig
// Pseudo-code for the command executor loop:
var scissor_stack: [8]ScissorRect = undefined;
var scissor_depth: u8 = 0;
const full_viewport_scissor = ScissorRect{ .x = 0, .y = 0, .w = fb_width, .h = fb_height };

// Apply the full-viewport scissor at frame start.
vkCmdSetScissor(..., full_viewport_scissor);

for (commands) |cmd| {
    switch (cmd) {
        .set_scissor => |sr| {
            scissor_stack[scissor_depth] = current_scissor;
            scissor_depth += 1;
            // Intersect with current active scissor to handle nesting correctly.
            const clipped = intersectScissor(current_scissor, sr);
            current_scissor = clipped;
            vkCmdSetScissor(..., current_scissor);
        },
        .restore_scissor => {
            scissor_depth -= 1;
            current_scissor = scissor_stack[scissor_depth];
            vkCmdSetScissor(..., current_scissor);
        },
        // ... existing command handling ...
    }
}
```

`intersectScissor(a, b)` returns the intersection rectangle of `a` and `b`, or a zero-area
rect if they do not overlap. A zero-area scissor causes no pixels to be written (all draw
commands inside are effectively invisible) — this is correct behavior when a scrollview is
fully outside the viewport.

`intersectScissor` is a pure function defined in `src/09/types.zig` (same file as
`buildDrawList`) and exposed as:

```zig
pub fn intersectScissor(a: ScissorRect, b: ScissorRect) ScissorRect
```

### `buildDrawList` changes

In `buildDrawList`, when visiting a `scrollview` element:

1. Before visiting its children, emit `set_scissor` with the element's layout rect
   (converted from `Rect{x,y,w,h}: f32` to `ScissorRect{x,y,w,h}: i32/u32`).
2. Apply the scroll offset to each child's draw commands by offsetting their rects by
   `-scroll_state.scroll_x` and `-scroll_state.scroll_y` respectively.
3. After all children are visited, emit `restore_scissor`.

```zig
// In buildDrawList DFS walk:
if (scene.kindOf(idx) == .scrollview) {
    const layout_rect = scene.elements.layout[idx].computed;
    const sr = ScissorRect{
        .x = @intFromFloat(layout_rect.x),
        .y = @intFromFloat(layout_rect.y),
        .w = @intFromFloat(@max(0, layout_rect.w)),
        .h = @intFromFloat(@max(0, layout_rect.h)),
    };
    try cmds.append(alloc, .{ .set_scissor = sr });
    // ... visit children with scroll offset applied to their rects ...
    try cmds.append(alloc, .{ .restore_scissor = {} });
} else {
    // Normal element — emit background/border/text commands as before.
}
```

The scroll offset translation is applied per child by carrying a `translate: struct{x,y: f32}`
argument through the recursive walk. For elements outside a scroll container, `translate` is
`{0, 0}`.

### `LayoutNode` overflow field

Add `.overflow` to `LayoutNode` in [03.types.zig](../specs/03.types.zig):

```zig
pub const Overflow = enum { visible, hidden };

pub const LayoutNode = struct {
    // ...existing fields...
    overflow: Overflow = .visible,
};
```

`defaultLayoutFor(.scrollview)` in module 07 sets `overflow = .hidden`. The layout engine
(module 04) uses this field to know that a scrollview's children are clipped — but the
actual clipping is performed by the renderer via `set_scissor`, not by the layout engine.

### Conversion helper

```zig
/// Convert a floating-point layout Rect to an integer ScissorRect, clamping to [0, max].
pub fn rectToScissor(r: Rect) ScissorRect {
    const x = @max(0, @as(i32, @intFromFloat(r.x)));
    const y = @max(0, @as(i32, @intFromFloat(r.y)));
    const x2 = @max(x, @as(i32, @intFromFloat(r.x + r.w)));
    const y2 = @max(y, @as(i32, @intFromFloat(r.y + r.h)));
    return .{
        .x = x,
        .y = y,
        .w = @intCast(x2 - x),
        .h = @intCast(y2 - y),
    };
}
```

### Behavioral contract

| Situation | Behavior |
|---|---|
| Normal element (no scrollview ancestor) | Renders with full-viewport scissor |
| Element inside a scrollview | Clipped to scrollview bounds; content outside bounds invisible |
| Nested scrollviews | Scissors are intersected (inner scissor is subset of outer scissor) |
| Scrollview with zero-size layout rect | All children invisible (zero-area scissor) |
| `set_scissor` depth exceeds 8 | Assert/panic in debug; truncated silently in release |

### Module location

```
src/09/types.zig         — ScissorRect, set_scissor/restore_scissor in DrawCommand,
                           intersectScissor, rectToScissor, buildDrawList changes
docs/specs/09.types.zig  — DrawCommand union updated, ScissorRect added
src/03/types.zig         — LayoutNode.overflow field added (Overflow enum)
docs/specs/03.types.zig  — LayoutNode.overflow added
src/01/types.zig         — VulkanBackend.drawFrame scissor stack handling
docs/requirements/R42_clipping_overflow_hidden.md
```

## Public API

New in module 09 (`docs/specs/09.types.zig`):

```zig
pub const ScissorRect = struct { x: i32, y: i32, w: u32, h: u32 }
// DrawCommand union gains .set_scissor and .restore_scissor tags
pub fn intersectScissor(a: ScissorRect, b: ScissorRect) ScissorRect
pub fn rectToScissor(r: Rect) ScissorRect
```

New in module 03 (`docs/specs/03.types.zig`):

```zig
pub const Overflow = enum { visible, hidden }
// LayoutNode gains: overflow: Overflow = .visible
```

## Non-goals (DO NOT implement — INV-5.4)

- **No `overflow: auto`** — the only modes are `visible` (default) and `hidden` (scrollview).
  Auto-scrollbar appearance is post-v1.
- **No per-element arbitrary clip path** — only axis-aligned scissor rects; no rounded
  clipping, no path clipping.
- **No nested scrollview support** — nesting is a non-goal per M3-06 (R35). The scissor
  intersection logic handles it correctly if it occurs, but it is not tested.
- **No partial-glyph clipping** — glyphs that are partially inside the scissor region are
  still emitted as full `GlyphCmd` entries; the GPU scissor clips at the pixel level. No
  glyph-level early-out is added to the serializer.
- **No clip in the overlay layer** — overlay slots (M4-02) always render with full-viewport
  scissor; overlay content is never clipped.

## Acceptance criteria

1. `zig build test-09-unit` passes. New CPU-only test cases:
   - `intersectScissor` of two overlapping rects returns correct intersection.
   - `intersectScissor` of two non-overlapping rects returns zero-area rect.
   - `rectToScissor` with negative x/y clamps to 0.
   - `buildDrawList` on a scene with a scrollview emits `set_scissor` before child
     commands and `restore_scissor` after them.
   - `buildDrawList` on a scene without any scrollview emits no scissor commands.
   - A child element whose layout rect is outside the scrollview bounds still appears in
     the draw list (clipping is GPU-side; the CPU serializer emits all children).

2. GPU integration test (skip if no Vulkan):
   - `drawFrame` with `set_scissor` / `restore_scissor` commands completes without
     Vulkan validation errors.
   - Visually: a scrollview with overflowing content shows no content outside the
     container bounds.

3. Scroll offset translation: a scrolled element's draw commands are offset by the
   correct amount (test by inspecting `filled_rect.rect.x` vs expected offset in a
   unit test with a known scroll state).

4. Depth limit: creating 9 nested `set_scissor` commands causes a debug assertion
   (test with `std.debug.assert` or equivalent in the test build).

5. Checklist fully ticked.

## Open questions

None. Axis-aligned scissor via `vkCmdSetScissor` is the correct and simplest v1 approach.
The 8-level stack covers all realistic UI layouts; nested scrollviews are explicitly out of scope.
