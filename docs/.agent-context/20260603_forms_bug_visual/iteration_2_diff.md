# Visual Validation Iteration 2 — Forms Screen Diff Report

Date: 2026-06-04
Build: `zig build visual-check` — PASS, 40.6% non-zero IDAT
Screen: Forms (captured with `--initial-screen forms`)

---

## STEP A: PASS — build succeeded, 40.6% non-zero IDAT

## STEP B: Forms screen visible

---

## Criterion Results

### Criterion 1 (input text with value= visible): MISMATCH

**Observation:** The Notes textarea field is rendered with its background box visible, but contains no visible text. The `value="Type here\xe2\x80\xa6"` attribute should display "Type here…" in the textarea. The text buffer (`InputState.text.items`) is populated by `instantiateNode` (src/07/types.zig lines 1741-1755), but `TextareaState.line_starts` is never rebuilt after the text is appended during instantiation.

The rendering path in `buildDrawList` (src/09/types.zig line 491-492) gates all text output on `ts.line_starts.items.len > 0`. Since `line_starts` remains `.empty` after `instantiateNode`, the text is silently suppressed even though the bytes exist in `inp.text.items`.

**Root cause:** `instantiateNode` must call a `rebuildLineStarts` helper (or equivalent) after appending the value= text, so that the textarea renderer finds at least one line-start entry (byte offset 0 for line 0).

**Fields with no value= attribute** (Full name, Email address): Correctly empty — acceptable.

---

### Criterion 2 (dropdown selected text): MATCH

**Observation:** The Country dropdown shows selected text "Australia" (rendered with minor glyph compression as "us|ralia" but recognizable). The selected option label is present in the closed-state dropdown widget.

---

### Criterion 3 (slider thumb): MATCH

**Observation:** The Volume slider has a clearly visible teal/green circular thumb positioned at approximately 55% along the track (corresponding to value=50 out of 0-100 range). The "50" numeric label is correctly displayed to the right of the slider.

---

### Criterion 4 (no invisible widgets): MATCH

**Observation:** All form widgets are rendered:
- Full name input (empty, correct — no value= attr)
- Email address input (empty, correct — no value= attr)
- Notes textarea (box visible, but text missing — see Criterion 1)
- Country dropdown (visible with selected label)
- Volume slider (track and thumb visible)
- Submit button (teal, visible)
- Reset button (lighter, visible)
- Schema section: Product name input, Price input, In stock checkbox, Validate button — all visible

---

### Criterion 5 (non-blank): MATCH

40.6% non-zero IDAT bytes — well above 5% threshold.

---

## VERDICT: VISUAL_FAIL

**Failing criterion:** Criterion 1 — input text with value= visible.

**Specific failure:** `TextareaState.line_starts` is not rebuilt after `instantiateNode` populates `InputState.text` from the `value=` attribute. The textarea renders no text even though the buffer contains "Type here…".

## Fix Required

In `src/07/types.zig`, after the block at lines 1741-1756 that appends to `inp.text`, add logic to rebuild `line_starts` for the textarea case. Something like:

```zig
// After populating inp.text, rebuild line_starts for textarea.
if (kind == .textarea) {
    var ts = &self._textarea_state.items[id.index];
    ts.line_starts.clearRetainingCapacity();
    try ts.line_starts.append(self.gpa, 0); // line 0 starts at byte 0
    for (inp.text.items, 0..) |byte, i| {
        if (byte == '\n') {
            try ts.line_starts.append(self.gpa, @intCast(i + 1));
        }
    }
}
```

This ensures the renderer sees at least one line entry and renders the initial value text.
