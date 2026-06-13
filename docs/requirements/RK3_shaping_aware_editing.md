# RK3 — M24-04: Shaping-aware caret, selection, and editing

> Roadmap item: M24-04
> Depends on: RK0 (shaping), RK1 (bidi), R32 (text input), R62 (text selection), R63 (textarea)
> Read `RK0_harfbuzz_shaping.md` and `RK1_bidirectional_text.md` before this file.

## Purpose

Make the existing editable-text widgets correct under shaping and bidi. v1 assumes one
codepoint = one advance = one caret stop, which breaks for ligatures, clusters, and RTL/mixed
text. This requirement defines the query API that text input (R32), textarea (R63), and
selection (R62) use instead of per-codepoint advances. This is the deepest-reaching v2 change
into existing widgets and the primary regression risk (`V2_ARCHITECTURE.md` §3).

## What to build

### `ShapedLine` query API (module 11)

```zig
pub const ShapedLine = struct {
    runs: []const ShapedRun,   // visual order (RK1)

    /// Pixel x of the caret for a given byte offset (cluster-snapped).
    pub fn caretX(self: *const ShapedLine, byte_offset: u32) f32;
    /// Map a pixel x to the nearest insertion byte offset (cluster boundary).
    pub fn byteAtX(self: *const ShapedLine, x: f32) u32;
    /// Next / previous caret stop from a byte offset, in VISUAL order (handles RTL + clusters).
    pub fn nextCaret(self: *const ShapedLine, byte_offset: u32) u32;
    pub fn prevCaret(self: *const ShapedLine, byte_offset: u32) u32;
    /// Selection rectangles for a byte range — may be multiple rects across direction runs.
    pub fn selectionRects(self: *const ShapedLine, start: u32, end: u32, gpa) ![]Rect;
};
```

### Widget integration

- **R32 text input / R63 textarea:** cursor movement (arrows, Home/End), insert, delete, and
  click-to-place all route through `ShapedLine` cluster boundaries instead of codepoint
  counts. A ligature is one caret stop; an RTL run moves the caret right-to-left visually
  while advancing logically.
- **R62 selection:** mouse drag and shift-extend use `byteAtX` / `selectionRects`. A selection
  spanning a direction boundary produces multiple highlight rects (one per visual run segment).
- Backspace/delete operate on logical byte offsets (so the underlying string stays correct)
  while caret motion is visual.

## Module location

```
src/11/types.zig          — ShapedLine + caretX/byteAtX/nextCaret/prevCaret/selectionRects
src/components/*           — R32 input, R63 textarea, R62 selection call ShapedLine
src/app/scene.zig          — text-edit parallel arrays store byte offsets (logical), not codepoint indices
docs/requirements/RK3_shaping_aware_editing.md
```

## Public API changes

```zig
// Module 11: ShapedLine query API (above).
// Text-edit state in Scene stores logical byte offsets; the per-codepoint-index assumption is removed.
```

## Behavioral contract

| Situation | Behavior |
|---|---|
| Click between "f" and "i" of an `fi` ligature | Caret snaps to the cluster boundary (before or after the ligature, nearest) |
| Arrow-right through an RTL word in LTR paragraph | Caret advances logically; visual position moves per UBA |
| Select across an LTR↔RTL boundary | Multiple highlight rects covering the visual segments |
| Backspace in CJK / multi-byte text | Deletes one cluster's bytes; string remains valid UTF-8 |
| Home / End | Move to visual line start / end (leftmost / rightmost caret stop) |
| Plain ASCII single-direction text | Behaves exactly as v1 (regression-protected) |

## Non-goals (DO NOT implement — INV-5.4)

- **No grapheme-cluster segmentation beyond shaping clusters** — caret stops are HarfBuzz
  clusters, which is sufficient for the supported scripts; no full UAX-29 engine.
- **No input-method editor (IME)** integration beyond GLFW's existing text-input events.
- **No bidi-aware text reflow during typing** beyond re-running itemize/shape on edit.
- **No selection across multiple paragraphs with mixed base directions** beyond per-line rects.

## Acceptance criteria

1. Module 11 acceptance test covers `caretX`, `byteAtX`, `nextCaret`/`prevCaret`, and
   `selectionRects` for: a ligature, an RTL run, and a CJK run.
2. Clicking inside a ligature snaps to the nearest cluster boundary (unit test with known
   shaped output).
3. Arrow navigation through a mixed LTR/RTL line visits caret stops in correct visual order.
4. Selection spanning a direction boundary yields the expected number of highlight rects.
5. Editing operations keep the underlying buffer valid UTF-8 (fuzz/round-trip test).
6. Visual + interaction: ASCII text input/selection in the demo app behaves identically to v1
   (no regression) — verified with the existing forms visual suite.
