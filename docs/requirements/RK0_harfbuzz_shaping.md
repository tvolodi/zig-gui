# RK0 — M24-01: HarfBuzz shaping pipeline

> Roadmap item: M24-01
> Depends on: 02 (Font, GlyphAtlas, layoutParagraphEx), 04 (layout consumes advances)
> Blocked by ratification of `V2_constitution_amendment.md` (INV-1.3-v2 permits shaping;
> §2 approves HarfBuzz).
> Read `00_constitution.md` and `V2_ARCHITECTURE.md` §3 before this file.

## Purpose

Add a text-shaping stage powered by HarfBuzz so the framework can render scripts that require
contextual glyph selection, ligatures, and mark positioning (Arabic, Indic, and the
contextual behaviors of Latin/Cyrillic too). Shaping sits between line breaking and glyph
rasterization; the layout engine and renderer see the same positioned-glyph output they see
today, so INV-2.3 and the atlas model are unchanged.

## What to build

### Shaping stage (module 11)

```zig
pub const ShapedGlyph = struct {
    glyph_id: u32,      // font-internal id (NOT a codepoint)
    cluster: u32,       // byte offset into the source run this glyph belongs to
    x_advance: f32,
    x_offset: f32,
    y_offset: f32,
};

pub const ShapedRun = struct {
    glyphs: []const ShapedGlyph,
    font_id: u16,
    direction: Direction,   // ltr | rtl (from RK1)
    script: Script,
};

/// Shape one itemized run (single script, single direction, single font).
pub fn shapeRun(hb: *HbContext, font: *const Font, run: TextRun) ShapeError!ShapedRun;
```

HarfBuzz is wrapped via `@cImport`. One `hb_font_t` is created per loaded `Font`/`FontVariant`
and cached. `shapeRun` builds an `hb_buffer_t`, sets direction/script/language, calls
`hb_shape`, and copies glyph infos + positions into `ShapedGlyph`s.

### Atlas keying change (module 02)

`GlyphKey` migrates from `(codepoint, size, variant)` to `(glyph_id, size, variant, font_id)`
because shaping selects glyphs by font-internal id. Rasterization uses
`stbtt_GetGlyphBitmap` by index (already available — v1 fallback uses `FindGlyphIndex`). This
is a contained change: the atlas insert/lookup signatures gain `glyph_id`/`font_id` fields.

### Integration with line breaking

`layoutParagraphEx` is refactored so that, per line, it: itemizes the text into runs (RK1),
shapes each run (RK0), then positions the shaped advances into the existing line-box model.
The break-opportunity logic (v1) is preserved; shaping happens within a measured run.

## Module location

```
src/11/types.zig         — ShapedGlyph, ShapedRun, shapeRun, HbContext
src/11/harfbuzz.zig       — @cImport wrapper, hb_font cache
src/02/types.zig          — GlyphKey gains glyph_id + font_id; atlas insert/lookup updated
src/02/types.zig          — layoutParagraphEx routes through the shaping stage
deps/                     — vendored HarfBuzz (pinned version)
build.zig.zon             — HarfBuzz dependency entry
docs/specs/11.types.zig   — spec mirror
docs/requirements/RK0_harfbuzz_shaping.md
```

## Public API changes

```zig
// Module 11 (new): ShapedGlyph, ShapedRun, shapeRun, HbContext
// Module 02: GlyphKey gains glyph_id: u32, font_id: u16 (codepoint removed from the key)
//            GlyphAtlas.insert/lookup take the new key shape
```

## Behavioral contract

| Situation | Behavior |
|---|---|
| Latin text "office" with `fi` ligature in the font | Shaped to the ligature glyph; one glyph, cluster spans both bytes |
| Arabic word | Contextual initial/medial/final forms selected; marks positioned |
| Codepoint absent from primary font | Itemization assigns a fallback font (R64 chain); shaped per font |
| Same string, same font, repeated | `hb_font` cached; atlas glyphs cached by glyph_id |
| Plain ASCII | Shapes correctly; visually identical to v1 for non-contextual text |

## Non-goals (DO NOT implement — INV-5.4)

- **No bidi reordering here** — that is RK1; RK0 shapes a single-direction run.
- **No vertical writing modes**, no justification-by-kashida (INV-1.3-v2 bounds the scope).
- **No font-discovery / fontconfig** — the app ships its own fonts (amendment §2).
- **No custom OpenType feature UI** — default feature set; no per-call feature toggling beyond
  what shaping requires.
- **No replacement of stb_truetype** — stb still rasterizes; HarfBuzz only shapes.

## Acceptance criteria

1. `zig build` links HarfBuzz; module 11 acceptance test passes.
2. `shapeRun` on an Arabic test string produces contextual glyph forms (verified against a
   known expected glyph-id sequence for the bundled font).
3. `shapeRun` on "office" produces the `fi` ligature when the font has it; cluster values map
   each glyph back to correct byte offsets.
4. Atlas correctly caches and reuses glyphs keyed by `(glyph_id, size, variant, font_id)`.
5. Visual: ASCII-only demo screens render identically to v1 (no regression for Latin text).
6. A fallback-font codepoint (e.g. an emoji or extended symbol) still resolves via the R64
   chain through the new pipeline.
