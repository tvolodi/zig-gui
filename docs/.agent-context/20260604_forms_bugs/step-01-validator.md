---
from_agent: validator
to_agent: implementer
step_number: 1
status: PASS
module: demo/forms + app + 09
timestamp: 2026-06-04T00:00:00Z
---

## Summary

Analysis of 8 reported bugs on the Forms screen (Screen 3) of the Showcase demo.
All 8 bugs are in scope and can be fixed without violating any constitution invariant.
No escalation is needed. Below is the full analysis of each bug, the affected files,
the root-cause area, and the relevant invariants.

---

## Bug Analysis

### Bug 1 — Reset button invisible when not in focus

**Classification:** Rendering bug (style resolution)

**Root-cause area:**
`src/demo/screens/forms.zig`, lines 172-173.

The Reset button is declared as:
```
const reset_btn = NodeDesc{ .tag = "Button", .classes = "bg-surface", ... };
```

`defaultStyleFor(.button, tokens)` calls `theme.buttonPrimary(tokens)`, which sets
`text_color = tokens.accent_text` (white) and `background = tokens.accent` (blue).
The class `bg-surface` overrides the background to `tokens.bg_surface` (gray/white in
light mode), which is fine. BUT the `text_color` is still `accent_text` (white). On a
light-mode surface background, white text on a near-white background is invisible.

The intended "ghost" style is `buttonGhost(tokens)`, which sets `text_color =
tokens.text_body` (dark). The correct fix is either:
  - Use the existing `buttonGhost` component style (which the spec calls "ghost style").
  - Or add a class that resolves `text_color` to a visible token.

In `src/05/types.zig` → `docs/specs/05.types.zig`, `buttonGhost()` already exists and
produces `background = transparent`, `text_color = tokens.text_body`, `border_color =
tokens.border_default`, `border_width = 1`.

The problem is that `forms.zig` uses `bg-surface` as a poor approximation of "ghost"
rather than selecting `buttonGhost` style. No class currently maps to `buttonGhost`;
the resolution path (`resolveClasses` in module 06) only sets per-field overrides over
the primary button style.

**Files to investigate:**
- `src/demo/screens/forms.zig` lines 172-173 (NodeDesc for reset_btn)
- `docs/specs/05.types.zig` — `buttonGhost` function (already exists)
- `src/07/types.zig` — `defaultStyleFor` (currently always calls `buttonPrimary`)

**Constitutional invariants:** INV-4.3 (no hex literals — fix must use token references).
INV-5.4 (no scope creep — only fix the ghost style lookup, do not add a new widget kind).

---

### Bug 2 — Radio buttons not selectable

**Classification:** Input handling bug (missing mouse-press dispatch)

**Root-cause area:**
`src/app/app.zig`, `handleMousePress` function, approximately lines 1312-1346.

The `switch (kind)` in `handleMousePress` handles `.button`, `.checkbox`, `.dropdown`,
`.accordion`, and `.slider`. There is **no case for `.radio`**. When the user clicks a
radio element, `hitTestFocusable` returns its index (radio IS in `focusable_indices`,
per the AGENT_GUIDE note on focusable kinds), but the mouse-press switch falls through
to the `else => {}` branch and does nothing — no `scene.selectRadio(hit)` is called.

`Scene.selectRadio(idx)` already exists (R71). It deselects all other radios in the
same group and marks dirty. It only needs to be called from `handleMousePress`.

**Files to investigate:**
- `src/app/app.zig` — `handleMousePress`, the `switch (kind)` block (lines ~1312-1346)

**Constitutional invariants:** None violated. INV-3.3 satisfied because the fix is a
signal write (selectRadio marks dirty) not an observer pattern.

---

### Bug 3 — Checkbox: strange image/glyph when selected

**Classification:** Rendering bug (checkmark geometry)

**Root-cause area:**
`src/09/types.zig`, `buildDrawList`, `.checkbox` case, approximately lines 703-745.

The checkmark is rendered as two `filled_rect` tick strokes at:
- Vertical left leg: `{ x: bx + S*0.25, y: by + S*0.45, w: S*0.15, h: S*0.45 }`
- Horizontal right leg: `{ x: bx + S*0.25, y: by + S*0.45, w: S*0.55, h: S*0.15 }`

