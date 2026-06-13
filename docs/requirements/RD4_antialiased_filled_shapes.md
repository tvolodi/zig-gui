# RD4 — M13-05: Anti-aliased filled shapes

> Roadmap item: M13-05  
> Depends on: 09 (renderer)  
> Read `00_constitution.md` before this file.

## Purpose

Add a 1-pixel anti-aliasing feather to filled rectangles and circles. Currently, `filled_rect`
and `filled_circle` draw commands emit quads with mode 0 (solid color), producing hard,
aliased edges that are visually jarring — especially for rounded rectangles and circles where
the edge is not aligned with the pixel grid.

This requirement applies a fragment-shader-based anti-aliasing that computes the per-fragment
distance to the shape edge and smoothly transitions the alpha channel over a 1-pixel band.

## What to build

### New shader modes: 5 (aa filled rect) and 6 (aa filled circle)

The fragment shader gains two new modes that compute edge distance in UV space:

**Mode 5 — anti-aliased filled rectangle:**

```glsl
if (fragMode == 5u) {
    // fragUV.x = 0..1 across width, fragUV.y = 0..1 across height
    // feather_uv = 1.0 / min(rectWidth, rectHeight) — passed via push constant
    // Edge distance: minimum of the four edge distances in UV space,
    // then scaled to pixel units.
    float d_left   = fragUV.x;
    float d_right  = 1.0 - fragUV.x;
    float d_top    = fragUV.y;
    float d_bottom = 1.0 - fragUV.y;
    float d = min(min(d_left, d_right), min(d_top, d_bottom));
    float alpha_val = smoothstep(0.0, featherUV, d);
    outColor = vec4(fragColor.rgb, fragColor.a * alpha_val);
}
```

`featherUV` is the feather width in UV space: `1.0 / min(rect_w, rect_h)`. It is passed
via a push constant `featherUV` (float, 4 bytes after the existing push constant block).

For rounded rectangles, the corner radii are encoded in a separate push constant
`cornerRadiusUV` (float). The fragment shader adjusts the distance computation for
corners — this is the same corner-test logic as RD1's rounded clipping but inverted
(smooth alpha instead of discard):

```glsl
// If cornerRadiusUV > 0, adjust edge distance in corners:
// For each corner zone, compute distance from corner center, subtract radius.
// d = max(d_edge, d_corner) where d_corner = radius - length(corner_center - fragUV)
```

However, combining AA feather with rounded corners in the same shader pass is complex.
For v1, a simpler approach: the `filled_rect` with `radius > 0` already has rounded
geometry (the quad vertices are adjusted) and the AA mode 5 handles the straight edges.
The rounded corners are approximated by the existing geometry — the fragment shader
applies AA to the quad's rasterized edges, which are already curved for rounded rects.

**Simplified v1 approach for mode 5:** The quad for a rounded rect already has its
vertices placed on the curved path. The fragment shader just computes the distance to
the *quad's raster edge* using screen-space derivatives:

```glsl
if (fragMode == 5u) {
    // Use screen-space partial derivatives to get pixel-size in UV space.
    vec2 dx = dFdx(fragUV);
    vec2 dy = dFdy(fragUV);
    float d_left   = fragUV.x / length(vec2(dx.x, dy.x));
    float d_right  = (1.0 - fragUV.x) / length(vec2(dx.x, dy.x));
    float d_top    = fragUV.y / length(vec2(dx.y, dy.y));
    float d_bottom = (1.0 - fragUV.y) / length(vec2(dx.y, dy.y));
    float d = min(min(d_left, d_right), min(d_top, d_bottom));
    float alpha_val = smoothstep(0.0, 1.0, d);  // 1 px feather
    outColor = vec4(fragColor.rgb, fragColor.a * alpha_val);
}
```

**Mode 6 — anti-aliased filled circle:**

```glsl
if (fragMode == 6u) {
    // fragUV centered at circle center: (0.5, 0.5) maps to center.
    // Distance from center in UV space (0 at center, 0.5 at edge).
    float dist_uv = length(fragUV - 0.5) * 2.0;  // 0 at center, 1.0 at edge
    // Convert dist_uv to pixel distance using derivatives.
    vec2 dx = dFdx(fragUV);
    vec2 dy = dFdy(fragUV);
    float pixel_scale = length(vec2(dx.x + dy.x, dx.y + dy.y)) * 0.5; // approximate
    float d_pixel = (1.0 - dist_uv) / pixel_scale;
    float alpha_val = smoothstep(0.0, 1.0, d_pixel);
    outColor = vec4(fragColor.rgb, fragColor.a * alpha_val);
}
```

The circle quad's UV is set such that `(0.5, 0.5)` is the circle center and the edge
is at distance 0.5 from center in UV space.

### Draw command changes (module 01)

Two new draw command variants, or flags on the existing variants. For clean separation:

```zig
// DrawCommand gains:
aa_filled_rect: FilledRect,   // same struct, but emits mode 5 quads
aa_filled_circle: CircleCmd,  // new struct for circle commands
```

