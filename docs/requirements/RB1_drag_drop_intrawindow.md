# RB1 — M11-02: Drag-and-drop (intra-window)

> Roadmap item: M11-02  
> Depends on: M1-02 (event delivery)  
> Read `00_constitution.md` before this file.

## Purpose

Allow elements to be designated as drag sources and drop targets within the same window.
When the user presses and holds the left mouse button over a drag source, moves beyond a
deadzone, and releases over a drop target, the framework fires `drag_start`, `drag_move`,
`drag_end`, and `drop` callbacks. Drag state is stored in a single `DragState` struct on
`AppInner` (not in `Scene` — this is transient interaction state, not per-element data).
No visual drag-proxy is rendered by default; apps render their own if desired.

## What to build

### `DragState` on `AppInner`

Add to `src/app/app.zig`:

```zig
/// Transient drag-and-drop state. Lives on AppInner, not in Scene (INV-3.1:
/// only one drag is active at a time — no per-element parallel array needed).
pub const DragState = struct {
    /// Index of the element that is the drag source. NONE = no drag in progress.
    source_idx: u32 = NONE,
    /// True once the deadzone has been exceeded and the drag has officially started.
    active: bool = false,
    /// Mouse position when left button was first pressed on the source.
    origin_x: f32 = 0,
    origin_y: f32 = 0,
    /// Current mouse position during drag.
    current_x: f32 = 0,
    current_y: f32 = 0,
    /// App-defined opaque payload (e.g. an index into a data array).
    /// Set by the drag_start callback; passed unchanged to drag_move/drag_end/drop.
    payload: u64 = 0,
};
```

`AppInner` gains one field: `drag: DragState = .{}`.

### Drag source and drop target registration in `Scene`

Intra-window DnD does not require new widget kinds. Two optional parallel arrays track
registrations:

In [07.types.zig](../specs/07.types.zig) and `src/07/types.zig`:

```zig
pub const DragCallbacks = struct {
    /// Called once when the drag deadzone is exceeded.
    /// Return value: u64 payload to carry through the drag lifetime.
    on_drag_start: ?*const fn (source_idx: u32, x: f32, y: f32) u64 = null,
    /// Called each mouse-move tick while dragging.
    on_drag_move:  ?*const fn (source_idx: u32, x: f32, y: f32, payload: u64) void = null,
    /// Called when the mouse button is released (whether or not over a drop target).
    on_drag_end:   ?*const fn (source_idx: u32, payload: u64) void = null,
};

pub const DropCallbacks = struct {
    /// Called when a dragged element is released over this target.
    on_drop: ?*const fn (target_idx: u32, source_idx: u32, payload: u64) void = null,
};

pub const Scene = struct {
    // ...existing fields...

    /// Drag source callbacks per element. null = element is not a drag source.
    _drag: std.ArrayListUnmanaged(?DragCallbacks) = .empty,
    /// Drop target callbacks per element. null = element is not a drop target.
    _drop: std.ArrayListUnmanaged(?DropCallbacks) = .empty,

    /// Register element `idx` as a drag source.
    pub fn setDragSource(self: *Scene, idx: u32, cbs: DragCallbacks) void

    /// Register element `idx` as a drop target.
    pub fn setDropTarget(self: *Scene, idx: u32, cbs: DropCallbacks) void

    /// Clear drag-source registration for `idx`.
    pub fn clearDragSource(self: *Scene, idx: u32) void

    /// Clear drop-target registration for `idx`.
    pub fn clearDropTarget(self: *Scene, idx: u32) void
};
```

`instantiateNode` does NOT set drag/drop from markup attributes — these are set
programmatically by the app after instantiation, exactly as `on_click` callbacks are.

### Drag deadzone

The drag is not "active" until the mouse has moved more than `DRAG_DEADZONE_PX = 4`
pixels (Euclidean distance) from the origin. This prevents accidental drags on slow
clicks.

### Input handling in `dispatchEvents` (app.zig)

Extend the existing mouse handling section:

```zig
// --- Drag-and-drop (M11-02) ---

// Phase 1: left button down — candidate source
if (ev == .mouse_button and ev.mouse_button.button == .left
    and ev.mouse_button.action == .press
    and self.drag.source_idx == NONE) {
    const hit = hitTest(&self.scene, ev.mouse_button.x, ev.mouse_button.y);
    if (hit != NONE and self.scene._drag.items[hit] != null) {
        self.drag = .{
            .source_idx = hit,
            .origin_x   = ev.mouse_button.x,
            .origin_y   = ev.mouse_button.y,
            .current_x  = ev.mouse_button.x,
            .current_y  = ev.mouse_button.y,
        };
    }
}

// Phase 2: mouse move — activate once deadzone exceeded
if (ev == .mouse_move and self.drag.source_idx != NONE and !self.drag.active) {
    self.drag.current_x = ev.mouse_move.x;
    self.drag.current_y = ev.mouse_move.y;
    const dx = self.drag.current_x - self.drag.origin_x;
    const dy = self.drag.current_y - self.drag.origin_y;
    if (dx * dx + dy * dy > DRAG_DEADZONE_PX * DRAG_DEADZONE_PX) {
        self.drag.active = true;
        const cbs = self.scene._drag.items[self.drag.source_idx].?;
        if (cbs.on_drag_start) |f| {
            self.drag.payload = f(self.drag.source_idx,
                                   self.drag.current_x, self.drag.current_y);
        }
    }
}

// Phase 3: mouse move while active — on_drag_move
if (ev == .mouse_move and self.drag.active) {
    self.drag.current_x = ev.mouse_move.x;
    self.drag.current_y = ev.mouse_move.y;
    const cbs = self.scene._drag.items[self.drag.source_idx].?;
    if (cbs.on_drag_move) |f| {
        f(self.drag.source_idx, self.drag.current_x, self.drag.current_y,
          self.drag.payload);
    }
}

// Phase 4: left button release — on_drag_end + on_drop
if (ev == .mouse_button and ev.mouse_button.button == .left
    and ev.mouse_button.action == .release
    and self.drag.source_idx != NONE) {
    if (self.drag.active) {
        const cbs = self.scene._drag.items[self.drag.source_idx].?;
        if (cbs.on_drag_end) |f| {
            f(self.drag.source_idx, self.drag.payload);
        }
        // Find drop target under cursor
        const hit = hitTest(&self.scene, ev.mouse_button.x, ev.mouse_button.y);
        if (hit != NONE and self.scene._drop.items[hit] != null) {
            const dcbs = self.scene._drop.items[hit].?;
            if (dcbs.on_drop) |f| {
                f(hit, self.drag.source_idx, self.drag.payload);
            }
        }
    }
    self.drag = .{};  // reset
}
```

