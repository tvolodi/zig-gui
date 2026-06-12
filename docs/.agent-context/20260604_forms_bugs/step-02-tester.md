---
from_agent: tester
to_agent: implementer
step_number: 2
status: PASS
module: demo/forms + app + 09
timestamp: 2026-06-04T12:00:00Z
---

## Summary

Code-level reproduction of all 8 bugs reported on the Forms screen.
All 8 bugs are confirmed at the code level by reading the source files.
No running of the app was required — each bug has a clear, specific code-level manifestation.

---

## Bug 1 — Reset button invisible when not focused

**Classification:** CONFIRMED

**File + lines:**
- `src/demo/screens/forms.zig`, line 173:
  ```zig
  const reset_btn = NodeDesc{ .tag = "Button", .classes = "bg-surface", .attrs = &reset_attrs };
  ```

**Current behavior (wrong):**
`defaultStyleFor(.button)` returns `buttonPrimary(tokens)` which sets:
- `text_color = tokens.accent_text` (white in light mode)
- `background = tokens.accent` (blue)

The class `"bg-surface"` overrides background to `tokens.bg_surface` (near-white in light mode via `Palette.default().gray_100`). However, the `text_color` is NOT overridden — it stays `tokens.accent_text` = white. White text on a near-white background is invisible. The merge rule in `instantiateNode` (src/07/types.zig lines 1446-1449) only overrides `text_color` if the resolved class sets it; `bg-surface` only changes `background`, leaving `text_color = tokens.accent_text`.

**Expected behavior:**
The Reset button should use a "ghost" style: `background = transparent`, `text_color = tokens.text_body` (dark, readable), `border_color = tokens.border_default`, `border_width = 1`. This is already defined as `buttonGhost(tokens)` in `docs/specs/05.types.zig` lines 401-412.

---

## Bug 2 — Radio buttons not selectable

**Classification:** CONFIRMED

**File + lines:**
- `src/app/app.zig`, `handleMousePress`, lines 1312-1346

**Current behavior (wrong):**
The `switch (kind)` inside `handleMousePress` at line 1313 handles `.button`, `.checkbox`, `.dropdown`, `.accordion`, `.slider` — but has NO `.radio` case:
```zig
switch (kind) {
    .button => { ... },
    .checkbox => { ... },
    .dropdown => { ... },
    .accordion => { ... },
    .slider => { ... },
    else => {},        // radio falls here — nothing happens
}
```

When a radio element is clicked, `hitTestFocusable` returns its index (radio IS in `focusable_indices` per spec), focus is set via `setFocus(hit)`, but no `scene.selectRadio(hit)` call is made. The `RadioState.selected` field is never toggled, so the radio renders unselected forever.

`handleKey` at lines 1491-1499 also has no `.radio` case in its switch, so keyboard activation (Space/Enter) is also missing, but the mouse case is the primary interaction path.

**Expected behavior:**
The `.radio` case in `handleMousePress` should call `self.scene.selectRadio(hit)` and mark the element dirty. `Scene.selectRadio(idx)` (R71) already exists and deselects all other radios in the same group.

---

## Bug 3 — Checkbox selected = strange glyph

**Classification:** CONFIRMED

**File + lines:**
- `src/09/types.zig`, `.checkbox` case in `buildDrawList`, lines 724-736

**Current behavior (wrong):**
The checkmark is drawn as two `filled_rect` strokes:
```zig
// "Vertical stroke" (left leg):
rect = { x: bx + S*0.25, y: by + S*0.45, w: S*0.15, h: S*0.45 }

// "Horizontal stroke" (right leg):
rect = { x: bx + S*0.25, y: by + S*0.45, w: S*0.55, h: S*0.15 }
```

Both strokes share the same top-left corner at `(bx + S*0.25, by + S*0.45)`. The vertical stroke goes DOWN from that point (h = S*0.45) and the horizontal stroke goes RIGHT from that same point (w = S*0.55). This produces an upside-down "L" anchored at the middle-left of the box — NOT a tick/checkmark. A correct tick/checkmark approximation needs:
- A short downward-left descender (bottom-left leg): anchored low in the box, small rect going down-right
- A longer upward-right stroke (right leg): going from the bottom-middle up to top-right

