# R83 — M8-04: Multi-window

> Roadmap item: M8-04  
> Depends on: M1-01 (App main loop)  
> Read `00_constitution.md` before this file.

## Purpose

Allow the application to open a second (or third) top-level window that shares the GPU
device and font atlas with the primary window but owns its own `Scene`, swapchain, and
`VulkanBackend` surface. Each window runs the same frame loop driven by a single
`MultiWindowApp`.

An application author writes:

```zig
var mw = try MultiWindowApp.init(gpa, primary_opts);
defer mw.deinit();

// Open a secondary window (shares GPU device + font atlas):
const sec_id = try mw.openWindow(secondary_opts, SecondaryScreen.build, null);

mw.run();    // drives all open windows in one loop; returns when all are closed
```

---

## Motivation

Some use cases require a second window: a detached inspector panel, a settings dialog that
floats separately from the main content, a preview window. Without this feature the author
must launch a second process or fake a second window with an overlay — both are worse options.

---

## What to build

### 1. `WindowEntry` — one managed window

```zig
pub const WindowEntry = struct {
    id: WindowId,
    platform: Platform,        // owns the GLFW window + surface
    backend: VulkanBackend,    // owns the swapchain for this window
    scene: Scene,
    bindings: BindingSet,
    overlay: OverlayLayer,
    pending_resize: ?Extent2D,
    event_queue: EventQueue,
    build: ScreenFn,           // called once after init (same type as Navigator.ScreenFn)
    ctx: ?*anyopaque,
    tokens: Tokens,
    open: bool,                // false → will be removed at the top of the next frame
};
```

`WindowId` is `u16`. Value `0` is reserved/invalid (same convention as `ImageId` and
`OverlayId` — INV-3.2 generational semantics are not used here because windows are not
indexed into the element store).

### 2. `MultiWindowApp` struct

```zig
pub const MultiWindowApp = struct {
    gpa: std.mem.Allocator,

    // Shared resources — owned once, used by all windows.
    font_family: FontFamily,
    atlas_cpu: GlyphAtlas,
    atlas_gpu: GpuAtlas,        // one GPU atlas, uploaded to the device once
    image_atlas: ImageAtlas,
    tokens: Tokens,

    // Per-window state.
    windows: std.ArrayListUnmanaged(WindowEntry),
    next_id: u16,

    // Atlas generation tracking (shared).
    atlas_generation_seen: u32,
    image_atlas_generation_seen: u32,

    pub fn init(gpa: std.mem.Allocator, opts: AppOptions) !MultiWindowApp;
    pub fn deinit(self: *MultiWindowApp) void;

    /// Open a new window. Returns the new window's id.
    /// build is called immediately to populate the window's scene.
    pub fn openWindow(
        self: *MultiWindowApp,
        opts: WindowOptions,
        build: ScreenFn,
        ctx: ?*anyopaque,
    ) !WindowId;

    /// Close a window by id. The window is removed at the start of the next frame.
    /// Closing the last window ends the run loop.
    pub fn closeWindow(self: *MultiWindowApp, id: WindowId) void;

    /// Run the frame loop until all windows are closed.
    pub fn run(self: *MultiWindowApp) void;

    /// Look up a WindowEntry by id. Returns null if not found or already closed.
    pub fn windowById(self: *MultiWindowApp, id: WindowId) ?*WindowEntry;
};
```

### 3. Shared GPU device

All `VulkanBackend` instances in a `MultiWindowApp` share the same `VkDevice`, `VkPhysicalDevice`,
`VkCommandPool`, and `VkQueue`. Module 01's `VulkanBackend.init` already selects a physical
device; for the shared case, the primary backend is initialized first and subsequent backends
reuse its device handle.

The exact mechanism is:

```zig
// Primary window: full init as today.
var primary_backend = try VulkanBackend.init(gpa, &primary_platform);

// Secondary window: partial init — reuse device, create new surface + swapchain.
var secondary_backend = try VulkanBackend.initShared(gpa, &primary_backend, &secondary_platform);
```

`VulkanBackend.initShared` is a new function in module 01 (`src/01/types.zig`) that:
1. Creates a new `VkSurfaceKHR` for the secondary platform/window.
2. Creates a new `VkSwapchainKHR` bound to that surface.
3. Reuses the device, physical device, command pool, and graphics queue from the primary.
4. Does NOT own the device — `deinit` on a shared backend destroys only the surface and
   swapchain, not the device.

The shared backend is marked with an `is_shared: bool` field. `deinit` checks this flag to
skip device destruction.

### 4. Shared glyph atlas

The `GlyphAtlas` (CPU) and `GpuAtlas` (GPU texture + memory) are created once in
`MultiWindowApp.init` and shared across all windows. Each window's draw pass uses the same
`atlas_cpu` and `atlas_gpu`.

The `GpuAtlas` is re-uploaded once per frame when `atlas_cpu.generation` changes, regardless
of which window triggered the change. The re-upload uses the primary backend's device.

### 5. Frame loop (`MultiWindowApp.run`)

