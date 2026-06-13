# RK1 — M24-02: Bidirectional text + itemization

> Roadmap item: M24-02
> Depends on: RK0 (shaping), RE3 (rtl layout-direction flag), 02 (text)
> Blocked by ratification of `V2_constitution_amendment.md` (INV-1.3-v2; §2 approves
> SheenBidi *or* a pure-Zig UBA port — this requirement records the choice).
> Read `RK0_harfbuzz_shaping.md` before this file.

## Purpose

Add Unicode Bidirectional Algorithm (UBA) support so mixed left-to-right and right-to-left
text (e.g. a phone number inside an Arabic sentence, or English inside Hebrew) lays out in
correct visual order. This replaces RE3's coarse coordinate-mirroring shortcut with proper
per-run embedding-level resolution, and feeds correctly-ordered runs into the RK0 shaper.

## Decision recorded here

**UBA implementation: pure-Zig port** is preferred over SheenBidi (C) because the UBA is a
well-specified, self-contained algorithm with no rendering dependency, and a Zig port keeps
the dependency surface minimal (INV-5.6 spirit). If the port proves too costly, SheenBidi (C,
Apache-2.0) is the approved fallback (amendment §2). **This choice requires owner sign-off at
ratification.**

## What to build

### Itemization + bidi (module 11)

```zig
pub const Direction = enum { ltr, rtl };

pub const TextItem = struct {
    byte_start: u32,
    byte_len: u32,
    level: u8,          // UBA embedding level; even = LTR, odd = RTL
    script: Script,     // resolved script for shaper hinting
    font_id: u16,       // resolved font from the R64 fallback chain
};

/// Resolve embedding levels for a paragraph given a base direction, then split into
/// itemized runs by (level, script, font). Returns runs in LOGICAL order.
pub fn itemize(text: []const u8, base: Direction, gpa) ![]TextItem;

/// Reorder a line's logical runs into VISUAL order per the UBA L2 rule.
pub fn reorderVisual(items: []const TextItem, gpa) ![]TextItem;
```

The pipeline (per `V2_ARCHITECTURE.md` §3): `itemize` (levels + script + font splitting) →
line breaking (existing) → `reorderVisual` per line → `shapeRun` (RK0) each run in visual
order → position into line boxes.

### Base direction source

RE3's `direction: rtl` flag on `LayoutNode` becomes the **paragraph base direction** input to
`itemize`. Auto-detection (first strong character) is the default when unset.

## Module location

```
src/11/bidi.zig          — UBA level resolution, reorderVisual (or SheenBidi @cImport)
src/11/types.zig          — Direction, TextItem, itemize, reorderVisual
src/11/types.zig          — layoutParagraphEx wires itemize → reorder → shape
src/04/types.zig          — LayoutNode.direction reused as base direction (RE3, no new field)
docs/requirements/RK1_bidirectional_text.md
```

## Public API changes

```zig
// Module 11: Direction, TextItem, itemize(), reorderVisual()
// RE3's direction flag is reinterpreted as base paragraph direction (no new public field).
```

## Behavioral contract

| Situation | Behavior |
|---|---|
| "مرحبا 123 world" (Arabic + digits + Latin) | Arabic RTL, digits + "world" in correct visual positions per UBA |
| Pure LTR paragraph | One LTR run; identical to v1 ordering |
| Pure RTL paragraph | One RTL run; glyphs laid right-to-left |
| Base direction unset | First-strong-character auto-detection picks the base |
| Caret movement across a direction boundary | Visual order respected (consumed by RK3) |

## Non-goals (DO NOT implement — INV-5.4)

- **No paragraph-level layout features** beyond UBA reordering (no `unicode-bidi: isolate`
  CSS-level controls; base direction + auto only).
- **No vertical text**, no mirrored-glyph synthesis beyond what the font + UBA provide.
- **No shaping** — that is RK0; this requirement only orders runs.
- **No script-specific line-break tailoring** beyond the existing break logic.

## Acceptance criteria

1. Module 11 bidi acceptance test passes against a set of UBA reference cases (the standard
   `BidiCharacterTest`-style vectors for the supported subset).
2. "مرحبا 123 world" renders with runs in the visually correct order.
3. Pure-LTR text is byte-for-byte identical in run order to v1 (no regression).
4. `reorderVisual` output, fed to RK0, produces a left-to-right sequence of shaped runs whose
   on-screen x positions are monotonic.
5. Base-direction auto-detection picks RTL for an Arabic-leading paragraph and LTR otherwise.
