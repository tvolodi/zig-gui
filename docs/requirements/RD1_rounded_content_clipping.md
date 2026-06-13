# RD1 — M13-02: Rounded content clipping

> Roadmap item: M13-02  
> Depends on: 09 (renderer), R42 (overflow-hidden clipping)  
> Read `00_constitution.md` before this file.

## Purpose

When an element has `overflow-hidden` and `rounded-{n}` classes, its children must be clipped
to the rounded-corner boundary of the container — not to a sharp axis-aligned rectangle.
Currently, `set_scissor` clips to a rectangular region only, so children (images, text, nested
elements) overlap the rounded corners of their parent container.

This requirement closes the visual gap between the rounded background (which already renders
with correct corner radii) and the content inside it.

## What to build

### Approach: per-fragment corner clipping in the shader

The existing scissor system (`set_scissor` / `restore_scissor`) applies `VkRect2D` scissor
commands that clip to axis-aligned rectangles in the GPU's fixed-function rasterization stage.
Rounded clipping requires per-fragment decisions, which only the fragment shader can make.

For v1, the approach is:

1. **Add a `clip_rounded_begin` / `clip_rounded_end` draw-command pair.** These bracket a
   draw range where the fragment shader additionally discards pixels outside the rounded rect.

2. **Rounded clip state is passed via push constants.** The push-constant block gains:

   ```glsl
   layout(offset = 32) uniform ClipParams {
       vec4 clipRect;      // x, y, w, h of the clip rect in screen pixels
       vec4 clipRadii;     // top_left, top_right, bottom_right, bottom_left corner radii
   };
   ```

   `clipRadii.x` = top-left radius, `clipRadii.y` = top-right, `clipRadii.z` = bottom-right,
   `clipRadii.w` = bottom-left.

3. **`clip_rounded_begin` sets the push constants and enables a `clip_active` uniform boolean.**
   All fragment-shader modes (0–6) check `clip_active` before output. If active, the fragment
   computes whether the fragment position is inside the rounded rect. If outside, the fragment
   is discarded (`discard`).

4. **`clip_rounded_end` resets `clip_active` to false.** Push constants are not reverted
   (they are irrelevant when clipping is inactive).

### Fragment shader rounded-corner test

```glsl
// clip_active is a push-constant boolean (packed into a u32)
if (clipActive != 0u) {
    vec2 cp = gl_FragCoord.xy - clipRect.xy;  // position within clip rect
    float r = 0.0;
    if (cp.x < clipRadii.x && cp.y < clipRadii.x) {
        // Top-left corner: distance from (radius, radius)
        r = clipRadii.x - length(vec2(clipRadii.x - cp.x, clipRadii.x - cp.y));
    } else if (cp.x > clipRect.z - clipRadii.y && cp.y < clipRadii.y) {
        // Top-right corner
        r = clipRadii.y - length(vec2(cp.x - (clipRect.z - clipRadii.y), clipRadii.y - cp.y));
    } else if (cp.x > clipRect.z - clipRadii.z && cp.y > clipRect.w - clipRadii.z) {
        // Bottom-right corner
        r = clipRadii.z - length(vec2(cp.x - (clipRect.z - clipRadii.z), cp.y - (clipRect.w - clipRadii.z)));
    } else if (cp.x < clipRadii.w && cp.y > clipRect.w - clipRadii.w) {
        // Bottom-left corner
        r = clipRadii.w - length(vec2(clipRadii.w - cp.x, cp.y - (clipRect.w - clipRadii.w)));
    } else {
        // Not in any corner zone — inside the rect by default
        return; // don't discard
    }
    if (r < 0.0) discard;
}
```

The fragment position `gl_FragCoord` is used directly because the clipping is in screen-space
pixels — matching the existing scissor coordinate system.

### New draw commands (module 01)

```zig
pub const ClipRounded = struct {
    rect: Rect09,   // same coordinate space as ScissorRect (screen pixels, top-left origin)
    radius_tl: f32,
    radius_tr: f32,
    radius_br: f32,
    radius_bl: f32,
};

// DrawCommand gains:
clip_rounded_begin: ClipRounded,
clip_rounded_end: void,
```

Individual corner radii allow non-uniform rounded corners (e.g., `rounded-tl-lg` only rounds
the top-left corner). When all four radii are equal, the value is duplicated.

The `clip_rounded_begin` command:
- Emits a zero-area draw that sets `pushConstants.clipRect` and `pushConstants.clipRadii`,
  and sets `pushConstants.clipActive = 1`.
