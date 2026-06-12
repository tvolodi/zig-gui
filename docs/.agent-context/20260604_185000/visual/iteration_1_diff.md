# Visual Diff Report — Iteration 1 — 2026-06-04

## Feature
Forms screen — 4 bug fixes verification (Forms screen, `src/app/` or `src/06/`)

## Screenshot
docs/.agent-context/20260604_185000/visual/iteration_1.png

---

## Mismatches

### Mismatch 1 — BUG 1: Font rendering / text content distortion
- **Criterion:** "Text on the Forms screen must sit on a shared baseline. Characters must not be vertically misaligned. All text (labels, input text, button labels) must look like normal proportional text."
- **Observed:**
  - Label "Full name" renders as **"Fuiname"** (space dropped, 'll' becomes 'ui')
  - Label "Email address" renders as **"Emailaddress"** (space dropped)
  - Placeholder text "Type here" renders as **"Typehere"** (space dropped)
  - Label "Preferred contact" renders as **"Preferredcontact"** (space dropped)
  - Dropdown option "Japan" renders as **"apan"** (leading 'J' dropped)
  - Dropdown option "Brazil" renders as **"Brail"** (wrong characters)
  - Schema form subtitle renders as a single unbroken string: **"AFormwidgetbuildfromaJSONSchemacompaeme"**
  - Schema form label "Product name" renders as **"Producname"**
- **Vertical baseline (within individual words):** characters appear at a consistent y-level; no obvious vertical jitter detected
- **"Normal proportional text":** FAILS — numerous words have incorrect characters and missing spaces
- **Suspected location:** Font atlas / glyph lookup in `src/05/` or `src/06/` — specifically the text rendering pipeline that maps character codes to glyphs. Spaces (U+0020) may be getting dropped; some codepoint mappings appear incorrect.
- **Suggested fix:** Audit the font atlas glyph map for the space character (U+0020) to ensure it is included and its advance width is non-zero. Also audit character code → glyph index mapping for glyphs that render incorrectly (U+004A 'J', U+006C 'l', U+007A 'z').

---

### Mismatch 2 — BUG 2: Checkbox and radio button widgets not rendering
- **Criterion:** "The 'Subscribe to newsletter' checkbox must be visible with its label. Radio buttons for Email, Phone, and Post must be visible with their labels."
- **Observed:**
  - No checkbox square widget is visible anywhere on the form
  - The text "Subscribe to newsletter" does not appear at all
  - No radio button circles (◯) are rendered
  - No "Email", "Phone", or "Post" option labels are visible
  - Only the text "Preferredcontact" appears as a plain text label without any associated interactive widgets
- **Suspected location:** Checkbox widget definition and radio group widget in `src/06/` or `src/app/forms.zig` (or equivalent). The widget instances may exist in the layout but their visual rendering (the checkbox square, radio circle) is returning zero-size or not drawing.
- **Suggested fix:** Check that the checkbox and radio button widgets have their `draw()` / render functions implemented and that they produce non-zero bounding boxes. Verify that any conditional rendering flag for these widgets is not accidentally `false`.

---

### Mismatch 3 — BUG 3: Dropdown selection does not update displayed value
- **Criterion:** "The Country dropdown must allow selection. Clicking an option must update the displayed value."
- **Observed:**
  - Dropdown opens correctly when the button is clicked (7 options shown)
  - Clicking on the "Germany" row did NOT change the displayed value
  - After two separate click attempts at different y-offsets (y=394, y=408 in full screen coords, both inside the dropdown list area), the dropdown closed but the displayed value remained **"Australia"**
  - The dropdown closes on click (suggesting the click is being received), but the selection state does not update
- **Suspected location:** Dropdown selection handler in `src/06/` or `src/07/` — the `onSelectItem` callback or the signal/state update that maps a clicked list item to the bound value. The click may be hitting the list but the state write is not propagating to the display.
- **Suggested fix:** Check that the dropdown item click handler writes the selected value to the bound signal/state variable, and that the display binding reads from that same variable. Verify signal dirty propagation fires a re-render after selection.

---

### Mismatch 4 — BUG 4: Volume slider readout frozen at "50"
- **Criterion:** "The Volume slider readout must update when the slider is dragged. The readout must not remain frozen at '50' after moving the handle."
- **Observed:**
  - The slider handle physically moves when dragged (confirmed: handle position changed from ~50% to ~12% of track width)
  - The readout value displayed to the right of the slider remained **"50"** throughout and after the drag
  - The handle moves visually, indicating the drag interaction is received, but the numeric value is not recomputed or the display is not re-bound
- **Suspected location:** Slider widget in `src/06/` or `src/07/` — the binding between the slider's internal drag state (normalized position → value) and the readout text node. Either the value is not being computed from the handle position, or the readout text is bound to an initial constant instead of the reactive signal.
- **Suggested fix:** Ensure the slider's `onDrag` handler computes `value = min + (handle_x / track_width) * (max - min)` and writes this to a signal. Verify the readout text is bound to that signal and that the signal's dirty flag triggers a re-render of the text node.

---

## UNCLEAR items
None — all criteria could be assessed definitively from screenshots and interaction tests.

---

## For Implementer
Fix the four mismatches above. Priority order:
1. **BUG 3** (dropdown selection) — likely a one-line signal write bug
2. **BUG 4** (slider readout) — likely a missing signal binding
3. **BUG 2** (checkbox/radio not rendering) — widgets not drawing at all
4. **BUG 1** (font/text distortion) — font atlas / glyph map issues

Do NOT change logic, data structures, or tests unless this report explicitly calls for it.

After fixes are applied, run `zig build run-demo` and hand back to the Visual Tester for Iteration 2 validation.
