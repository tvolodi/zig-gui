# R44 — M4-05: Text truncation with ellipsis

> Roadmap item: M4-05  
> Depends on: module 02 (GlyphAtlas, layoutParagraph), module 09 (buildDrawList)  
> Read `00_constitution.md` before this file.

## Purpose

When a text element's content is wider than its container, replace the trailing glyphs that
overflow with an ellipsis character ("…", U+2026). Truncation happens in the CPU serializer
(`buildDrawList`); no GPU changes are needed. The feature is opt-in per element via a
`truncate: bool` flag on `ComputedStyle`. The Tailwind class `truncate` enables it (resolved
by the module-06 class resolver).

## What to build

### `truncate` flag on `ComputedStyle`

Add to [05.types.zig](../specs/05.types.zig):

```zig
pub const ComputedStyle = struct {
    background:   Color   = transparent,
    text_color:   Color   = transparent,
    border_color: Color   = transparent,
    border_width: f32     = 0,
    radius:       f32     = 0,
    padding:      Insets  = .{},
    gap:          f32     = 0,
    font_size:    f32     = 14,
    truncate:     bool    = false,  // NEW
};
```

Default `false` — existing behavior is unchanged for all elements that do not set this flag.

### Tailwind class resolver update (module 06)

In `src/06/types.zig` (or wherever the class resolver maps class names to style fields), add:

```zig
// In the class-to-style mapping table:
// "truncate" → style.truncate = true
```

The `truncate` class sets only the `truncate` flag; it does not set `overflow: hidden` on the
layout node (text clipping is handled purely in the serializer by skipping glyph commands,
not by the GPU scissor). The two mechanisms are independent.

### Ellipsis measurement

The ellipsis character "…" must be measured once per font size and cached. Add to
`GlyphAtlas` (module 02):

```zig
pub const EllipsisMetrics = struct {
    advance: f32,       // total pixel width of "…"
    glyph_id: u16,      // atlas cell for the "…" glyph (single codepoint U+2026)
};

pub const GlyphAtlas = struct {
    // ...existing fields...

    /// Cached ellipsis metrics per font size (keyed by font_size rounded to nearest integer).
    /// Populated lazily on first use. Stored in a small fixed-size array (max 8 distinct
    /// font sizes for v1; the Tokens type defines only text_sm/text_base/text_lg = 3 sizes).
    ellipsis_cache: [8]?struct { font_size: u32, metrics: EllipsisMetrics } = [_]?struct{...}{null} ** 8,

    /// Return the ellipsis metrics for `font_size`, rasterizing "…" into the atlas if not
    /// already present. May increment `generation` if a new glyph is added.
    pub fn ellipsisMetrics(
        self: *GlyphAtlas,
        font: *Font,
        font_size: f32,
    ) error{OutOfMemory}!EllipsisMetrics
};
```

The ellipsis is a single codepoint (U+2026). If the font does not have U+2026, fall back to
three ASCII period characters "..." rendered as three separate glyphs — measure their combined
advance instead.

### Serializer changes in `buildDrawList`

In `src/09/types.zig` `buildDrawList`, in the text-emission path:

```zig
// Existing path (simplified):
// for each glyph in layoutParagraph(...):
//     emit GlyphCmd if glyph.x + glyph.w <= element_rect.x + element_rect.w

// NEW truncation path (only when effective_style.truncate == true):
if (effective_style.truncate) {
    const em = try atlas.ellipsisMetrics(font, effective_style.font_size);
    const available_w = element_rect.w - em.advance;  // reserve room for ellipsis

    var truncated = false;
    for (glyphs) |g| {
        if (g.dst.x + g.dst.w > element_rect.x + available_w) {
            // This glyph would overflow the reserved zone; emit ellipsis and stop.
            truncated = true;
            break;
        }
        try cmds.append(alloc, .{ .glyph = .{
            .dst   = g.dst,
            .uv    = g.uv,
            .color = effective_style.text_color,
        }});
    }

    if (truncated) {
        // Emit the ellipsis glyph at the position where we stopped.
        const ellipsis_x = last_glyph_x_end;  // track x_end of last emitted glyph
        try cmds.append(alloc, .{ .glyph = .{
            .dst   = .{ .x = ellipsis_x, .y = element_rect.y + baseline_offset,
                        .w = em.advance, .h = effective_style.font_size },
            .uv    = em_uv_rect,  // from atlas cell for "…"
            .color = effective_style.text_color,
        }});
    }
} else {
    // Existing overflow handling: skip glyphs beyond element_rect.x + element_rect.w.
    for (glyphs) |g| {
        if (g.dst.x + g.dst.w > element_rect.x + element_rect.w) continue;
        try cmds.append(alloc, .{ .glyph = ... });
    }
}
```