- The VkRect2D scissor is ALSO set to the bounding rectangle of `clip.rect` — this gives the
  GPU an early coarse cull (axis-aligned), and the fragment shader handles the corner detail.

The `clip_rounded_end` command:
- Emits `pushConstants.clipActive = 0`.
- Issues a `restore_scissor` equivalent.

### Integration with buildDrawList (module 09)

In `buildDrawList`, when visiting an element with both `overflow == .hidden` and one or more
`rounded_*` corner radii set:

1. Emit `clip_rounded_begin` with the element's content rect and corner radii.
2. Emit children's draw commands (as normal).
3. Emit `clip_rounded_end`.

If the element has `overflow == .hidden` but NO rounded corners, use the existing
`set_scissor` / `restore_scissor` path (unchanged).

## Module location

```
src/01/types.zig         — ClipRounded struct, clip_rounded_begin / clip_rounded_end DrawCommand variants
src/09/types.zig         — buildDrawList: emit clip_rounded_begin/end for rounded overflow-hidden containers
src/09/shaders/quad.vert — pass through clipActive, clipRect, clipRadii as push constants
src/09/shaders/quad.frag — clipActive check + per-corner discard logic (all modes)
docs/specs/09.types.zig  — spec mirror
docs/requirements/RD1_rounded_content_clipping.md
```

## Public API changes

```zig
// Module 01
pub const ClipRounded = struct {
    rect: Rect09,
    radius_tl: f32, radius_tr: f32, radius_br: f32, radius_bl: f32,
};
// DrawCommand gains:
clip_rounded_begin: ClipRounded,
clip_rounded_end: void,
```

## Behavioral contract

| Situation | Behavior |
|---|---|
| Container: `rounded-lg overflow-hidden`, children extend into corners | Children clipped to rounded rect; corner pixels outside radius discarded |
| Container: `rounded-lg` only, no `overflow-hidden` | No clipping occurs (only the container's own background has rounded corners) |
| Container: `overflow-hidden` only, no rounded corners | Existing `set_scissor` path used (axis-aligned clip, no shader clipping) |
| Nested `clip_rounded_begin` blocks | Innermost clip wins (push constants overwritten); `clip_rounded_end` restores prior state via a clip stack in push constants |
| All radii = 0 | Equivalent to a plain scissor; fragment shader corner test is skipped |
| Degenerate rect (w=0 or h=0) | No draw commands emitted; clip_rounded_begin is a no-op |

## Non-goals (DO NOT implement — INV-5.4)

- **No stencil-buffer approach** — clipping is done in the fragment shader, not via
  VkStencilOp state. A stencil pass would require an extra render pass.
- **No render-to-texture mask** — no offscreen buffer for masking.
- **No clip-path shapes other than rounded rectangles** — no elliptical, polygonal, or
  SVG-path clipping.
- **No `clip-rule` property** — no even-odd vs non-zero fill rule selection.
- **No nested clip stack** beyond push-constant overwrite — if two `clip_rounded_begin`
  calls nest, the second overwrites the first's clip params. A clip stack is a future
  enhancement.
- **No anti-aliased clip edges** — the clip boundary is a hard discard. Anti-aliased
  clipping requires alpha accumulation and is deferred.
- **No `border-radius` shorthand that differs from `rounded`** — the corner radii used
  for clipping are the same as the visual border-radius values.

## Acceptance criteria

1. `zig build` passes; SPIR-V shaders recompile with the new `clipActive` and `clipRect`/`clipRadii` push constants.

2. Unit tests in `src/09/09_test.zig` cover:
   - `buildDrawList` emits `clip_rounded_begin` / `clip_rounded_end` for an element with
     `overflow_hidden` and `rounded` corners.
   - `buildDrawList` emits plain `set_scissor` / `restore_scissor` for `overflow_hidden`
     without rounded corners (no regression for R42).
   - `buildDrawList` emits no clip commands for `overflow_visible` even with rounded corners.

3. Visual: demo app screen shows a `<Card>` with `rounded-xl overflow-hidden` containing an
   `<Image>` that extends to the card edges. The image corners are visibly clipped to the
   card's rounded border.

4. Visual: same card with `overflow-visible` (or no `overflow-hidden`) — the image extends
   past the rounded corners (existing behavior, unchanged).

5. No regression: plain `overflow-hidden` containers still clip correctly.
