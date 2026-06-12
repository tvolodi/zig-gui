# Validator Verdict — Sidebar Navigation Bug

**Date**: 2026-06-04  
**Validator**: validator-mode agent  
**Scope**: Workflow 2, Step 1 — Root-cause identification (no fix suggested)

---

## Bug Report Summary

Clicking any sidebar button does nothing (screen stays on Home).  
Keyboard Tab+Enter navigation does nothing.  
Buttons show NO hover state change when cursor moves over them.  
Buttons show NO pressed state change when mouse button is held.

Previously applied fixes that did NOT resolve the issue:
1. `scene.fireQueuedCallbacks()` added to both `run()` and `runWithNav()` loops
2. `.button` keyboard case added to `handleKey()` dispatching to `handleButtonKey()`

---

## ROOT CAUSE ANALYSIS — Sidebar Navigation — FAIL

### Root module/file

**`src/app/app.zig`** — function `handleMouseRelease()`, approximately lines 1290–1330.

---

### Confirmed Bug: Stale `hovered` Guard in `handleMouseRelease()`

`handleMouseRelease()` fires the `on_click` callback **only** when both `st.pressed` and
`st.hovered` are simultaneously `true`:

```zig
fn handleMouseRelease(self: *AppInner, x: f32, y: f32) void {
    _ = x;   // ← cursor position DISCARDED
    _ = y;   // ← cursor position DISCARDED
    for (self.scene.focusable_indices.items) |idx| {
        ...
        .button => {
            const st = self.scene.buttonStateOf(idx);
            if (st.pressed) {
                st.pressed = false;
                if (st.hovered and !st.disabled) {   // ← GATE: requires prior mouse_move
                    if (st.on_click) |cb| {
                        self.scene._queued_callbacks.append(...) catch {};
                    }
                }
```

The `hovered` flag is maintained **exclusively** by `updateHoverStates()`, which is
invoked **only** in the `mouse_move` branch of `dispatchEvents()`:

```zig
.mouse_move => |mm| {
    self.last_cursor_x = mm.x;
    self.last_cursor_y = mm.y;
    self.updateHoverStates(mm.x, mm.y);
```

`handleMouseRelease()` receives `(x, y)` from the GLFW mouse-button event (which
carries the cursor position at release time), but discards them immediately on entry.
It performs **no independent hit test** at release time.

---

### Why This Breaks After Navigation

Every navigation triggers this sequence (in `drainPending` → `navigator.push()`):

```
scene.reset()                         → _button_state.clearRetainingCapacity()
new_screen.build()
  → scene.instantiate()
    → instantiateNode() per element   → _button_state.items[i] = .{}  (hovered = false)
    → wireSidebarCallbacks()          → sets on_click for indices 2–9
```

After `_button_state.clearRetainingCapacity()` and re-population by `instantiateNode()`,
**every button on the new screen starts with `hovered = false`**.

On Windows, GLFW does **not** synthesize a `mouse_move` event when window content
changes. If the physical cursor has not moved since the previous `mouse_move` event,
`updateHoverStates()` is never called on the new screen. The buttons remain permanently
`hovered = false` until the cursor physically moves.

Consequence:

| User action | What happens |
|---|---|
| Cursor stationary over button; click | `pressed = true` (via `handleMousePress` hit test), `hovered = false` (no prior move on this screen) → release fires no callback |
| Cursor stationary over button; no move | `hovered` stays false → `syncPseudoStates` renders no hover style → no visual change |
| Cursor moves INTO button area | `mouse_move` → `updateHoverStates` → `hovered = true` → frame renders hover style ✓ |
| Cursor moves INTO button then clicks | `pressed = true`, `hovered = true` → callback queued → fires correctly ✓ |

This explains ALL reported symptoms simultaneously:
- **No hover visual on cursor movement**: true only when cursor enters button area without
  having moved after the most recent scene reset; once the cursor moves after that,
  hover correctly appears.
- **No pressed visual**: `handleMousePress` sets `pressed = true` and marks dirty, so a
  frame IS triggered. But if `hovered = false`, `syncPseudoStates` sets no pseudo state
  (the pseudo-state logic uses `bs.pressed AND bs.hovered` to emit `.active`). The
  button renders without a pressed style.
- **Click does nothing**: callback gate `st.hovered AND !st.disabled` blocks queueing.

---