`buildDrawList` must have access to `Font` to call `ellipsisMetrics`. Add a `font: *Font`
parameter to `buildDrawList`:

```zig
pub fn buildDrawList(
    alloc: std.mem.Allocator,
    scene: *Scene,
    glyph_atlas: *GlyphAtlas,
    image_atlas: *const ImageAtlas,
    font: *Font,
    tokens: Tokens,
) error{OutOfMemory}![]DrawCommand
```

(This parameter was not in the original module 09 spec. It is required because ellipsis
measurement needs the font; surface this change to the human if it conflicts with any
existing implementation.)

### Behavioral contract

| Situation | Behavior |
|---|---|
| `truncate = false` (default) | Glyphs that exceed the rect are skipped (existing behavior) |
| `truncate = true`, text fits | All glyphs emitted, no ellipsis |
| `truncate = true`, text overflows | Trailing glyphs cut; ellipsis appended at cutoff position |
| `truncate = true`, container too narrow for even ellipsis | Only ellipsis emitted (if even that fits); otherwise nothing |
| Multi-line text with `truncate = true` | Truncation applies to the first line only; multi-line layout is post-v1 (M6-04) |

### Tailwind markup usage

```html
<Text class="truncate w-48">Some long text that will be clipped…</Text>
```

The `w-48` class sets a fixed width. Without a constrained width, layout may give the
element unlimited space and truncation never triggers.

### Module location

```
src/05/types.zig          — ComputedStyle.truncate field added
docs/specs/05.types.zig   — ComputedStyle.truncate field
src/06/types.zig          — "truncate" Tailwind class mapped to ComputedStyle.truncate
src/02/types.zig          — GlyphAtlas.ellipsisMetrics, EllipsisMetrics type
docs/specs/02.types.zig   — EllipsisMetrics, ellipsisMetrics added
src/09/types.zig          — buildDrawList truncation logic, font parameter added
docs/specs/09.types.zig   — buildDrawList signature update (font parameter)
docs/requirements/R44_text_truncation_ellipsis.md
```

## Public API

New in module 05:

```zig
// ComputedStyle gains: truncate: bool = false
```

New in module 02:

```zig
pub const EllipsisMetrics = struct { advance: f32, glyph_id: u16 }
// GlyphAtlas gains: pub fn ellipsisMetrics(self, font, font_size) !EllipsisMetrics
```

New in module 09:

```zig
// buildDrawList signature: adds font: *Font parameter
```

## Non-goals (DO NOT implement — INV-5.4)

- **No `text-overflow: clip`** — there is no separate clip mode; the existing glyph-skip
  behavior continues to serve as implicit clipping when `truncate = false`.
- **No multi-line truncation** — only the first/only line is truncated; true multi-line
  support (M6-04) is post-v1.
- **No custom ellipsis string** — always "…" (U+2026) or fallback "..."; no configurable
  suffix.
- **No right-to-left truncation** — ellipsis always at the trailing (right) end of the
  line (INV-1.3 Latin/Cyrillic only, LTR only).
- **No ellipsis in non-text elements** — truncation applies only to elements with text
  content (`textOf(idx) != null`); layout-only elements are unaffected.
- **No `white-space: nowrap`** — line-breaking behavior is controlled by module 02's
  `layoutParagraph`; truncation is a post-layout rendering decision.

## Acceptance criteria

1. `zig build test-09-unit` passes. New CPU tests:
   - `buildDrawList` on a text element with `truncate = false` and overflowing text emits
     glyph commands only for glyphs that fit (existing overflow behavior, now explicitly
     tested).
   - `buildDrawList` on a text element with `truncate = true` and overflowing text emits
     fewer glyph commands followed by exactly one glyph command for the ellipsis.
   - `buildDrawList` on a text element with `truncate = true` where all text fits emits all
     glyph commands with no ellipsis.
   - The ellipsis glyph command's `dst.x` is <= `element_rect.x + element_rect.w`.

2. `GlyphAtlas.ellipsisMetrics` returns consistent metrics for the same font size (cached —
   no re-rasterization on second call; `generation` unchanged).

3. Module-06 class resolver test: parsing class `"truncate"` sets
   `ComputedStyle.truncate = true`.

4. Integration: run the app with a `<Text class="truncate w-32">` element containing a
   long string. Visually confirm the ellipsis appears at the right edge.

5. No per-frame allocations in the truncation path beyond the existing draw-list slice.

6. Checklist fully ticked.

## Open questions

One: the module 09 spec does not include a `Font` parameter on `buildDrawList`. This is
required by ellipsis measurement. If an existing partial implementation of `buildDrawList`
has no `Font` access, surface this to the human before implementing — do not silently
diverge from the types.zig contract (INV-5.1).
