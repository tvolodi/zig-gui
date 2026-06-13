# RD0 — M13-01: Gradient fills

> Roadmap item: M13-01  
> Depends on: 09 (renderer), 05 (theme)  
> Read `00_constitution.md` before this file.

## Purpose

Add horizontal, vertical, and diagonal gradient fills as a new draw-command variant. Gradients
replace flat-color filled rects where a `bg-gradient-to-*` class is present on the element.
This is the first rendering effect that computes color per-fragment based on UV coordinates,
and it establishes the pattern for subsequent shader modes (SDF, AA shapes).

Without gradients, every filled rectangle is a single solid color — no smooth transitions
between theme tokens are possible.

## What to build

### `GradientDirection` enum and `GradientRect` struct (module 01)

```zig
pub const GradientDirection = enum { right, bottom, bottom_right };

pub const GradientRect = struct {
    rect: Rect09,
    color_a: Color09,  // left/top color
    color_b: Color09,  // right/bottom color
    direction: GradientDirection,
};
```

Add `.gradient_rect: GradientRect` to the `DrawCommand` union.

### New shader mode 2: gradient (module 09 — `quad.frag`)

The fragment shader gains a new mode:

```glsl
if (fragMode == 2u) {
    // Linear interpolation between two colors using fragUV.
    // direction encoded in the UV coordinates set by the vertex:
    //   right:        t = fragUV.x
    //   bottom:       t = fragUV.y
    //   bottom_right: t = (fragUV.x + fragUV.y) * 0.5
    // The vertex shader sets UV.x = 0..1 and UV.y = 0..1 across the rect.
    // The shader uses a selectable mix coordinate; for simplicity,
    // the vertex stage encodes the gradient direction into the UV range,
    // and the fragment shader reads t from a single axis or diagonal.
    float t = fragUV.x * gradientAxis.x + fragUV.y * gradientAxis.y;
    outColor = mix(fragColor.colorA, fragColor.colorB, t);
}
```

However, since the vertex shader sets the same `[0..1, 0..1]` UV for every gradient rect
regardless of direction, the fragment shader needs to know the axis. The direction is passed
via a new push-constant: `layout(offset = 16) uniform GradientParams { vec4 gradientAxis; }`.

The vertex shader encodes `color_a` and `color_b` into the existing `fragColor` channel by
splitting them: the vertex shader passes `color_a` as the vertex color and `color_b` as a
second vertex attribute (or encodes both via the UV.z/w channels). For v1 simplicity, use
two quads for each gradient rect — one per color stop — with the fragment shader blending
them via `t`. Actually simpler: pass `color_a` in the vertex color attribute and use the
push-constant block to carry `color_b`:

Simplest v1 approach (no vertex format change):
- `gradient_rect` emits two `filled_rect` draw commands internally: one for `color_a` and one
  for `color_b`, OR
- The vertex shader is extended with a second color attribute (`fragColorB`), used only by
  mode 2. The `QuadVertex` gains: `color_b: [4]u8` (4 bytes, 24 → 28 bytes per vertex).
  Mode 2 fragment shader: `outColor = mix(fragColor, fragColorB, t)`.

The vertex format extension is preferred — it keeps the draw-command API clean (one command
= one render call) and avoids duplicating geometry.

**Fragment shader logic for mode 2:**

```glsl
// Inputs added: fragColorB (location 3), gradientAxis push constant
float t = clamp(dot(fragUV, gradientAxis), 0.0, 1.0);
outColor = mix(fragColor, fragColorB, t);
```

`gradientAxis` is `(1, 0)` for `right`, `(0, 1)` for `bottom`, `(0.7071, 0.7071)` for
`bottom_right` (normalized so the diagonal reaches full range at (1,1)).

### Tailwind class resolver (module 06)

| Class | Effect |
|---|---|
| `bg-gradient-to-r` | Sets a `gradient_direction: GradientDirection` field on the resolved style; defaults to `.right` |
| `bg-gradient-to-b` | Sets direction to `.bottom` |
| `bg-gradient-to-br` | Sets direction to `.bottom_right` |

The color stops come from theme tokens: `color_a = tokens.bg_canvas`, `color_b = tokens.bg_surface`.
No arbitrary `from-{color}` / `to-{color}` classes in v1.

A new field on `LayoutNode` or `ComputedStyle`:
```zig
gradient_direction: ?GradientDirection = null,
```

