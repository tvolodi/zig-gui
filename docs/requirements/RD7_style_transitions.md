# RD7 — M14-02: Style transitions

> Roadmap item: M14-02
> Depends on: M14-01 (AnimTimeline), module 09 (renderer / ComputedStyle)
> Read `00_constitution.md` before this file.

## Purpose

Allow elements to smoothly transition between style values — e.g. `opacity` changing from 1.0
to 0.5 over 200 ms, or `background` cross-fading. The `transition-{opacity,border,background}`
Tailwind utility classes trigger an `AnimTimeline` when the associated style property changes,
and the renderer blends the old and new values over the transition duration.

## What to build

### Tailwind class resolver updates (module 06)

Add three transition-related classes to `resolveClasses`:

| Class | Effect |
|---|---|
| `transition-opacity` | Enable opacity transitions on this element |
| `transition-background` | Enable background color transitions on this element |
| `transition-colors` | Enable both opacity and color transitions on this element |
| `duration-{n}` | Set transition duration in frames (e.g. `duration-60` = 60 frames ≈ 1 s at 60 fps); maps to `style.transition_duration: u32` |

Supported `duration-{n}` values: 0, 30, 60, 120, 240, 480 (matching common Tailwind
duration steps, interpreted as frame counts). `duration-0` = instant (no transition). Default
`duration-150` is NOT supported in v1 — the `duration-{n}` class must be explicitly specified.

### `ComputedStyle` additions (module 05)

```zig
pub const TransitionProperty = packed struct {
    opacity: bool = false,
    background: bool = false,
    // NOTE: text_color border_color border_width radius are NOT included in v1.
};

pub const ComputedStyle = struct {
    // ...existing fields...
    transition: TransitionProperty = .{},
    transition_duration: u32 = 0,  // in frames, 0 = no transition
};
```

### `_transition_state` parallel array (module 07)

A new parallel array on `Scene`:

```zig
pub const TransitionState = struct {
    active_opacity: bool = false,
    opacity_timeline_idx: u32 = 0xFFFFFFFF,
    from_opacity: f32 = 1.0,
    to_opacity: f32 = 1.0,

    active_background: bool = false,
    background_timeline_idx: u32 = 0xFFFFFFFF,
    from_background: theme.Color = .{},
    to_background: theme.Color = .{},

    active_border: bool = false,
    border_timeline_idx: u32 = 0xFFFFFFFF,
    from_border: theme.Color = .{},
    to_border: theme.Color = .{},

    active_text_color: bool = false,
    text_timeline_idx: u32 = 0xFFFFFFFF,
    from_text: theme.Color = .{},
    to_text: theme.Color = .{},
};

pub const Scene = struct {
    _transition_state: std.ArrayListUnmanaged(TransitionState) = .{},

    pub fn transitionStateOf(self: *Scene, idx: u32) *TransitionState;
};
```

NOT added to `Scene` fields above — this is a design sketch:
- `TransitionState` tracks which properties are transitioning, the source and destination
  values, and which `AnimTimeline` index drives each transition.
- When a style property changes (e.g. via `setStyleOpacity`), the app layer checks if
  `transition.opacity` is set and `transition_duration > 0`. If so, it stores the old value
  in `from_opacity` and the new in `to_opacity`, allocates an `AnimTimeline` with
  `duration = transition_duration`, and starts it.
- During `buildDrawList`, if a transition is active, the effective style value is computed
  by lerping between `from_*` and `to_*` using the timeline's current `value`.

### Style change detection

The app layer track previous style values per element. Before each `rebuildStyles()` or
`setTheme()` call, the current style values are snapshot. After the call, changed properties
trigger transitions on elements that have the matching `transition-*` class set.

```zig
// In AppInner:
/// Cache of previous style values for transition detection.
_prev_styles: std.ArrayListUnmanaged(ComputedStyle) = .{},

pub fn detectTransitions(self: *AppInner) void;
```