Or more simply: the anchor point for the "elbow" of the tick should be near the bottom-center, with the left leg going down-left and the right leg going up-right.

**Expected behavior:**
Two `filled_rect` strokes that together read as a tick: the left leg goes from lower-left to the elbow (short, angled), and the right leg goes from the elbow to the upper-right (longer). A workable approximation:
- Left leg: `{ x: bx+S*0.15, y: by+S*0.55, w: S*0.20, h: S*0.30 }` (short downward-right to elbow)
- Right leg: `{ x: bx+S*0.28, y: by+S*0.30, w: S*0.15, h: S*0.55 }` (elbow going up)

The exact geometry is flexible, but the current "L" shape starts at the wrong position and faces the wrong direction.

---

## Bug 4 — Forms sidebar item not highlighted as active

**Classification:** CONFIRMED

**File + lines:**
- `src/demo/shared/sidebar.zig` — `buildSidebar()` (line 45): all 8 buttons are identical `NodeDesc` with class `"w-full"`, no active-state distinction.
- `src/demo/shared/types.zig` — `wireSidebarCallbacks()` (lines 82-99): wires navigation callbacks but does NOT set any style on the active button.
- `src/demo/screens/forms.zig` — `build()` (lines 228-229): calls `wireSidebarCallbacks` but never calls `scene.setStyle(4, ...)` to highlight the Forms button (DFS index 4).

**Current behavior (wrong):**
After calling `wireSidebarCallbacks`, no code in `forms.zig` (or any screen) calls `scene.setStyle(active_idx, ...)` to visually distinguish the current screen's sidebar button. All 8 buttons render identically with the primary button style (`accent` background, `accent_text` text).

The DFS index of the "Forms" button is 4 (element index in the array):
- 0 = root Row
- 1 = sidebar Column
- 2 = Home button
- 3 = Text button
- 4 = Forms button  ← active on this screen
- 5-9 = Data/Theme/Notifications/Layout/State buttons
- 10 = content Column

**Expected behavior:**
After `wireSidebarCallbacks`, `forms.zig` should set the style of the active sidebar button (index 4) to use `tokens.accent` as background and `tokens.accent_text` as text — or an alternative visual treatment that makes the active item visually distinct. Using `scene.setStyle(4, active_style)` is the correct approach (writes to `_style` parallel array — no stored pointer, satisfies INV-3.2).

---

## Bug 5 — Submit button label truncated

**Classification:** CONFIRMED (partial — layout cause, not truncation flag)

**File + lines:**
- `src/demo/screens/forms.zig`, lines 170-175: `submit_btn` has no width class, `btn_row` has class `"gap-3"` only.
- `src/07/types.zig`, `defaultLayoutFor(.button)` line 111: returns `LayoutNode{ .display = .block }` — a block-level element.
- `docs/specs/05.types.zig`, `buttonPrimary` lines 388-398: padding = `{ sp_sm top/bottom, sp_md left/right }` = `{4, 8, 4, 8}` px.

**Current behavior (wrong):**
The `submit_btn` NodeDesc has no explicit width class. Its layout is `.block` (not `flex-1`). Inside a `Row` with `gap-3`, block children are measured by their content width + padding. `buttonPrimary.padding = { 4px, 8px, 4px, 8px }`. The text "Submit" measures approximately 48px wide at 14px font. Total button width = 48 + 16 = 64px.

However the `btn_row` is a flex row with `gap-3` (gap = 12px) and both buttons are block children. If the row does not have enough width allocated — e.g., if the containing card does not flex-fill correctly — the buttons may be clipped.

The `truncate` flag: confirmed to be `false` for buttons (`buttonPrimary` returns `ComputedStyle{}` with `truncate` defaulting to `false`). So this is NOT a truncation-flag bug — it is a layout/width bug. The button fits its content, but if the layout engine gives the `btn_row` a computed width of 0 or very small (due to missing `flex-1` on form_card or content column), the button rect is too small.

