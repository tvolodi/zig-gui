# R62 — M6-03: Text selection

> Roadmap item: M6-03  
> Depends on: M1-02 (event delivery), module 09 (`buildDrawList`), module 02 (`layoutParagraph`, `PositionedGlyph`), M3-03 (text input, `InputState`)  
> Read `00_constitution.md` before this file.

## Purpose

The user can select a range of text in a `<Text>` (read-only) or `<Input>` element by
clicking and dragging, or by using keyboard shortcuts. The selected range is highlighted with
a colored background rect drawn behind the glyph commands. The selection is stored as a
`{start, end}` byte range in the `Scene` parallel arrays. Copy (Ctrl+C) works on both
read-only `<Text>` and `<Input>` elements.

## What to build

### `TextSelection` — selection state in `Scene`

Add to [07.types.zig](../specs/07.types.zig):

```zig
/// Byte-offset selection range for a text or input element.
/// anchor = where the drag/selection started.
/// active = where it currently ends (may be before or after anchor).
/// When anchor == active, no text is selected (collapsed selection / caret).
pub const TextSelection = struct {
    anchor: u32 = 0,
    active: u32 = 0,

    pub fn isEmpty(self: TextSelection) bool {
        return self.anchor == self.active;
    }

    /// Return the selection as a normalized [lo, hi) range.
    pub fn range(self: TextSelection) struct { lo: u32, hi: u32 } {
        if (self.anchor <= self.active) {
            return .{ .lo = self.anchor, .hi = self.active };
        } else {
            return .{ .lo = self.active, .hi = self.anchor };
        }
    }
};

pub const Scene = struct {
    // ...existing fields...

    /// Per-element selection state. Meaningful for .text and .input elements.
    /// All other element kinds keep the default (empty) selection.
    _selection: std.ArrayListUnmanaged(TextSelection) = .empty,

    pub fn selectionOf(self: *Scene, idx: u32) *TextSelection

    /// Set selection for element `idx` and mark dirty.
    /// Setting anchor == active collapses the selection.
    pub fn setSelection(self: *Scene, idx: u32, anchor: u32, active: u32) void

    /// Clear selection (set anchor = active = 0) and mark dirty.
    pub fn clearSelection(self: *Scene, idx: u32) void
};
```

### `InputState` — remove duplicate selection tracking

M3-03 (`R32`) defined `InputState.selection_start` and `InputState.cursor` to track the
input selection. With M6-03, the `TextSelection` array is the canonical selection store for
both `text` and `input` elements. `InputState.selection_start` is **replaced** by the
`_selection` array:

- `InputState.cursor` is kept (it is the text insertion point, not purely a selection end).
- `InputState.selection_start` is removed from `InputState`.
- `InputState.active` is kept (denotes whether the input widget has keyboard focus).
- Selection in an active input is tracked via `_selection[idx].anchor` and
  `_selection[idx].active == InputState.cursor`.

This is a **breaking change** to `InputState`. All existing references to
`InputState.selection_start` in `app.zig` must be replaced with
`scene.selectionOf(idx).anchor`.

### Mouse click-drag selection for `<Text>` elements

In `App.run()`, add hit-testing for read-only `<Text>` elements:

```zig
// On mouse button press:
for each text element at idx:
    const rect = scene.elements.layout.items[idx].computed;
    if (!rect.containsPoint(mouse_pos)) continue;
    const byte_offset = hitTestText(scene, idx, mouse_pos, family, glyph_atlas);
    scene.setSelection(idx, byte_offset, byte_offset);  // collapsed; start drag
    dragging_text_idx = idx;
    scene.elements.dirty.set(idx);

// On mouse move while button held (dragging_text_idx is set):
if (dragging_text_idx) |idx| {
    const byte_offset = hitTestText(scene, idx, mouse_pos, family, glyph_atlas);
    scene.selectionOf(idx).active = byte_offset;
    scene.elements.dirty.set(idx);
}

// On mouse button release:
dragging_text_idx = null;
```

### `hitTestText` — map pixel X to byte offset

```zig
/// Return the byte offset in the element's text string that corresponds to
/// the given mouse position. Returns 0 if before the first glyph, or
/// text.len if after the last. Uses the midpoint of each glyph's advance
/// to decide which side of the gap the click lands on.
fn hitTestText(
    scene: *const Scene,
    idx: u32,
    mouse_pos: Vec2,       // {x: f32, y: f32}
    family: *const FontFamily,
    atlas: *GlyphAtlas,
) u32
```

