# R45 — M4-06: Opacity

> Roadmap item: M4-06  
> Depends on: module 09 (renderer/buildDrawList)  
> Read `00_constitution.md` before this file.

## Purpose

Allow any element to be rendered at less than full opacity by multiplying all draw commands
in that element's subtree by an alpha factor at serialization time. The opacity value is
stored on `ComputedStyle`. The Tailwind `opacity-{n}` classes (e.g. `opacity-50`,
`opacity-0`, `opacity-100`) set it. No GPU changes are required — opacity is implemented by
pre-multiplying the alpha channel of every `Color` in the draw commands emitted for the
element and its children.

## What to build

### `opacity` field on `ComputedStyle`

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
    opacity:      f32    = 1.0,  // NEW: 0.0 = fully transparent, 1.0 = fully opaque
};
```

Valid range is `[0.0, 1.0]`. Values outside this range are clamped at resolve time (module 06
resolver). Default `1.0` means no change to existing behavior.

### Tailwind class resolver update (module 06)

Map the `opacity-{n}` family to `ComputedStyle.opacity`. The values in the Tailwind
standard set:

| Class | `opacity` value |
|---|---|
| `opacity-0` | 0.0 |
| `opacity-25` | 0.25 |
| `opacity-50` | 0.5 |
| `opacity-75` | 0.75 |
| `opacity-100` | 1.0 |

Only these five values are supported in v1. Unknown `opacity-{n}` variants are ignored
(no-op, style unchanged).

### Alpha multiplication helper

Add a pure helper to `src/09/types.zig`:

```zig
/// Multiply the alpha channel of `c` by `factor` (clamped to [0, 1]).
/// The RGB channels are unchanged (non-premultiplied alpha model).
pub fn applyOpacity(c: Color, factor: f32) Color {
    const a = @as(f32, @floatFromInt(c.a)) * std.math.clamp(factor, 0.0, 1.0);
    return .{ .r = c.r, .g = c.g, .b = c.b, .a = @intFromFloat(a) };
}
```

### Serializer changes in `buildDrawList`

Pass an `alpha: f32` accumulator through the DFS walk. At each element, multiply the
current `alpha` by `effective_style.opacity`. Apply the resulting alpha to every `Color`
value in all draw commands emitted for that element.

```zig
// DFS walk — simplified pseudo-code:
fn visitElement(idx: u32, alpha: f32, ...) !void {
    const style = resolveStyle(scene.styleOf(idx).*, overrides, pseudo);
    const effective_alpha = alpha * style.opacity;

    // Background
    if (style.background.a > 0) {
        try cmds.append(.{ .filled_rect = .{
            .rect   = layout_rect,
            .color  = applyOpacity(style.background, effective_alpha),
            .radius = style.radius,
        }});
    }

    // Border
    if (style.border_width > 0) {
        try cmds.append(.{ .border_rect = .{
            .rect   = layout_rect,
            .color  = applyOpacity(style.border_color, effective_alpha),
            .width  = style.border_width,
            .radius = style.radius,
        }});
    }

    // Text glyphs
    for (glyphs) |g| {
        try cmds.append(.{ .glyph = .{
            .dst   = g.dst,
            .uv    = g.uv,
            .color = applyOpacity(style.text_color, effective_alpha),
        }});
    }

    // Recurse into children with effective_alpha
    for (children(idx)) |child_idx| {
        try visitElement(child_idx, effective_alpha, ...);
    }
}