These two rects form an "L" shape starting at the same top-left corner. The vertical
stroke goes DOWN from the midpoint, and the horizontal stroke goes RIGHT. This produces
a bottom-left-to-right-and-down "L" that looks like a checkmark rotated incorrectly or
resembles unexpected geometry. A proper tick should have a short downward-left stroke
(the bottom-left leg) and a longer upward-right stroke (the right leg angled up).

Because the GPU renderer uses `filled_rect` (not true circles/diagonals), perfectly
diagonal strokes are not possible. However, the two-rect approximation needs its
proportions corrected so it visually reads as a tick mark: the left leg anchor should be
lower-left, and the right leg should go upper-right. The current geometry likely renders
as a flat "L" or an oversized bottom-anchored mark.

**Files to investigate:**
- `src/09/types.zig` — `.checkbox` case in `buildDrawList`, lines ~703-745 (the
  `filled_rect` tick stroke geometry: constants `S*0.25`, `S*0.45`, etc.)

**Constitutional invariants:** INV-4.3 (all colors through tokens — already satisfied).
INV-2.3 (renderer consumes flat draw-command list — this is purely the draw-command
geometry, no architecture change needed).

---

### Bug 4 — Forms sidebar item not highlighted

**Classification:** Missing demo feature / rendering omission

**Root-cause area:**
`src/demo/shared/types.zig`, `wireSidebarCallbacks` + all screen build functions.
`src/demo/shared/sidebar.zig`, `buildSidebar`.

The DEMO_APP spec (section 4) states:
> "The active sidebar item is highlighted with `tokens.accent` background and
> `tokens.accent_text` text."

Currently:
- `buildSidebar()` creates 8 identical `Button` nodes all with class `w-full` and no
  active-state visual distinction.
- `wireSidebarCallbacks()` only wires navigation callbacks; it does not set the active
  button's style.
- No screen's `build()` function sets a style override on the active sidebar button.