`hitTestText` re-runs `layoutParagraph` to get positioned glyphs, then finds the nearest
glyph midpoint to `mouse_pos.x`. The glyph's `dest_x` + `dest_w/2` is the midpoint; clicks
to the left map to that glyph's byte offset, clicks to the right map to the offset after it.

`hitTestText` re-uses glyph layout computed during `measurePass` if it is cached; in v1 it
re-runs `layoutParagraph` since the `Paragraph` result is not currently cached. This is a
known v1 limitation (acceptable for click events which are infrequent).

### Keyboard selection for `<Text>` elements

For read-only `<Text>` elements that have keyboard focus (M3-01):

- `Shift+Left`: `active -= 1` (byte, clamped to 0).
- `Shift+Right`: `active += 1` (byte, clamped to `text.len`).
- `Shift+Home`: `active = 0`.
- `Shift+End`: `active = text.len`.
- `Ctrl+A`: `anchor = 0, active = text.len` (select all).

`Left`/`Right` without Shift collapses the selection: `anchor = active = new_cursor`.

### Keyboard selection for `<Input>` elements

M3-03's input handling already handles `Shift+Left/Right` using `InputState.selection_start`
and `cursor`. With M6-03, these are unified:

- `_selection[idx].anchor` replaces `InputState.selection_start`.
- `_selection[idx].active == InputState.cursor` at all times for inputs.
- All existing input keyboard handling that writes `selection_start` now writes
  `_selection[idx].anchor` instead.

### Ctrl+C on `<Text>` elements

Add copy support for focused read-only text elements:

```zig
// In App.run() key handling, if focused element is a .text kind:
if (event.key == Key.c and modifiers.ctrl) {
    const sel = scene.selectionOf(focused_idx).*;
    if (!sel.isEmpty()) {
        const text = scene.textOf(focused_idx) orelse continue;
        const r = sel.range();
        platform.setClipboard(text[r.lo..r.hi]);
    }
}
```

### Selection highlight rendering in `buildDrawList`

For each `text` or `input` element, after emitting the background rect and before emitting
glyph commands, emit selection highlight rects:

```zig
// For each element with a non-empty selection:
const sel = scene.selectionOf(idx).*;
if (!sel.isEmpty()) {
    const text_str = ...; // textOf or inputStateOf text
    const para = layoutParagraph(...);  // re-layout to get glyph positions

    const r = sel.range();
    // Find glyph rects that fall within the selected byte range.
    // Emit one filled_rect per contiguous run of selected glyphs on the same line.
    // Color: a semi-transparent accent color (e.g. tokens.accent with alpha 80).
    var run_start_x: ?f32 = null;
    var run_end_x: f32 = 0;

    for (para.glyphs) |g| {
        const in_sel = glyph_byte_offset_within(g, r.lo, r.hi);
        if (in_sel) {
            if (run_start_x == null) run_start_x = g.dest_x;
            run_end_x = g.dest_x + g.dest_w;
        } else if (run_start_x != null) {
            // End of a selected run — emit highlight rect.
            try cmds.append(.{ .filled_rect = .{
                .rect  = .{ .x = layout_rect.x + run_start_x.?, .y = layout_rect.y,
                             .w = run_end_x - run_start_x.?, .h = layout_rect.h },
                .color = .{ .r = tokens.accent.r, .g = tokens.accent.g,
                            .b = tokens.accent.b, .a = 80 },
            }});
            run_start_x = null;
        }
    }
    if (run_start_x != null) {
        // Flush final run.
        try cmds.append(.{ .filled_rect = ... });
    }
}
// Then emit glyph commands (on top of the selection highlight).
```

The selection highlight is drawn **after** the element background but **before** the glyphs,
so the text remains readable.

### `glyph_byte_offset_within` — map glyph to byte range

`layoutParagraph` returns `PositionedGlyph` which contains `codepoint` and position but not
the byte offset in the original string. To determine which glyphs fall within a byte-offset
selection range, `layoutParagraph` must also return the byte offset of each glyph. Extend
`PositionedGlyph`:

```zig
pub const PositionedGlyph = struct {
    codepoint: u21,
    dest_x: f32,
    dest_y: f32,
    dest_w: f32,
    dest_h: f32,
    uv: AtlasRect,
    byte_offset: u32,  // NEW — byte offset of this glyph's codepoint in the source string
};
```

`layoutParagraph` fills this during glyph iteration (advance a byte cursor alongside the
UTF-8 decoder). This is a breaking change to `PositionedGlyph`; all existing consumers
(module 09 serializer) must accept the new field (no behavioral change — new field is just
ignored in the existing text-draw path).

### `hitTestText` with `byte_offset` field

