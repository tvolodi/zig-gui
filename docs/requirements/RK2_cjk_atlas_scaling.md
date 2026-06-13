# RK2 — M24-03: CJK fallback and atlas scaling

> Roadmap item: M24-03
> Depends on: RK0 (shaping), R64 (font fallback), 02 (GlyphAtlas)
> Read `RK0_harfbuzz_shaping.md` before this file.

## Purpose

Make the glyph atlas viable for CJK and large mixed-script text. v1's atlas assumed a small
Latin+Cyrillic glyph set with a fixed capacity. CJK fonts have thousands of glyphs per size;
the atlas needs growth and eviction, and the fallback chain needs a CJK font. This is the
"volume" half of complex-script support, complementing RK0's "correctness" half.

## What to build

### Atlas growth + eviction (module 02)

```zig
pub const GlyphAtlas = struct {
    // existing fields ...
    /// LRU eviction metadata, one entry per packed glyph.
    last_used_frame: []u32,

    /// Insert; if full, evict least-recently-used glyphs to make room. Returns the rect.
    pub fn insertOrEvict(self: *GlyphAtlas, key: GlyphKey, w: u32, h: u32,
        pixels: []const u8, frame: u32) AtlasError!AtlasRect;

    /// Grow the backing texture to the next size tier (e.g. 1024→2048) when eviction churn
    /// exceeds a threshold. Triggers a GPU re-upload (RJ0 uploadAtlas).
    pub fn grow(self: *GlyphAtlas) AtlasError!void;
};
```

Policy: the atlas starts at a modest size, grows in power-of-two tiers up to a configured
ceiling (interacts with the RA1 memory budget), and uses LRU eviction once at the ceiling.
Eviction marks the freed shelf region reusable; a glyph evicted and re-needed is re-rasterized.

### CJK fallback font (R64 chain)

Extend the R64 fallback chain to include a bundled CJK font (e.g. a subset of Noto Sans CJK).
Itemization (RK1) assigns CJK runs this font_id; shaping (RK0) and rasterization proceed
normally. The CJK font is an app asset, not a system lookup (no fontconfig — amendment §2).

### Line breaking for CJK

CJK allows line breaks between most ideographs (no spaces). Extend the existing break-
opportunity logic with a minimal CJK rule: a break opportunity exists between two ideographic
characters, with a small kinsoku set (do not break before closing punctuation / after opening
punctuation). This is the only line-break tailoring v2 adds (bounded per INV-1.3-v2).

## Module location

```
src/02/types.zig          — GlyphAtlas growth, LRU eviction, insertOrEvict, grow
src/02/types.zig          — break-opportunity logic gains the CJK ideograph rule
src/02/fallback.zig        — CJK font added to the R64 chain
assets/                   — bundled CJK font subset
docs/requirements/RK2_cjk_atlas_scaling.md
```

## Public API changes

```zig
// Module 02: GlyphAtlas gains insertOrEvict(), grow(), last_used_frame.
// The fixed-capacity insert() remains for non-CJK callers; CJK path uses insertOrEvict().
```

## Behavioral contract

| Situation | Behavior |
|---|---|
| Render a screen of CJK text exceeding atlas capacity | LRU eviction keeps the working set; no crash, no missing glyphs in view |
| Atlas churn high | `grow` bumps to the next tier (until ceiling); GPU re-uploads once |
| Atlas at ceiling, still churning | LRU eviction continues; off-screen glyphs evicted first |
| CJK codepoint not in primary/Latin fonts | Resolved to the bundled CJK fallback font |
| Long CJK paragraph, no spaces | Wraps between ideographs; respects basic kinsoku |
| Latin-only screen | Uses fixed `insert` path; behavior unchanged from v1 |

## Non-goals (DO NOT implement — INV-5.4)

- **No full kinsoku/JLREQ line-break ruleset** — only the minimal ideograph + basic
  punctuation rule (INV-1.3-v2 bounds scope).
- **No system font discovery** — the CJK font is a bundled asset.
- **No vertical CJK layout.**
- **No multi-texture atlas array** — a single growing texture up to the ceiling; if the
  ceiling is exceeded, eviction handles it (no second texture binding).
- **No subsetting tool in the production binary** — any font subsetting is an offline asset
  step.

## Acceptance criteria

1. Module 02 acceptance test covers `insertOrEvict` (eviction picks the LRU entry) and `grow`
   (tier bump preserves existing live glyphs).
2. A CJK test string renders fully with the bundled fallback font.
3. A stress test rendering more distinct glyphs than the initial atlas capacity completes with
   all currently-visible glyphs present (no holes).
4. CJK line-wrapping breaks between ideographs and honors the basic kinsoku set.
5. Latin-only screens show no atlas behavior change (regression check).
6. Atlas ceiling honors the RA1 memory budget.
