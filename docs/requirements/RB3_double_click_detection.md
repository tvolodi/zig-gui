# RB3 — M11-04: Double-click detection

> Roadmap item: M11-04  
> Depends on: M1-02 (event delivery)  
> Read `00_constitution.md` before this file.

## Purpose

Detect when the user clicks the left mouse button twice in rapid succession on the same
element and deliver a `mouse_button_double` event. The detection uses a configurable
timing threshold (default 250 ms) and a position deadzone: both clicks must land within
`DOUBLE_CLICK_DEADZONE_PX = 4` pixels of each other. Double-click state is stored on
`AppInner` (not in `Scene`) — it is transient interaction state, not per-element data.

## What to build

### `mouse_button_double` event variant in module 01

Extend `InputEvent` in [01.types.zig](../specs/01.types.zig) and `src/01/types.zig`:

```zig
pub const InputEvent = union(enum) {
    mouse_move:          struct { x: f32, y: f32 },
    mouse_button:        struct { button: MouseButton, action: InputAction, x: f32, y: f32 },
    mouse_button_double: struct { button: MouseButton, x: f32, y: f32 },  // NEW
    scroll:              struct { dx: f32, dy: f32 },
    key:                 struct { key: Key, action: InputAction, mods: Modifiers },
    char:                struct { codepoint: u21 },
};
```

The `mouse_button_double` event is synthesized by `dispatchEvents` in `app.zig` — it is
NEVER pushed by GLFW callbacks. The event exists in the type so app code can pattern-match
on it in the same `switch` as other events.

### `DoubleClickState` on `AppInner`

Add to `src/app/app.zig`:

```zig
pub const DoubleClickState = struct {
    /// Timestamp of the last left button press (ms since app start).
    last_press_ms: u64 = 0,
    /// Position of the last left button press.
    last_x: f32 = 0,
    last_y: f32 = 0,
    /// Element index that received the last left button press. NONE = none.
    last_hit: u32 = NONE,
};
```

`AppInner` gains one field: `double_click: DoubleClickState = .{}`.

### Configurable threshold in `AppOptions`

```zig
pub const AppOptions = struct {
    // ...existing fields...

    /// Maximum interval between two clicks to be considered a double-click.
    /// Default: 250 ms. Valid range: [100, 1000].
    double_click_threshold_ms: u64 = 250,
};
```

`AppInner` stores `double_click_threshold_ms: u64` copied from `AppOptions.double_click_threshold_ms`.

### Double-click synthesis in `dispatchEvents` (app.zig)

Insert immediately after the existing single-click (`mouse_button` `.press`) handling:

```zig
if (ev == .mouse_button and ev.mouse_button.button == .left
    and ev.mouse_button.action == .press) {
    const now_ms  = @intCast(u64, std.time.milliTimestamp());
    const x       = ev.mouse_button.x;
    const y       = ev.mouse_button.y;
    const hit     = hitTest(&self.scene, x, y);

    const dt      = now_ms -| self.double_click.last_press_ms;
    const dx      = x - self.double_click.last_x;
    const dy      = y - self.double_click.last_y;
    const close   = dx * dx + dy * dy <= DOUBLE_CLICK_DEADZONE_PX * DOUBLE_CLICK_DEADZONE_PX;
    const same_el = hit == self.double_click.last_hit and hit != NONE;

    if (dt <= self.double_click_threshold_ms and close and same_el) {
        // Synthesize double-click event and dispatch it.
        const dbl = InputEvent{ .mouse_button_double = .{
            .button = .left, .x = x, .y = y,
        }};
        self.dispatchSingleEvent(dbl);  // see below
        // Reset so a triple-click doesn't count as two doubles.
        self.double_click = .{};
    } else {
        // Record for next comparison.
        self.double_click = .{
            .last_press_ms = now_ms,
            .last_x        = x,
            .last_y        = y,
            .last_hit      = hit,
        };
    }
}
```

The `DOUBLE_CLICK_DEADZONE_PX` constant is `4` (same as the drag deadzone in RB1).

### `on_double_click` callback per element in `Scene`

Elements opt in to double-click handling via a parallel array:

In [07.types.zig](../specs/07.types.zig) and `src/07/types.zig`:

