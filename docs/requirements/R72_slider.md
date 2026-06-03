# R72 — M7-03: Slider

> Roadmap item: M7-03  
> Depends on: M1-02 (event delivery), M4-01 (pseudo-state styling)  
> Read `00_constitution.md` before this file.

## Purpose

A `<Slider>` widget lets the user select a numeric value from a continuous range by dragging
a thumb along a track. The value, min, max, and step are stored in `SliderState` (parallel
array). Mouse drag and keyboard arrows change the value. The widget renders as a track rect
plus a circular thumb.

## What to build

### Widget kind

```zig
pub const WidgetKind = enum { /* ...existing... */ slider };  // NEW
// tagToKind: "Slider" → .slider
// defaultLayoutFor: .slider → { .display = .block, .height = .{ .px = 24 } }
```

### `SliderState`

```zig
pub const SliderState = struct {
    value:    f32  = 0,
    min:      f32  = 0,
    max:      f32  = 100,
    step:     f32  = 1,    // 0 = continuous (no snapping)
    dragging: bool = false,
    hovered:  bool = false,
    disabled: bool = false,
};

pub const Scene = struct {
    _slider_state: std.ArrayListUnmanaged(SliderState) = .empty,

    pub fn sliderStateOf(self: *Scene, idx: u32) *SliderState

    /// Set value, clamped to [min, max], snapped to step, and mark dirty.
    pub fn setSliderValue(self: *Scene, idx: u32, value: f32) void

    pub fn getSliderValue(self: *Scene, idx: u32) f32
};
```

`setSliderValue` applies step snapping:

```zig
fn snapToStep(value: f32, min: f32, step: f32) f32 {
    if (step == 0) return value;
    return min + @round((value - min) / step) * step;
}
```

### Markup attributes

```html
<Slider min="0" max="100" step="5" value="50" class="w-full" />
```

During `instantiate`, parse the `min`, `max`, `step`, and `value` literal attrs as floats
and store in `SliderState`.

### Input handling in `App.run()`

**Mouse drag:**

```zig
// On hover:
if (layout_rect.containsPoint(mouse_pos)) { state.hovered = true; }

// On press over the thumb or track:
if (layout_rect.containsPoint(mouse_pos) and left_press) {
    state.dragging = true;
    updateSliderFromMouse(scene, idx, mouse_pos, layout_rect);
}

// While dragging:
if (state.dragging) {
    updateSliderFromMouse(scene, idx, mouse_pos, layout_rect);
}

// On release:
if (state.dragging and !left_held) {
    state.dragging = false;
    scene.elements.dirty.set(idx);
}
```

```zig
fn updateSliderFromMouse(scene: *Scene, idx: u32,
                          mouse: Vec2, rect: Rect) void {
    const state = scene.sliderStateOf(idx);
    const t = std.math.clamp((mouse.x - rect.x) / rect.w, 0, 1);
    const raw = state.min + t * (state.max - state.min);
    scene.setSliderValue(idx, raw);
}
```

**Keyboard (focused slider):**

- `Right` / `Up` → value + step (or +1 % of range if step == 0).
- `Left` / `Down` → value - step.
- `Home` → min value.
- `End` → max value.

### Visual rendering in `buildDrawList`

```zig
const S = scene.sliderStateOf(idx);
const track_h: f32 = 4;
const thumb_r: f32 = effective_style.font_size * 0.5;  // half of text_base ≈ 7 px

// Track background:
const track_rect = Rect{
    .x = layout_rect.x, .y = layout_rect.y + (layout_rect.h - track_h) / 2,
    .w = layout_rect.w, .h = track_h,
};
try cmds.append(.{ .filled_rect = .{
    .rect = track_rect, .color = tokens.border_default, .radius = track_h / 2 } });

// Filled portion (left of thumb):
const t = std.math.clamp((S.value - S.min) / (S.max - S.min), 0, 1);
const filled_rect = Rect{ .x = track_rect.x, .y = track_rect.y,
                           .w = track_rect.w * t, .h = track_h };
try cmds.append(.{ .filled_rect = .{
    .rect = filled_rect, .color = tokens.accent, .radius = track_h / 2 } });

// Thumb circle:
const thumb_x = layout_rect.x + layout_rect.w * t;
const thumb_rect = Rect{
    .x = thumb_x - thumb_r, .y = layout_rect.y + (layout_rect.h / 2) - thumb_r,
    .w = thumb_r * 2, .h = thumb_r * 2,
};
const thumb_color = if (S.dragging) tokens.accent_hover else tokens.accent;
try cmds.append(.{ .filled_rect = .{
    .rect = thumb_rect, .color = thumb_color, .radius = thumb_r } });
```

### Module location

```
src/07/types.zig   — WidgetKind.slider, SliderState, setSliderValue, getSliderValue
src/09/types.zig   — slider rendering
src/app/app.zig    — slider mouse drag + keyboard handling
docs/requirements/R72_slider.md
```

## Non-goals (DO NOT implement — INV-5.4)

- **No range slider** (two thumbs) — single thumb only.
- **No vertical slider** — horizontal only; class overrides for rotation are post-v1.
- **No tick marks / labels along track** — plain track only.
- **No value tooltip on drag** — post-v1 (tooltip is M7-13).
- **No slider-change callbacks** — INV-3.3; read value via `getSliderValue`.
- **No touch drag** — mouse only (INV-1.2 desktop).

## Acceptance criteria

1. `zig build test-07` passes. New tests: `setSliderValue` snaps correctly; min/max clamping
   works; `getSliderValue` returns updated value.
2. `zig build test-09-unit` passes. Slider with value 50 on a [0,100] range emits a filled
   portion rect of width = 50 % of track width.
3. Integration: drag thumb, see value update. Left/Right arrows nudge by step. Home/End jump
   to extremes. Checklist ticked.
