# R61 — M6-02: Mixed font sizes in one scene

> Roadmap item: M6-02  
> Depends on: module 02 (`GlyphKey`, `layoutParagraph`), module 07 (`Scene.measurePass`), module 05 (`Tokens`)  
> Read `00_constitution.md` before this file.

## Purpose

Text elements in the same scene can use different font sizes (`text-sm`, `text-base`,
`text-lg`). Currently `ComputedStyle.font_size` stores the size but the class resolver and
`measurePass` already read it — the glyph atlas and measurement are already per-size via
`GlyphKey.px`. This item closes the remaining gap: verifying the full path works correctly
end-to-end, adding the `GlyphKey.px` field to match `font_size` rounded to the nearest
integer, and ensuring the Tailwind size classes resolve to the correct token-driven pixel
sizes.

## What to build

### Verify: `GlyphKey.px` already keys per-size

`GlyphKey.px` is `u16` and is set from `@intFromFloat(px)` in `layoutParagraph`. Because
`Tokens` defines three sizes (`text_sm = 12`, `text_base = 14`, `text_lg = 18` by default),
glyphs rasterized at different sizes already get distinct cache keys. No change to
`GlyphKey` is needed. This item confirms the design and adds tests.

### Tailwind size classes — confirm resolver entries

The class resolver already maps `text-sm|base|lg` to `font_size` from tokens. This was part
of the M0 Tailwind subset (module 06 spec). The entries are present in `applyClass`. This
item adds acceptance tests and confirms the correct token lookup:

| Class | `ComputedStyle.font_size` | Example value |
|---|---|---|
| `text-sm` | `tokens.text_sm` | 12 px |
| `text-base` | `tokens.text_base` | 14 px |
| `text-lg` | `tokens.text_lg` | 18 px |

### Missing: `text-xs` and `text-xl`

Two common sizes are absent from the current token set and class resolver. Add them:

**Token additions** in [05.types.zig](../specs/05.types.zig):

```zig
pub const Tokens = struct {
    // ...existing fields...
    text_xs: f32,   // NEW — smaller than text_sm (e.g. 10 px)
    text_xl: f32,   // NEW — larger than text_lg  (e.g. 24 px)
};
```

Add to `Tokens.light` and `Tokens.dark`:

```zig
.text_xs = 10,
.text_xl = 24,
```

**Class resolver additions** in `applyClass`:

```zig
} else if (std.mem.eql(u8, cls, "text-xs")) {
    r.style.font_size = tokens.text_xs;
} else if (std.mem.eql(u8, cls, "text-xl")) {
    r.style.font_size = tokens.text_xl;
```

`text-2xl` and larger are post-v1.

### `measurePass` — per-element font size

`measurePass` already reads `styleOf(idx).font_size` and passes it to `layoutParagraph` as
`px`. This is already correct; no change needed. The acceptance test confirms it.

### Atlas key rounding

`GlyphKey.px` is `u16`. `font_size` is `f32`. The conversion `@intFromFloat(font_size)` used
in `layoutParagraph` truncates (e.g. `14.5 → 14`). For token-defined sizes (all integers),
this is exact. For inline-style sizes (`style:font-size="13.5"`), truncation may cause a
slight discrepancy between measured and rendered glyph size. This is acceptable for v1; exact
sub-pixel keys are post-v1. Document this behavior.

Add a rounding helper in module 02 to make the conversion explicit and consistent:

```zig
/// Convert a font size in pixels to the integer key used in GlyphKey.
/// Rounds to the nearest integer to minimize rasterization artifacts.
pub fn fontSizePx(size: f32) u16 {
    return @intCast(@as(u32, @intFromFloat(@round(size))));
}
```

Use `fontSizePx(px)` everywhere a `GlyphKey.px` is constructed in `layoutParagraph` (was
`@intFromFloat(px)`).

### `measurePass` sizing contract

The layout engine uses `LayoutNode.measured` to size leaf elements. After `measurePass`,
each text-bearing element has `measured = .{ .w = extent.w, .h = extent.h }` where the
extent was computed at the element's `font_size`. If two siblings have different sizes,
their `measured` heights differ, and the flex layout stacks/aligns them correctly by their
actual heights.

