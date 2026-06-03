# R60 — M6-01: Bold and italic font variants

> Roadmap item: M6-01  
> Depends on: module 02 (`Font`, `GlyphAtlas`, `layoutParagraph`), module 07 (`Scene.measurePass`), module 09 (`buildDrawList`)  
> Read `00_constitution.md` before this file.

## Purpose

Allow any `<Text>` element (or text-bearing widget) to render in bold and/or italic by
loading separate font files for those variants and switching the active `Font` pointer during
`measurePass` and `buildDrawList`. Style is set via Tailwind classes `font-bold` and
`font-italic`. The font family (regular + bold + italic) is loaded once at app startup and
stored on `App`.

## What to build

### `FontFamily` — three `Font` slots

Add `src/app/font_family.zig`:

```zig
pub const FontFamily = struct {
    regular: Font,
    bold:    ?Font,   // null if no bold face was loaded
    italic:  ?Font,   // null if no italic face was loaded
    gpa:     std.mem.Allocator,

    /// Load fonts from byte slices. `bold_ttf` and `italic_ttf` may be null.
    pub fn init(
        gpa: std.mem.Allocator,
        regular_ttf: []const u8,
        bold_ttf:    ?[]const u8,
        italic_ttf:  ?[]const u8,
    ) FontError!FontFamily

    pub fn deinit(self: *FontFamily) void

    /// Return the best matching Font for the given style flags.
    /// Falls back to regular if the requested variant is not loaded.
    pub fn face(self: *const FontFamily, bold: bool, italic: bool) *Font
};
```

`face` priority: bold+italic requested → try bold (no bold+italic face in v1), then regular.
Italic only → try italic, then regular. Bold only → try bold, then regular. Neither → regular.

`App` gains `font_family: FontFamily` replacing the single `font: Font` field. All existing
references to `app.font` in `measurePass` and `buildDrawList` are updated to call
`app.font_family.face(false, false)` (regular, preserving current behavior).

### `ComputedStyle` font variant flags

Add to [05.types.zig](../specs/05.types.zig):

```zig
pub const ComputedStyle = struct {
    // ...existing fields...
    font_bold:   bool = false,  // NEW
    font_italic: bool = false,  // NEW
};
```

### Tailwind class resolver update (module 06)

```zig
} else if (std.mem.eql(u8, cls, "font-bold")) {
    r.style.font_bold = true;
} else if (std.mem.eql(u8, cls, "font-normal")) {
    r.style.font_bold = false;
} else if (std.mem.eql(u8, cls, "font-italic") or std.mem.eql(u8, cls, "italic")) {
    r.style.font_italic = true;
} else if (std.mem.eql(u8, cls, "not-italic")) {
    r.style.font_italic = false;
```

### `measurePass` — use per-element font face

In `Scene.measurePass`, instead of receiving a single `*Font`, receive a `*const FontFamily`:

```zig
// Updated signature (breaking change — update all callers):
pub fn measurePass(
    self: *Scene,
    family: *const FontFamily,
    atlas: *GlyphAtlas,
) FontError!void
```

For each text-bearing element, select the face before calling `layoutParagraph`:

```zig
for each text-bearing element at idx:
    const style = self.styleOf(idx).*;
    const font = family.face(style.font_bold, style.font_italic);
    const para = try layoutParagraph(gpa, font, atlas, text, style.font_size, max_w);
    self.elements.layout.items[idx].measured = .{ .w = para.extent.w, .h = para.extent.h };
```

### `buildDrawList` — use per-element font face for ellipsis measurement (R44)

`buildDrawList` already gains a `font: *Font` parameter from R44 (text truncation). Update
it to receive a `*const FontFamily` instead and select the face per element:

```zig
pub fn buildDrawList(
    alloc: std.mem.Allocator,
    scene: *Scene,
    glyph_atlas: *GlyphAtlas,
    image_atlas: *const ImageAtlas,
    family: *const FontFamily,   // was: font: *Font
    tokens: Tokens,
) error{OutOfMemory}![]DrawCommand
```

For each text-bearing element: `const font = family.face(style.font_bold, style.font_italic)`.

### `GlyphKey` — font variant in the cache key

`GlyphKey` currently keys on `{ codepoint: u21, px: u16 }`. With multiple faces, the same
codepoint at the same size would produce different bitmaps for regular vs bold. Add a variant
discriminant:

```zig
pub const FontVariant = enum(u8) { regular, bold, italic };  // NEW in 02.types.zig

pub const GlyphKey = struct {
    codepoint: u21,
    px:        u16,
    variant:   FontVariant = .regular,  // NEW
};
```

All existing `GlyphKey` construction sites pass `variant = .regular` (the default). Bold
elements pass `variant = .bold`; italic pass `variant = .italic`.

The atlas uses `GlyphKey` as the hash map key, so this is a purely additive change — no
existing cached glyphs are invalidated (they have the default `.regular` variant).

### `layoutParagraph` — variant passthrough

`layoutParagraph` calls `atlas.insert(key, ...)` using the `GlyphKey`. The `key.variant`
field must match the face being used:

```zig
// Inside layoutParagraph, when building the GlyphKey:
const variant: FontVariant = if (is_bold) .bold else if (is_italic) .italic else .regular;
const key = GlyphKey{ .codepoint = cp, .px = @intFromFloat(px), .variant = variant };
```

