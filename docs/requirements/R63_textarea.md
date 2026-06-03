# R63 — M6-04: Multi-line text input (Textarea)

> Roadmap item: M6-04  
> Depends on: M3-03 (text input, `InputState`), M6-03 (text selection, `TextSelection`), module 02 (`layoutParagraph`, line wrapping), M4-03 (scroll container clipping)  
> Read `00_constitution.md` before this file.

## Purpose

A `<Textarea>` widget is a multi-line editable text field. It extends the single-line
`<Input>` by enabling newlines, wrapping long lines within the widget's width, and scrolling
vertically when content overflows the visible area. Cursor navigation is aware of line
boundaries (Up/Down arrows move by line). The widget is a new `WidgetKind`; its state is an
extension of `InputState`.

## What to build

### New widget kind

Add to [07.types.zig](../specs/07.types.zig):

```zig
pub const WidgetKind = enum {
    text, button, input, card, row, column, dropdown,
    checkbox, scrollview, image, icon,
    textarea,  // NEW
};

pub fn tagToKind(tag: []const u8) ?WidgetKind {
    // ...existing cases...
    if (eql(u8, tag, "Textarea")) return .textarea;
    return null;
}

pub fn defaultLayoutFor(kind: WidgetKind) LayoutNode {
    return switch (kind) {
        // ...existing cases...
        .textarea => .{ .display = .block, .overflow = .hidden },
        else => .{ .display = .block },
    };
}
```

`defaultStyleFor(.textarea, tokens)` returns the same base style as `inputDefault(tokens)`.

### `TextareaState` — extends `InputState`

Rather than adding all multi-line fields to `InputState` (which would bloat every single-line
input), `Textarea` has its own parallel state array:

```zig
pub const TextareaState = struct {
    /// Byte position of each line's start in the text buffer.
    /// Index 0 is always 0. Rebuilt on every text mutation.
    /// Max 1024 lines in v1.
    line_starts: std.ArrayListUnmanaged(u32) = .empty,

    /// Vertical scroll offset within the textarea (pixels scrolled down).
    scroll_y: f32 = 0,

    /// Total content height in pixels (sum of all line heights).
    content_h: f32 = 0,

    /// Height of the visible textarea area (from layout rect).
    container_h: f32 = 0,
};

pub const Scene = struct {
    // ...existing fields...
    _textarea_state: std.ArrayListUnmanaged(TextareaState) = .empty,

    pub fn textareaStateOf(self: *Scene, idx: u32) *TextareaState
};
```

`InputState` (from M3-03) is shared: `_input_state[idx]` holds the text buffer, cursor
byte position, and `active` flag. `TextareaState` holds the extra multi-line bookkeeping.
Both arrays are indexed by `ElementId.index`; non-textarea elements have a zeroed
`TextareaState` slot (unused).

### Line-start index — `rebuildLineStarts`

After any text mutation (insertion, deletion, paste), call `rebuildLineStarts`:

```zig
fn rebuildLineStarts(textarea_state: *TextareaState, text: []const u8) void {
    textarea_state.line_starts.clearRetainingCapacity();
    textarea_state.line_starts.appendAssumeCapacity(0);  // always starts at 0
    for (text, 0..) |c, i| {
        if (c == '\n') {
            const next = @intCast(u32, i + 1);
            if (next <= text.len) {
                textarea_state.line_starts.append(textarea_state.line_starts.allocator(), next)
                    catch break;  // silently truncate at 1024 lines
            }
        }
    }
}
```

Line number for a byte offset: binary search `line_starts` for the largest value ≤ offset.
Column within line: `offset - line_starts[line_num]`.

### Newline handling in `App.run()`

For `textarea` elements, the existing text input handler (M3-03) is extended to:

1. Allow `'\n'` (Enter key, not char=10) to insert a newline into the text buffer.
2. After any text mutation, call `rebuildLineStarts`.

```zig
// In the text-character input path for textarea:
Key.enter => {
    // Insert '\n' at cursor (same as inserting any other character).
    try input_state.text.insert(gpa, input_state.cursor, '\n');
    input_state.cursor += 1;
    scene.selectionOf(idx).* = .{ .anchor = input_state.cursor, .active = input_state.cursor };
    rebuildLineStarts(scene.textareaStateOf(idx), input_state.text.items);
    scene.elements.dirty.set(idx);
},
```

### Up/Down arrow navigation

Up/Down arrows move the cursor by one line, preserving the column (byte offset within line)
if possible:

```zig
Key.up => {
    const ts = scene.textareaStateOf(idx);
    const line = lineOfByte(ts, input_state.cursor);
    if (line == 0) {
        input_state.cursor = 0;  // already on first line
    } else {
        const col = input_state.cursor - ts.line_starts.items[line];
        const prev_line_start = ts.line_starts.items[line - 1];
        const prev_line_len = ts.line_starts.items[line] - 1 - prev_line_start; // excl \n
        input_state.cursor = prev_line_start + @min(col, prev_line_len);
    }
    if (!modifiers.shift) {
        scene.selectionOf(idx).* = .{ .anchor = input_state.cursor,
                                      .active = input_state.cursor };
    } else {
        scene.selectionOf(idx).active = input_state.cursor;
    }
    scene.elements.dirty.set(idx);
},
// Key.down: symmetric — move to the next line at the same column
```

### Vertical scrolling within the textarea

After layout, `TextareaState.container_h` is set from the element's `computed.h`. After
`measurePass`, `TextareaState.content_h` is set from the total line count times line height.
On cursor movement, if the cursor is outside the visible area, scroll to keep it visible:

