# R11 — M1-02: Event delivery

> Roadmap item: M1-02  
> Depends on: module 01 (Platform), M1-01 (App main loop)  
> Read `00_constitution.md` before this file.

## Purpose

Expose mouse position, mouse buttons, scroll wheel, keyboard keys, and text-input characters
from GLFW to application code through a typed, buffered event queue drained once per frame.

## What to build

### Event types

Add to `src/app/types.zig`:

```zig
pub const MouseButton = enum { left, right, middle };
pub const Action = enum { press, release };
pub const Key = enum {
    // printable row — used for keyboard shortcuts and navigation
    enter, escape, tab, backspace, delete,
    left, right, up, down, home, end, page_up, page_down,
    // modifier detection
    left_shift, right_shift, left_ctrl, right_ctrl, left_alt, right_alt,
    // function keys
    f1, f2, f3, f4, f5, f6, f7, f8, f9, f10, f11, f12,
    // catch-all for any key not in the above list
    other,
};

pub const Event = union(enum) {
    mouse_move:   struct { x: f32, y: f32 },
    mouse_button: struct { button: MouseButton, action: Action, x: f32, y: f32 },
    scroll:       struct { dx: f32, dy: f32 },
    key:          struct { key: Key, action: Action, mods: Modifiers },
    char:         struct { codepoint: u21 },   // UTF-8 text input (not key codes)
};

pub const Modifiers = packed struct {
    shift: bool = false,
    ctrl:  bool = false,
    alt:   bool = false,
    super: bool = false,
};
```

`char` events carry the Unicode codepoint of a typed character (from GLFW's
`glfwSetCharCallback`). They are separate from `key` events — a key press that generates a
character produces both a `key` event and a `char` event; the application layer decides which
it needs.

### `EventQueue`

A thin ring buffer (or `std.ArrayList`) drained once per frame. Lives in `src/app/events.zig`.

```zig
pub const EventQueue = struct {
    pub fn init(gpa: std.mem.Allocator) EventQueue
    pub fn deinit(self: *EventQueue) void
    pub fn push(self: *EventQueue, event: Event) void  // called from GLFW callbacks
    pub fn drain(self: *EventQueue) []const Event      // returns slice, valid until next drain
    pub fn clear(self: *EventQueue) void               // called after drain is processed
};
```

`drain` returns the buffered events as a slice owned by the queue. The caller iterates it,
then calls `clear()`. No allocation on `drain` or `clear`.

Capacity: pre-allocate for 256 events. If a frame produces more (extremely unlikely in a
personal tool), the extras are silently dropped and a `std.log.warn` is emitted once per
overflow.

### Integration with `Platform`

`Platform` gains two new methods:

```zig
// Register the event queue that GLFW callbacks will push into.
// Must be called once after Platform.init, before the frame loop.
pub fn setEventQueue(self: *Platform, queue: *EventQueue) void

// Return the current cursor position in screen pixels (top-left origin).
// Useful for hit-testing when no mouse_move event has arrived yet.
pub fn cursorPos(self: *Platform) struct { x: f32, y: f32 }
```

`setEventQueue` installs GLFW callbacks via `glfwSetCursorPosCallback`,
`glfwSetMouseButtonCallback`, `glfwSetScrollCallback`, `glfwSetKeyCallback`, and
`glfwSetCharCallback`. Each callback calls `queue.push(...)`.

GLFW callback context: the queue pointer is stored via `glfwSetWindowUserPointer` and
retrieved in each callback with `glfwGetWindowUserPointer`. Do NOT use a global variable.

### Integration with `App`

`App` gains:

- An `EventQueue` field.
- A call to `platform.setEventQueue(&event_queue)` at the end of `App.init`.
- In the frame loop, after `platform.pollEvents()`:
  ```
  const events = event_queue.drain();
  defer event_queue.clear();
  self.dispatchEvents(events);  // placeholder for M3 widget interaction
  ```
- `dispatchEvents` is a no-op stub in this milestone — it exists so M3 can fill it in without
  changing the loop structure.

### Coordinate system

All positions delivered in `mouse_move`, `mouse_button`, and `cursorPos` are in **logical
pixels** (GLFW's default on all platforms — no DPI scaling applied at this layer). DPI
handling is post-v1.

## Module location

```
src/app/events.zig       — EventQueue, Event, MouseButton, Key, Action, Modifiers
src/app/types.zig        — re-exports Event, Key, etc. (or inline if file stays small)
src/app/events_test.zig  — unit tests for EventQueue (no GPU, no GLFW)
```

The new Platform methods (`setEventQueue`, `cursorPos`) are added to `src/01/types.zig`
with the same stub pattern as the existing Platform methods.

## Non-goals (DO NOT implement — INV-5.4)

- NO hit-testing — translating a mouse position into an element is M3-01 (focus model).
- NO event routing to widgets — M3's `dispatchEvents` stub is the hook; don't fill it here.
- NO gamepad / joystick input.
- NO touch / pointer events.
- NO DPI / HiDPI scaling — logical pixels only at this layer.
- NO global event filters or middleware.

## Acceptance criteria

1. `zig build test-events` runs `src/app/events_test.zig`. Tests cover:
   - Push N events, drain returns all N in order.
   - Drain after clear returns zero events.
   - Push more than 256 events — only 256 delivered, warn logged.
2. Manual verification: on a running app, GLFW callbacks fire and events appear in the queue
   (verified by a temporary `std.log.debug` print in the stub `dispatchEvents`).
3. `setEventQueue` and `cursorPos` added to `src/01/types.zig` with matching signatures.
4. Checklist fully ticked.

## Open questions

None. If the GLFW callback threading model (callbacks fire on the polling thread, which is the
main thread for single-threaded apps) ever causes issues, surface it — do not add locks
speculatively.
