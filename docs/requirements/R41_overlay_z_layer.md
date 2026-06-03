# R41 — M4-02: Overlay / z-layer

> Roadmap item: M4-02  
> Depends on: module 09 (renderer/buildDrawList)  
> Read `00_constitution.md` before this file.

## Purpose

Provide a second draw pass so that popups, dropdowns, and tooltips can be painted above all
normal-layer elements without modifying the element tree's depth-first order. The overlay
layer is a flat list of `DrawCommand` slices that the renderer appends after the main pass.
The existing painter's-order (DFS pre-order) guarantee for the normal layer is unchanged.

## What to build

### Overlay slot concept

An **overlay slot** is a named region that owns a `[]DrawCommand` slice produced outside of
the normal `buildDrawList` walk. Slots are identified by an `OverlayId` (a `u16`). The
overlay list is owned by a new `OverlayLayer` struct stored in `App`.

```zig
/// Opaque identifier for one overlay slot.
pub const OverlayId = u16;

pub const OverlaySlot = struct {
    id:       OverlayId,
    commands: []DrawCommand,  // owned by caller; OverlayLayer does NOT free these
};

/// Ordered list of overlay slots. Slots are rendered in insertion order
/// (first inserted = painted first, i.e., behind later slots).
pub const OverlayLayer = struct {
    slots:    std.ArrayListUnmanaged(OverlaySlot) = .empty,
    next_id:  OverlayId = 0,
    gpa:      std.mem.Allocator,

    pub fn init(gpa: std.mem.Allocator) OverlayLayer

    pub fn deinit(self: *OverlayLayer) void

    /// Allocate a new slot id. Does not set any commands yet.
    pub fn allocId(self: *OverlayLayer) OverlayId

    /// Write or replace the command slice for an existing slot.
    /// If no slot with `id` exists, appends a new entry.
    /// The commands slice must outlive the next call to VulkanBackend.drawFrame.
    /// Passing an empty slice hides the slot without removing it.
    pub fn setSlot(self: *OverlayLayer, id: OverlayId, commands: []DrawCommand) void

    /// Remove the slot entirely. Subsequent renders will not include it.
    pub fn removeSlot(self: *OverlayLayer, id: OverlayId) void

    /// Return a flat view: all slot command slices concatenated in order.
    /// Caller provides a scratch allocator; result is valid until the next mutation.
    pub fn flatten(self: *const OverlayLayer, alloc: std.mem.Allocator) error{OutOfMemory}![]DrawCommand
};
```

### Changes to `App`

Add `overlay: OverlayLayer` to the `App` struct (`src/app/app.zig`). Initialize after the
platform, before the frame loop. Deinit before the scene.

### Changes to the draw path

In `App.run()`, the frame submission currently calls `VulkanBackend.drawFrame(commands, atlas)`.
Replace this with a two-pass submission:

```zig
// Build main-layer commands
const main_cmds = try buildDrawList(alloc, &scene, &atlas, tokens);
defer alloc.free(main_cmds);

// Build overlay commands (callers must have populated app.overlay by now)
const overlay_cmds = try app.overlay.flatten(frame_alloc);
defer frame_alloc.free(overlay_cmds);

// Concatenate into one submission slice
const all_cmds = try std.mem.concat(frame_alloc, DrawCommand, &.{ main_cmds, overlay_cmds });
defer frame_alloc.free(all_cmds);

backend.drawFrame(all_cmds, &gpu_atlas);
```