This is already the behavior; this item adds an acceptance test that verifies two `<Text>`
siblings with `text-sm` and `text-lg` produce different `measured.h` values after
`measurePass`.

### `GlyphAtlas.generation` on font-size change

When a new font size is first encountered, `layoutParagraph` rasterizes new glyphs and
inserts them into the atlas, incrementing `atlas.generation`. The GPU re-upload path (module
09) detects this via the generation counter. No changes needed; this item confirms the path
works by testing with a multi-size scene.

### Behavioral contract

| Situation | Behavior |
|---|---|
| `text-sm` class | `font_size = tokens.text_sm`; glyphs keyed at `fontSizePx(text_sm)` |
| `text-lg` class | `font_size = tokens.text_lg`; distinct glyph cache entries |
| Two siblings: `text-sm` and `text-lg` | Different `measured.h`; layout stacks/aligns correctly |
| `style:font-size="13.5"` | Rounded to `14` for atlas key; slight size discrepancy documented |
| Same codepoint at two sizes | Two distinct atlas entries; no overlap in packed rects |

### Module location

```
src/05/types.zig          — Tokens.text_xs, text_xl; Tokens.light/dark updated
docs/specs/05.types.zig   — Tokens changes
src/06/types.zig          — text-xs, text-xl class entries
src/02/types.zig          — fontSizePx helper; @round instead of @trunc in GlyphKey construction
docs/specs/02.types.zig   — fontSizePx signature
docs/requirements/R61_mixed_font_sizes.md
```

No changes to `measurePass`, `buildDrawList`, or `GlyphKey` structure.

## Public API

New in module 02:

```zig
pub fn fontSizePx(size: f32) u16
```

New in module 05:

```zig
// Tokens gains: text_xs: f32, text_xl: f32
```

## Non-goals (DO NOT implement — INV-5.4)

- **No `text-2xl` through `text-9xl`** — only the five sizes (xs, sm, base, lg, xl) are
  in v1.
- **No sub-pixel font rasterization** — integer pixel sizes only; fractional sizes are
  rounded.
- **No per-run font-size changes** (rich text / `<span>` inside `<Text>`) — one size per
  element.
- **No responsive size classes** (`sm:text-lg`) — no breakpoint system (INV-4.2).
- **No `line-height-*` classes** — line height is derived from `FontMetrics.ascent +
  descent + line_gap`; no separate override.
- **No `letter-spacing-*` classes** — kerning comes from the font only; no CSS-style letter
  spacing override.

## Acceptance criteria

1. `zig build test-06` passes. New tests:
   - `"text-xs"` → `font_size = tokens.text_xs` (= 10).
   - `"text-xl"` → `font_size = tokens.text_xl` (= 24).
   - `"text-sm"` → `font_size = tokens.text_sm` (= 12).
   - `"text-lg"` → `font_size = tokens.text_lg` (= 18).

2. `zig build test-02` passes. New test (font-dependent):
   - `layoutParagraph` called with `px = 12` and then `px = 18` on the same string:
     - Produces different `TextExtent.w` values (larger size = wider).
     - Atlas contains distinct entries for the same codepoint at both sizes
       (`lookup({codepoint, 12}) != lookup({codepoint, 18})`).
   - `fontSizePx(14.0) == 14`, `fontSizePx(13.5) == 14`, `fontSizePx(13.4) == 13`.

3. `zig build test-scene` passes. New test:
   - Two `<Text>` siblings with `text-sm` and `text-lg`. After `measurePass`, the
     `text-lg` element has a larger `measured.h` than `text-sm`.
   - After `solve`, the flex container correctly sizes to accommodate both.

4. No atlas overlap between glyphs rasterized at different font sizes.

5. Checklist fully ticked.

## Open questions

None. The `GlyphKey.px` field already provides per-size isolation. The rounding convention
(`@round` vs `@trunc`) is a minor implementation detail; `@round` is chosen for consistency
with how pixel sizes are typically displayed.
