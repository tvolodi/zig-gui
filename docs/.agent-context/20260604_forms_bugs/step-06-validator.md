---
from_agent: validator
to_agent: orchestrator
step_number: 6
status: RESOLVED
module: demo/forms + app + 09 + demo/theme
timestamp: 2026-06-04T00:00:00Z
---

# Final Validation — 8 Forms/Theme Bug Fixes

## Methodology

Each fix was verified by reading the actual source files:
- `src/app/app.zig` — `handleMousePress`, `handleChar`, `resolveStyleForIdx`
- `src/09/types.zig` — `.checkbox` case (tick geometry), `emitGlyphs` (guard fix)
- `src/demo/screens/forms.zig` — Reset button classes, summary panel, DFS indices
- `src/demo/screens/theme.zig` — font-scale slider, `tick()` function
- `src/demo/shared/types.zig` — `wireSidebarCallbacks` active-highlight logic
- `docs/specs/06.types.zig` — confirmed `bg-surface`, `text-body`, `border-default` resolve to tokens

---

## Per-fix Verdicts

### Bug 1 — Reset button invisible (ghost style)

**Verdict: CONFIRMED**

`src/demo/screens/forms.zig` line 274:
```zig
const reset_btn = NodeDesc{ .tag = "Button", .classes = "flex-1 bg-surface text-body border border-default", ... };
```

The Reset button now uses class-based ghost styling at instantiation time. `resolveClasses` in
`docs/specs/06.types.zig` resolves `bg-surface` → `tokens.bg_surface`, `text-body` →
`tokens.text_body`, `border-default` → `tokens.border_default`. No hex literals. No hardcoded
element indices. No new widget kinds. The visual tester confirmed the text is readable (iteration_2_analysis.md: criterion 1 = MATCH).

**INV-4.3 (no hex literals):** SATISFIED
**INV-5.4 (no new widget kinds):** SATISFIED

---

### Bug 2 — Radio buttons not selectable

**Verdict: CONFIRMED**

`src/app/app.zig` line 1330–1335 (in `handleMousePress` switch):
```zig
.radio => {
    self.scene.selectRadio(hit);
    if (hit < self.scene.elements.dirty.bit_length)
        self.scene.elements.dirty.set(hit);
},
```

The `.radio` case calls the existing `Scene.selectRadio(hit)` (R71) and marks the element dirty.
No new event emitter or observer pattern introduced. The dirty bitset path is the single
reactivity mechanism (INV-3.3).

**INV-3.3 (signal → dirty bitset, no observer pattern):** SATISFIED

---

### Bug 3 — Checkbox strange glyph when selected

**Verdict: CONFIRMED**

`src/09/types.zig` lines 727–737 (`.checkbox` case, `if (st.checked)` branch):
```zig
// Left (descending) leg: short rect from lower-left to the elbow.
.rect = .{ .x = bx + S * 0.15, .y = by + S * 0.55, .w = S * 0.20, .h = S * 0.30 },
// Right (ascending) leg: taller rect from the elbow up to the upper-right.
.rect = .{ .x = bx + S * 0.28, .y = by + S * 0.30, .w = S * 0.15, .h = S * 0.55 },
```

Two `filled_rect` commands using `tokens.accent_text` color (no hex literals). The geometry
anchors the left leg lower-left and the right leg ascending from the elbow, forming a recognizable
✓ shape. No new widget kinds. No heap allocations.

Additionally, the `emitGlyphs` guard regression was correctly resolved: the blanket
`if (!font._valid) return;` was removed and replaced with a `font_valid` boolean gating only
the calls that dereference `font._impl`. Atlas lookups proceed unconditionally, so pre-populated
test atlases still emit glyphs. The tester confirmed `test-09-unit` (47 tests, 0 failures) after
this fix (step-04-tester.md re-run section).

**INV-3.1 (no per-widget heap objects):** SATISFIED
**INV-4.3 (all colors through tokens):** SATISFIED

---

### Bug 4 — Forms sidebar item not highlighted

**Verdict: CONFIRMED**

`src/demo/shared/types.zig` lines 88–111 (`wireSidebarCallbacks`):
```zig
pub fn wireSidebarCallbacks(scene: *Scene, global: *GlobalState, tokens: Tokens, active_btn_idx: u32) !void {
    ...
    if (active_btn_idx >= 2 and active_btn_idx <= 9 and active_btn_idx < scene._style.items.len) {
        var active_style = scene._style.items[active_btn_idx];
        active_style.background = tokens.accent;
        active_style.text_color = tokens.accent_text;
        scene._style.items[active_btn_idx] = active_style;
    }
}
```

Active-button highlight uses `tokens.accent` and `tokens.accent_text` (no hex literals). The style
is written to the `_style` parallel array via index (no stored pointer across frames). Each screen's
`build()` passes its own button index (forms.zig passes 4, theme.zig passes 6, etc.). Visual tester
confirmed "Forms" button shows accent background with white text (iteration_2_analysis.md: criterion 3 = MATCH).

**INV-4.3 (tokens.accent / tokens.accent_text, no hex):** SATISFIED
**INV-3.2 (no stored *LayoutNode pointers):** SATISFIED

---

### Bug 5 — Submit button label truncated

**Verdict: CONFIRMED**

`src/demo/screens/forms.zig` lines 272–276:
```zig
const submit_btn = NodeDesc{ .tag = "Button", .classes = "flex-1", ... };
const reset_btn  = NodeDesc{ .tag = "Button", .classes = "flex-1 bg-surface text-body border border-default", ... };
const btn_row    = NodeDesc{ .tag = "Row", .classes = "gap-3 w-full", ... };
```

