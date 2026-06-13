# RB5 — M11-06: Touch / trackpad gesture support

> Roadmap item: M11-06  
> Depends on: M1-02 (event delivery)  
> Read `00_constitution.md` before this file.

## Purpose

Expose swipe-to-scroll and pinch-to-zoom gesture events from GLFW's scroll and zoom
callbacks to app code. GLFW does not have a separate "gesture" API — on macOS (out of
scope — INV-1.2) it maps trackpad gestures to scroll deltas; on Windows and Linux
precision trackpads and scroll wheels both arrive as `glfwScrollCallback` events. Pinch
zoom is reported by GLFW via a dedicated `glfwSetScrollCallback` with large `dy` values
on some drivers, but more reliably via `glfwSetZoomCallback` on platforms that support
it.

This requirement adds two new `InputEvent` variants (`gesture_swipe` and
`gesture_pinch`) synthesized by the Platform layer from GLFW scroll data, plus wires
them into the existing `dispatchEvents` path for scroll containers and a new optional
`on_pinch` callback.

**Scope clarification:** Windows and Linux precision trackpads report two-finger scroll
as scroll events with fractional `dy`/`dx` values. This requirement treats any scroll
event as a potential swipe — no driver-level gesture recognition is needed. For pinch,
GLFW 3.4 exposes `glfwSetScrollCallback` only; a heuristic based on rapid `dy` magnitude
changes is used where the platform does not report distinct pinch events.

## What to build

### Two new `InputEvent` variants in module 01

Extend `InputEvent` in [01.types.zig](../specs/01.types.zig) and `src/01/types.zig`:

```zig
pub const InputEvent = union(enum) {
    mouse_move:           struct { x: f32, y: f32 },
    mouse_button:         struct { button: MouseButton, action: InputAction, x: f32, y: f32 },
    mouse_button_double:  struct { button: MouseButton, x: f32, y: f32 },  // RB3
    scroll:               struct { dx: f32, dy: f32 },
    gesture_swipe:        struct { dx: f32, dy: f32 },  // NEW
    gesture_pinch:        struct { scale_delta: f32 },  // NEW  >1 = zoom in, <1 = zoom out
    key:                  struct { key: Key, action: InputAction, mods: Modifiers },
    char:                 struct { codepoint: u21 },
};
```

`gesture_swipe` carries fractional pixel deltas (same coordinate system as `scroll`).
`gesture_pinch` carries a multiplicative scale delta: `1.0` = no change, `1.1` = 10%
zoom in, `0.9` = 10% zoom out.

### Synthesis in the GLFW scroll callback (module 01)

The existing `glfwScrollCallback` pushes `InputEvent.scroll`. This requirement adds a
synthesis step in `PlatformImpl` to distinguish "scroll" (single-axis, large steps,
likely a mouse wheel) from "swipe" (two-axis, small fractional values, likely a
trackpad):

```zig
// In the GLFW scroll callback (src/01/types.zig):
fn scrollCallback(window: ?*c.GLFWwindow, xoffset: f64, yoffset: f64) callconv(.C) void {
    const ctx = getCtx(window);
    const dx = @floatCast(f32, xoffset);
    const dy = @floatCast(f32, yoffset);

    // Heuristic: if both axes have non-zero fractional values, treat as a swipe gesture.
    // A mouse wheel produces integer dy with dx=0; a trackpad produces small fractional
    // dx and/or dy simultaneously.
    const is_swipe = (dx != 0 and dy != 0)
        or (std.math.floor(dy) != dy)
        or (std.math.floor(dx) != dx);

    const ev: InputEvent = if (is_swipe)
        .{ .gesture_swipe = .{ .dx = dx * 20, .dy = dy * 20 } }
    else
        .{ .scroll = .{ .dx = dx, .dy = dy } };

    pushEvent(ctx, ev);
}
```

The `* 20` scale factor on swipe makes trackpad pixel deltas comparable to scroll wheel
step sizes. This constant is named `SWIPE_SCALE: f32 = 20` in `src/01/types.zig`.

### Pinch synthesis via zoom callback (module 01, Windows/Linux only)

GLFW 3.4 added `glfwSetWindowContentScaleCallback` but no dedicated zoom/pinch callback.
On Windows, precision trackpad pinch events arrive as a synthetic scroll with `dy`
substantially larger than typical scroll steps (heuristic threshold: `|dy| > 5` with no
mouse-button held). A proper pinch callback requires a Win32 `WM_GESTURE` handler.

For v1 scope: synthesize `gesture_pinch` from the scroll callback when `|dy| > 5` and
`dx == 0`:

```zig
const PINCH_THRESHOLD: f32 = 5.0;

// Inside scrollCallback, after the swipe check:
if (!is_swipe and std.math.fabs(dy) > PINCH_THRESHOLD and dx == 0) {
    // Treat as pinch: scale_delta > 1 for zoom in (dy > 0), < 1 for zoom out.
    const scale_delta: f32 = 1.0 + dy * 0.05;  // 5% per threshold unit
    const ev: InputEvent = .{ .gesture_pinch = .{ .scale_delta = scale_delta } };
    pushEvent(ctx, ev);
    return;  // do NOT also emit a scroll event
}
```

The `0.05` factor (`PINCH_SCALE: f32 = 0.05`) is named in `src/01/types.zig`.

### `gesture_swipe` routing to scroll containers (app.zig)

`gesture_swipe` is treated identically to `scroll` for scroll container handling:

```zig
.gesture_swipe => |gs| {
    // Reuse the same scroll-container hit-test + offset logic as .scroll.
    handleScrollEvent(&self.scene, mouse_x, mouse_y, gs.dx, gs.dy);
},
```

