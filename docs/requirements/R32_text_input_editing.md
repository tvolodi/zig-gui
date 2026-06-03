# R32 — M3-03: Text input editing

> Roadmap item: M3-03  
> Depends on: M1-02 (event delivery), M3-01 (focus model), R36 (clipboard), M2-01 (signals)  
> Read `00_constitution.md` before this file.

## Purpose

An `input` widget maintains an editable text buffer, cursor position, and selection. The user
can insert/delete characters, select text with Shift+arrow keys, copy/paste via Ctrl+C/V,
and delete selection. The text buffer and cursor state are stored in parallel arrays in `Scene`
(INV-3.1). Input state changes mark elements dirty so the renderer can draw the cursor and
selection highlight (M4-01).

## What to build

### Text input state storage in `Scene`

Extend [07.types.zig](../specs/07.types.zig) `Scene` struct:

```zig
pub const InputState = struct {
    /// Mutable text buffer for this input. Owned by Scene.
    text: std.ArrayListUnmanaged(u8) = .empty,
    
    /// Byte offset of the cursor in `text`.
    /// Valid range: [0, text.items.len].
    /// Cursor is *before* the character at this offset (insertion point).
    cursor: u32 = 0,
    
    /// Byte offset of the start of the selection, or equal to `cursor` if no selection.
    selection_start: u32 = 0,
    
    /// true if this input is focused and ready to receive text input.
    /// (Different from Scene.focused_idx — focused_idx is which element has focus,
    /// but only inputs have editable state.)
    active: bool = false,
};

pub const Scene = struct {
    // ...existing fields...
    
    /// Parallel array of input states, indexed by ElementId.index.
    /// Only meaningful for elements with WidgetKind.input.
    _input_state: std.ArrayListUnmanaged(InputState) = .empty,
    
    /// Get the input state for element `idx` (only valid if kindOf(idx) == .input).
    pub fn inputStateOf(self: *Scene, idx: u32) *InputState
    
    /// Set the text buffer for input `idx` to a copy of `initial_text`.
    /// Clears cursor and selection.
    pub fn setInputText(self: *Scene, idx: u32, initial_text: []const u8) !void
    
    /// Get the current text in input `idx` as a slice.
    pub fn getInputText(self: *Scene, idx: u32) []const u8
    
    /// Clear undo/redo history and reset all input fields on scene reset.
    /// (Already part of existing reset(); just ensure inputs are included.)
};
```

### Focus → input activation

When an `input` element receives focus (via R30 `setFocus`):

```zig
// In Scene.setFocus:
pub fn setFocus(self: *Scene, idx: u32) void {
    var old_idx = self.focused_idx
    self.focused_idx = idx
    
    // Deactivate old input (if it was one)
    if (old_idx < self.count() and self.kindOf(old_idx) == .input) {
        self.inputStateOf(old_idx).active = false
        self.elements.dirty.set(old_idx)
    }
    
    // Activate new input (if it is one)
    if (idx < self.count() and self.kindOf(idx) == .input) {
        self.inputStateOf(idx).active = true
        self.elements.dirty.set(idx)
    }
    
    // ... mark all focusable elements dirty for focus ring update ...
}
```

### Text input events in `App.run()`

Add text-character input handling after focus/button handling:

```zig
while (!platform.shouldClose()) {
    platform.pollEvents()
    
    // ... focus and button handling ...
    
    // NEW: Text input handling
    if (scene.getFocus() < scene.count() and scene.kindOf(scene.getFocus()) == .input) {
        const input_idx = scene.getFocus()
        const input_state = scene.inputStateOf(input_idx)
        
        // Collect text input events (printable characters)
        for (event_queue.text_input) |char| {
            if (input_state.active and char >= 32) {  // printable
                try input_state.text.insertSlice(
                    gpa,
                    input_state.cursor,
                    &[_]u8{char},
                )
                input_state.cursor += 1
                input_state.selection_start = input_state.cursor
                scene.elements.dirty.set(input_idx)
            }
        }
        
        // Handle key events
        while (event_queue.next()) |event| {
            if (!input_state.active) continue
            
            switch (event.key) {
                Key.backspace => {
                    if (input_state.selection_start != input_state.cursor) {
                        // Delete selection
                        const start = @min(input_state.selection_start, input_state.cursor)
                        const end = @max(input_state.selection_start, input_state.cursor)
                        input_state.text.replaceRangeValue(start, end - start, &[_]u8{}) catch {}
                        input_state.cursor = start
                        input_state.selection_start = start
                    } else if (input_state.cursor > 0) {
                        // Delete character before cursor
                        input_state.cursor -= 1
                        input_state.text.replaceRangeValue(input_state.cursor, 1, &[_]u8{}) catch {}
                        input_state.selection_start = input_state.cursor
                    }
                    scene.elements.dirty.set(input_idx)
                },
                Key.delete => {
                    if (input_state.selection_start != input_state.cursor) {
                        // Delete selection (same as backspace)
                        const start = @min(input_state.selection_start, input_state.cursor)
                        const end = @max(input_state.selection_start, input_state.cursor)
                        input_state.text.replaceRangeValue(start, end - start, &[_]u8{}) catch {}
                        input_state.cursor = start
                        input_state.selection_start = start
                    } else if (input_state.cursor < input_state.text.items.len) {
                        // Delete character at cursor
                        input_state.text.replaceRangeValue(input_state.cursor, 1, &[_]u8{}) catch {}
                    }
                    scene.elements.dirty.set(input_idx)
                },
                Key.left => {
                    if (modifiers.shift) {
                        if (input_state.cursor > 0) input_state.cursor -= 1
                    } else {
                        input_state.cursor = @max(
                            input_state.cursor -| 1,
                            input_state.selection_start,
                        )
                        input_state.selection_start = input_state.cursor
                    }
                    scene.elements.dirty.set(input_idx)
                },
                Key.right => {
                    if (modifiers.shift) {
                        if (input_state.cursor < input_state.text.items.len) {
                            input_state.cursor += 1
                        }
                    } else {
                        input_state.cursor = @min(
                            input_state.cursor + 1,
                            input_state.selection_start,
                        )
                        input_state.selection_start = input_state.cursor
                    }
                    scene.elements.dirty.set(input_idx)
                },
                Key.home => {
                    if (!modifiers.shift) {
                        input_state.selection_start = 0
                    }
                    input_state.cursor = 0
                    scene.elements.dirty.set(input_idx)
                },
                Key.end => {
                    input_state.cursor = @intCast(input_state.text.items.len)
                    if (!modifiers.shift) {
                        input_state.selection_start = input_state.cursor
                    }
                    scene.elements.dirty.set(input_idx)
                },
                Key.c => {
                    if (modifiers.ctrl and input_state.selection_start != input_state.cursor) {
                        const start = @min(input_state.selection_start, input_state.cursor)
                        const end = @max(input_state.selection_start, input_state.cursor)
                        const selected_text = input_state.text.items[start..end]
                        platform.setClipboard(selected_text) // Uses R36
                    }
                },
                Key.x => {
                    if (modifiers.ctrl and input_state.selection_start != input_state.cursor) {
                        const start = @min(input_state.selection_start, input_state.cursor)
                        const end = @max(input_state.selection_start, input_state.cursor)
                        const selected_text = input_state.text.items[start..end]
                        platform.setClipboard(selected_text)
                        input_state.text.replaceRangeValue(start, end - start, &[_]u8{}) catch {}
                        input_state.cursor = start
                        input_state.selection_start = start
                        scene.elements.dirty.set(input_idx)
                    }
                },
                Key.v => {
                    if (modifiers.ctrl) {
                        if (platform.getClipboard(gpa)) |clipboard_text| {
                            defer gpa.free(clipboard_text)
                            if (input_state.selection_start != input_state.cursor) {
                                const start = @min(input_state.selection_start, input_state.cursor)
                                const end = @max(input_state.selection_start, input_state.cursor)
                                input_state.text.replaceRangeValue(start, end - start, &[_]u8{}) catch {}
                                input_state.cursor = start
                            }
                            input_state.text.insertSlice(
                                gpa,
                                input_state.cursor,
                                clipboard_text,
                            ) catch {}
                            input_state.cursor += @intCast(clipboard_text.len)
                            input_state.selection_start = input_state.cursor
                            scene.elements.dirty.set(input_idx)
                        }
                    }
                },
                else => {},
            }
        }
    }
    
    // ... layout, render ...
}
```

