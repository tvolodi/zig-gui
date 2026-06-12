---
from_agent: implementer
to_agent: visual-tester
step_number: 6
status: FIX_APPLIED
module: demo/forms
timestamp: 2026-06-04T08:00:00Z
---

# Fix Note — Iteration 1 — Forms Screen Visual Mismatches

## Summary

Two mismatches were fixed in `src/demo/screens/forms.zig`:

1. Reset button invisible → ghost style applied via Tailwind classes at instantiation time
2. Summary panel absent → added a 7-element Card below the button row with live per-frame updates

---

## Mismatch 1 — Reset button not visible

### Root cause

The post-instantiation override `scene._style.items[42] = mod05.buttonGhost(tokens)` was
structurally correct (index 42 IS valid — the scene has 64+ elements), but fragile and
redundant: every time `rebuildStyles()` is called (on theme change), it re-resolves
element 42 from its stored class string `"flex-1"`, which produces `buttonPrimary` style
again, overwriting the ghost override. On the initial render the override does apply, but
on any theme or font-scale change it is silently lost.

More critically, the class `bg-transparent` cannot override the button's `accent` background
via the standard class-merge system, because `transparent` equals the empty-class default for
the `background` field, so `colorEq(resolved, empty)` is true and the base is kept.

### Fix applied

**File:** `src/demo/screens/forms.zig`

**Lines changed:** ~274 (Reset button NodeDesc) and removed lines ~234-236

Changed the Reset button's class string from `"flex-1"` to
`"flex-1 bg-surface text-body border border-default"`.

- `bg-surface` → `tokens.bg_surface` (light gray in light theme), which IS different from
  the empty-class default (`transparent`), so the merge rule correctly overrides the base
  `buttonPrimary` accent background.
- `text-body` → `tokens.text_body` (near-black in light theme) — dark readable text.
- `border border-default` → 1 px border in `tokens.border_default`.

These classes are stored in `_classes[42]` at instantiation, so `rebuildStyles()` on theme
change also produces the ghost appearance (no more silent loss on theme swap).

The fragile post-instantiation block:
```zig
if (42 < scene._style.items.len) {
    scene._style.items[42] = mod05.buttonGhost(tokens);
}
```
was removed entirely.

---

## Mismatch 2 — Summary panel absent

### Root cause

The summary panel described in `docs/requirements/DEMO_APP.md` §3a was never implemented.
The `build` function ended after `btn_row` with no summary card NodeDesc.

### Fix applied

**File:** `src/demo/screens/forms.zig`

**Lines changed:** ~282-398 (new NodeDescs, new form_children array, new per-frame logic)

#### NodeDesc additions

Added `summary_card` as the 9th child of `form_card`:

```
summary_card  Card  (class: "p-3 gap-1 bg-canvas")
  sum_name_txt       Text  text-sm  "Name: "
  sum_email_txt      Text  text-sm  "Email: "
  sum_country_txt    Text  text-sm  "Country: "
  sum_newsletter_txt Text  text-sm  "Newsletter: No"
  sum_contact_txt    Text  text-sm  "Contact: —"
  sum_volume_txt     Text  text-sm  "Volume: 50"
```

`bg-canvas` (light off-white) gives the card a visually distinct gray tone relative to
the form card's `bg-surface`.

`form_children` changed from `[8]NodeDesc` to `[9]NodeDesc`.

#### DFS index assignments (post-instantiate)

The summary card lands at DFS index 43 (btn_row=40, submit_btn=41, reset_btn=42,
summary_card=43). The 6 Text children occupy indices 44-49:

| Index | Element           |
|-------|-------------------|
| 44    | sum_name_txt      |
| 45    | sum_email_txt     |
| 46    | sum_country_txt   |
| 47    | sum_newsletter_txt|
| 48    | sum_contact_txt   |
| 49    | sum_volume_txt    |

These are stored in module-level `u32` variables set at the end of `build()`.

Source widget indices also recorded:
- name_input=19, email_input=22, country_dd=28, checkbox=29,
  r_email=32, r_phone=33, r_post=34

#### Per-frame update (tick function)

The existing `tick(scene)` function was extended to update all 6 summary Text elements
each frame after the volume readout. No heap allocations — 6 module-level stack buffers
(`[48]u8`, `[24]u8`, `[32]u8`) are used with `std.fmt.bufPrint`.

Guard: `if (_sum_name_idx == 0) return;` prevents any update when the forms screen is not
active (other screens reset the scene but do not re-run `build()`).

---

## Build results

```
zig build             → clean (0 errors, 0 warnings)
zig build test-09-unit → 47 passing, 0 failing
zig build test-app     → exit 0 (pre-existing EventQueue overflow warn is unrelated)
```

---

## Files changed

- `src/demo/screens/forms.zig` — only file modified