```zig
pub const Scene = struct {
    // ...existing fields...

    /// Per-element double-click callbacks. null = element has no double-click handler.
    _double_click: std.ArrayListUnmanaged(?CallbackFn) = .empty,

    pub fn setDoubleClick(self: *Scene, idx: u32, cb: CallbackFn) void
    pub fn clearDoubleClick(self: *Scene, idx: u32) void
    pub fn doubleClickOf(self: *const Scene, idx: u32) ?CallbackFn
};
```

### Dispatching `mouse_button_double` in `dispatchSingleEvent`

The synthesized `mouse_button_double` event is dispatched through the existing hit-test
and callback-queue path:

```zig
.mouse_button_double => |dbl| {
    const hit = hitTest(&self.scene, dbl.x, dbl.y);
    if (hit != NONE) {
        if (self.scene.doubleClickOf(hit)) |cb| {
            self.scene._queued_callbacks.append(self.gpa, cb) catch {};
        }
    }
},
```

The callback is queued via `_queued_callbacks` and fired at frame-end (INV-3.3).

### Module location

```
src/01/types.zig         — InputEvent.mouse_button_double variant
docs/specs/01.types.zig  — same
src/07/types.zig         — _double_click array, setDoubleClick, clearDoubleClick,
                           doubleClickOf
docs/specs/07.types.zig  — same
src/app/app.zig          — DoubleClickState, double_click_threshold_ms, dispatchEvents
                           extension, dispatchSingleEvent double-click case
docs/requirements/RB3_double_click_detection.md
```

## Public API

```zig
// Module 01 — InputEvent
.mouse_button_double: struct { button: MouseButton, x: f32, y: f32 }

// AppOptions
double_click_threshold_ms: u64 = 250

// Scene
pub fn setDoubleClick(self: *Scene, idx: u32, cb: CallbackFn) void
pub fn clearDoubleClick(self: *Scene, idx: u32) void
pub fn doubleClickOf(self: *const Scene, idx: u32) ?CallbackFn
```

## Behavioral contract

| Situation | Behavior |
|---|---|
| Two clicks within threshold, same element, within deadzone | `mouse_button_double` synthesized; `on_double_click` queued |
| Two clicks within threshold, different elements | No double-click; second click resets state |
| Two clicks outside threshold | No double-click; second click resets state |
| Two clicks within threshold, positions > deadzone apart | No double-click |
| Triple-click | First double recognised; triple treated as new first click |
| `on_double_click` and `on_click` both registered | Both fire: single-click fires first, then double-click if threshold met |
| `on_double_click` registered but `on_click` not | Only double-click fires (single-click is silently ignored for that element) |

Note: the framework does NOT suppress the single-click callback when a double-click is
detected. Suppression would require a timer wait, which contradicts the zero-idle-spin
requirement (M1-04). Apps that need to distinguish single from double must implement
their own timer-based suppression.

## Non-goals (DO NOT implement — INV-5.4)

- **No single-click suppression** — single-click always fires; double-click fires
  additionally when the second click lands in time.
- **No triple-click** — triple is two doubles; no distinct triple-click event.
- **No right-button double-click** — left button only for now.
- **No `on_double_click=` markup attribute** — programmatic registration only.
- **No OS threshold query** — a fixed app-level default (250 ms) is used; the OS
  double-click interval is NOT read at startup (it would require platform-specific code
  that violates INV-1.2's single-code-path rule; GLFW exposes no portable accessor).

## Acceptance criteria

1. Unit tests in `src/app/double_click_test.zig` cover:
   - Two press events within threshold on the same hit: `mouse_button_double` synthesized.
   - Two press events outside threshold: no synthesis.
   - Two press events on different elements within threshold: no synthesis.
   - Two press events within threshold but position > deadzone: no synthesis.
   - Third press immediately after double: state reset; no second double synthesized.
   - `setDoubleClick` stores callback; `doubleClickOf` returns it.
   - `clearDoubleClick` restores `null`.

2. `AppOptions.double_click_threshold_ms` is wired to `AppInner` and used in the
   comparison (verified by unit test with a custom threshold value).

3. `zig build` passes with no regressions in single-click (R31), text-selection (R62),
   and other input tests.

4. Checklist fully ticked.

## Open questions

None. Single-click non-suppression is an explicit design decision documented above.