`VulkanBackend.drawFrame` already accepts `[]const DrawCommand`; no changes to the GPU
pipeline are needed. The overlay commands are simply appended and rendered after the main
layer (painter's algorithm: last drawn = on top).

### Dropdown integration (M3-04)

M3-04 (Dropdown open/close) is the first consumer of the overlay layer. When a dropdown is
open, it:

1. Calls `app.overlay.allocId()` once during initialization.
2. Each frame while open, builds a `[]DrawCommand` for the popup list (background rect,
   border rect, one text glyph row per option).
3. Calls `app.overlay.setSlot(dropdown_id, cmds)`.
4. On close, calls `app.overlay.setSlot(dropdown_id, &.{})` (empty slice hides it) or
   `removeSlot`.

This keeps the dropdown popup above all other UI without modifying z-ordering in the element
store.

### Tooltip / popup pattern

Any future overlay consumer (tooltip, modal, context menu) follows the same pattern:
`allocId` → build commands → `setSlot` → `removeSlot` when dismissed.

### Behavioral contract

| Situation | Behavior |
|---|---|
| No overlay slots | `flatten()` returns empty slice; `drawFrame` submits only main commands |
| One dropdown slot open | Its commands append after all main-layer commands |
| Multiple slots | Slots drawn in insertion order (first allocated = lowest z) |
| Slot set to empty slice | Slot exists but contributes zero commands; no visible change |
| Slot removed | No contribution to subsequent frames |
| `flatten()` on large overlay | O(total commands) time, O(1) allocations beyond output slice |

### Module location

```
src/app/overlay.zig          — OverlayLayer, OverlaySlot, OverlayId
src/app/app.zig              — App.overlay field, two-pass draw path
docs/specs/09.types.zig      — OverlayLayer added to module 09 public API (it uses DrawCommand)
docs/requirements/R41_overlay_z_layer.md
```

## Public API

New types:

```zig
pub const OverlayId = u16;
pub const OverlaySlot = struct { id: OverlayId, commands: []DrawCommand };
pub const OverlayLayer = struct {
    pub fn init(gpa: std.mem.Allocator) OverlayLayer
    pub fn deinit(self: *OverlayLayer) void
    pub fn allocId(self: *OverlayLayer) OverlayId
    pub fn setSlot(self: *OverlayLayer, id: OverlayId, commands: []DrawCommand) void
    pub fn removeSlot(self: *OverlayLayer, id: OverlayId) void
    pub fn flatten(self: *const OverlayLayer, alloc: std.mem.Allocator) error{OutOfMemory}![]DrawCommand
};
```

## Non-goals (DO NOT implement — INV-5.4)

- **No z-index integer per element** — the overlay layer is the only z-ordering mechanism;
  there is no per-element z-index on the normal layer (INV-4.2).
- **No more than two layers** — normal + overlay is sufficient for v1. A third
  "tooltip-above-modal" layer is post-v1.
- **No compositor / blend modes** — overlay commands are drawn with standard alpha blending
  only; no multiply, screen, or other blend modes.
- **No hit-testing in the overlay layer** — input dispatch reads the element store and
  layout rects; overlay draw commands have no associated hit area. Dropdown/tooltip hit
  logic is handled separately by their respective widget implementations.
- **No scroll / clip for overlay contents** — overlay slots paint unclipped (they are
  intended for popups that float above all content).
- **No persistence across scene resets** — `App.overlay` is independent of `Scene.reset()`;
  callers are responsible for clearing their slots when the scene resets.

## Acceptance criteria

1. Unit tests in `src/app/overlay_test.zig` cover:
   - `allocId()` returns distinct IDs across multiple calls.
   - `setSlot` with a new ID appends the slot.
   - `setSlot` with an existing ID replaces commands in place.
   - `removeSlot` removes the slot; subsequent `flatten` does not include it.
   - `flatten` on an empty `OverlayLayer` returns an empty slice.
   - `flatten` on two slots returns the first slot's commands followed by the second's.
   - Empty command slice (`setSlot(id, &.{})`) contributes zero commands to `flatten`.
   - `deinit` frees all slots without double-free.

2. Integration test (can be headless — no GPU required):
   - Build main layer commands and two overlay slots, call `flatten`, verify the resulting
     slice is `main ++ slot_a ++ slot_b` in that order.

3. `App` initializes and deinits `overlay` correctly; no memory leaks under Zig's testing
   allocator.

4. Running the full app with a dropdown open: the dropdown popup list is visually above all
   other UI content (no z-fighting).

5. No per-frame allocations in `setSlot` or `removeSlot` (only in `flatten`, which is
   called once per frame and frees via the frame allocator).

6. Checklist fully ticked.

## Open questions

None. Two layers (main + overlay) cover all v1 overlay use cases. The `OverlayId` type is
`u16` to cap the maximum slot count at 65 535, which is more than sufficient for v1.