With `byte_offset` in `PositionedGlyph`, `hitTestText` is straightforward:

```zig
fn hitTestText(...) u32 {
    const para = layoutParagraph(...);
    var best_offset: u32 = 0;
    var best_dist: f32 = std.math.inf(f32);
    for (para.glyphs) |g| {
        const mid_x = layout_rect.x + g.dest_x + g.dest_w / 2;
        const dist = @abs(mouse_pos.x - mid_x);
        if (dist < best_dist) {
            best_dist = dist;
            best_offset = g.byte_offset;
        }
    }
    return best_offset;
}
```

### `App` drag state

Add to `App`:

```zig
dragging_text_idx: ?u32 = null,
```

Reset to `null` on each mouse-button release.

### Behavioral contract

| Event | Behavior |
|---|---|
| Click on text element | Collapsed selection at nearest glyph byte offset |
| Click-drag on text element | Selection extends as mouse moves |
| `Shift+Right` on focused text | `active` advances one byte; anchor unchanged |
| `Ctrl+A` on focused text | Select all (`anchor=0, active=text.len`) |
| `Ctrl+C` on focused text | Copies selected substring to clipboard |
| Empty selection | No highlight rect emitted; `isEmpty() == true` |
| Selection on non-text/input element | Selection array slot exists but is always `.{0, 0}` |

### Module location

```
src/07/types.zig          — TextSelection, selectionOf, setSelection, clearSelection; InputState change
docs/specs/07.types.zig   — TextSelection, selectionOf, setSelection, clearSelection
src/02/types.zig          — PositionedGlyph.byte_offset field
docs/specs/02.types.zig   — PositionedGlyph change
src/09/types.zig          — selection highlight emission in buildDrawList
src/app/app.zig           — hitTestText, drag state, keyboard selection handling, Ctrl+C for text
docs/requirements/R62_text_selection.md
```

## Public API

New in module 07:

```zig
pub const TextSelection = struct { anchor: u32, active: u32; pub fn isEmpty, range }
pub fn selectionOf(self: *Scene, idx: u32) *TextSelection
pub fn setSelection(self: *Scene, idx: u32, anchor: u32, active: u32) void
pub fn clearSelection(self: *Scene, idx: u32) void
// InputState: selection_start field REMOVED; callers use _selection array
```

Changed in module 02:

```zig
// PositionedGlyph gains: byte_offset: u32
```

## Non-goals (DO NOT implement — INV-5.4)

- **No double-click word selection** — only character-by-character drag or keyboard; word
  selection is post-v1.
- **No triple-click line selection** — post-v1.
- **No selection in container widgets** (card, row, column) — only `text` and `input`.
- **No selection persistence across focus changes** — when a `text` element loses focus,
  its selection is cleared.
- **No drag-start delay / click tolerance** — any mouse move with button held extends the
  selection immediately.
- **No multi-element selection** — selection is per-element; no spanning across multiple
  `<Text>` nodes.
- **No selection color customization** — accent with alpha 80 is hardcoded; theming is
  post-v1.
- **No IME composition underline** — (INV-1.3).

## Acceptance criteria

1. `zig build test-scene` passes. New tests:
   - `setSelection(idx, 2, 5)` → `selectionOf(idx).anchor == 2, .active == 5`.
   - `range()` returns `{lo=2, hi=5}`.
   - `setSelection(idx, 5, 2)` → `range()` returns `{lo=2, hi=5}` (normalized).
   - `clearSelection` → `isEmpty() == true`.
   - `setSelection` marks the element dirty.

2. `zig build test-02` passes. New test (font-dependent):
   - `layoutParagraph` produces `PositionedGlyph` entries with monotonically increasing
     `byte_offset` matching UTF-8 decode positions in the source string.

3. Integration:
   - Click and drag over a `<Text>` element. Selected glyphs highlighted in accent color.
   - `Ctrl+C` copies the selected text to clipboard (verify by pasting into another input).
   - `Ctrl+A` selects all text in a focused `<Text>`.

4. `InputState.selection_start` removed; all `App.run()` input key handlers updated to use
   `scene.selectionOf(idx)`.

5. No per-frame allocations in the selection highlight path beyond the draw-list output slice.

6. Checklist fully ticked.

## Open questions

One: `hitTestText` re-runs `layoutParagraph` on every click. For long strings this adds
latency. A cached `Paragraph` per element (cleared when text/style changes) would fix this.
The cache would live in a `Scene` parallel array `_paragraph: []?Paragraph`. Defer to post-
M6-03 unless profiling shows it matters; the current approach is correct and simple.