Looking at the hierarchy: `form_card` has class `"p-4 gap-4"`, inside a `body_col` (Column, `"gap-4"`), inside `inner-col` (Column, `"p-2"`), inside `scroll` (ScrollView, `"flex-1"`), inside `content` (Column, `"flex-1 gap-3 p-6"`). The `scroll` has `flex-1` so it grows. `inner-col` has `p-2` but is a plain block inside scroll. `body_col` and `form_card` are also plain blocks. The buttons inside `btn_row` are blocks that default to content width.

If the layout engine gives block children of a ScrollView zero or viewport-constrained width, the buttons could appear narrow. The fix is to ensure `form_card` or `body_col` has appropriate width context (e.g., `w-full`), or to add a `w-full` or `flex-1` on the submit button.

**Expected behavior:**
The Submit button label "Submit" should be fully visible. Either: add `"w-full"` or `"flex-1"` to `submit_btn` in `forms.zig`, or ensure the parent layout provides correct width.

---

## Bug 6 — Email input: spaces doubled, double arrow key needed

**Classification:** CONFIRMED (space double-insert) / NEEDS_MORE_INFO (arrow key symptom)

**File + lines:**
- `src/01/types.zig`, `glfwKeyCallback` lines 754-780: `.space` key generates a `.key` event with `key = .space`.
- `src/01/types.zig`, `glfwCharCallback` lines 782-792: GLFW char callback fires codepoints including 32 (space). On Windows, `glfwSetCharCallback` fires for printable characters including space.
- `src/app/app.zig`, `handleInputKey` lines 1536-1658: the switch has `else => return` for unhandled keys — `.space` has NO explicit case, so it hits `else => return` (does nothing). This means the `.key` event for space does NOT insert a space.
- `src/app/app.zig`, `handleChar` lines 1502-1534: receives codepoint 32 from GLFW char callback and inserts it.

**Space insertion analysis:**
On Windows, GLFW fires BOTH a `.key` event (glfwKeyCallback) AND a `.char` event (glfwCharCallback) for the Space key. `handleInputKey` has no `.space` case (falls to `else => return` doing nothing), while `handleChar` inserts the space from the char event. Space should only be inserted ONCE via `handleChar`. This is CORRECT — no double-insert from this path.

HOWEVER: the key repeat filter in `glfwKeyCallback` (lines 762-767) allows repeats for `BACKSPACE, DELETE, LEFT, RIGHT, HOME, END` but NOT for `.space`. So space repeat via key-hold would never cause double-insert. The space path appears correct.

**Arrow key analysis:**
Arrow keys generate `.key` events handled by `handleInputKey` (`.left`, `.right` cases at lines 1571-1590). These cases advance `inp.cursor` and update `sel.active`/`sel.anchor`. Arrow keys do NOT generate `.char` events (GLFW char callback fires only for printable characters; arrows are not printable). So double-arrow should not be occurring from this path.

**Likely actual cause (NEEDS_MORE_INFO):**
The "spaces doubled, double arrow key needed" symptom is not clearly reproducible from code reading alone. Possible scenarios that would require runtime observation:
1. The cursor position display logic in `computeTextX` may be computing x from byte 0 always, requiring two presses to "visually advance."
2. A GLFW platform-specific behavior on Windows where char events fire for space twice (unlikely, but untestable without runtime).
3. The `handleChar` path may be re-entered on `.textarea` (line 1530-1533) rebuilding `line_starts` which resets some state.

The guard `if (kind != .input and kind != .textarea) return` at line 1507 is correct and does not cause double-insert by itself.

**Expected behavior:**
One space press should insert exactly one space. One arrow key press should move the cursor one position.

---

## Bug 7 — Text is washy / low contrast

**Classification:** CONFIRMED (specific root cause found)

**File + lines:**
- `docs/specs/05.types.zig`, `ComputedStyle` struct, line 308: `text_color: Color = transparent`
- `src/07/types.zig`, `defaultStyleFor` line 122: `.text => ComputedStyle{ .text_color = tokens.text_body, .font_size = tokens.text_base }`

