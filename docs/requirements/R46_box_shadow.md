# R46 — M4-07: Box shadow

> Roadmap item: M4-07  
> Depends on: module 09 (renderer/buildDrawList)  
> Read `00_constitution.md` before this file.

## Purpose

Allow elements to display a single-level drop shadow rendered as a blurred rect drawn
behind the element. The blur is approximated by drawing 5–7 concentric `filled_rect`
commands with decreasing alpha — no GPU compute shader or framebuffer blitting is required.
Shadow parameters are stored on `ComputedStyle`. The Tailwind `shadow` / `shadow-md` /
`shadow-lg` utility classes enable them.

## What to build

### Shadow fields on `ComputedStyle`

Add to [05.types.zig](../specs/05.types.zig):

```zig
pub const ComputedStyle = struct {
    background:   Color  = transparent,
    text_color:   Color  = transparent,
    border_color: Color  = transparent,
    border_width: f32    = 0,
    radius:       f32    = 0,
    padding:      Insets = .{},
    gap:          f32    = 0,
    font_size:    f32    = 14,
    truncate:     bool   = false,
    opacity:      f32    = 1.0,
    shadow_blur:  f32    = 0,   // NEW: effective blur radius in pixels; 0 = no shadow
    shadow_offset_x: f32 = 0,   // NEW: horizontal shadow offset in pixels
    shadow_offset_y: f32 = 4,   // NEW: vertical shadow offset in pixels (positive = down)
    shadow_color: Color  = .{ .r = 0, .g = 0, .b = 0, .a = 64 },  // NEW: shadow color
};
```

`shadow_blur = 0` means no shadow is drawn (default — all existing elements unchanged).

### Tailwind class resolver update (module 06)

Map standard Tailwind shadow classes to shadow fields. Use these values (matching Tailwind
defaults):

| Class | `shadow_blur` | `shadow_offset_x` | `shadow_offset_y` | `shadow_color.a` |
|---|---|---|---|---|
| `shadow-sm` | 4 | 0 | 1 | 20 |
| `shadow` | 6 | 0 | 2 | 30 |
| `shadow-md` | 8 | 0 | 4 | 45 |
| `shadow-lg` | 16 | 0 | 8 | 50 |
| `shadow-xl` | 24 | 0 | 10 | 55 |
| `shadow-none` | 0 | 0 | 0 | 0 |

`shadow_color` RGB is always `{0, 0, 0}` (black) — color is not configurable via Tailwind
classes in v1.

### Soft-shadow approximation algorithm

A "blurred" shadow is approximated by drawing `N` concentric filled rects, each slightly
larger than the element rect and offset by `shadow_offset_x / shadow_offset_y`, with alpha
that decreases linearly from the center outward.

```zig
/// Emit N filled_rect commands that together approximate a blurred drop shadow.
/// The rects are drawn BEFORE the element's own background (painter's algorithm ensures
/// the shadow is behind the element).
/// `N = 5` for all blur levels in v1 (sufficient visual quality).
pub fn emitShadow(
    cmds: *std.ArrayListUnmanaged(DrawCommand),
    alloc: std.mem.Allocator,
    element_rect: Rect,
    style: ComputedStyle,
    effective_alpha: f32,   // from opacity accumulation (M4-06)
) error{OutOfMemory}!void {
    const N: comptime_int = 5;
    const blur = style.shadow_blur;
    const ox   = style.shadow_offset_x;
    const oy   = style.shadow_offset_y;

    var i: u32 = 0;
    while (i < N) : (i += 1) {
        // t goes from 0 (outermost, most transparent) to 1 (innermost, most opaque).
        const t = @as(f32, @floatFromInt(i + 1)) / @as(f32, N + 1);
        // Expand rect outward (less expansion for inner layers).
        const expand = blur * (1.0 - t);
        const shadow_rect = Rect{
            .x = element_rect.x + ox - expand,
            .y = element_rect.y + oy - expand,
            .w = element_rect.w + expand * 2,
            .h = element_rect.h + expand * 2,
        };
        // Alpha: outermost is most transparent, innermost is most opaque.
        const base_alpha = @as(f32, @floatFromInt(style.shadow_color.a));
        const layer_alpha: u8 = @intFromFloat(base_alpha * t * effective_alpha);

        try cmds.append(alloc, .{ .filled_rect = .{
            .rect   = shadow_rect,
            .color  = .{
                .r = style.shadow_color.r,
                .g = style.shadow_color.g,
                .b = style.shadow_color.b,
                .a = layer_alpha,
            },
            .radius = style.radius,  // match element's corner radius
        }});
    }
}
```

Shadow rects are emitted **before** the element's `filled_rect` (background) in
`buildDrawList`. Because the draw list uses painter's algorithm (earlier = further back),
the shadow renders behind the element.