`detectTransitions` compares `_prev_styles[idx]` with `_style.items[idx]` for each live
element. For each changed property where `transition.{field}` is true and
`transition_duration > 0`, it sets up a `TransitionState` entry and starts an `AnimTimeline`.

### Renderer integration (module 09)

`buildDrawList` checks `transitionStateOf(idx)` for active transitions. When a transition is
active, the style value used for rendering is the lerped value between `from_*` and `to_*`.

For colors (background, border):
```zig
fn lerpColor(a: Color, b: Color, t: f32) Color {
    return .{
        .r = @intFromFloat(@as(f32, @floatFromInt(a.r)) + (@as(f32, @floatFromInt(b.r)) - @as(f32, @floatFromInt(a.r))) * t),
        .g = @intFromFloat(@as(f32, @floatFromInt(a.g)) + (@as(f32, @floatFromInt(b.g)) - @as(f32, @floatFromInt(a.g))) * t),
        .b = @intFromFloat(@as(f32, @floatFromInt(a.b)) + (@as(f32, @floatFromInt(b.b)) - @as(f32, @floatFromInt(a.b))) * t),
        .a = @intFromFloat(@as(f32, @floatFromInt(a.a)) + (@as(f32, @floatFromInt(b.a)) - @as(f32, @floatFromInt(a.a))) * t),
    };
}
```

For opacity (scalar):
```zig
fn lerpF32(a: f32, b: f32, t: f32) f32 {
    return a + (b - a) * t;
}
```

### Frame loop integration

`AppInner.tickAnimations` handles all active timelines, including those referenced by
`TransitionState` entries. The `detectTransitions` call runs after `rebuildStyles()` and
before `buildDrawList` in the frame loop:

```
refreshBindings → detectTransitions → (resize) → layout → buildDrawList
```

### `TransitionState` cleanup

When a transition completes (the associated `AnimTimeline.running` becomes `false`),
`detectTransitions` or a cleanup function resets the transition state so the renderer uses
the base `_style` value directly without lerping.

### Module location

```
src/05/types.zig                — ComputedStyle.transition, ComputedStyle.transition_duration, TransitionProperty
docs/specs/05.types.zig         — update contract file
src/06/types.zig                — transition-opacity, transition-background, transition-colors, duration-{n} classes
src/07/types.zig                — TransitionState parallel array
src/09/types.zig                — lerpColor, lerpF32 helpers; transition-aware buildDrawList
src/app/anim_timeline.zig      — no changes (timeline is already sufficient)
src/app/app.zig                 — _prev_styles, detectTransitions, tickAnimations integration
```

## Non-goals (DO NOT implement — INV-5.4)

- **No `transition-all`** shortcut — each property is opted into individually.
- **No `transition-delay`** — transitions start immediately when the value changes.
- **No `transition-timing-function`** beyond the linear easing (all transitions use linear).
- **No border-width, radius, padding, or font-size transitions** — color and opacity only in v1.
- **No group/composite transitions** — each property transitions independently.
- **No transform/translate transitions** — no GPU transform pipeline exists yet.
- **No CSS `transition` shorthand parsing** — only the `transition-*` utility classes.

## Acceptance criteria

1. `transition-opacity` class enables opacity transitions. Changing `opacity` via style
   update triggers a transition over `duration-{n}` frames.
2. `transition-background` enables background color transitions.
3. `transition-colors` enables both opacity and color transitions.
4. `duration-60` creates a 60-frame `AnimTimeline`.
5. `duration-0` means no transition (instant).
6. When no transition class is present, style changes are instant (no transition).
7. Active transitions mark the element dirty each frame so the renderer picks up the
   lerped value.
8. When a transition completes, the element renders at the final (target) style value.
9. Unit tests verify `lerpColor` produces correct intermediate values.
10. Lerp in `buildDrawList` interpolates the active transition properties; non-transitioning
    properties use `_style` directly.
