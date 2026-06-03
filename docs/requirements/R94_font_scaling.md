# R94 — M9-05: Accessibility — font scaling

> Roadmap item: M9-05  
> Depends on: module 05 (theme), module 06 (class resolver)  
> Read `00_constitution.md` before this file.

## Purpose

Add a global font-size multiplier that scales every font size in the `Tokens` type scale
(`text_xs` through `text_xl`) without changing the palette or border/spacing tokens. The
multiplier is applied once when building or rebuilding the token set, not at paint time.

An author wires an accessibility setting:

```zig
app.setFontScale(1.5);   // 150% — all text is 50% larger
app.setFontScale(1.0);   // reset to 100%
```

---

## Motivation

Users with visual impairments need larger text. Without a global multiplier, every font size
is baked into the token set at startup and cannot be changed without a full restart. This
item makes font size accessible without requiring the application author to plumb a scale
factor through every widget.

---

## What to build

### 1. `Tokens.scaled` — a new method on `Tokens`

```zig
/// Return a copy of the tokens with all five type-scale sizes multiplied by `factor`.
/// factor = 1.0 → no change. factor = 1.5 → 50% larger.
/// All other tokens (colors, spacing, radii) are unaffected.
/// The result is clamped: each size is at least 6 px and at most 96 px.
pub fn scaled(self: Tokens, factor: f32) Tokens {
    var result = self;
    const clamp = std.math.clamp;
    result.text_xs   = clamp(self.text_xs   * factor, 6, 96);
    result.text_sm   = clamp(self.text_sm   * factor, 6, 96);
    result.text_base = clamp(self.text_base * factor, 6, 96);
    result.text_lg   = clamp(self.text_lg   * factor, 6, 96);
    result.text_xl   = clamp(self.text_xl   * factor, 6, 96);
    return result;
}
```

`Tokens.scaled` is a pure function — no side effects, no allocation.

### 2. `App.setFontScale`

```zig
pub fn setFontScale(self: *AppInner, factor: f32) void
```

Steps:
1. Clamp `factor` to `[0.5, 4.0]`. Values outside this range are silently clamped.
   Rationale: 50% is the practical minimum (legibility floor); 400% is the practical maximum
   (beyond that layout collapses). Clamping in `setFontScale` is sufficient — `Tokens.scaled`
   also clamps individual sizes but has a wider range.
2. Store the factor: `self._font_scale = factor`.
3. Rebuild the token set: `self.tokens = Theme.build(self._current_palette, self._current_mode).tokens.scaled(factor)`.
4. Call `self.scene.rebuildStyles(self.tokens)` — same path as the theme live-swap (R93).
5. Call `self.scene.elements.markAllDirty()`.

`AppInner` gains one new field:

```zig
_font_scale: f32 = 1.0,
```

`setFontScale(1.0)` is a no-op in effect but still rebuilds styles (identical to calling
`setTheme` with the same theme — idempotent but not truly a no-op).

### 3. `App.getFontScale`

```zig
pub fn getFontScale(self: *const AppInner) f32
```

Returns `self._font_scale`. Provided for UI that wants to display the current scale (e.g.
a slider showing the current accessibility level).

### 4. Interaction with theme live-swap (R93)

`setTheme` (R93) and `setFontScale` (this item) must cooperate:

- `setTheme` rebuilds the token set from palette + mode, then applies the current
  `_font_scale`: `self.tokens = Theme.build(p, m).tokens.scaled(self._font_scale)`.
- `setFontScale` similarly uses the current `_current_palette` and `_current_mode` then
  applies the new factor.

Both functions follow this pattern to ensure the two adjustments compose correctly:
```
tokens = Theme.build(palette, mode).tokens.scaled(font_scale)
```

`App.init` sets `_font_scale = 1.0` and builds initial tokens as:
```zig
self.tokens = default_tokens;   // Tokens.light(Palette.default()) — already correct
```
No scaling is applied at init time because `factor = 1.0` is an identity.

### 5. Measurement invalidation

`GlyphAtlas` caches rasterized glyphs keyed by `(codepoint, font_size_px, variant)`.
When `font_scale` changes, the effective pixel sizes of `text_xs` … `text_xl` change, so
new glyph cache entries will be generated automatically on the next `measurePass` call
(the cache key changes → cache misses → atlas grows). The old entries are never explicitly
evicted — the atlas accumulates entries for both the old and new sizes. For v1 this is
acceptable; the atlas is 1024×1024 and a typical app uses 5 sizes × 2 variants = 10
distinct font configurations, well within capacity.

