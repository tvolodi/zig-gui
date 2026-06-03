# R64 — M6-05: Font fallback

> Roadmap item: M6-05  
> Depends on: module 02 (`Font`, `GlyphAtlas`, `layoutParagraph`), R60 (`FontFamily`, `FontVariant`)  
> Read `00_constitution.md` before this file.

## Purpose

When the primary font does not contain a glyph for a codepoint, try a registered fallback
font before emitting a replacement glyph (□ U+25A1 or similar). This is necessary for
emoji, symbols, or extended Unicode characters that the primary family (e.g. DejaVu Sans)
does not cover. The fallback chain is a small ordered list of `Font` pointers appended to
`FontFamily`. Fallback selection is performed in `layoutParagraph`, keeping the rest of the
rendering pipeline unchanged.

## What to build

### `FontFamily` fallback chain

Extend `FontFamily` (from R60, `src/app/font_family.zig`):

```zig
pub const FontFamily = struct {
    regular:   Font,
    bold:      ?Font,
    italic:    ?Font,
    /// Ordered list of fallback fonts. Tried in order when the primary face
    /// does not contain a codepoint. Max 4 fallbacks in v1.
    fallbacks: [4]?Font = .{null} ** 4,
    fallback_count: u8 = 0,
    gpa: std.mem.Allocator,

    /// Add a fallback font. `ttf` bytes are owned by the caller and must outlive the Family.
    /// Returns error.TooManyFallbacks if the 4-fallback limit is reached.
    pub fn addFallback(self: *FontFamily, ttf: []const u8) !void

    /// Return the best Font for `codepoint` starting from `primary`, then trying fallbacks.
    /// Returns null if no font in the chain covers the codepoint.
    pub fn fontForCodepoint(
        self: *const FontFamily,
        primary: *Font,
        codepoint: u21,
    ) ?*Font
};
```

`fontForCodepoint` checks whether a font covers a codepoint using stb_truetype's
`stbtt_FindGlyphIndex`: a return value of 0 means the glyph is absent.

```zig
pub fn fontForCodepoint(
    self: *const FontFamily,
    primary: *Font,
    codepoint: u21,
) ?*Font {
    if (fontHasGlyph(primary, codepoint)) return primary;
    for (self.fallbacks[0..self.fallback_count]) |maybe_fb| {
        const fb = maybe_fb orelse continue;
        if (fontHasGlyph(&fb, codepoint)) return &fb;
    }
    return null;
}

fn fontHasGlyph(font: *Font, codepoint: u21) bool {
    // Calls stbtt_FindGlyphIndex; returns true if index > 0.
    return font.glyphIndex(codepoint) != 0;
}
```

Add `glyphIndex` to `Font`:

```zig
pub const Font = struct {
    // ...existing fields and methods...

    /// Return the stb_truetype glyph index for `codepoint`, or 0 if absent.
    pub fn glyphIndex(self: *Font, codepoint: u21) i32
};
```

### Replacement glyph — `REPLACEMENT_CODEPOINT`

Define a constant in module 02:

```zig
/// Rendered when no font in the fallback chain covers a codepoint.
/// U+FFFD REPLACEMENT CHARACTER (widely supported in common fonts).
/// Falls back to U+25A1 (WHITE SQUARE) if U+FFFD is also absent.
pub const REPLACEMENT_CODEPOINT: u21 = 0xFFFD;
```

### `layoutParagraph` — fallback lookup per codepoint

In `layoutParagraph`, for each codepoint during the shaping pass, replace the direct
`font.rasterize(cp, px)` call with a fallback-aware version:

```zig
// Current (no fallback):
const render = try font.rasterize(gpa, cp, px);

// New (with fallback):
const active_font = family.fontForCodepoint(font, cp) orelse blk: {
    // No font covers this codepoint — use replacement character from primary.
    break :blk font;
};
const actual_cp = if (family.fontForCodepoint(font, cp) != null) cp else REPLACEMENT_CODEPOINT;
const render = try active_font.rasterize(gpa, actual_cp, px);
```

The `GlyphKey` uses the `actual_cp` (which may be `REPLACEMENT_CODEPOINT`), not the
original codepoint. This means all unsupported codepoints share one cached atlas entry
for the replacement glyph. This is correct: they all look like □.

**`layoutParagraph` gains a `family` parameter:**

```zig
pub fn layoutParagraph(
    gpa: std.mem.Allocator,
    font: *Font,
    atlas: *GlyphAtlas,
    str: []const u8,
    px: f32,
    max_width: f32,
    variant: FontVariant,
    family: ?*const FontFamily,  // NEW — null = no fallback (preserves old callers)
) FontError!Paragraph
```

When `family` is `null`, behavior is unchanged (the `font` argument is used unconditionally;
unsupported codepoints attempt rasterization and may return `error.GlyphNotFound`). This
preserves backward compatibility with existing tests that do not need fallback.

When `family` is non-null, the fallback chain is consulted per codepoint.

### `FontError` — new variant

When no font covers a codepoint and no replacement is available either, the error is logged
but does not propagate:

```zig
// In layoutParagraph, when replacement also fails:
// Log once: std.log.warn("no glyph for U+{X:04} — skipping", .{cp});
// Skip the glyph (advance by space_w); do not return an error.
```

The "skip silently" behavior means the output text has a gap where the unsupported glyph
would be. This is preferable to crashing or returning an error that aborts rendering.