### Cursor and selection rendering

In `src/app/renderer.zig` `buildDrawList()`, for each input element with `active = true`:

- Draw the text (from `inputStateOf(idx).text`).
- Draw a selection highlight rect covering the selected range.
- Draw a cursor line (thin vertical rect) at the cursor position.

(Exact positioning is part of text layout; M4-05 adds text truncation.)

### Behavioral contract

| Event | Behavior |
|---|---|
| Input receives focus | `active = true`, cursor reset to 0 |
| Text character typed | Inserted at cursor, cursor advanced, selection cleared |
| Backspace | Deletes before cursor (or selection if present) |
| Delete | Deletes at cursor (or selection if present) |
| Left/Right arrow | Moves cursor, clears selection (unless Shift held) |
| Shift+Left/Right | Extends selection without moving primary cursor |
| Home/End | Jumps cursor to start/end of text |
| Ctrl+C | Copies selection to clipboard (R36) |
| Ctrl+X | Cuts selection to clipboard and deletes |
| Ctrl+V | Pastes clipboard text at cursor, replacing selection if present |
| Input loses focus | `active = false` |

### Module location

```
src/app/types.zig                 — InputState, Scene extensions
docs/specs/07.spec.md             — inputStateOf, setInputText, getInputText
docs/specs/07.types.zig           — InputState struct, Scene._input_state field
docs/requirements/R32_text_input_editing.md
src/app/app.zig                   — Text input event loop integration
src/app/renderer.zig              — Cursor and selection rendering
```

## Public API

New `Scene` methods and types:

```zig
pub const InputState = struct { text, cursor, selection_start, active }
pub fn inputStateOf(self: *Scene, idx: u32) *InputState
pub fn setInputText(self: *Scene, idx: u32, initial_text: []const u8) !void
pub fn getInputText(self: *Scene, idx: u32) []const u8
```

## Non-goals (DO NOT implement — INV-5.4)

- **No undo/redo** — post-v1.
- **No multi-line input** — single-line text fields only.
- **No IME (Input Method Editor)** — Latin/Cyrillic text only (INV-1.3).
- **No text truncation with ellipsis** — that is M4-05.
- **No input validation** — all text is accepted; validation is M08 schema forms.
- **No maxlength attribute** — size is unbounded; truncation is post-v1.
- **No input-change callbacks** — changing text does not fire a signal or callback; input is a UI concern (INV-3.3).
- **No autocomplete** — post-v1.
- **No multi-selection input** (contenteditable or textarea) — single-line only.

## Acceptance criteria

1. Unit tests in `src/app/input_test.zig` (or added to existing test file) cover:
   - After instantiate, input has empty text, cursor at 0, no selection.
   - Text insertion advances cursor and clears selection.
   - Backspace deletes character before cursor.
   - Delete deletes character at cursor.
   - Left/Right arrows move cursor without changing text.
   - Shift+Left/Right extends selection.
   - Ctrl+C copies selection (verified by checking clipboard via R36).
   - Ctrl+V pastes from clipboard.
   - Home/End jump cursor.
   - Input loses focus, then regains focus — state is preserved.

2. Integration test with a simple form:
   - Run the app, click an input field (focus it).
   - Type text, see it appear in the input.
   - Use arrow keys, Backspace, Delete.
   - Select text with Shift+arrows, copy/paste.

3. No memory leaks:
   - Inputs created and destroyed do not leak.
   - Large text pasting does not cause issues.
   - Cursor bounds never exceed `text.len`.

4. Checklist fully ticked.

## Open questions

None. Text input is scoped: single-line, no IME, no undo, copy/paste to system clipboard via R36.