```
while (any window is open):
    // 1. Remove windows marked closed.
    prune closed windows (deinit their backend + scene)

    // 2. Poll events for all windows.
    for each open window:
        window.platform.pollEvents()
        drain + dispatch window.event_queue

    // 3. Skip GPU work if no window has dirty elements.
    if no window has any dirty element:
        glfwWaitEvents()   // block until any OS event
        continue

    // 4. Re-upload shared atlas if dirty.
    if atlas_cpu.generation changed:
        re-upload GpuAtlas

    // 5. For each dirty window: layout + draw.
    for each open window whose scene has dirty elements:
        apply pending resize
        backend.beginFrame()  — skip window if false
        scene.measurePass()
        layout.solve()
        cmds = buildDrawList() + overlay.flatten()
        backend.clear(black)
        backend.drawFrame(cmds, &shared_atlas_gpu)
        backend.endFrame()
        scene.elements.dirty.unsetAll()

    // 6. Close any window whose shouldClose() is true.
    for each open window:
        if window.platform.shouldClose():
            closeWindow(window.id)
```

### 6. Event dispatch isolation

Each window has its own `EventQueue`. GLFW delivers events to callbacks registered per
window. Module 01's `Platform` already supports per-window callbacks (`setEventQueue` is
called once per `Platform` instance); no changes needed to module 01 beyond `initShared`.

Events in one window do not affect focus or state in another window.

### 7. `initShared` addition to module 01

`src/01/types.zig` gets one new function signature:

```zig
/// Create a VulkanBackend that shares the device from `primary`.
/// Only surface + swapchain are created; device is not owned.
pub fn initShared(
    gpa: std.mem.Allocator,
    primary: *VulkanBackend,
    platform: *Platform,
) !VulkanBackend;
```

This is the only change to module 01 required by M8-04.

---

## Module location

```
src/app/multi_window.zig          — MultiWindowApp, WindowEntry, WindowId
src/app/multi_window_test.zig     — acceptance tests (headless — no GPU required)
src/01/types.zig                  — VulkanBackend.initShared (new function)
docs/requirements/R83_multi_window.md
```

`src/app/types.zig` must re-export `MultiWindowApp`, `WindowEntry`, and `WindowId`.

---

## Invariant interactions

- **INV-2.1**: One Vulkan device, one code path. `initShared` does not create a second
  device; it reuses the first.
- **INV-2.2**: Each window still gets its own GLFW window and GLFW surface. The windowing
  layer is not bypassed.
- **INV-3.5**: Each `WindowEntry` owns its own `Scene` and arena. Closing a window resets
  and deinits that arena; other windows are unaffected.
- **INV-5.1**: The new `VulkanBackend.initShared` signature is added to `src/01/types.zig`.
  Do NOT change the existing `init` signature.

---

## Glossary addition

Add to `docs/specs/glossary.md`:

```
## MultiWindowApp

A top-level application host that owns multiple `WindowEntry` instances and drives a single
frame loop for all of them. Shares one `VkDevice`, one `GlyphAtlas`, and one `GpuAtlas`
across all windows. Secondary windows are created via `VulkanBackend.initShared` so they
do not own the device. Each window has its own `Scene`, `VulkanBackend` (surface +
swapchain), `BindingSet`, and `OverlayLayer`. Defined in `src/app/multi_window.zig`.

See: R83 (M8-04).

## WindowId

A `u16` opaque handle identifying one `WindowEntry` within a `MultiWindowApp`. Value `0`
is reserved/invalid. Allocated monotonically; not reused after `closeWindow`.

See: R83 (M8-04), `src/app/multi_window.zig`.
```

---

## Non-goals (DO NOT implement — INV-5.4)

- NO macOS or Windows DX12 backend — INV-2.1.
- NO shared `Scene` between windows — each window owns its own scene (INV-3.5).
- NO drag-and-drop between windows.
- NO per-window icon or menu bar.
- NO fullscreen mode — deferred post-v1.
- NO animated window transitions.
- NO window grouping or tab-in-titlebar (OS-level feature).
- The `MultiWindowApp` API does NOT replace `AppInner.run` for single-window apps.
  `AppInner` is unchanged; `MultiWindowApp` is an additive type.

---

## Acceptance criteria

The module is done when:

1. `zig build test-multi-window` runs `src/app/multi_window_test.zig` and all tests pass
   (the headless subset — Vulkan paths are stubbed in tests).
2. `openWindow` returns a valid `WindowId`; `windowById` returns the entry; `closeWindow`
   marks it closed; the entry is removed at the top of the next frame.
3. The frame loop exits when `windows` is empty.
4. `GlyphAtlas` re-upload happens at most once per frame regardless of how many windows
   triggered a glyph miss.
5. Closing one window does not affect the `Scene` or `BindingSet` of another.
6. `deinit` on a shared backend does NOT destroy the device (verified by checking the
   `is_shared` flag path in the test).
7. No memory leaks (tested with `std.testing.allocator`).
8. The checklist for this item is fully ticked.

---

## Edge cases (each has a test)

- `openWindow` when `windows` is empty → first window becomes primary; `run` exits when
  it closes.
- `closeWindow` for an id that is already closed → no error, no double-free.
- All windows closed on the same frame → loop exits cleanly.
- Atlas changes triggered by window A are picked up by window B on the same frame.
- `windowById` for an unknown id → returns `null`.
