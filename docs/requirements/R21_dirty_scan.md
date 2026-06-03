# R21 — M2-02: Dirty bitset scan

> Roadmap item: M2-02  
> Depends on: M2-01 (Signal type and `StaleFn`), M1-01 (App main loop), M1-04 (Frame pacing)  
> Read `00_constitution.md` before this file.

## Purpose

Make the frame loop idle-friendly and signal-aware. When no element is dirty, skip layout,
draw-command building, and GPU submission entirely — the thread blocks until the OS delivers
a new input event. When at least one element is dirty, run the full pipeline, then clear all
dirty bits so the next frame is clean unless a signal changes again.

This delivers the first half of INV-3.3: "Each frame scans only set bits." The scan in M2-02
is binary (any dirty vs. none dirty); incremental subtree layout is post-v1.

## What to build

### `ElementStore.hasDirty()` — `src/03/types.zig`

Add one read-only method to `ElementStore`:

```zig
/// Return true if any element has its dirty bit set.
/// O(capacity / 64) — negligible for < 1 000 elements.
pub fn hasDirty(self: *const ElementStore) bool {
    return self.dirty.count() > 0;
}
```

`std.DynamicBitSetUnmanaged.count()` scans a word array; there is no O(1) shortcut in the
standard library at this time. For the element counts expected in this project the cost is
unmeasurable.

### `ElementStore.markAllDirty()` — `src/03/types.zig`

Add a helper that marks every **live** element index dirty. Used by `Scene.instantiate()`
to guarantee the first frame always paints:

```zig
/// Mark all live elements dirty. Called once after Scene.instantiate()
/// so the very first frame runs the full layout + paint pipeline.
pub fn markAllDirty(self: *ElementStore) void {
    var i: u32 = 0;
    while (i < self.gen.items.len) : (i += 1) {
        // gen > 0 means the slot has been used at least once and is currently live
        // (freed slots reuse an index with the same gen until next alloc increments it;
        // checking `free` list membership is O(n) — gen > 0 is the conservative but safe
        // check here because a first-frame full paint of a stale-freed slot is harmless).
        if (self.gen.items[i] > 0) self.dirty.set(i);
    }
}
```

`Scene.instantiate()` (module 07) must call `self.elements.markAllDirty()` at the end of
a successful instantiation. Add this call to the module 07 implementation; do NOT change
the `instantiate` public signature.

### `Platform.waitEvents()` — `src/01/types.zig`

Add one method to `Platform`:

```zig
/// Block the calling thread until the OS delivers at least one windowing or
/// input event, then return. Wraps `glfwWaitEvents`.
/// Call only from the main thread (GLFW requirement).
pub fn waitEvents(self: *Platform) void
```

Implementation body:

```zig
pub fn waitEvents(self: *Platform) void {
    _ = self;
    c.glfwWaitEvents();
}
```

`glfwWaitEvents` is already in scope because `src/01/` uses `@cImport` for GLFW.

### Frame loop changes — `src/app/app.zig`

Modify `App.run()`. The full loop after M2-02:

```
while (!platform.shouldClose()) {
    // 1. Collect OS events.
    platform.pollEvents();
    const events = event_queue.drain();
    defer event_queue.clear();
    self.dispatchEvents(events);

    // 2. Refresh bindings — copy current signal values into Scene arrays.
    //    (Stub for now; filled in by M2-04.)
    self.refreshBindings();

    // 3. Skip GPU work when nothing has changed.
    if (!self.scene.elements.hasDirty()) {
        self.platform.waitEvents();   // yield until the OS wakes us
        continue;
    }

    // 4. Standard frame pipeline (unchanged from M1).
    if (!self.backend.beginFrame()) continue;
    try self.scene.measurePass(&self.font, &self.atlas_cpu);
    if (self.atlas_cpu.generation != self.atlas_generation_seen) {
        self.atlas_gpu.deinit(&self.backend);
        self.atlas_gpu = try GpuAtlas.upload(
            &self.backend, self.atlas_cpu.bitmap, self.atlas_cpu.width, self.atlas_cpu.height,
        );
        self.atlas_generation_seen = self.atlas_cpu.generation;
    }
    LayoutEngine.solve(self.gpa, &self.scene.elements.layout);
    self.draw_list.clearRetainingCapacity();
    buildDrawList(&self.scene, &self.atlas_cpu, &self.draw_list);
    self.backend.clear(.{ 0, 0, 0, 1 });
    self.backend.drawFrame(self.draw_list.items, &self.atlas_gpu);
    self.backend.endFrame();

    // 5. Clear dirty bits — every dirty element was just painted.
    self.scene.elements.dirty.unsetAll();
}
```

Key details:

- **`waitEvents` placement:** called only when `hasDirty()` is false, immediately before
  `continue`. Do NOT call it when dirty elements exist — that would delay a needed repaint.
- **`unsetAll` placement:** after `backend.endFrame()`, before the next iteration. Dirty bits
  set by a `Signal.set()` call inside `dispatchEvents` in the **same** iteration are already
  accounted for (painted this frame) and must be cleared.
- **No partial layout:** when any element is dirty, the full `LayoutEngine.solve()` runs over
  all elements. Incremental subtree layout is post-v1.

### `App.refreshBindings` stub

Add a private method to `App` so M2-04 has a hook to fill in:

```zig
/// Copy current signal values into Scene arrays before layout.
/// Stub — implemented by M2-04 (BindingSet.refresh).
fn refreshBindings(self: *App) void {
    _ = self;
}
```

M2-04 replaces this stub body with `self.bindings.refresh(&self.scene)`.

## Non-goals (DO NOT implement — INV-5.4)

- **No incremental subtree layout** — full layout when any element is dirty.
- **No dirty propagation to ancestors** — signals write dirty bits directly; no
  parent/ancestor marking logic.
- **No vsync mode switching per-frame** — present mode is set once at backend init (M1-04).
- **No frame budget measurement or timing display** — that is M9-03.
- **No `waitEventsTimeout` variant** — add it only if headless CI hangs surface it as an
  open question; do not add it speculatively.

## Acceptance criteria

1. With no signals set after `instantiate`, the frame loop calls `platform.waitEvents()` on
   each iteration and does NOT call `backend.beginFrame()`. Verified by a test double (stub
   `Platform` that counts `beginFrame` calls).
2. After exactly one `Signal.set()` that subscribes one element, the **next** loop iteration
   calls `backend.beginFrame()` and clears the dirty bitset.
3. After `backend.endFrame()` in a dirty frame, `scene.elements.hasDirty()` returns `false`.
4. `Scene.instantiate()` leaves every live element with its dirty bit set — verified by
   calling `hasDirty()` immediately after `instantiate`.
5. `ElementStore.hasDirty()` and `ElementStore.markAllDirty()` compile and pass unit tests:
   - `hasDirty()` returns `false` on an empty store and `true` after `dirty.set(i)`.
   - `markAllDirty()` sets the dirty bit for every slot with `gen > 0`.
6. `Platform.waitEvents()` added to `src/01/types.zig` with matching signature.
7. Checklist fully ticked.

## Open questions

If `glfwWaitEvents` causes hangs in a headless test environment (no display), investigate
`glfwWaitEventsTimeout(0.016)` as a fallback. Do NOT implement speculatively — raise it
with the human before adding the timeout variant to the `Platform` API.
