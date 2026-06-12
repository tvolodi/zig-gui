# Visual Diff Report — Iteration 2 — 2026-06-04

## Feature
DEMO_APP.md Section 3a — Forms screen

## Primary Screenshot
docs/.agent-context/20260604_forms_vc2/visual/iteration_2.png

## Mismatches

### Mismatch 1
- **Criterion:** "Checkbox 'Subscribe to newsletter' must be visible"
- **Observed:** No checkbox or label "Subscribe to newsletter" appears anywhere on the Forms screen. The form shows: Full name input, Email address input, Notes textarea, Country dropdown, Preferred contact section (3 bare checkboxes), Volume slider, Submit button. The "Subscribe to newsletter" checkbox is entirely absent.
- **Suspected location:** `src/demo/` (forms screen definition) — the widget for the "Subscribe to newsletter" checkbox was either never added or its conditional rendering expression evaluates to false/hidden.
- **Suggested fix:** Locate the Forms screen source file, find or add a checkbox widget with label "Subscribe to newsletter", and ensure it is unconditionally visible.

### Mismatch 2
- **Criterion:** "Radio buttons 'Email', 'Phone', 'Post' must be visible with labels"
- **Observed:** Three small unlabeled checkbox-style squares appear under the "Preferred contact" label. No text labels ("Email", "Phone", "Post") appear next to them. The widgets also appear to be checkboxes (square), not radio buttons (round), which may indicate they are the wrong widget type or the label text is not rendering.
- **Suspected location:** `src/demo/` (forms screen definition) — the label text attribute on each radio/checkbox widget may be empty, missing, or the text render path for radio labels is broken. Cross-reference with `src/09/types.zig` — the .radio_button case in emitGlyphs may not emit label text.
- **Suggested fix:** Ensure each option widget in the "Preferred contact" group has its label attribute set to "Email", "Phone", and "Post" respectively, and that the label rendering path emits those glyphs.

## UNCLEAR items
None — all interactive tests completed successfully.

## For Implementer
Fix the two mismatches above (both are part of Bug 2 — checkbox/radio labels). Do NOT change logic, data structures, or tests unless this report explicitly calls for it.

Bugs 1, 3, and 4 are confirmed FIXED:
- Bug 1 (font rendering): All text labels are correctly spelled and readable.
- Bug 3 (dropdown): Opens, allows selection, updates displayed value, closes correctly.
- Bug 4 (slider readout): Dragging slider updates the numeric readout (confirmed "50" → "81").
