# RN16 — Animated component library (`src/app/ui/`)

> Status: `done` (2026-08-01). Hover/press color transitions, enter/exit fade, and Button
> loading state implemented and independently visually verified — see
> `docs/.agent-context/rn16_animated_components/visual/independent_verification.md` and
> `docs/AGENT_GUIDE.md` §14.7. One related-but-out-of-scope item remains open:
> `prefer_reduced_motion` (RDA_reduced_motion.md) was not implemented — it was never part of
> this requirement's acceptance criteria (§6) and is tracked separately as ROADMAP M14-05.
> Read `docs/specs/00_constitution.md` before this file.

## 1. Goal

Give the `src/app/ui/` component library (`button.zig`, `card.zig`, `input.zig`, `badge.zig`)
real motion, matching the reference product's own CSS transition behavior
(`c:\Users\tvolo\dev\ai-dala\aiqadam\design-system\tokens.css` / `components.css` —
`transition: all 150ms var(--ease-out)` on interactive elements). Three kinds of motion, in
priority order:

1. **Hover/press micro-interactions** — background/border color eases over ~150ms instead of
   snapping instantly, on hover and on press (active), for Button/Card(hoverable)/Input.
2. **Enter/exit animations** — a component fades and/or slides in when it is first instantiated
   (e.g. a card appearing on screen), and fades out on removal.
3. **Loading/active-state animation** — a busy/loading visual state for Button (spinner replaces
   label, or a pulsing fill) and Card (skeleton-style pulsing placeholder), reusing the pattern
   already established by `spinner`/`progress_bar` (frame-driven, `Scene.frame_count`).

This is a **rendering feature** — any change to `buildDrawList`, `resolveStyle`, or a `*State`
render path requires `zig build visual-check` before being called done (constitution
`docs/AGENT_GUIDE.md` §11.2).

## 2. What already exists — reuse, do not reinvent

Do NOT design a new animation mechanism. Three pieces of infrastructure already exist in the
codebase (module 05 `src/05/types.zig`, module 07 `src/07/types.zig`, module 09
`src/09/types.zig`) but are **undocumented and not wired into any `ui/` component**:

- **`TransitionState`** (`src/05/types.zig` ~L404, mirrored in `src/07/types.zig` ~L669) —
  per-element `active_opacity`, `opacity_timeline_idx`, `from_opacity` fields; `Scene`
  owns a parallel array `_transition_state` (`src/07/types.zig` L822) with
  `transitionStateOf(idx)` accessor. `ComputedStyle` already declares
  `transition_opacity`/`transition_background`/`transition_colors`/`transition_duration`
  flags (`src/05/types.zig` L387-391) that presumably drive this — confirm what (if anything)
  currently reads them; likely nothing does yet (this is the M14-02 stub).
- **`EnterExitState`** (`src/05/types.zig` L417, mirrored `src/07/types.zig` L685) —
  `entering`/`exiting`/`enter_timeline_idx` fields; `ComputedStyle` declares
  `animate_in`/`animate_out`/`fade_in`/`fade_out`/`slide_in_from_top` flags (`src/05/types.zig`
  L392-397). `Scene._enter_exit_state` parallel array + `enterExitStateOf(idx)` accessor
  already exist (M14-03 stub).
- **`PseudoStyleSet`/`resolveStyle`** (`src/05/types.zig` L442, `src/09/types.zig` L372) —
  ALREADY WORKING: hover/focus/active/disabled color overrides resolve correctly today, just
  with an instant snap (no interpolation). This is the target to smooth, not to build from
  scratch.
- **Frame-driven animation precedent** — `spinner`/`progress_bar` (`indeterminate`) already
  animate purely from `Scene.frame_count`/`frame_time_ms`, set once per frame by the app layer
  before `buildDrawList` (see `docs/AGENT_GUIDE.md` R73). Any new "loading" state animation
  should follow this exact pattern — read `frame_count`, do not add a second animation clock.

**First implementation step is investigation, not code:** determine exactly how far M14-02/M14-03
got. Grep `_transition_state`/`_enter_exit_state`/`opacity_timeline_idx`/`AnimTimeline` across
`src/` for every read site, not just the struct declarations. If an `AnimTimeline` type/owner
doesn't exist yet (only referenced by field name), that's the actual gap to fill — a small
per-Scene array of `{ start_frame: u64, duration_frames: u32, from: f32, to: f32 }` entries,
advanced once per frame, is very likely all that's missing given the existing spinner/progress_bar
precedent for frame-driven timing.

## 3. Non-goals

- No physics-based/spring easing beyond a simple ease-out curve (matches AI-Qadam's own
  `cubic-bezier(0.4, 0, 0.2, 1)` — a lerp with an eased `t` is sufficient; do not add a generic
  animation-curve system).