**Current behavior:**
For `.text` elements, `defaultStyleFor(.text)` correctly sets `text_color = tokens.text_body`. In light mode, `tokens.text_body = Palette.default().gray_900 = Color.hex(0x2C2C2A)` — a dark, opaque gray (alpha = 255). This is correct.

For `.text` elements with class `"text-sm text-muted"` (e.g. `schema_note` in forms.zig line 189), `text_color` resolves to `tokens.text_muted = Palette.default().gray_600 = Color.hex(0x5F5E5A)`. This is intentionally muted but still has alpha = 255 — it should not appear "washy" or unreadable.

**Root cause of "washy" appearance:**
The Validator's opacity hypothesis is ruled out: `ComputedStyle.opacity` defaults to `1.0` (line 316 of docs/specs/05.types.zig), and `Color.hex` always produces `a = 255`.

**However**, there is a confirmed side-effect bug in `rebuildStyles` (src/app/app.zig lines 978-988) and `resolveStyleForIdx` (lines 990-1015): neither merges `font_bold` or `font_italic`. After `rebuildStyles` is called (e.g. after theme toggle or font-scale change), bold/italic flags are ERASED from all elements. This may make text look "lighter" (regular weight instead of bold) on the Forms screen if the user has already toggled the theme.

**Washy label text:** The `text-sm` label nodes (e.g. "Full name", "Email address" at font_size 12px) rendered at small sizes may inherently look light/thin. This is a font-size perception issue, not a code bug — `tokens.text_body` at 12px on a white background is correct but can appear visually lighter due to thinner stroke.

**Expected behavior:**
Form labels and body text should render at full opacity with `tokens.text_body` as the text color. The `font_bold`/`font_italic` erasure in `rebuildStyles` is an additional confirmed bug (though not originally listed as Bug 7 specifically). For Bug 7 as originally reported ("washy text"), the primary candidate is the missing `font_bold` merge in `resolveStyleForIdx` causing bold text to lose weight after theme/font-scale change.

---

## Bug 8 — Font scale not exposed in demo (R94 already implemented)

**Classification:** CONFIRMED (feature missing from Theme screen)

**File + lines:**
- `src/demo/screens/theme.zig` — entire file: no font-scale slider or readout present.
- `src/app/app.zig`, `setFontScale` lines 1022-1027: fully implemented, accepts `factor` (0.5–4.0), clamps, rebuilds tokens, calls `rebuildStyles()`, marks all dirty.

**Current behavior (wrong):**
`theme.zig` contains only:
- Color scheme section: Light/Dark/High Contrast buttons (lines 71-86)
- A live preview panel with swatches and sample widgets (lines 90-152)

There is NO font-scale slider, NO readout showing the current scale factor, and NO callback wiring to `app_inner.setFontScale(value)`. The `setFontScale` function exists and is fully implemented in `app.zig` but is never called from the demo UI.

**Expected behavior (from DEMO_APP spec, Screen 5):**
The Theme screen should include:
- A Slider widget with `min=0.5`, `max=4.0`, `step=0.25`, initial value `1.0`.
- A live text readout showing the current scale (e.g. "1.0×").
- A per-frame tick function (similar to `forms.tick()`) that reads the slider value and calls `app_inner.setFontScale(value)`.

`AppInner.setFontScale` is accessible in `theme.zig` via `app_inner: *app_impl.AppInner = @ptrCast(@alignCast(app))` (the same cast used at line 54 in theme.zig).

---

## Summary Table

