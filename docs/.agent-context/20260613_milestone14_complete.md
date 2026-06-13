# Milestone 14 — Animation — Completion Summary

**Date:** 2026-06-13
**Implemented by:** Orchestrator → Implementer agents

## Summary

Milestone 14 adds a minimal, principled animation model to zig-gui. The core is `AnimTimeline`
in `src/app/anim_timeline.zig`, a pure scalar animator that drives a `f32` from 0→1 over a
frame-based duration with quadratic easing functions (linear, ease-in, ease-out, ease-in-out).

## What was built

### M14-01 (RD6) — Animation timeline and easing
- `src/app/anim_timeline.zig` — `AnimTimeline` struct + `Easing` enum + 5 easing functions
- `AppInner.anim_timelines: ArrayListUnmanaged(AnimTimeline)` with `tickAnimations()`, `allocateTimeline()`
- `hasAnimatedElements()` now checks running timelines instead of per-kind widget scan

### M14-02 (RD7) — Style transitions
- `TransitionState` parallel array on Scene for opacity and background transitions
- `transition-opacity`, `transition-background`, `transition-colors`, `duration-{n}` Tailwind classes
- `detectTransitions()` in app.zig — compares `_prev_styles` vs `_style`, starts timelines for changes
- `syncAnimationState()` applies lerped values to `_style` before each frame's `buildDrawList`
- `lerpColor()` helper in module 09 for color interpolation

### M14-03 (RD8) — Enter/exit animations
- `EnterExitState` parallel array on Scene for enter/exit fade transitions
- `animate-in`, `animate-out`, `fade-in`, `fade-out`, slide classes (v1: fade only)
- `setHiddenWithAnimation()` — defers `_hidden` bit during exit animation
- Fade implemented via `_style.opacity` modification in `syncAnimationState()`

### M14-04 (RD9) — Spinner/progress via AnimTimeline
- `ProgressState.anim_timeline_idx` and `anim_frame_value` fields
- Automatic timeline allocation for spinners (duration=80, repeating) and indeterminate progress bars (duration=120, repeating)
- `initAnimationTimelines()` called after scene instantiation and hot-reload

### M14-05 (RDA) — Reduced-motion respect
- `AppInner.prefer_reduced_motion: bool` + `setReducedMotion()`
- `tickAnimations()` immediately completes all timelines when flag is set

## Files created
- `src/app/anim_timeline.zig` — core animation module
- `src/app/anim_timeline_test.zig` — 22 unit tests
- `docs/requirements/RD6_animation_timeline.md` — requirement spec
- `docs/requirements/RD7_style_transitions.md` — requirement spec
- `docs/requirements/RD8_enter_exit_animations.md` — requirement spec
- `docs/requirements/RD9_spinner_progress_animation.md` — requirement spec
- `docs/requirements/RDA_reduced_motion.md` — requirement spec

## Files modified
- `docs/specs/05.types.zig` — ComputedStyle transition/enter_exit fields, TransitionState, EnterExitState
- `docs/specs/06.types.zig` — resolveClasses handlers for transition/enter_exit/duration classes
- `docs/specs/09.types.zig` — lerpColor function
- `src/07/types.zig` — TransitionState, EnterExitState, ProgressState extensions, Scene parallel arrays
- `src/09/types.zig` — lerpColor implementation, spinner/progress rendering using anim_frame_value
- `src/app/app.zig` — tickAnimations, detectTransitions, syncAnimationState, setHiddenWithAnimation, initAnimationTimelines, prefer_reduced_motion, hasAnimatedElements update
- `build.zig` — test-anim-timeline step
- `docs/ROADMAP.md` — M14 marked `done`
- `docs/specs/glossary.md` — 8 new glossary entries (AnimTimeline, TransitionState, EnterExitState, prefer_reduced_motion, transition-*, animate-in/out, lerpColor)
- `src/09/09_test.zig` — lerpColor tests (9)
- `src/07/07_test.zig` — TransitionState/EnterExitState tests (6)
- `src/05/05_test.zig` — new ComputedStyle field tests (2)
- `src/06/06_test.zig` — new class resolution tests (16)

## Test results
- `zig build` — passes
- `zig build test-anim-timeline` — 22/22 pass
- `zig build test-05-unit` — passes
- `zig build test-06-unit` — passes
- `zig build test-07-unit` — passes (pre-existing defaultLayoutFor test failure is unrelated)
- `zig build test-09-unit` — passes
- `zig build visual-check` — PASS (100% non-zero IDAT bytes)