// Top-level call:
try visitElement(root_idx, 1.0, ...);
```

Opacity is **inherited** through the subtree: a parent with `opacity = 0.5` and a child with
`opacity = 0.5` produces an effective `0.25` for the child's commands. This matches browser
behavior and requires no special handling — multiplication through the DFS walk is
sufficient.

### Behavioral contract

| Situation | Behavior |
|---|---|
| `opacity = 1.0` (default) | No change; `applyOpacity` returns `c` unchanged |
| `opacity = 0.0` | All colors have `a = 0`; element is invisible but still occupies layout space |
| `opacity = 0.5` on parent, `opacity = 1.0` on child | Child is rendered at effective `0.5` |
| `opacity = 0.5` on parent, `opacity = 0.5` on child | Child is rendered at effective `0.25` |
| Element with `opacity = 0.0` | Still receives input events (opacity is visual-only; M3-02 hit-testing is unchanged) |

### Interaction with pseudo-state styling (M4-01)

`opacity` is not part of `PseudoOverride` — pseudo-state overrides do not change opacity.
If a disabled element needs a dimmed appearance, the `disabled.text_color` and
`disabled.background` overrides with muted token colors provide visual dimming without
touching `opacity`.

### Interaction with the overlay layer (M4-02)

Overlay slots (`OverlayLayer`) build their own `[]DrawCommand` slices. The `buildDrawList`
alpha-accumulation walk does not apply to overlay commands. Overlay producers are responsible
for applying opacity to their own draw commands if needed.

### Module location

```
src/05/types.zig          — ComputedStyle.opacity field
docs/specs/05.types.zig   — ComputedStyle.opacity field
src/06/types.zig          — opacity-{n} Tailwind classes
src/09/types.zig          — applyOpacity helper, buildDrawList alpha accumulator
docs/specs/09.types.zig   — applyOpacity signature
docs/requirements/R45_opacity.md
```

## Public API

New in module 05:

```zig
// ComputedStyle gains: opacity: f32 = 1.0
```

New in module 09:

```zig
pub fn applyOpacity(c: Color, factor: f32) Color
```

## Non-goals (DO NOT implement — INV-5.4)

- **No GPU-composited layers** — opacity is implemented by pre-multiplying alpha in the
  CPU serializer; there is no off-screen render target for the opacity group. This means
  overlapping sibling elements with `opacity < 1` will show through each other individually
  rather than compositing as a group. Group opacity is post-v1.
- **No `visibility: hidden`** — `opacity-0` is the v1 way to make an element invisible
  while retaining layout space.
- **No `display: none`** — hiding an element from layout is out of scope for M4-06
  (covered separately in M5-03 conditional rendering).
- **No `opacity-{n}` for n outside {0, 25, 50, 75, 100}** — only the five standard
  Tailwind steps.
- **No opacity animation** — instantaneous; no transition support (post-v1).
- **No opacity on scrollbar draw commands** — scrollbar rendering (M3-06) does not
  propagate the parent scroll container's opacity to the scrollbar overlay rects.

## Acceptance criteria

1. `zig build test-09-unit` passes. New CPU tests:
   - `applyOpacity(Color{255, 0, 0, 255}, 0.5)` returns `Color{255, 0, 0, 127}` (±1 rounding).
   - `applyOpacity(Color{255, 0, 0, 255}, 0.0)` returns `Color{255, 0, 0, 0}`.
   - `applyOpacity(Color{255, 0, 0, 255}, 1.0)` returns `Color{255, 0, 0, 255}`.
   - `buildDrawList` with an element at `opacity = 0.5` emits draw commands whose colors
     have `a ≈ original_a * 0.5`.
   - Child element inside a `0.5`-opacity parent, itself at `0.5` opacity, produces `a ≈
     original_a * 0.25` in draw commands.
   - `opacity = 0.0` element produces draw commands with `a == 0` (all invisible).

2. Module-06 resolver test: class `"opacity-50"` sets `ComputedStyle.opacity = 0.5`.

3. Integration: run the app with a `<Card class="opacity-50">` wrapping a button. Visually
   confirm the card and its contents render at half opacity.

4. No per-frame allocations in `applyOpacity` or the alpha-accumulation path.

5. Checklist fully ticked.

## Open questions

None. CPU alpha pre-multiplication is the simplest correct approach for v1. The group-opacity
compositing limitation is a known trade-off and is explicitly post-v1.