### `GlyphKey` — fallback font identity

If a fallback font is used for a codepoint, its glyph must be cached under a key that
distinguishes it from the primary font's glyph for the same codepoint (which may be absent,
but future changes could add it). Extend `GlyphKey`:

```zig
pub const GlyphKey = struct {
    codepoint: u21,
    px:        u16,
    variant:   FontVariant = .regular,
    font_id:   u8 = 0,  // NEW: 0 = primary, 1–4 = fallback index + 1
};
```

`font_id = 0` is the primary font. When a codepoint is resolved to `fallbacks[i]`, use
`font_id = i + 1`.

This is a backward-compatible addition: existing `GlyphKey` construction sites pass
`font_id = 0` (the default).

### Callers — `measurePass` and `buildDrawList`

Both `measurePass` and `buildDrawList` call `layoutParagraph`. They pass `family =
&app.font_family` (from R60). After R64, all calls pass the `family` pointer; the null
compatibility path is used only in module-02 unit tests.

### Replacement font recommendation

The project's `testdata/` directory should include one fallback TTF with broad Unicode
coverage (e.g. Noto Sans or Unifont) to exercise the fallback path in integration tests.
This is a runtime asset, not a build dependency. Document in `HOW_TO_USE.md`.

### Behavioral contract

| Situation | Behavior |
|---|---|
| Codepoint present in primary | Primary font used; `font_id = 0` in key |
| Codepoint absent from primary, present in fallback[0] | Fallback[0] used; `font_id = 1` in key |
| Codepoint absent from all fonts | U+FFFD from primary used; if U+FFFD also absent, glyph skipped with log warning |
| `family = null` (unit tests) | Old behavior — direct `font.rasterize`; `GlyphNotFound` may be returned |
| Same codepoint at same size from two fonts | Two distinct atlas entries (different `font_id`) |

### Module location

```
src/app/font_family.zig    — FontFamily.fallbacks, addFallback, fontForCodepoint
src/02/types.zig           — Font.glyphIndex, REPLACEMENT_CODEPOINT, GlyphKey.font_id, layoutParagraph signature
docs/specs/02.types.zig    — Font.glyphIndex, GlyphKey.font_id, layoutParagraph signature
src/07/types.zig           — measurePass passes family to layoutParagraph
src/09/types.zig           — buildDrawList passes family to layoutParagraph
docs/requirements/R64_font_fallback.md
```

## Public API

New / changed in module 02:

```zig
pub const REPLACEMENT_CODEPOINT: u21 = 0xFFFD
// GlyphKey gains: font_id: u8 = 0
// Font gains: pub fn glyphIndex(self: *Font, codepoint: u21) i32
// layoutParagraph gains: family: ?*const FontFamily parameter
```

New in `FontFamily` (`font_family.zig`):

```zig
pub fn addFallback(self: *FontFamily, ttf: []const u8) !void
pub fn fontForCodepoint(self: *const FontFamily, primary: *Font, codepoint: u21) ?*Font
```

## Non-goals (DO NOT implement — INV-5.4)

- **No more than 4 fallback fonts** — the fixed array `[4]?Font` is the hard limit for v1.
- **No per-script fallback routing** (e.g. Cyrillic → font A, Greek → font B) — the chain
  is tried in order for every missing codepoint; no script-aware dispatch.
- **No GSUB / OpenType features** — fallback selection only; no ligatures or contextual
  substitution (INV-1.3).
- **No emoji color rendering** — COLR/SVG emoji are out of scope; fallback to grayscale
  bitmap if a fallback font has one, or to the replacement glyph.
- **No automatic fallback font download** — all fonts are local files loaded at startup
  (INV-5.6 no network dependencies).
- **No tofu-free guarantee** — if no font covers a codepoint and replacement also fails,
  the glyph is silently skipped (visible gap). This is acceptable under INV-1.3.

## Acceptance criteria

1. `zig build test-02` (font-dependent) passes. New tests:
   - `Font.glyphIndex('A')` returns non-zero for a standard Latin font.
   - `Font.glyphIndex(0x1F600)` (emoji) returns 0 for DejaVuSans (which lacks emoji).
   - `fontForCodepoint(primary, 'A')` returns `primary` (primary has 'A').
   - `fontForCodepoint(primary, 0x1F600)` with a fallback that has the emoji returns the
     fallback font pointer.
   - `fontForCodepoint` returns `null` when no font has the codepoint.
   - `layoutParagraph` with `family != null` on a string containing an unsupported codepoint
     produces a glyph for `REPLACEMENT_CODEPOINT` (or skips it with a log warning) without
     returning an error.

2. `GlyphKey.font_id` unit test: two entries with `font_id = 0` vs `font_id = 1` for the
   same codepoint/size/variant do not collide in the atlas hash map.

3. Integration: load a fallback font. Render a `<Text>` with a mix of Latin and a codepoint
   outside DejaVu's range. The Latin renders from the primary; the unusual codepoint renders
   from the fallback or shows a replacement glyph (no crash, no blank screen).

4. No regressions: all existing module-02 tests still pass (font_id defaults to 0).

5. Checklist fully ticked.

## Open questions

None. The 4-fallback limit is a deliberate simplification. If more fallbacks are needed, the
`[4]?Font` array can be increased to `[8]` in a one-line change; the algorithm is O(n) in
the fallback count and the cost per codepoint is negligible (one `stbtt_FindGlyphIndex` call
per font in the chain).