### Architecture of the Defect

`handleMousePress()` performs a **fresh hit test** using the cursor coordinates embedded
in the mouse-button event:

```zig
fn handleMousePress(self: *AppInner, x: f32, y: f32) void {
    const hit_idx = self.hitTestFocusable(x, y);   // fresh hit test
    if (hit_idx != NONE) {
        const kind = self.scene.kindOfIdx(hit_idx);
        switch (kind) {
            .button => {
                const st = self.scene.buttonStateOf(hit_idx);
                st.pressed = true;
```

`handleMouseRelease()` does not. The two halves of click detection use **inconsistent
state sources**: `handleMousePress` uses a fresh geometric query; `handleMouseRelease`
uses a stale cached flag from a different event type. This inconsistency is the root
of the failure.

---

### Affected Code Area (no fix suggested)

| File | Function | Lines (approximate) |
|---|---|---|
| `src/app/app.zig` | `handleMouseRelease()` | ~1290–1330 |
| `src/app/app.zig` | `dispatchEvents()` — `mouse_move` branch only updates `hovered` | ~1104–1120 |

The `(x, y)` parameters of `handleMouseRelease()` are already present and available;
they are currently discarded at lines:

```
_ = x;   // line ~1295
_ = y;   // line ~1296
```

---

### Keyboard Path Status

The keyboard fix (`handleButtonKey()`) is **correctly implemented**:

```
handleKey() → .tab → focusNext/focusPrev
handleKey() → .button → handleButtonKey(focused, key)
handleButtonKey() → queues on_click callback independent of hovered state
```

Tab+Enter DOES queue a callback without requiring `hovered`. If keyboard navigation
"also does nothing," the most likely explanation is:

- First Tab press focuses button 2 (Home). Enter navigates to "home", which rebuilds
  the **identical** home screen. No visible change. The user perceives this as failure.
- A second Tab press is required to reach button 3 (Text) before Enter produces a
  visually distinct screen.

---

### Disconfirmed Hypotheses

| Hypothesis | Status |
|---|---|
| DPI coordinate mismatch (cursor logical vs framebuffer physical) | **DISPROVED** — at DPI scale N, logical cursor `x < rect_width/N` ⟹ `x < rect_width`, hit test passes. DPI > 1 expands hit areas, does not shrink them. |
| `dirty.bit_length` guard blocking dirty set for buttons 2–9 | **DISPROVED** — after 25-element home build, `bit_length = 25 > 9`; guard passes. |
| `on_click` callbacks never registered (missing `wireSidebarCallbacks`) | **DISPROVED** — all 8 screen files call `wireSidebarCallbacks(scene, c.global)` after `scene.instantiate()`. |
| `focusable_indices` empty after reset | **DISPROVED** — `instantiate()` always rebuilds `focusable_indices` by scanning `_kind.items` after `instantiateNode()`. |
| `fireQueuedCallbacks()` missing from `runWithNav()` | **WAS TRUE** (pre-fix). Now correctly placed inside the `hasDirty()` block. |

---

### Unverified Suspects (requires runtime confirmation)

1. **`mod04.solve()` computed rects** — if all sidebar button `computed.w/h = 0`,
   `updateHoverStates()` would always produce `hit = false`, making hover impossible
   even after cursor movement. This would require that buttons are also invisible (zero
   area), so it is unlikely if the buttons are rendered visibly. Not confirmed through
   static analysis of the layout solver.

2. **Other screen files** — forms.zig, data.zig, theme.zig, notifications.zig,
   layout.zig, state.zig — not all verified to call `wireSidebarCallbacks()`. If any
   screen omits the call, sidebar callbacks are null (`on_click = null`) after
   navigating to that screen, and navigation from it silently fails even when `hovered`
   is correctly set.

---

## Summary

**Root cause**: `handleMouseRelease()` in `src/app/app.zig` discards the `(x, y)` cursor
position it receives and instead gates callback queueing on the stale `hovered` flag.
Because every scene reset zeroes all `ButtonState` records (including `hovered = false`),
and GLFW emits no synthetic `mouse_move` after a scene rebuild, all sidebar buttons
on every screen following navigation start permanently unclickable until the cursor
physically moves. The hover visual indicator also fails to appear for the same reason
when the cursor was already positioned over a button at the time of navigation.

**Verdict: FAIL — escalate to implementer.**