where `handleScrollEvent` is an extracted helper that processes both `scroll` and
`gesture_swipe` events (DRY refactor of the existing scroll-wheel path — R35).

### `on_pinch` callback per element in `Scene`

```zig
/// Pinch callback receives the scale_delta from the gesture_pinch event.
pub const PinchCallbackFn = *const fn (idx: u32, scale_delta: f32) void;

pub const Scene = struct {
    // ...existing fields...

    /// Per-element pinch callbacks. null = element ignores pinch.
    _pinch: std.ArrayListUnmanaged(?PinchCallbackFn) = .empty,

    pub fn setPinch(self: *Scene, idx: u32, cb: PinchCallbackFn) void
    pub fn clearPinch(self: *Scene, idx: u32) void
    pub fn pinchOf(self: *const Scene, idx: u32) ?PinchCallbackFn
};
```

`gesture_pinch` dispatch in `dispatchEvents`:

```zig
.gesture_pinch => |gp| {
    // Deliver to the topmost element under the cursor that has on_pinch registered.
    const hit = hitTest(&self.scene, self.last_cursor_x, self.last_cursor_y);
    if (hit != NONE) {
        if (self.scene.pinchOf(hit)) |cb| {
            cb(hit, gp.scale_delta);  // called immediately, not queued (INV-3.3 note below)
        }
    }
},
```

`on_pinch` is called synchronously (not queued) because its purpose is to update a
zoom signal (`scene.markDirty` is called inside the callback). This is consistent with
INV-3.3 because the pinch callback does not propagate state change through a second
reactivity channel — it calls `signal.set`, which marks the bitset dirty via the normal
path.

### Module location

```
src/01/types.zig         — InputEvent.gesture_swipe / gesture_pinch variants,
                           scroll callback synthesis, SWIPE_SCALE, PINCH_THRESHOLD,
                           PINCH_SCALE constants
docs/specs/01.types.zig  — InputEvent additions
src/07/types.zig         — PinchCallbackFn, _pinch array, setPinch, clearPinch, pinchOf
docs/specs/07.types.zig  — same
src/app/app.zig          — gesture_swipe and gesture_pinch dispatch in dispatchEvents,
                           handleScrollEvent helper
docs/requirements/RB5_touch_trackpad_gestures.md
```

## Public API

```zig
// Module 01 — InputEvent
.gesture_swipe: struct { dx: f32, dy: f32 }
.gesture_pinch: struct { scale_delta: f32 }

// Scene
pub const PinchCallbackFn = *const fn (idx: u32, scale_delta: f32) void
pub fn setPinch(self: *Scene, idx: u32, cb: PinchCallbackFn) void
pub fn clearPinch(self: *Scene, idx: u32) void
pub fn pinchOf(self: *const Scene, idx: u32) ?PinchCallbackFn
```

## Behavioral contract

| Situation | Behavior |
|---|---|
| Smooth trackpad two-finger scroll (fractional dx/dy) | `gesture_swipe` event; scroll containers respond |
| Mouse wheel (integer dy, dx=0) | `scroll` event; scroll containers respond (unchanged) |
| Trackpad pinch heuristic (large `|dy|`, dx=0) | `gesture_pinch` event; `on_pinch` callback fires on hit element |
| `gesture_swipe` over scroll container | Content scrolls (same as `scroll`) |
| `gesture_swipe` not over scroll container | Event ignored |
| `gesture_pinch` over element with `on_pinch` | Callback fires synchronously |
| `gesture_pinch` over element without `on_pinch` | Event silently dropped |

## Non-goals (DO NOT implement — INV-5.4)

- **No Win32 `WM_GESTURE` API** — heuristic-only pinch detection; native gesture API
  would require platform-specific code paths violating INV-1.2's spirit.
- **No gesture velocity / momentum** — instant offset with no inertia.
- **No three-finger or four-finger gesture** — two-finger only (scroll + pinch).
- **No gesture-begin / gesture-end events** — single-event model only.
- **No `on_swipe` element callback** — swipe routes to scroll containers only.
- **No on-screen zoom UI** — pinch callback gives the app a scale delta; the app
  implements any zoom UI it wants using its own signals.
- **No touch screen** — GLFW does not expose a touch API on Windows/Linux; this
  requirement covers trackpad only.

## Acceptance criteria

1. Unit tests in `src/01/gesture_test.zig` (or `src/01/01_test.zig`) cover:
   - Integer `dy`, `dx=0` scroll input → `scroll` event (not `gesture_swipe`).
   - Fractional `dy` scroll input → `gesture_swipe` event.
   - Both `dx ≠ 0` and `dy ≠ 0` → `gesture_swipe` event.
   - Large `|dy| > 5`, `dx=0`, integer `dy` → `gesture_pinch` event (not `scroll`).
   - `scale_delta` for `dy = 10`: equals `1.0 + 10 * 0.05 = 1.5`.
   - `scale_delta` for `dy = -6`: equals `1.0 + (-6) * 0.05 = 0.7`.

2. Unit tests in `src/07/07_test.zig` (or `src/app/gesture_test.zig`) cover:
   - `setPinch` stores callback; `pinchOf` returns it.
   - `clearPinch` restores `null`.

3. Integration (verified manually on a precision trackpad or via synthetic events):
   - Two-finger scroll on a scroll container moves its content.
   - Pinch gesture fires `on_pinch` callback on the hit element.

4. `zig build` passes with no regressions in existing scroll-container (R35) tests.

5. Checklist fully ticked.

## Open questions

The heuristic pinch threshold (`PINCH_THRESHOLD = 5.0`) and scale factor
(`PINCH_SCALE = 0.05`) were chosen to give a reasonable feel on Windows precision
trackpads. These may need tuning after device testing; they are named constants for easy
adjustment without searching the code.