### 6. Persistent settings integration (M8-03)

`setFontScale` and the settings store are not coupled by this spec. An application author
who wants to persist the scale writes:

```zig
try prefs.setF32("font_scale", factor);
// At startup:
const scale = prefs.getF32("font_scale") orelse 1.0;
app.setFontScale(scale);
```

This is an application-layer pattern, not a framework concern.

---

## Module location

```
src/05/types.zig               — Tokens.scaled (additive method)
src/app/app.zig               — setFontScale, getFontScale, _font_scale field;
                                 setTheme updated to compose with _font_scale
src/app/font_scale_test.zig   — acceptance tests (headless)
docs/requirements/R94_font_scaling.md
```

`src/app/types.zig` re-exports `setFontScale` and `getFontScale`.

---

## Glossary addition

Add to `docs/specs/glossary.md`:

```
## font scale

A global multiplier (`AppInner._font_scale`, default `1.0`) applied to all five type-scale
sizes in `Tokens` (`text_xs`…`text_xl`). Applied via `Tokens.scaled(factor)` whenever the
theme or scale factor changes. Composes with the theme: the effective token set is always
`Theme.build(palette, mode).tokens.scaled(font_scale)`. Controlled at runtime via
`App.setFontScale(factor)`. Clamped to `[0.5, 4.0]`.

See: R94 (M9-05), `src/app/app.zig`, `src/05/types.zig`.
```

---

## Invariant interactions

- **INV-4.3**: `Tokens.scaled` produces a `Tokens` struct whose values are derived from
  the input token set — not from raw hex literals. The multiplied sizes are `f32` arithmetic
  on existing token values.
- **INV-3.3**: `markAllDirty()` is the change-propagation mechanism. No new paths.
- **INV-5.1**: `Tokens.scaled` is a new additive method on `Tokens` in `src/05/types.zig`.
  No existing signature changes.

---

## Non-goals (DO NOT implement — INV-5.4)

- NO per-widget font scale override — one global multiplier only.
- NO fractional pixel rounding (sub-pixel rendering) — `Tokens.scaled` produces `f32`
  values; existing rendering code already works with `f32` font sizes.
- NO UI for selecting a scale factor — that is the application's responsibility.
- NO OS-level font DPI integration (reading the Windows DPI setting or GTK font scale) —
  the app author calls `setFontScale` from platform-specific startup code if desired;
  the framework does not query the OS.
- NO automatic atlas eviction of old glyph sizes — the v1 atlas is large enough.

---

## Acceptance criteria

The module is done when:

1. `zig build test-font-scale` passes all tests in `src/app/font_scale_test.zig`.
2. `Tokens.scaled(1.5)` on the default light tokens returns a `Tokens` with
   `text_base = 14 * 1.5 = 21.0` and all other non-size fields unchanged.
3. `Tokens.scaled(0.0)` clamps `text_xs` to 6 px (not 0).
4. `Tokens.scaled(100.0)` clamps `text_xl` to 96 px (not 2400).
5. `setFontScale(1.5)` calls `rebuildStyles` and marks all elements dirty.
6. `getFontScale()` returns the last value passed to `setFontScale`.
7. `setFontScale` called before `setTheme` → subsequent `setTheme` preserves the scale.
8. `setTheme` called after `setFontScale` → resulting `tokens.text_base` is correctly scaled.
9. `setFontScale(0.4)` is clamped to `0.5` (verified by `getFontScale()` returning `0.5`).
10. The checklist for this item is fully ticked.

---

## Edge cases (each has a test)

- `setFontScale(1.0)` → `tokens.text_base == 14.0` (identity).
- `setFontScale(2.0)` then `setTheme(dark)` → `tokens.text_base == 28.0` (scale persists).
- `setFontScale(2.0)` then `setFontScale(1.0)` → `tokens.text_base == 14.0` (reset).
- Scale factor `NaN` — clamped behavior with `std.math.clamp`; Zig's `clamp` with NaN
  returns the min value; resulting tokens have minimum sizes. (Acceptable; document as
  undefined behavior in production.)
