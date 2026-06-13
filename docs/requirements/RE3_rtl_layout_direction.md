# RE3 — M15-04: RTL layout direction

> Roadmap item: M15-04
> Depends on: module 04 (layout engine — LayoutNode), module 09 (renderer — buildDrawList)
> Read `00_constitution.md` before this file.

## Purpose

Add support for right-to-left layout direction, a prerequisite for Hebrew and Arabic
localization (post-v1 — this item only adds the layout infrastructure). A `direction: rtl`
flag on `LayoutNode` reverses the main flex axis and mirrors text layout coordinates.

**Important scope note:** This implements RTL LAYOUT only, not RTL text shaping. The project's
invariant INV-1.3 (no complex-script shaping) remains in effect. RTL layout allows a Hebrew
or Arabic interface to use the correct visual layout (menus on the right, text flows right
to left within containers) even though the actual glyph shaping is not supported.

## What to build

### LayoutNode.direction field

Add to `LayoutNode` in `src/03/types.zig` and `docs/specs/03.types.zig`:

```zig
pub const Direction = enum(u8) {
    ltr = 0,
    rtl = 1,
};

pub const LayoutNode = struct {
    // ...existing fields...
    display: Display = .block,
    direction: FlexDirection = .row,
    // ...
    /// M15-04: text/layout direction. Default ltr.
    /// When rtl, flex main axis is reversed and text baseline is right-aligned.
    layout_direction: Direction = .ltr,
};
```

### Flex direction reversal in layout engine (module 04)

In `solve()` (module 04), when `layout_direction == .rtl`:

1. **Flex container children are laid out right-to-left.** The first child is placed at
   the right edge of the container instead of the left edge; subsequent children are placed
   to the left of the previous child. This is equivalent to reversing the child ordering
   before applying the normal LTR flex algorithm.

2. **Justify-content values are mirrored:**
   - `flex-start` → children align to the RIGHT edge
   - `flex-end` → children align to the LEFT edge
   - `center` → unchanged

Implementation approach: In the flex layout solver, before iterating children, check
`layout_direction`. If `.rtl`, reverse the child iteration order and mirror the
justify-content calculation. This is the minimal change to support RTL without a
full flex-direction reversal.

Specifically, the flex solver in module 04 places children left-to-right along the main
axis. For RTL:
- Compute child positions starting from `container.x + container.w` (right edge) going left.
- Child `i` is placed at `right_edge - sum_of_widths_of_placed_children - child_i_width`.
- Margins are included in the width calculation.
- `margin-left` and `margin-right` retain their CSS-standard logical meaning:
  margin-left always adds space on the logical left side of the element. In RTL, the
  "logical left" side of the page is the right edge. This means:
  - In RTL, `margin-left: auto` pushes the element to the LEFT (it's the "right margin"
    to the browser) — wait, no. In the CSS spec, margin-left/margin-right are logical
    and swap in RTL. Since this project uses Tailwind-like `ml-*`/`mr-*` classes and
    the project is not committed to CSS logical properties, for v1:
  - `margin-left` and `margin-right` are NOT swapped by RTL. They maintain their physical
    meanings. RTL only reverses the primary flex-direction child-placement order.

3. **Text alignment within a text element:** When `layout_direction == .rtl`, the
   `text-anchor` for emitted glyphs is right-aligned: glyphs are positioned relative to
   the RIGHT edge of the element's content rect instead of the LEFT edge. The `emitGlyphs`
   function in module 09 is updated to check `layout_direction` and adjust the X baseline.

### Renderer changes (module 09)

In `buildDrawList`, when iterating elements, check `layout_direction` on text elements:
- If `.ltr` (default): current behavior — glyphs positioned from the left edge.
- If `.rtl`: offset glyph X positions so that the text visually ends at the right edge
  of the element rect (right-aligned within the layout rect).

```zig
// In emitGlyphs or the text handling path:
if (node.layout_direction == .rtl) {
    // Right-align: text_end_x = element_right_edge
    // Instead of baseline_start_x = element_left_edge + padding_left
    // shift all glyphs right by (content_width - measured_text_width)
    const rtl_offset = content_width - measured_line_widths[line];
    // apply rtl_offset to x for every glyph on this line
}
```

### Tailwind class resolver (module 06)

Add `direction-rtl` and `direction-ltr` classes:

```zig
// In applyClass:
if (eql(u8, cls, "direction-rtl")) { r.layout.layout_direction = .rtl; return; }
if (eql(u8, cls, "direction-ltr")) { r.layout.layout_direction = .ltr; return; }
```

These map to the `LayoutNode.layout_direction` field.

### Default styles

No widget kind changes `layout_direction` by default. It is always `.ltr` unless explicitly
set by the `direction-rtl` class.

### Module location

```
docs/specs/03.types.zig      — Direction enum, LayoutNode.layout_direction field
src/03/types.zig             — re-exports the Direction enum and updated LayoutNode
src/04/types.zig             — flex solver RTL reversal logic
src/06/types.zig             — direction-rtl, direction-ltr classes
src/09/types.zig             — buildDrawList RTL text alignment
docs/specs/03.types.zig      — contract file update
```

## Non-goals (DO NOT implement — INV-5.4)

- **No complex-script shaping** — INV-1.3 remains in effect. Hebrew and Arabic glyphs will
  be rendered using the existing stb_truetype pipeline with basic glyph lookup. This is
  acceptable for a developer preview but not for real RTL content.
- **No bidirectional (bidi) text** — all text in an element is treated as either LTR or RTL;
  mixed-direction text (e.g. English numbers inside Hebrew text) is not handled.
- **No mirroring of icons or images** — icon/image rendering is direction-agnostic in v1.
- **No RTL-aware scrollbar position** — scrollbars remain on the right side regardless of
  direction.
- **No RTL overlay positioning** — dropdowns, tooltips, and modals open at the same relative
  position regardless of direction.
- **No `direction` attribute in `.ui` markup** — only the `direction-rtl` Tailwind class.
- **No grid layout reversal** — RTL only affects flex containers and text alignment. Grid
  tracks remain left-to-right.

## Acceptance criteria

1. `LayoutNode.layout_direction` defaults to `.ltr`.
2. `Direction` enum has `.ltr` (value 0) and `.rtl` (value 1).
3. Class `direction-rtl` sets `layout_direction = .rtl`.
4. Flex container with `direction-rtl` places children from right to left.
5. Text element with `direction-rtl` renders glyphs right-aligned within the element rect.
6. Default (no class) behavior is unchanged — all existing layout and text tests pass.
7. A flex container with `direction-rtl` and `justify-content: center` centers children
   (no mirroring for center).
8. Unit tests verify the LayoutNode field default, class resolution, and flex RTL placement.
