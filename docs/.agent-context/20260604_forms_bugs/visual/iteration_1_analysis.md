---
from_agent: visual-tester
to_agent: orchestrator
step_number: 5
status: VISUAL_FAIL
module: demo/forms + demo/theme
timestamp: 2026-06-04T07:30:00Z
---

# Visual Analysis — Iteration 1 — Forms Screen Bug Fixes

## Build and screenshot status

- `zig build visual-check` passed: **40.7% non-zero IDAT bytes** (PASS threshold: 5%).
- Forms screen screenshot captured: `testdata/screenshot_forms_vc4.png` (most recent at 06:12).
- Theme screen screenshot: **NOT CAPTURED** — every attempt to run with `--initial-screen theme` produced a Vulkan `vkDestroySampler` error and exited without writing a PNG. This is a pre-existing teardown race in the Vulkan backend (not introduced by the fixes); it prevents the screenshot from being written. Bug 8 criterion assessed via source code review instead.
- Primary screenshot used for analysis: `testdata/screenshot_forms_vc4.png`

## Criteria Assessment

| # | Criterion | Verdict | Observation |
|---|---|---|---|
| 1 | Bug 1 — Reset button text visible (dark text on surface background) even when not focused | MISMATCH | Only the "Submit" button (teal/accent) is visible at the bottom of the form card. The Reset button — which should appear immediately to the right of Submit in the same `btn_row` — is not visible in the screenshot. Source code confirms the ghost style is applied post-instantiation at index 42, and `buttonGhost` sets `text_color = tokens.text_body` (dark gray). Despite this, "Reset" does not appear visually. |
| 2 | Bug 3 — Checkbox checkmark looks like a ✓ tick (not an "L" or random glyph) | UNCLEAR | The checkbox at index 29 ("Subscribe to newsletter") is visible in the vc4 screenshot as an unchecked square. The checkmark shape cannot be verified without a checked state. The screenshot was taken at startup; the checkbox defaults to unchecked. |
| 3 | Bug 4 — Active sidebar item has accent-colored background and light text | MATCH | "Forms" in the sidebar shows a teal/accent background with white text. All other sidebar items show the default surface background with body-colored text. |
| 4 | Bug 5 — Submit button shows the full word "Submit" without truncation | MATCH | The "Submit" button renders the full word in white text on a teal/accent background. No truncation observed. |
| 5 | Bug 7 — Body text is clearly readable (not washed out or transparent) | MATCH | Field labels ("Full name", "Email address", "Notes", "Country", "Preferred contact", "Volume") are all visible and readable. They appear in the intended `text-muted` gray style, which is consistent with the light-mode theme and confirmed readable. |
| 6 | Bug 8 — Font scale slider is present in Theme screen left panel | UNCLEAR | Theme screen screenshot could not be captured (Vulkan teardown error kills the process before `png_writer` writes the file). Source code review of `src/demo/screens/theme.zig` confirms `fs_slider` (Slider node, `min=0.5 max=4.0 step=0.25 value=1.0`) is declared as `fs_group_children[1]` and included in the left panel as `left_children[1]`. Indices wired at lines 213-215: `_fs_slider_idx = 24; _fs_val_idx = 25; _fs_app_inner = app_inner`. Cannot VISUALLY confirm. |
| 7 | Spec baseline — Forms screen renders without crashing (non-blank screenshot) | MATCH | Forms screen renders with 40.7% non-zero IDAT bytes. No crash. |
| 8 | Spec baseline — Overall layout: centered column, labeled inputs, summary panel | MISMATCH | The form card and schema form card are both present and centered. Labeled inputs are visible. However, the live summary panel ("Name: / Email: / Country: / Newsletter: / Contact: / Volume:") specified in DEMO_APP.md §3a is NOT present anywhere in the screenshot. Search of `src/demo/screens/forms.zig` confirms it was never implemented. |

## Summary

**VISUAL_FAIL** — 2 MISMATCH, 2 UNCLEAR.

MISMATCHes:
1. Reset button text not visible (Bug 1 fix may not be working visually)
2. Summary panel absent (spec baseline: layout completeness)

UNCLEARs:
1. Checkbox checkmark shape (cannot verify without a checked checkbox in the screenshot)
2. Font scale slider in theme screen (screenshot capture failing for theme screen)