### Integration in `buildDrawList`

In the per-element drawing section:

```zig
// NEW: Shadow (before background)
if (effective_style.shadow_blur > 0) {
    try emitShadow(&cmds, alloc, layout_rect, effective_style, current_alpha);
}

// Existing: Background
if (effective_style.background.a > 0) {
    try cmds.append(alloc, .{ .filled_rect = ... });
}
// ... border, text ...
```

### Interaction with opacity (M4-06)

The `effective_alpha` argument to `emitShadow` is the accumulated opacity from the DFS walk
(M4-06). Shadow alpha is multiplied by `effective_alpha` so that a semi-transparent card
also shows a proportionally faint shadow.

### Interaction with clipping (M4-03)

Shadow rects are emitted before the `set_scissor` / `restore_scissor` wrapping of their
container. If the element is inside a scrollview, its shadow rects are included inside the
scissor and are clipped along with the element. This is the correct behavior — shadows
should not bleed outside a scroll container's bounds.

### Interaction with the overlay layer (M4-02)

Overlay slot producers that want shadows must call `emitShadow` themselves. The serializer
only automatically emits shadows for elements in the normal-layer DFS walk.

### Token-driven shadow values (future)

For v1, shadow values are hardcoded in the Tailwind class resolver. A future M5 token
addition could add `shadow_sm/md/lg` token fields to `Tokens`. This spec does not require
that; hardcoded values in the class resolver are sufficient.

### Behavioral contract

| Situation | Behavior |
|---|---|
| `shadow_blur = 0` (default) | No shadow rects emitted |
| `shadow-md` on a card | 5 concentric rects behind the card, offset 4px down |
| Element with `opacity-50` and `shadow-md` | Shadow alpha halved |
| Element inside scrollview | Shadow clipped to scrollview bounds |
| `shadow-none` class | `shadow_blur = 0`; shadow rects suppressed |

### Module location

```
src/05/types.zig          — ComputedStyle shadow fields
docs/specs/05.types.zig   — ComputedStyle shadow fields
src/06/types.zig          — shadow-{sm,md,lg,xl,none} class mappings
src/09/types.zig          — emitShadow helper, buildDrawList changes
docs/specs/09.types.zig   — emitShadow signature
docs/requirements/R46_box_shadow.md
```

## Public API

New in module 05:

```zig
// ComputedStyle gains: shadow_blur, shadow_offset_x, shadow_offset_y, shadow_color
```

New in module 09:

```zig
pub fn emitShadow(
    cmds: *std.ArrayListUnmanaged(DrawCommand),
    alloc: std.mem.Allocator,
    element_rect: Rect,
    style: ComputedStyle,
    effective_alpha: f32,
) error{OutOfMemory}!void
```

## Non-goals (DO NOT implement — INV-5.4)

- **No GPU blur / Gaussian convolution** — approximation via concentric rects only.
  True Gaussian blur requires a separate render pass and framebuffer copy, which is
  post-v1.
- **No inset shadows** — `box-shadow: inset` is out of scope.
- **No multiple shadows per element** — only one shadow level (one set of concentric rects).
- **No `shadow-color` Tailwind utility** — shadow color is always black; the alpha only
  comes from the preset classes.
- **No spread radius** — only blur + offset; CSS `spread` is not modeled.
- **No shadow on text** — `text-shadow` is out of scope; only box-level shadow.
- **No animated shadow changes** — instantaneous; transitions are post-v1.

## Acceptance criteria

1. `zig build test-09-unit` passes. New CPU tests:
   - `emitShadow` with `shadow_blur = 0` does not append any commands.
   - `emitShadow` with `shadow_blur = 8` (shadow-md) appends exactly 5 `filled_rect`
     commands.
   - The 5 rects have strictly increasing `w` and `h` (outer rects are larger).
   - The innermost rect is closest to the element rect in position and size.
   - Shadow rect `y` values are offset by `shadow_offset_y`.
   - `effective_alpha = 0.5` halves all shadow alphas.
   - `buildDrawList` on an element with `shadow-md` emits shadow rects before the
     element's background rect.

2. Module-06 resolver test: class `"shadow-md"` sets `shadow_blur = 8`, `shadow_offset_y
   = 4`.

3. Integration: run the app with a `<Card class="shadow-md">`. Visually confirm a soft
   drop shadow below and behind the card.

4. No per-frame allocations beyond the draw-list slice growth.

5. Checklist fully ticked.

## Open questions

The approximation quality (N=5 layers) may look coarse for large `shadow_blur` values. If
the visual result is unsatisfactory at `shadow-xl` (blur=24), increasing N to 7 or 9 is a
one-line change. The algorithm is correct regardless of N; this is a tuning parameter.