The fix belongs in `wireSidebarCallbacks` (or in each screen's `build` function) by
calling `scene.setStyle(active_idx, ...)` or by using `scene.setPseudo(active_idx, ...)`
after identifying which screen is currently active. The `FormsCtx` or `GlobalState`
needs to carry the active screen name so `wireSidebarCallbacks` can identify the active
button index (2–9 for screens 0–7) and apply an accent background + accent_text color.

Note: `setPseudo` alone is insufficient because `buttonPseudo` for `.focus` sets a blue
border, not an accent background. The active sidebar state is NOT a pseudo-state in the
widget sense; it requires a direct style override.

**Files to investigate:**
- `src/demo/shared/sidebar.zig` — `buildSidebar()` (line 45)
- `src/demo/shared/types.zig` — `wireSidebarCallbacks()` (line 82), `GlobalState` struct
- `src/demo/screens/forms.zig` — `build()` function (active screen = "forms" = idx 4,
  sidebar button at element index 4 in DFS)

**Constitutional invariants:** INV-4.3 (fix must use `tokens.accent` and
`tokens.accent_text`, not hex literals). INV-3.2 (do not store `*LayoutNode` across
frames — use `scene.setStyle(idx, ...)` which writes to the `_style` parallel array).
INV-5.4 (only add active-state highlight, do not add animation or transition effects).

---

### Bug 5 — Submit button label truncated

**Classification:** Layout bug (button too narrow / text overflow)

**Root-cause area:**
`src/demo/screens/forms.zig`, lines 170-175, and `src/07/types.zig` `defaultLayoutFor`.

The Submit button NodeDesc has no explicit width or padding class:
```
const submit_btn = NodeDesc{ .tag = "Button", .attrs = &submit_attrs };
```

`buttonPrimary` style sets `padding = { top: sp_sm, bottom: sp_sm, left: sp_md, right: sp_md }`.
However, the button is inside `btn_row` (`Row` with `gap-3`) alongside the Reset button.
Layout may be giving the button too little width if the row does not have a `flex-1` or
explicit `w-` on the buttons, or if the padding tokens produce insufficient visual space.

There is also a possible interaction with the `truncate` style field in `ComputedStyle`
— if `style.truncate` is accidentally set to `true` for buttons (check `defaultStyleFor`
and `resolveClasses` for the button path), text would be clipped with an ellipsis.

The check path: `src/09/types.zig` in `buildDrawList`, step 3 "Text glyphs" uses
`emitGlyphs`, which checks `style.truncate`. If `buttonPrimary` or the resolved classes
leave `truncate: true`, the "Submit" text would be clipped even with enough space.

**Files to investigate:**
- `src/demo/screens/forms.zig` — `submit_btn` / `btn_row` NodeDesc (lines 170-175)
- `src/05/types.zig` (→ `docs/specs/05.types.zig`) — `buttonPrimary` padding tokens
- `src/09/types.zig` — `emitGlyphs` / text truncation path
- `src/07/types.zig` — `defaultStyleFor(.button)` — check if `truncate` defaults to false

**Constitutional invariants:** INV-4.3 (padding values must come from `tokens.sp_md`
etc., not hardcoded pixels). INV-4.2 (layout fix via Tailwind utility classes, not
inline style overrides).

---

### Bug 6 — Email address input: spaces added, double arrow key needed

**Classification:** Input handling bug (event double-dispatch)

**Root-cause area:**
`src/app/app.zig`, `handleKey` + `handleChar` interaction.

The `.key` event fires `handleKey` which dispatches `.space` → `handleInputKey`. But
`handleInputKey` has no explicit `.space` case, so it falls through to the `else => {}`
default. Meanwhile `handleChar` receives the character codepoint `' '` (0x20) and
inserts it. If the platform fires both a `.key` event AND a `.char` event for the Space
key, the character is inserted twice — or a separate `.key` handler for space inserts
one extra space before `handleChar` fires.

The arrow key "double press needed" symptom suggests the cursor advance is being
called twice per arrow event, or the cursor position is being reset between the
`handleKey` (which moves cursor) and a subsequent `handleChar` (which inserts nothing
but resets `sel.anchor = inp.cursor`). The anchor/active sync in `handleChar` at line
1525 (`sel.anchor = inp.cursor; sel.active = inp.cursor`) runs every time a char is
inserted, but if arrow keys also advance cursor and then `handleChar` fires with
codepoint 0 or garbage — this needs to be confirmed.

The specific issue may also be that the GLFW `key` callback fires for every key repeat,
and certain keys (like arrow, space) are both in the `key` event AND generate a `char`
event with their ASCII value. The `handleChar` filter at `src/app/app.zig` line 1507
only skips if `kind != .input and kind != .textarea` — it does not skip control keys
(arrow, tab, space via GLFW may generate char events with codepoint 32 on some platforms).

**Files to investigate:**
- `src/app/app.zig` — `handleChar` (line ~1502): check if GLFW char callback fires for
  arrow keys and/or space producing duplicate insertion
- `src/app/app.zig` — `handleInputKey` (line ~1536): check the `.space` key case (or
  absence thereof) and whether it double-inserts
- `src/01/types.zig` — GLFW key callback vs. char callback binding: verify that the
  `char_callback` only fires for printable codepoints and not for arrow/space keys

**Constitutional invariants:** INV-2.2 (windowing via GLFW — fix must stay within GLFW
event model, not add a custom input layer). INV-3.3 (no parallel reactivity path).

---

### Bug 7 — Text is washy / hard to read

**Classification:** Rendering bug (token color / style resolution)

**Root-cause area:**
`src/07/types.zig` `defaultStyleFor(.text, tokens)` and `src/05/types.zig` token values.

`defaultStyleFor(.text, tokens)` returns:
```
ComputedStyle{ .text_color = tokens.text_body, .font_size = tokens.text_base }
```

In light mode, `tokens.text_body = p.gray_900` (very dark), which should be readable.
However, if `ComputedStyle.opacity` defaults to something other than `1.0`, the
`applyOpacity` call in `buildDrawList` would multiply `text_color.a` by that factor,
washing out the text.

The likely cause: `ComputedStyle` struct initialization. In `src/05/types.zig` (or
`docs/specs/05.types.zig`), if `ComputedStyle` has a field `opacity: f32 = 0` instead
of `opacity: f32 = 1.0`, ALL text rendered via `applyOpacity` would have `a = 0` and
be completely invisible. Or if `opacity` field defaults to `0.5` or similar, text would
appear washed out.

Separately, the `text_color.a` in the `Color` struct at `tokens.text_body` may have
been defined with `a = 128` or similar (non-opaque) in the palette — check
`docs/specs/05.types.zig` `Palette.default()` and the `gray_900` definition.

Also check: `emitGlyphs` in `src/09/types.zig` applies `applyOpacity(style.text_color,
effective_alpha)`. If `effective_alpha` is near zero for some elements, this explains
the symptom.

**Files to investigate:**
- `docs/specs/05.types.zig` — `ComputedStyle` struct default for `opacity` field
- `docs/specs/05.types.zig` — `Palette.default()`: `gray_900` color definition (check
  alpha channel)
- `src/09/types.zig` — `emitGlyphs` function: verify `applyOpacity` is called with the
  correct `effective_alpha` chain
- `src/07/types.zig` — `defaultStyleFor(.text, tokens)` — ensure `opacity` is not set
  to 0

**Constitutional invariants:** INV-4.3 (any color fix must go through tokens, not hex
literals in rendering code). INV-2.3 (fix is within the draw-command serializer).

---

### Bug 8 — Add a parameter to change text size (HiDPI)

**Classification:** Missing demo feature (font scale exposed in Forms/demo)

**Root-cause area:**
`src/demo/screens/forms.zig` (or more likely Screen 5 — Theme screen).

`AppInner.setFontScale(factor)` already exists and is fully implemented (R94). The
`Tokens.scaled(factor)` function also exists (M9 spec). The feature is implemented in
the framework but NOT exposed in the Forms screen demo UI.

Per DEMO_APP.md, Screen 5 (Theme) is the correct location for this control:
> "Font size: A Slider (min 0.75, max 2.0, step 0.25, initial 1.0). A live readout
> shows '1.0×'. Changing the slider calls `app.setFontScale(value)`."

The Forms screen (Screen 3) does NOT need to expose font scale itself. The requirement
is that Screen 5 (Theme) already has this slider. If Screen 5's theme.zig does not wire
the slider to `app.setFontScale`, that is the missing piece.

**Files to investigate:**
- `src/demo/screens/theme.zig` — check whether the font-scale slider is present and
  wired to `AppInner.setFontScale`
- `src/app/app.zig` — `setFontScale` (line ~1022): confirm it exists and works
- `docs/requirements/DEMO_APP.md` — Screen 5 spec (section 5a)

**Constitutional invariants:** INV-5.4 (do not add font scale to Forms screen if it is
only specified for Theme screen). INV-4.3 (slider value must call `setFontScale`, which
rebuilds tokens through the four-layer model — no direct pixel assignments).

---

## Artifacts Produced

- `docs/.agent-context/20260604_forms_bugs/step-01-validator.md` (this file)

## For Next Agent (Implementer)

Fix all 8 bugs in the order listed. Each fix is narrowly scoped:

1. **Bug 1 (Reset invisible):** In `forms.zig`, change the Reset button to use
   `buttonGhost` style. Options: add a `variant="ghost"` attr or use a class that
   overrides both `background` AND `text_color` to ghost values. Best approach: make
   `defaultStyleFor(.button)` check for a `ghost` class or introduce `buttonGhost`
   resolution in `resolveClasses`. Do NOT add new widget kinds.

2. **Bug 2 (Radio not selectable):** In `app.zig` `handleMousePress`, add a `.radio`
   case that calls `self.scene.selectRadio(hit)` and marks dirty.

3. **Bug 3 (Checkbox glyph):** In `src/09/types.zig` `.checkbox` case, correct the
   two `filled_rect` tick geometry so it reads as a recognizable tick (not an "L").

4. **Bug 4 (Sidebar not highlighted):** In `wireSidebarCallbacks` or each screen's
   `build()`, after `wireSidebarCallbacks`, set the active sidebar button (index 4 for
   Forms, mapped from the `SCREEN_NAMES` array in `sidebar.zig`) to use
   `tokens.accent` background and `tokens.accent_text` text color via `scene.setStyle`.

5. **Bug 5 (Submit truncated):** In `forms.zig`, ensure the submit button (and btn_row)
   has enough width. Likely fix: add explicit width class to button or ensure `font_size`
   and padding produce sufficient button width. Also verify `ComputedStyle.truncate`
   defaults to `false` in the button style.

6. **Bug 6 (Email spaces/double arrow):** In `app.zig`, audit `handleChar` to ensure
   it does not fire for non-printable codepoints (e.g. space via GLFW may send both key
   and char events). Add a guard: `if (codepoint < 32) return;` in `handleChar`, or
   confirm that GLFW char callback only fires for printable characters.

7. **Bug 7 (Washy text):** Check `ComputedStyle` default for `opacity` (must be 1.0).
   Check `Palette.default()` color alpha values. Fix whichever is wrong.

8. **Bug 8 (HiDPI font scale):** In `src/demo/screens/theme.zig`, verify and (if
   missing) add the font-scale slider wired to `app.setFontScale`. If the Theme screen
   already has it, this bug may be a documentation issue only.

## Files to Read / Modify for the Implementer

| File | Action |
|---|---|
| `src/demo/screens/forms.zig` | Modify: Reset button style (Bug 1), Submit button width (Bug 5) |
| `src/demo/shared/types.zig` | Modify: `wireSidebarCallbacks` — add active-button style (Bug 4) |
| `src/demo/shared/sidebar.zig` | Read: understand DFS layout and button indices (Bug 4) |
| `src/app/app.zig` | Modify: `handleMousePress` add `.radio` case (Bug 2), `handleChar` guard (Bug 6) |
| `src/09/types.zig` | Modify: `.checkbox` tick geometry (Bug 3) |
| `docs/specs/05.types.zig` | Read: `ComputedStyle` opacity default, `Palette.default()` alpha (Bug 7) |
| `src/07/types.zig` | Read: `defaultStyleFor` — verify `opacity` not set to 0 (Bug 7) |
| `src/demo/screens/theme.zig` | Read/Modify: font-scale slider wiring (Bug 8) |

## Constitution Invariants Relevant to Each Fix

| Bug | Relevant Invariants |
|---|---|
| 1 Reset invisible | INV-4.3 (tokens only, no hex), INV-5.4 (don't add new widget kinds) |
| 2 Radio not selectable | INV-3.3 (signal → dirty, no observer pattern) |
| 3 Checkbox glyph | INV-2.3 (renderer is draw-command list only), INV-4.3 (token colors) |
| 4 Sidebar highlight | INV-4.3 (accent/accent_text tokens), INV-3.2 (no stored pointers) |
| 5 Submit truncated | INV-4.3 (padding via tokens), INV-4.2 (Tailwind classes, no cascade) |
| 6 Email spaces/arrows | INV-2.2 (GLFW event model — stay within it) |
| 7 Washy text | INV-4.3 (color through tokens), INV-2.3 (fix in draw-command path) |
| 8 HiDPI font scale | INV-5.4 (only expose what R94 already implements, no new mechanism) |

## Issues / Escalation

None. All 8 bugs are within scope and fixable without constitution violations.

The most complex fix is **Bug 4 (sidebar highlight)** because it requires knowing the
active screen at `wireSidebarCallbacks` time. The `FormsCtx.global` pointer is available
in every screen's `build()` function. A `global.active_screen_name: []const u8` field
(or simply hardcoding the active index per screen) is the cleanest approach. Since each
screen's `build()` already knows which screen it IS, the implementer should hardcode the
active index in each screen's `build()` and call `scene.setStyle(active_idx, active_style)`
after `wireSidebarCallbacks`. This does not require a new architecture mechanism.

**Bug 6 (email input behavior)** may need platform-level investigation. On Windows,
GLFW's `char` callback (glfwSetCharCallback) fires only for printable codepoints and NOT
for arrow keys or control sequences. If spaces are being doubled, the likely cause is
that `.space` in `handleKey` → `handleInputKey` has an unintended branch that also
inserts a space character in addition to the `handleChar` call. Confirm whether the
`handleInputKey` `else` branch does anything for `.space` before concluding.