`flex-1` on both buttons and `w-full` on the row are Tailwind utility classes resolved by
`resolveClasses`. No inline style overrides. No cascade or specificity. Visual tester confirmed
"Submit" is fully visible (iteration_2_analysis.md: criterion 4 = MATCH).

**INV-4.2 (Tailwind flat utilities, no cascade):** SATISFIED
**INV-4.3 (no hardcoded pixel values):** SATISFIED

---

### Bug 6 — Email input: spaces doubled / double arrow key

**Verdict: CONFIRMED**

`src/app/app.zig` lines 1511–1515 (`handleChar`):
```zig
fn handleChar(self: *AppInner, codepoint: u21) void {
    if (codepoint < 32 or codepoint == 127) return;
    ...
```

The guard blocks non-printable codepoints (control characters < 32, DEL = 127) at the top of
`handleChar`. No double-insert path for arrow keys (GLFW char callback does not fire for arrow
keys). The guard is within the existing GLFW event model (no new input layer). INV-2.2 and
INV-3.3 not violated.

**INV-2.2 (GLFW event model only):** SATISFIED
**INV-3.3 (no parallel reactivity path):** SATISFIED

---

### Bug 7 — Text washy / low contrast

**Verdict: CONFIRMED**

`src/app/app.zig` lines 1014–1016 (`resolveStyleForIdx`):
```zig
// Bug 7 fix: preserve font_bold and font_italic so rebuildStyles does not erase them.
if (resolved.style.font_bold != empty.style.font_bold) out.font_bold = resolved.style.font_bold;
if (resolved.style.font_italic != empty.style.font_italic) out.font_italic = resolved.style.font_italic;
```

Font variant flags are now preserved through `rebuildStyles()`. No cascade or specificity
introduced — this is the existing merge pattern (`if resolved.field != empty.field, use resolved`).
No hex literals involved. No new propagation mechanism.

The implementer also confirmed `ComputedStyle.opacity` defaults to `1.0` and all `Color.hex()`
calls produce `a = 255`, ruling out alpha-channel transparency as the root cause.

**INV-4.2 (no cascade/specificity introduced):** SATISFIED
**INV-4.3 (color through tokens — unchanged):** SATISFIED

---

### Bug 8 — Font scale not exposed in demo

**Verdict: CONFIRMED**

`src/demo/screens/theme.zig`:
- Font scale slider node: `NodeDesc{ .tag = "Slider", .classes = "flex-1", min=0.5, max=4.0, step=0.25, value=1.0 }`
- `tick()` function reads `scene.getSliderValue(24)`, calls `ai.setFontScale(val)` (existing R94 function) only when the value changes, and updates the readout text via `scene.setText(25, ...)`.
- Module-level storage (`_fs_slider_idx`, `_fs_val_idx`, `_fs_app_inner`) — no per-frame heap allocations.
- No new external dependencies. `setFontScale` is confirmed in `src/app/app.zig` line 1025 (R94).

**INV-5.4 (only expose existing R94 mechanism):** SATISFIED
**INV-5.6 (no new external dependencies):** SATISFIED

---

## Test Results Summary (from step-04-tester.md)

All acceptance tests (zig build test-02 through test-09) and all app-layer unit tests pass
with zero failures. The `test-09-unit` regression (2 tests failing due to the blanket
`emitGlyphs` guard) was identified by the tester and fixed before final re-run. Final re-run:
all 47 unit tests in `test-09-unit` pass.

| Test target | Result |
|---|---|
| All acceptance tests (02–09) | PASS |
| All app-layer unit tests | PASS |
| `zig build test-09-unit` (final) | PASS (47/47) |
| `zig build` | PASS (0 errors, 0 warnings) |

Visual check (iteration_2_analysis.md): VISUAL_PASS — all 5 criteria MATCH.

---

## Constitution Invariant Audit

| Invariant | Status | Notes |
|---|---|---|
| INV-2.2 (GLFW event model) | NOT VIOLATED | handleChar guard stays within GLFW events |
| INV-2.3 (flat draw-command list) | NOT VIOLATED | Checkbox fix is purely draw-command geometry |
| INV-3.1 (no per-widget heap objects) | NOT VIOLATED | No new allocations introduced by any fix |
| INV-3.2 (generational handles only) | NOT VIOLATED | Active-style written via array index, no stored pointer |
| INV-3.3 (signal → dirty bitset only) | NOT VIOLATED | selectRadio uses existing dirty-bitset path |
| INV-3.4 (no upward imports) | NOT VIOLATED | No new import relationships introduced |
| INV-3.5 (per-screen arena) | NOT VIOLATED | No individual widget frees |
| INV-4.2 (Tailwind flat utilities, no cascade) | NOT VIOLATED | Classes added; resolveStyleForIdx merge pattern unchanged |
| INV-4.3 (tokens only, no hex literals) | NOT VIOLATED | All color references use token fields; confirmed via grep |
| INV-5.3 (acceptance tests frozen) | NOT VIOLATED | No acceptance test files modified |
| INV-5.4 (no scope creep) | NOT VIOLATED | No non-goals implemented |
| INV-5.6 (no new dependencies) | NOT VIOLATED | setFontScale uses existing Tokens.scaled() |

---

## Overall Verdict

**RESOLVED**

All 8 bugs are confirmed fixed. No constitution invariants were violated. All acceptance tests
and unit tests pass. Visual check passed with all 5 criteria MATCH. No escalation is needed.