- No per-property custom durations exposed to callers yet — a single constant duration
  (~150ms, convert to frames via the app's frame timing) matching AI-Qadam's own CSS is enough
  for v1. A configurable-duration API is a future enhancement, not required here.
- No animating layout (position/size). Only paint properties: background, border_color,
  text_color, opacity. Animating `Rect`/layout would touch module 04 and is out of scope.
- No JS-style "animation library" (keyframes, staggering, spring physics). This is component
  polish, not a general animation module.
- Loading-state spinner reuses the EXISTING spinner widget rendering path
  (`docs/AGENT_GUIDE.md` R73) — do not invent a second spinner implementation for buttons.

## 4. Scope — files likely touched

| File | Expected change |
|---|---|
| `src/05/types.zig` | Confirm/complete `TransitionState`/`EnterExitState` field shapes; add an `AnimTimeline`-equivalent if genuinely missing (additive only, INV-5.1). Document the 150ms-in-frames constant as a named value derived from theme, not a magic number scattered across call sites. |
| `src/07/types.zig` | Wire `Scene.instantiate` to start an enter animation (`animate_in`) for newly-created Button/Card/Input/Badge elements when the class opts in. Wire hover/press pseudo-state transitions to start/advance a `TransitionState` timeline instead of just returning the target color from `resolveStyle` unconditionally. |
| `src/09/types.zig` | `buildDrawList` reads the current interpolated color (lerped between `from`/`to` using the timeline's elapsed-frame ratio) instead of the raw resolved pseudo-state color, when a transition is active. Loading-state render path for Button (spinner-in-place-of-label) and Card (pulsing skeleton fill, can reuse the existing `.skeleton`-equivalent approach — check if one exists already for any widget, e.g. loading table rows). |
| `src/app/ui/{button,card,input,badge}.zig` | Add the class strings / opt-in flags needed to enable transition/enter-exit/loading behavior on each component's variants (e.g. a `loading` variant for Button). |
| `src/demo/screens/components.zig` | Add visible demonstration of each new behavior: a hover-transition button, a card that animates in on screen entry (or a button that toggles a card's visibility to demonstrate enter/exit), and a "Loading" button variant. This is required for the Visual Validation Loop to have something to screenshot — a feature with no demo coverage is invisible per `docs/AGENT_GUIDE.md` §7. |

Confirm the exact current filenames before starting — `docs/requirements/RN13_ui_component_library.md`
(the original component-library spec) names `input_field.zig`/`stat_card.zig`/`select.zig`/
`switch_field.zig`, but the actual files that exist and were most recently updated (RN14/RN15,
2026-08-01) are `button.zig`/`card.zig`/`input.zig`/`badge.zig`/`separator.zig`. Work against
the real files, not the older spec's aspirational list.

## 5. Known renderer constraints (read before starting — learned the hard way this session)

- The Vulkan renderer's `quad.frag` had (until 2026-08-01, commit `7337a76`) a double sRGB
  gamma-encode bug and missing rounded-corner/border-stroke wiring for ordinary widget fills.
  Both were fixed, but if any new visual artifact looks gamma-wrong or loses rounding, check
  `docs/AGENT_GUIDE.md` §14 (RN14/RN15 patterns) for the CPU/shader draw-mode mapping table
  before assuming it's a new bug.
- **Known open gap:** Badge corner radius does not currently render (square corners despite a
  non-zero `radius` in `ComputedStyle` — confirmed via independent pixel sampling,
  `docs/.agent-context/aiqadam_components_v1/visual/iteration_5_final_analysis.md`). If this
  RN16 work touches Badge rendering at all, investigating/fixing this known gap is in scope
  under this project's "fix issues immediately" rule — do not defer it a second time if you're
  already in the badge render path for another reason.
- `zig build run-demo` has been observed to hang in this environment. Use
  `zig-out\bin\showcase.exe` directly for screenshots (see `run_demo.bat` at repo root, and
  `docs/AGENT_GUIDE.md` §14).

## 6. Acceptance criteria

- [ ] `zig build` exits 0; `zig build test` (aggregate gate) passes with zero regressions.
- [ ] Button, Card (hoverable variant), and Input show a visibly eased color transition on
      hover and on press — verified by comparing 2+ screenshots taken at different points in
      the transition (e.g. frame 1 vs frame 10 after a synthetic hover event), not just a
      single-frame screenshot (a snap and a smooth transition look identical in a single still
      frame at the start or end state — the test must sample mid-transition).
- [ ] At least one component demonstrates enter animation (fade and/or slide) when instantiated,
      and exit animation when removed — verified the same way (multi-frame sampling).
- [ ] Button has a working `loading` state (spinner replaces label or an equivalent busy
      indicator) driven by `Scene.frame_count`, matching the existing spinner animation pattern.
- [ ] No layout properties (position, size) are animated — only paint properties.
- [ ] `zig build visual-check` passes.
- [ ] Visual Validation Loop (`docs/agents/AGENT_WORKFLOWS.md` §10) run against the Components
      screen's new animated section, with **independent** (non-self-reported) verification —
      this project has had repeated instances of self-reported visual passes not matching
      reality; every visual claim in this task must be checked by a fresh agent inspecting
      actual screenshot pixels, not the implementer's own account.
- [ ] `docs/requirements/DEMO_APP.md` updated to describe the new animated Components section.
- [ ] `docs/AGENT_GUIDE.md` gains a pattern entry (§14 continuation) documenting the
      transition/enter-exit/loading wiring for future agents, the same way RN14/RN15 did for
      the token/renderer work.

## 7. How to verify

```powershell
zig build
zig build test
zig build visual-check
zig-out\bin\showcase.exe --dark --initial-screen components --screenshot-frames 1 --screenshot-out testdata/rn16_frame1.png
zig-out\bin\showcase.exe --dark --initial-screen components --screenshot-frames 10 --screenshot-out testdata/rn16_frame10.png
```

Compare `rn16_frame1.png` vs `rn16_frame10.png` for any element whose transition was triggered
between those frames (e.g. via `--click-idx`/`--click-count` synthetic interaction, already
supported by `src/demo/main.zig` — reuse it rather than adding a new interaction-injection
mechanism) — colors should differ between the two frames if a transition is genuinely
interpolating, and should NOT differ if the transition completed before frame 1 or hasn't
started.