When `gradient_direction` is non-null and the element is a filled container, the renderer emits
a `gradient_rect` instead of a `filled_rect`.

### Renderer changes (module 09 — `buildDrawList`)

In `buildDrawList`, when emitting the background draw command for an element whose
`computed_style.gradient_direction` is non-null:

1. Read `color_a` = `tokens.bg_canvas` resolved, `color_b` = `tokens.bg_surface` resolved.
2. Emit `DrawCommand{ .gradient_rect = .{ .rect = ..., .color_a = ..., .color_b = ..., .direction = ... } }`.
3. The existing filled_rect path is skipped.

### Vertex format change (module 01)

`QuadVertex` gains `color_b: [4]u8` (after `color`). Vertex size: 28 bytes.
Update the Vulkan `VkVertexInputBindingDescription` and `VkVertexInputAttributeDescription`
arrays to include the new attribute at location 3 (RGBA8 UNORM).

## Module location

```
src/01/types.zig         — GradientDirection enum, GradientRect struct, .gradient_rect DrawCommand variant, QuadVertex.color_b
src/06/types.zig         — gradient_direction field, bg-gradient-to-{r,b,br} class resolver
docs/specs/06.types.zig  — updated class table
src/09/types.zig         — emit gradient_rect in buildDrawList, set push-constant gradientAxis
src/09/shaders/quad.vert — add fragColorB output, pass gradientAxis push constant
src/09/shaders/quad.frag — mode 2: gradient mix
docs/specs/09.types.zig  — spec mirror
docs/requirements/RD0_gradient_fills.md
```

## Public API changes

```zig
// Module 01
pub const GradientDirection = enum { right, bottom, bottom_right };
pub const GradientRect = struct {
    rect: Rect09, color_a: Color09, color_b: Color09,
    direction: GradientDirection,
};
// DrawCommand gains: gradient_rect: GradientRect,
// QuadVertex gains: color_b: [4]u8,
```

## Behavioral contract

| Situation | Behavior |
|---|---|
| Element has class `bg-gradient-to-r` | Background rendered with left→right gradient: `bg_canvas` → `bg_surface` |
| Element has class `bg-gradient-to-b` | Top→bottom gradient |
| Element has class `bg-gradient-to-br` | Top-left→bottom-right diagonal gradient |
| Element has no gradient class | Solid `filled_rect` as before (mode 0), no shader-mode change |
| Gradient element also has `rounded` | Gradient respects the corner radius via the rounded-rect geometry |
| Gradient rect has `w = 0` or `h = 0` | No draw command emitted (same as filled_rect degenerate check) |

## Non-goals (DO NOT implement — INV-5.4)

- **No radial gradients** — only linear.
- **No conical gradients.**
- **No `from-{color}` / `to-{color}` / `via-{color}` custom stop classes** — stops are always
  `bg_canvas` and `bg_surface` in v1.
- **No more than 2 color stops.**
- **No gradient on text or borders** — gradient applies only to element backgrounds.
- **No CSS gradient-angle syntax** (`bg-gradient-{45deg}`).
- **No gradient repeat modes** (`bg-repeat-gradient`).
- **No gradient texture tile** — interpolation is in-shader, using fragUV.
- **No `opacity` interaction with gradient** — opacity is applied later (R45).

## Acceptance criteria

1. `zig build` passes after all changes; SPIR-V shaders recompile without errors.

2. Unit tests in `src/06/06_test.zig` cover:
   - `bg-gradient-to-r` class → `gradient_direction = .right`.
   - `bg-gradient-to-b` → `gradient_direction = .bottom`.
   - `bg-gradient-to-br` → `gradient_direction = .bottom_right`.
   - No gradient class → `gradient_direction = null`.

3. Unit tests in `src/09/09_test.zig` cover:
   - `buildDrawList` emits `.gradient_rect` (not `.filled_rect`) for an element with
     `gradient_direction = .right`.
   - The emitted `GradientRect.color_a` and `color_b` match the resolved theme tokens.
   - `direction` is correctly passed through to the draw command.

4. Visual: a screen in the demo app shows a `<Card>` with `bg-gradient-to-r` — visible
   left-to-right color transition from `bg_canvas` to `bg_surface`.

5. No regression: existing rects with no gradient class still render as solid fills.
