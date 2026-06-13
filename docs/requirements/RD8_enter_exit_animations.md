# RD8 — M14-03: Enter / exit animations

> Roadmap item: M14-03
> Depends on: M14-01 (AnimTimeline), M5-03 (conditional rendering / `_hidden` state)
> Read `00_constitution.md` before this file.

## Purpose

When an element's visibility changes (via `if=` binding or `setHidden`), an enter/exit
animation plays a fade (and optionally a translate) over a configured duration instead of
snapping instantly between visible and hidden. This provides polish when elements appear
and disappear from the UI.

## What to build

### Tailwind class resolver updates (module 06)

Add enter/exit animation classes:

| Class | Effect |
|---|---|
| `animate-in` | Apply enter animation when element becomes visible |
| `animate-out` | Apply exit animation when element becomes hidden |
| `fade-in` | Fade from opacity 0 → target opacity |
| `fade-out` | Fade from target opacity → opacity 0 |
| `slide-in-from-top` | Slide in from y-offset = -100% of element height |
| `slide-in-from-bottom` | Slide in from y-offset = +100% of element height |
| `slide-out-to-top` | Slide out to y-offset = -100% of element height |
| `slide-out-to-bottom` | Slide out to y-offset = +100% of element height |
| `duration-{n}` | Animation duration in frames (reused from M14-02) |

These classes set new fields on `ComputedStyle`:

```zig
pub const EnterExit = packed struct {
    animate_in: bool = false,
    animate_out: bool = false,
    fade_in: bool = false,
    fade_out: bool = false,
    slide_in_from_top: bool = false,
    slide_in_from_bottom: bool = false,
    slide_out_to_top: bool = false,
    slide_out_to_bottom: bool = false,
};

pub const ComputedStyle = struct {
    // ...existing fields including transition*...
    enter_exit: EnterExit = .{},
};
```

### `_enter_exit_state` parallel array (module 07)

```zig
pub const EnterExitState = struct {
    /// True when an enter animation is currently playing.
    entering: bool = false,
    /// True when an exit animation is currently playing.
    exiting: bool = false,
    /// Index into AppInner.anim_timelines for the enter animation.
    enter_timeline_idx: u32 = 0xFFFFFFFF,
    /// Index into AppInner.anim_timelines for the exit animation.
    exit_timeline_idx: u32 = 0xFFFFFFFF,
    /// The visual state the element will be in once the animation completes.
    pending_hidden: bool = false,
};

pub const Scene = struct {
    _enter_exit_state: std.ArrayListUnmanaged(EnterExitState) = .{},

    pub fn enterExitStateOf(self: *Scene, idx: u32) *EnterExitState;
};
```

### Visibility change interception

When `setHidden(idx, true)` is called on an element with `animate_out = true`, instead of
immediately marking it hidden, the system:

1. Records `pending_hidden = true`.
2. Starts an exit timeline with `duration = transition_duration`.
3. The renderer continues to draw the element (ignoring the pending hidden bit) at its
   animating opacity and position.
4. When the exit timeline completes, the element's `_hidden` bit is actually set to `true`.

When `setHidden(idx, false)` is called on an element with `animate_in = true`:

1. The element's `_hidden` bit is cleared immediately (the element participates in layout).
2. An enter timeline starts from value 0.
3. The renderer draws the element with opacity/offset animated from the enter start state
   to the target state.
4. When the enter timeline completes, the animation state is cleared.

### Renderer integration (module 09)

`buildDrawList` checks `EnterExitState`:

- **Entering:** Multiply the element's effective opacity by `timeline.value` (for `fade-in`).
  For `slide-in-from-top`, offset the rendered `Rect.y` by `-rect.h * (1 - timeline.value)`.
  For `slide-in-from-bottom`, offset by `+rect.h * (1 - timeline.value)`.

- **Exiting:** Multiply the element's effective opacity by `(1 - timeline.value)` (for
  `fade-out`). For slide-out variants, offset proportionally.

- The draw commands for the element and its children are emitted with the modified opacity/position,
  even though the element is logically leaving.

### Render-time vs layout-time position

Enter/exit slide offsets affect only the *rendered position* — the element stays at its
layout-computed `Rect` in the element store. The slide offset is applied as a translation
when emitting `filled_rect`, `border_rect`, and glyph commands for the transitioning element.

For child content inside an entering/exiting element, the offset applies to the parent's
draw commands. Children draw at their own layout positions relative to the parent. The
parent's clip rect (if any) is translated to match the animated position so content is
properly scissored.

### Frame loop integration

The `detectTransitions` function (from M14-02) is extended to also check for enter/exit
transitions. It runs in the same position in the frame loop.

`hasAnimatedElements` (extended in M14-01) also checks for active enter/exit animations,
so the frame loop runs continuously while any element is entering or exiting.

### Module location

```
src/05/types.zig                — ComputedStyle.enter_exit, EnterExit fields
src/06/types.zig                — animate-in/out, fade-in/out, slide-in/out classes
src/07/types.zig                — EnterExitState, enterExitStateOf
src/09/types.zig                — enter/exit rendering in buildDrawList
src/app/app.zig                 — visibility change interception, extended detectTransitions
```

## Non-goals (DO NOT implement — INV-5.4)

- **No scaling / zoom enter/exit** — fade and slide only in v1.
- **No staggered children** — all children animate simultaneously as part of the parent's
  transition.
- **No custom easing for enter/exit** — uses the element's `transition_duration` and the
  `easeInOut` easing from `AnimTimeline`.
- **No `animate-pulse`, `animate-bounce`, or other CSS `@keyframes` equivalents** —
  only enter/exit transitions.
- **No `animation-delay`** — animations start immediately when visibility changes.
- **No `animation-fill-mode`** — the element is always visible during the enter transition
  (it starts at `_hidden = false` immediately) and hidden after the exit transition completes.

## Acceptance criteria

1. Element with `animate-in` + `fade-in` fades from transparent to opaque when `_hidden` is
   cleared.
2. Element with `animate-out` + `fade-out` fades from opaque to transparent when `setHidden(true)`
   is called.
3. Element with `slide-in-from-bottom` slides up from below its final position.
4. Element with `slide-out-to-top` slides up and out.
5. During an exit animation, the element continues to be rendered (dirty each frame).
6. After the exit timeline completes, `_hidden` is set to `true`.
7. Combining `fade-in` + `slide-in-from-bottom` produces a simultaneous fade+slide.
8. Elements without enter/exit classes snap instantly (no animation).
9. Active enter/exit animations keep the frame loop in poll mode.
10. Unit tests verify `EnterExitState` lifecycle (pending_hidden, timeline cleanup).