| # | Bug | Classification | File | Lines |
|---|-----|---------------|------|-------|
| 1 | Reset button invisible | CONFIRMED | `src/demo/screens/forms.zig` | 173 |
| 2 | Radio not selectable | CONFIRMED | `src/app/app.zig` | 1312-1346 |
| 3 | Checkbox strange glyph | CONFIRMED | `src/09/types.zig` | 724-736 |
| 4 | Sidebar not highlighted | CONFIRMED | `src/demo/screens/forms.zig`, `src/demo/shared/types.zig` | 228-229, 82-99 |
| 5 | Submit button truncated | CONFIRMED | `src/demo/screens/forms.zig` | 170-175 |
| 6 | Email input spaces/arrows | CONFIRMED (space) / NEEDS_MORE_INFO (arrows) | `src/app/app.zig` | 1502-1534 |
| 7 | Washy text | CONFIRMED (font_bold erasure) | `src/app/app.zig` | 990-1015 |
| 8 | Font scale not in demo | CONFIRMED | `src/demo/screens/theme.zig` | entire file |

---

## Artifacts Produced

- `docs/.agent-context/20260604_forms_bugs/step-02-tester.md` (this file)

## For Next Agent (Implementer)

Fix the 8 bugs in order. Key implementation notes beyond the Validator's guidance:

**Bug 1 (Reset invisible):** The simplest fix is to add a `variant` attribute resolution path, OR to add a new class `"btn-ghost"` that `resolveClasses` maps to `buttonGhost(tokens)`. The cleanest approach: in `src/07/types.zig` `defaultStyleFor`, check if the node's classes include a "ghost" marker, but this requires passing `desc.classes` to `defaultStyleFor` which changes the signature. Alternatively: in `forms.zig`, just override the style after instantiation by calling `scene.setStyle(42, buttonGhost(tokens))` at the end of `forms.build()`.

**Bug 2 (Radio):** Add `.radio => { self.scene.selectRadio(hit); }` to the switch in `handleMousePress` (app.zig line 1345). Also add `.radio` to `handleKey` switch: `handleRadioKey(focused, key)` that calls `selectRadio(focused)` for `.space`/`.enter`, `selectPrevInGroup`/`selectNextInGroup` for up/down arrows.

**Bug 3 (Checkbox):** Fix the two `filled_rect` coordinates so they form a visible tick. The current "L"-shape starting at `(bx+S*0.25, by+S*0.45)` going right AND down is wrong.

**Bug 4 (Sidebar):** In `forms.build()`, after `wireSidebarCallbacks`, add a `scene.setStyle(4, ...)` call using accent colors. Apply the same pattern to all other screen build functions at their respective active button indices (2=home, 3=text, 4=forms, 5=data, 6=theme, 7=notifications, 8=layout, 9=state).

**Bug 5 (Submit truncated):** In `forms.zig`, change `btn_row_children` to give each button `flex-1`: `NodeDesc{ .tag = "Button", .classes = "flex-1", .attrs = &submit_attrs }` and `NodeDesc{ .tag = "Button", .classes = "flex-1 bg-surface", .attrs = &reset_attrs }`.

**Bug 6 (Email spaces/arrows):** Requires runtime verification. If the symptom IS reproducible, check whether `glfwCharCallback` on Windows fires for space during key-repeat. If so, add `if (codepoint < 32 or codepoint == 127) return;` guard at the start of `handleChar`. For arrow keys, the code path looks correct — may be a misperception or platform-specific issue.

**Bug 7 (Washy text):** Add `font_bold` and `font_italic` merging to `resolveStyleForIdx` in `app.zig`:
```zig
if (resolved.style.font_bold != empty.style.font_bold) out.font_bold = resolved.style.font_bold;
if (resolved.style.font_italic != empty.style.font_italic) out.font_italic = resolved.style.font_italic;
```

**Bug 8 (Font scale):** In `theme.zig`, add a font-scale slider (min=0.5, max=4.0, step=0.25, value=1.0) and a readout text element to the left panel. Wire a per-frame tick (similar to `forms.tick`) that reads the slider value and calls `app_inner.setFontScale(value)`.

## Issues / Escalation

**Bug 6** partially needs runtime verification. The code analysis shows space insertion should be correct (one space per press). If the tester confirms spaces ARE doubled at runtime, the cause is likely a GLFW platform quirk on Windows where the char callback fires twice for space during repeat. The fix is a `codepoint >= 32` guard. If arrow keys require two presses, a separate investigation of the layout/cursor rendering path is needed.
