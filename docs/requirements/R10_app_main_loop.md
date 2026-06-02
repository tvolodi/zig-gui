# R10 — M1-01: App main loop

> Roadmap item: M1-01  
> Depends on: module 09 (renderer complete)  
> Read `00_constitution.md` before this file.

## Purpose

Provide a single `App.run()` entry point that owns `Platform`, `VulkanBackend`, `Scene`,
`GlyphAtlas`, and `GpuAtlas`, drives the frame lifecycle in the correct order, and tears
everything down cleanly on exit.

After this item ships, an application author writes:

```zig
var app = try App.init(gpa, opts);
defer app.deinit();
app.run();  // returns when the window is closed
```

and the framework handles the rest: window creation, Vulkan bring-up, font loading, frame
pacing, scene instantiation, layout, rendering, and shutdown.

## What to build

### `App` struct

Lives in `src/app/app.zig`. Owns:

| Field | Type | Notes |
|---|---|---|
| `platform` | `Platform` | module 01 |
| `backend` | `VulkanBackend` | module 01 |
| `scene` | `Scene` | module 07 |
| `atlas_cpu` | `GlyphAtlas` | module 02 |
| `atlas_gpu` | `GpuAtlas` | module 09 |
| `font` | `Font` | module 02 |
| `gpa` | `std.mem.Allocator` | general-purpose allocator passed by caller |

No per-frame heap allocations for the draw list; a pre-allocated `std.ArrayList(DrawCommand)`
is a field of `App` and is cleared and refilled each frame.

### `App.init`

```zig
pub fn init(gpa: std.mem.Allocator, opts: AppOptions) !App
```

`AppOptions`:

```zig
pub const AppOptions = struct {
    window: WindowOptions = .{},      // title, width, height — passed to Platform.init
    font_path: []const u8,            // path to a .ttf file; read with std.fs
    font_size_px: f32 = 16,
};
```

Initialization order (must be exactly this — each step depends on the previous):

1. `Platform.init(gpa, opts.window)` — creates the GLFW window.
2. `VulkanBackend.init(gpa, &platform)` — creates the Vulkan device + swapchain.
3. `VulkanBackend.initQuadPipeline(gpa)` — sets up the quad pipeline (module 09 method).
4. Load font bytes from `opts.font_path` via `std.fs.cwd().readFileAlloc`.
5. `Font.init(gpa, font_bytes, opts.font_size_px)` — parse the TTF (module 02).
6. `GlyphAtlas.init(gpa, 1024, 1024)` — create the CPU atlas (module 02).
7. `GpuAtlas.upload(...)` with the (initially empty) CPU atlas — module 09.
8. `Scene.init(gpa)` — create an empty scene (module 07).

If any step fails, deinit what was already initialized in reverse order before returning the
error. Do NOT leave partially-initialized state.

### `App.run`

```zig
pub fn run(self: *App) void
```

The frame loop, runs until `platform.shouldClose()` returns true:

```
while (!platform.shouldClose()) {
    platform.pollEvents()
    if (!backend.beginFrame()) continue   // swapchain out of date — skip frame
    scene.measurePass(&font, &atlas_cpu)
    if atlas_cpu.generation changed since last frame:
        GpuAtlas.deinit(&backend)
        atlas_gpu = GpuAtlas.upload(...)
    layout.solve(&scene.elements)         // module 04 layout solve
    commands = buildDrawList(&scene, &atlas_cpu)
    backend.clear(.{0,0,0,1})
    backend.drawFrame(commands, &atlas_gpu)
    backend.endFrame()
}
```

Details:

- `atlas_cpu.generation` is a `u32` field on `GlyphAtlas` (added in module 09 spec). Cache
  the last-seen generation in `App` as `atlas_generation_seen: u32`. Re-upload only when it
  changes.
- The draw list is produced by `buildDrawList` (module 09) into the pre-allocated
  `ArrayList(DrawCommand)`, then passed as a slice to `drawFrame`.
- Layout solve: call `LayoutEngine.solve(gpa, &scene.elements.layout)` (module 04 public
  API). The `LayoutEngine` is instantiated once in `App.init` and reused each frame.
- `clear` is called before `drawFrame`; the clear color is opaque black `{0,0,0,1}`.

### `App.deinit`

```zig
pub fn deinit(self: *App) void
```

Destroy in reverse init order:

1. `scene.deinit()`
2. `atlas_gpu.deinit(&backend)`
3. `atlas_cpu.deinit()`
4. `font.deinit()`
5. `backend.deinitQuadPipeline()`
6. `backend.deinit()`
7. `platform.deinit()`

### Module location

```
src/app/app.zig        — App struct, init/run/deinit
src/app/app_test.zig   — unit tests (headless subset)
docs/requirements/R10_app_main_loop.md
```

## Public API (`types.zig` addendum)

Because `App` is a new top-level struct, there is no existing `types.zig` file for the app
layer. Create `src/app/types.zig` with:

```zig
pub const AppOptions = struct { ... };
pub const App = struct {
    pub fn init(gpa, opts) !App
    pub fn run(self: *App) void
    pub fn deinit(self: *App) void
};
```

These three methods are the entire public API. Do not expose fields.

## Non-goals (DO NOT implement — INV-5.4)

- NO event callback registration — input delivery is M1-02.
- NO multi-window — one `App` owns one window (INV-1.1).
- NO screen/navigation model — that is Milestone 8.
- NO state management — signals and dirty bitsets are Milestone 2.
- NO hot-reload — dev-only, behind a flag, tracked in M5-07.
- NO frame-time measurement or display — that is M9-03.
- NO configurable clear color via `AppOptions` — always opaque black; change if a spec requires it.

## Acceptance criteria

The module is done when:

1. `zig build test-app` runs `src/app/app_test.zig` and all tests pass.
2. A minimal application (one `Text` widget with "Hello, world") can be instantiated and
   runs `App.run()` for 5 frames on a machine with a GPU without crashing or producing
   Vulkan validation errors.
3. `App.deinit()` produces no memory leaks (checked via `std.testing.allocator` or a
   `GeneralPurposeAllocator` with leak detection in the test harness).
4. The checklist for this item is fully ticked.

## Open questions

None — all dependencies are specced. If a module 04 or 07 API discrepancy surfaces,
stop and surface it before diverging from the existing types.