Drag callbacks are called immediately (synchronous), NOT queued through
`_queued_callbacks`. They are read-only observers of transient drag geometry;
they do not mutate scene state directly (INV-3.3).

### Cursor during drag

While `self.drag.active`, override the cursor shape to `resize_all` to give the user
a visual cue that a drag is in progress. This is handled in the existing cursor-update
path added by RB0:

```zig
if (self.drag.active) {
    platform.setCursor(.resize_all);
} else {
    // ... normal cursor selection from RB0 ...
}
```

### Module location

```
src/app/app.zig          — DragState struct, drag fields on AppInner, dispatchEvents extension
src/07/types.zig         — DragCallbacks, DropCallbacks, _drag/_drop parallel arrays, accessors
docs/specs/07.types.zig  — DragCallbacks, DropCallbacks, _drag/_drop, setDragSource/setDropTarget
docs/requirements/RB1_drag_drop_intrawindow.md
```

## Public API

```zig
// Scene
pub const DragCallbacks = struct { on_drag_start, on_drag_move, on_drag_end }
pub const DropCallbacks = struct { on_drop }
pub fn setDragSource(self: *Scene, idx: u32, cbs: DragCallbacks) void
pub fn setDropTarget(self: *Scene, idx: u32, cbs: DropCallbacks) void
pub fn clearDragSource(self: *Scene, idx: u32) void
pub fn clearDropTarget(self: *Scene, idx: u32) void
```

## Behavioral contract

| Event | Behavior |
|---|---|
| Left press on drag source | Candidate recorded; no callback yet |
| Mouse move < deadzone | No drag started |
| Mouse move ≥ deadzone | `on_drag_start` fires; `drag.active = true` |
| Mouse move while active | `on_drag_move` fires each move event |
| Left release while active, over drop target | `on_drag_end` fires, then `on_drop` fires |
| Left release while active, not over target | `on_drag_end` fires; no `on_drop` |
| Left release before deadzone | No callbacks; state reset |
| Escape key while drag active | `on_drag_end` fires with `payload`; state reset |

### Escape key cancel

If `Key.escape` is pressed while `self.drag.active`, treat it as a drag cancel:
call `on_drag_end` (if registered) and reset `self.drag = .{}`.

## Non-goals (DO NOT implement — INV-5.4)

- **No cross-window drag** — intra-window only; multi-window DnD is post-v1.
- **No OS-level drag** — no MIME types, no inter-process data transfer.
- **No visual drag proxy / ghost image** — apps render their own if desired.
- **No drag-over highlight** — no automatic hover state on drop targets; apps style
  them via signal-driven style overrides if needed.
- **No drag data types** — one `u64` payload; type interpretation is app responsibility.
- **No multi-element drag** — one source element per drag.
- **No markup `draggable=` attribute** — registration is programmatic only.
- **No touch drag** — mouse only (INV-1.2 desktop scope).

## Acceptance criteria

1. Unit tests in `src/app/drag_drop_test.zig` cover:
   - `setDragSource` / `setDropTarget` store callbacks; `clearDragSource` / `clearDropTarget`
     restore `null`.
   - Pressing left button on a non-source element: `drag.source_idx` stays `NONE`.
   - Pressing left button on a source, moving < deadzone, releasing: no callbacks fired.
   - Pressing left button on a source, moving ≥ deadzone: `on_drag_start` called once.
   - Subsequent move events: `on_drag_move` called each time.
   - Release over a registered drop target: `on_drag_end` then `on_drop` both called.
   - Release not over a target: `on_drag_end` called; `on_drop` not called.
   - Escape key during active drag: `on_drag_end` called; state reset.
   - After any drag ends, `drag.active` is `false` and `drag.source_idx` is `NONE`.

2. Integration (verified manually):
   - Drag a source element over a drop target; `on_drop` fires.
   - Cursor shows `resize_all` during active drag.

3. Checklist fully ticked.

## Open questions

None. The `u64` payload is intentionally opaque — callers can cast a pointer or an index.