Since `layoutParagraph` receives a specific `*Font` (already resolved via `family.face`),
it does not need to know about `FontFamily` — the `variant` must be passed as a parameter:

```zig
// Updated signature:
pub fn layoutParagraph(
    gpa: std.mem.Allocator,
    font: *Font,
    atlas: *GlyphAtlas,
    str: []const u8,
    px: f32,
    max_width: f32,
    variant: FontVariant,  // NEW — used to key the atlas cache
) FontError!Paragraph
```

All existing callers pass `variant = .regular`.

### Fallback behavior when variant not loaded

If `font_bold = true` but `FontFamily.bold = null`, `family.face(.bold)` returns
`FontFamily.regular`. The `variant` passed to `layoutParagraph` is still `.bold` so the
glyph cache key is distinct — but the pixels come from the regular face. This means "bold"
text renders as regular weight when no bold face is available. This is the defined fallback
behavior: no crash, correct cache key, visually graceful degradation.

### Markup usage

```html
<Text class="font-bold text-lg">Header text</Text>
<Text class="font-italic text-muted">Subtitle</Text>
<Text class="font-bold font-italic">Bold italic (renders as bold fallback in v1)</Text>
```

### Behavioral contract

| Situation | Behavior |
|---|---|
| `font_bold = false, font_italic = false` | Regular face; glyph key variant = `.regular` |
| `font_bold = true`, bold face loaded | Bold face used; glyph key variant = `.bold` |
| `font_bold = true`, bold face NOT loaded | Regular face used; glyph key variant = `.bold` (distinct cache entry, same pixels) |
| `font_italic = true`, italic face loaded | Italic face used; glyph key variant = `.italic` |
| `font-normal` class | `font_bold = false` |
| `not-italic` class | `font_italic = false` |

### Module location

```
src/app/font_family.zig    — FontFamily struct
src/02/types.zig           — FontVariant enum, GlyphKey.variant field, layoutParagraph signature update
docs/specs/02.types.zig    — FontVariant, GlyphKey change, layoutParagraph signature update
src/05/types.zig           — ComputedStyle.font_bold, font_italic fields
docs/specs/05.types.zig    — ComputedStyle changes
src/06/types.zig           — font-bold, font-italic class entries
src/07/types.zig           — measurePass signature update
docs/specs/07.types.zig    — measurePass signature update
src/09/types.zig           — buildDrawList font param change
docs/specs/09.types.zig    — buildDrawList signature update
src/app/app.zig            — FontFamily field, init/deinit, measurePass/buildDrawList call-site updates
docs/requirements/R60_bold_italic_variants.md
```

## Public API

New in module 02:

```zig
pub const FontVariant = enum(u8) { regular, bold, italic }
// GlyphKey gains: variant: FontVariant = .regular
// layoutParagraph gains: variant: FontVariant parameter
```

New in module 05:

```zig
// ComputedStyle gains: font_bold: bool = false, font_italic: bool = false
```

New (`font_family.zig`):

```zig
pub const FontFamily = struct { regular: Font, bold: ?Font, italic: ?Font, ... }
// pub fn init, deinit, face
```

Updated signatures (callers must update):

```zig
// measurePass: font: *Font → family: *const FontFamily
// buildDrawList: font: *Font → family: *const FontFamily
// layoutParagraph: gains variant: FontVariant
```

## Non-goals (DO NOT implement — INV-5.4)

- **No bold+italic combined face** — only three faces: regular, bold, italic. Bold-italic
  falls back to bold.
- **No synthetic bold** (stroke widening) — if no bold face is loaded, regular is used.
  No algorithmic weight emulation.
- **No synthetic italic** (shear transform) — same; regular if no italic face.
- **No per-run mixed styles** (rich text) — one style per element; mixed bold/regular in
  one `<Text>` is M6-04 (multi-line textarea), which is also v1 non-goal until further
  spec'd.
- **No `font-weight: 600/700/800`** numeric weights — only `font-bold` (boolean toggle).
- **No `font-semibold` / `font-extrabold`** Tailwind classes — only `font-bold` and
  `font-normal`.
- **No variable fonts** — three static TTF files only.

## Acceptance criteria

1. `zig build test-02` (and the acceptance test with a font present) passes. New font tests:
   - `layoutParagraph` called with the same string at the same size but with `variant =
     .bold` vs `variant = .regular` produces different cache keys in the atlas.
   - When bold face is `null`, `family.face(true, false)` returns the regular font pointer.

2. `zig build test-06` passes. New resolver tests:
   - `"font-bold"` → `style.font_bold = true`.
   - `"font-italic"` → `style.font_italic = true`.
   - `"font-normal"` after `"font-bold"` → `style.font_bold = false`.

3. Integration: load a real bold face (e.g. `DejaVuSans-Bold.ttf`). Render `<Text
   class="font-bold">Bold text</Text>` alongside `<Text>Normal text</Text>`. Bold text
   visually appears heavier than normal text.

4. When bold TTF is absent, bold-class text renders as regular weight (no crash, no blank
   glyph).

5. All callers of `measurePass` and `buildDrawList` updated to pass `FontFamily`; no
   compilation errors.

6. Checklist fully ticked.

## Open questions

One: `layoutParagraph` signature adds `variant: FontVariant`. This is a breaking change to
the module 02 contract (`docs/specs/02.types.zig`). Before implementing, confirm with the
human that the types.zig contract may be updated. Surface the conflict per INV-5.1 rather
than silently diverging.