Where:
```zig
pub const CircleCmd = struct {
    center: struct { x: f32, y: f32 },
    radius: f32,
    color: Color09,
};
```

The `buildDrawList` function chooses between `filled_rect` and `aa_filled_rect` (and
between the circle equivalent) based on a global or per-element anti-aliasing flag.

### Activation

Anti-aliasing is applied by default for all filled shapes. There is no opt-out per
element in v1 — the performance cost is negligible (a few extra fragment shader
instructions) and the visual improvement is universal.

The existing non-AA `filled_rect` mode 0 is retained so border rects, debug rects,
and other internal geometry continue to render with hard edges where appropriate.

### When AA is NOT applied

- `border_rect` commands — thin lines look worse with AA (they become fuzzy). Border
  rects continue using mode 0.
- `glyph` commands — text already has its own anti-aliasing via the atlas (grayscale
  or subpixel). AA is not applied to glyph quads.
- `image_rect` — the image texture provides its own edge appearance; adding AA would
  introduce border artifacts.

## Module location

```
src/01/types.zig         — CircleCmd struct, aa_filled_rect / aa_filled_circle DrawCommand variants
src/09/types.zig         — buildDrawList emits aa_filled_rect (mode 5) for rect backgrounds, aa_filled_circle (mode 6) for circles
src/09/shaders/quad.vert — pass through fragUV for AA computation
src/09/shaders/quad.frag — mode 5: aa filled rect, mode 6: aa filled circle (with dFdx/dFdy)
docs/specs/09.types.zig  — spec mirror
docs/requirements/RD4_antialiased_filled_shapes.md
```

## Public API changes

```zig
// Module 01
pub const CircleCmd = struct {
    center: struct { x: f32, y: f32 },
    radius: f32,
    color: Color09,
};
// DrawCommand gains:
aa_filled_rect: FilledRect,
aa_filled_circle: CircleCmd,
```

## Behavioral contract

| Situation | Behavior |
|---|---|
| `filled_rect` with no rounding, mode 5 (AA) | All four edges have a 1-px smooth alpha transition → no visible stair-stepping |
| `filled_rect` with `radius > 0`, mode 5 (AA) | Rounded corners are smooth; straight edges have 1-px AA feather |
| `filled_rect` with mode 0 (non-AA) | Hard edges, as before — used for border_rect and internal geometry |
| `filled_circle`, mode 6 (AA) | Circular edge has 1-px AA feather; no polygon-faceted edges visible |
| AA rect placed at non-integer pixel position | `dFdx`/`dFdy` correctly compute subpixel edge distances |
| AA rect with `w < 2px` or `h < 2px` | Both edges' feather bands overlap in the middle; the rect appears semi-transparent. This is acceptable — thin rects should not use AA; the renderer falls back to mode 0 when `min(w, h) <= 2` |
| Theme change (light ↔ dark) | No change in AA behavior — anti-aliasing is color-independent |

## Non-goals (DO NOT implement — INV-5.4)

- **No configurable feather width** — always 1 pixel. No `aa-feather-{n}` class.
- **No MSAA (multi-sample anti-aliasing)** — fragment-shader AA only. Hardware MSAA
  requires multisample framebuffers and a different render-pass setup.
- **No anti-aliased text** — that's M13-03 (subpixel glyph rendering).
- **No anti-aliased borders** — `border_rect` rendered with mode 0. Anti-aliasing
  thin lines (1–2 px) produces fuzzy borders that look worse than aliased ones.
- **No anti-aliased rounded container backgrounds** — the container background uses
  the same `aa_filled_rect` mode; no separate AA mode for container backgrounds.
- **No anti-aliased shadow edges** — box shadows (R46) rendered with mode 0; AA on
  shadows is a future enhancement.
- **No coverage-based AA** — the fragment shader uses analytic distance-to-edge, not
  multi-sample coverage masks.

## Acceptance criteria

1. `zig build` passes; SPIR-V shaders recompile with mode 5 and mode 6.

2. Unit tests in `src/09/09_test.zig` cover:
   - `buildDrawList` emits `.aa_filled_rect` for a filled rectangle element (not `.filled_rect`).
   - `buildDrawList` emits `.filled_rect` for a `border_rect` (mode 0 preserved).
   - `buildDrawList` emits `.aa_filled_circle` for a circle element.
   - When rect width or height is <= 2 px, `buildDrawList` falls back to mode 0 (`.filled_rect`).

3. Visual: demo app screen shows an unrounded filled rect, a rounded filled rect
   (`rounded-lg`), and a filled circle side by side. All edges are visibly smooth
   (no stair-stepping) when viewed at 1× zoom.

4. Visual: compare the same shapes with hard edges (mode 0) vs anti-aliased (mode 5/6).
   The AA versions have smooth edges; the non-AA versions have visible jaggies.

5. No regression: border_rect borders, glyphs, and image_rect commands render unchanged.
