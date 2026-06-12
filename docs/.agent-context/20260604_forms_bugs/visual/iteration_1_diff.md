---
from_agent: visual-tester
to_agent: implementer
step_number: 5
status: VISUAL_FAIL
module: demo/forms + demo/theme
timestamp: 2026-06-04T07:30:00Z
---

# Visual Diff Report — Iteration 1 — Forms Screen Bug Fixes

## Screenshot path
`testdata/screenshot_forms_vc4.png` (captured at 2026-06-04 06:12)

---

## MISMATCH Items

### MISMATCH 1 — Reset button not visible

**Criterion (verbatim):**
> The Reset button text is visible (dark text on surface background) even when not focused

**What was observed:**
At the bottom of the form card, only the "Submit" button (teal/accent background, white text) is visible. No "Reset" button appears to the right of Submit. The `btn_row` should contain both Submit (index 41, `flex-1`) and Reset (index 42, `flex-1`) sharing the row width equally. Neither a transparent-background "Reset" box nor any dark "Reset" text is visible.

**Suspected code location:**
`src/demo/screens/forms.zig` lines 232-236:
```zig
if (42 < scene._style.items.len) {
    scene._style.items[42] = mod05.buttonGhost(tokens);
}
```

The ghost style (`background = transparent`, `text_color = tokens.text_body`) should make "Reset" text dark gray on the white card background. The silent guard `if (42 < scene._style.items.len)` may be failing (element count < 43), so the ghost style is never applied, leaving the Reset button with the default primary button style: `background = transparent` NOT applied, `text_color = tokens.accent_text` (white), which is invisible on the near-white card background.

**Suggested fix direction:**
1. Add a debug check: print `scene._style.items.len` after instantiation to confirm index 42 is valid.
2. If the guard fails: the DFS count in the comment may be wrong. Trace the actual DFS order by counting element indices from the scene root.
3. Alternatively, approach differently: instead of post-instantiation override, add a `ghost` class or `variant="ghost"` attribute to the Reset button `NodeDesc` and handle it in `resolveClasses` or `defaultStyleFor`. This avoids the fragile index-based override.
4. If the guard passes but text is still invisible: verify `tokens.text_body` alpha is 255 in the test environment. Confirm `buildDrawList` renders ghost button text using `style.text_color` (not hardcoded `tokens.accent_text`).

---

### MISMATCH 2 — Summary panel absent

**Criterion (verbatim):**
> Overall layout matches the spec: centered column, labeled inputs, summary panel

**What was observed:**
The live summary panel described in `docs/requirements/DEMO_APP.md` §3a is completely absent from the rendered forms screen. The spec requires:
```
Name: <current value>
Email: <current value>
Country: <selected label>
Newsletter: Yes / No
Contact: <selected radio>
Volume: <slider value>
```
This panel should appear below the button row in a gray card. Searching `src/demo/screens/forms.zig` shows no implementation of this panel.

**Suspected code location:**
`src/demo/screens/forms.zig` — feature was never implemented. The file ends after `validate_btn` in the schema section with no summary card NodeDesc.

**Suggested fix direction:**
Add a summary card after the btn_row (still inside the form card, or as a sibling below the form card). The card should use `text-sm` class with six `Text` elements showing the live values. Updating them reactively per keystroke is a stretch goal; static values showing current state at render time is sufficient for the visual criterion to pass.

---

## UNCLEAR Items

### UNCLEAR 1 — Checkbox checkmark shape

**Criterion (verbatim):**
> The checkbox checkmark looks like a ✓ tick, not an "L" or random glyph

**Why unclear:**
The checkbox (index 29, "Subscribe to newsletter") renders as an unchecked box at startup. The checkmark shape is only visible when the checkbox is in the `checked` state. No checked checkbox is visible in any available screenshot.

**How to verify:**
Run the demo, click the "Subscribe to newsletter" checkbox to check it, then take a screenshot. Alternatively, set `scene._checkbox_state.items[29].checked = true` after instantiation in `forms.zig` to show it pre-checked.

---

### UNCLEAR 2 — Font scale slider in Theme screen

**Criterion (verbatim):**
> A Font scale slider is present in the Theme screen's left panel

**Why unclear:**
Every attempt to capture a screenshot of the Theme screen resulted in a Vulkan `vkDestroySampler` error:
```
vkDestroySampler(): sampler can't be called on VkSampler 0x... that is currently in use by VkDescriptorSet 0x...
```
The process exits before writing the PNG. This is a pre-existing GPU teardown race not introduced by the current fixes.

**Source code evidence that the slider exists:**
`src/demo/screens/theme.zig` lines 126-138 define `fs_slider` (Slider, flex-1, min=0.5, max=4.0, step=0.25, value=1.0) and `fs_group` containing it. Lines 213-215 wire `_fs_slider_idx = 24`.

**How to verify:**
Fix the Vulkan sampler teardown race so that the theme screen screenshot can be captured. One approach: add a `vkQueueWaitIdle` call in `VulkanBackend.deinit` before `vkDestroySampler`. Alternatively, manually navigate to the Theme screen in an interactive run and visually inspect.

---

## Non-MISMATCH observations (informational)

- Checkbox for "In stock" in the schema form section also has no visible label text (vc3 shows only a box, vc4 shows "In stock" label). This improved between iterations but is noted.
- The "Validate" button renders as a full-width teal bar that spans the entire content width — much wider than Submit. This may be intentional (no `flex-1` constraint vs. the narrower Submit), but looks visually unpolished.
- Radio button labels (Email, Phone, Post) are visible and readable in vc4 (Bug 2 fix result is visually confirmed).
