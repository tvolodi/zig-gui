# Visual Tester — Forms Screen Iteration 1 Diff Report

**Date:** 2026-06-03  
**Screenshot:** `testdata/screenshot_forms.png`  
**Build step:** `zig build run-demo -- --screenshot-frames 5 --screenshot-out testdata/screenshot_forms.png --initial-screen forms`  
**Verdict:** VISUAL_FAIL

---

## MISMATCH Criteria

### Criterion 1 — Input fields show no visible text

**Verbatim criterion:** Input fields on the Forms screen show visible text. Specifically, the "Full name", "Email address", and "Notes" input fields should display their placeholder or content text (not just an empty box with a cursor).

**Observation:** All three input widgets render as empty grey boxes. No text of any kind (placeholder or content) is visible inside the "Full name", "Email address", or "Notes" areas. The Notes textarea was declared in `forms.zig` with `value = "Type here…"` — this text is not displayed.

**Root cause analysis:**

Two separate issues:

1. **Placeholder text** — `src/09/types.zig` `buildDrawList` has no code to render a `placeholder` attribute for `.input` kind elements when `inp.text.items` is empty. The placeholder string is stored in the element store (`_text` via the markup `text=` mechanism only; `placeholder=` is an unrecognized attr stored nowhere), so no rendering path exists.

2. **Textarea `value` initialization** — `src/07/types.zig` `instantiate` processes `value=` for `.slider`, `.radio`, `.date_picker`, and `.progress_bar` kinds, but **not** for `.textarea` (or `.input`). The `notes_ta` node in `forms.zig` sets `value = "Type here…"`, but this string is silently discarded during `instantiate`. As a result `inp.text.items` is empty and the Bug 1 fix (which renders `inp.text.items`) has nothing to render.

**Suspected code locations:**

- `src/07/types.zig` ~line 1759 onwards — the `if (kind == .slider)` block for parsing `value=`. A parallel block for `kind == .textarea` (and optionally `.input`) is missing. Fix: add a block like:
  ```zig
  if (kind == .textarea or kind == .input) {
      for (desc.attrs) |attr| {
          const attr_val: []const u8 = switch (attr.value) { .literal => |s| s, .bind => continue };
          if (std.mem.eql(u8, attr.name, "value")) {
              const inp = &self._input_state.items[id.index];
              inp.text.clearRetainingCapacity();
              try inp.text.appendSlice(self.gpa, attr_val);
              inp.cursor = @intCast(attr_val.len);
          }
      }
  }
  ```
- `src/09/types.zig` ~line 682–700 — the `.input` case in `buildDrawList`. To support placeholder rendering, add a fallback before the `if (inp.text.items.len > 0)` block:
  ```zig
  const placeholder = scene.textOf(id) orelse "";
  if (inp.text.items.len == 0 and placeholder.len > 0) {
      var ph_style = style;
      ph_style.text_color = tokens.text_muted; // or similar
      try emitGlyphs(..., placeholder, ..., inp_font, ...);
  }
  ```
  Note: this requires the `placeholder=` attribute to be stored in `_text` during instantiation, which it currently is not (only `text=` is mapped to `_text`).

**Fix direction:**

1. In `src/07/types.zig` `instantiate`: add a `value=` attribute handler for `.textarea` and `.input` kinds that initializes `inp.text` (parallels the existing slider handler). This fixes the "Notes" textarea.
2. Optionally (for input placeholders): store `placeholder=` in `_text` during instantiate, then render it in a muted color when `inp.text.items` is empty.

---

## UNCLEAR Items

None — all other criteria were clearly MATCH or MISMATCH based on visual inspection.

---

## MATCH Criteria (for reference)

- **Criterion 2** — Country dropdown shows "Australia" in closed state. MATCH.
- **Criterion 3** — Volume slider shows a visible teal thumb at ~50% position. MATCH.
- **Criterion 4** — All form widgets render visibly (input boxes, dropdown, slider, checkbox, buttons). No invisible widgets. MATCH.
- **Criterion 5** — `zig build visual-check` passed with 40.6% non-zero IDAT bytes. MATCH.