```zig
fn scrollToCursor(ts: *TextareaState, cursor: u32, line_h: f32) void {
    const line = lineOfByte(ts, cursor);
    const cursor_y = @as(f32, @floatFromInt(line)) * line_h;
    if (cursor_y < ts.scroll_y) {
        ts.scroll_y = cursor_y;
    } else if (cursor_y + line_h > ts.scroll_y + ts.container_h) {
        ts.scroll_y = cursor_y + line_h - ts.container_h;
    }
}
```

### `measurePass` for textarea

`Scene.measurePass` for `textarea` elements calls `layoutParagraph` for each line of text
independently (at the element's `computed.w` width), sums the heights, and stores in
`TextareaState.content_h`. The `LayoutNode.measured` is NOT set for textarea (the element
has a declared height from markup, e.g. `class="h-48"`); measured is only used for leaf
text elements that auto-size to their content.

### `buildDrawList` for textarea

In the serializer, for a `textarea` element:

1. Emit a `set_scissor` for the textarea's rect (same as scrollview; uses M4-03).
2. Translate all child draw commands by `-ts.scroll_y`.
3. For each line of text (parsed from the text buffer at `line_starts`), call `layoutParagraph`
   and emit glyph commands.
4. Emit cursor rect (thin vertical line) at the cursor's (x, y) within the content.
5. Emit selection highlight rects (using `TextSelection` from M6-03).
6. Emit `restore_scissor`.

### Markup usage

```html
<Textarea class="h-32 w-full p-2" />
<Textarea class="h-48 border rounded-sm" />
```

The textarea's displayed text is sourced from `InputState.text.items`. An initial value can
be set via:

```zig
try scene.setInputText(textarea_idx, "Initial content\nSecond line");
scene.textareaStateOf(textarea_idx).line_starts = rebuildLineStarts(...);
```

### Behavioral contract

| Event | Behavior |
|---|---|
| Type characters | Inserted at cursor; line breaks at declared width |
| Enter key | Inserts `\n`; cursor moves to start of new line |
| Backspace at start of line | Merges with previous line (removes `\n`) |
| Up/Down arrows | Move cursor by one line, same column |
| Cursor below visible area | `scroll_y` advances to keep cursor visible |
| Ctrl+A | Select all text (anchor=0, active=text.len) |
| Ctrl+C | Copy selected text to clipboard |
| Ctrl+V | Paste; replaces selection if present |
| Textarea without declared height | Grows to fill parent (layout height = percent 100 or flex-1) |

### Module location

```
src/07/types.zig          — WidgetKind.textarea, TextareaState, textareaStateOf, defaultLayoutFor
docs/specs/07.types.zig   — same
src/app/app.zig           — Enter key handling, Up/Down arrows, rebuildLineStarts, scrollToCursor
src/09/types.zig          — buildDrawList textarea path
docs/requirements/R63_textarea.md
```

## Public API

New in module 07:

```zig
// WidgetKind gains: .textarea
pub const TextareaState = struct { line_starts, scroll_y, content_h, container_h }
pub fn textareaStateOf(self: *Scene, idx: u32) *TextareaState
```

## Non-goals (DO NOT implement — INV-5.4)

- **No `rows=` / `cols=` attributes** — size is controlled by Tailwind sizing classes.
- **No `resize` handle** — the textarea's size is fixed; no drag-to-resize corner.
- **No soft-wrap word-boundary** — text wraps at the element's pixel width at any byte
  position (no word-boundary-aware soft-wrap). True word-wrap requires re-running `wrap()`
  from module 02; this is post-v1.
- **No `placeholder` text** — post-v1 (requires conditional rendering of a placeholder).
- **No `max-length` attribute** — text is unbounded; the 1024-line limit is a hard cap to
  prevent pathological inputs.
- **No horizontal scrolling** — vertical only (horizontal overflow is not visible; text
  wraps at element width instead).
- **No `tab` key behavior** — Tab moves focus (M3-01), not inserts a tab character, for
  consistency with single-line inputs.
- **No undo/redo** — post-v1.
- **No IME** — (INV-1.3).

## Acceptance criteria

1. `zig build test-scene` passes. New tests:
   - `rebuildLineStarts` on `"hello\nworld"` → `[0, 6]`.
   - `rebuildLineStarts` on `"no newlines"` → `[0]`.
   - `rebuildLineStarts` on `""` → `[0]`.
   - `lineOfByte` at byte 0 → line 0; at byte 6 → line 1.
   - `scrollToCursor` with cursor on the third line scrolls `scroll_y` to keep it visible.

2. Integration:
   - Run the app with a `<Textarea class="h-32 w-full">`. Type multiple lines. Verify
     text wraps, newlines are accepted, and the cursor is visible.
   - Scroll via the scroll_y mechanism when content overflows.
   - Up/Down arrows navigate between lines.
   - Backspace at line start merges lines.
   - Ctrl+A selects all text.

3. `WidgetKind.textarea` added to `tagToKind`; `<Textarea/>` instantiates without error.

4. No memory leaks: `TextareaState.line_starts` freed via `Scene.deinit`.

5. Checklist fully ticked.

## Open questions

One: word-wrap within each logical line (i.e. a single line in the buffer that is wider than
the textarea). In v1, text overflows the textarea width and is clipped by the scissor.
Proper soft-wrap (visual line breaking without inserting `\n`) requires re-running module
02's `wrap()` against each logical line during measurement and rendering. This is a
significant addition to `measurePass` and `buildDrawList`; surface it to the human before
implementing if needed.
