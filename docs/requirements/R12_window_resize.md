# R12 — M1-03: Window resize handling

> Roadmap item: M1-03  
> Depends on: module 01 (Platform/VulkanBackend), module 09 (renderer), M1-01 (App main loop)  
> Read `00_constitution.md` before this file.

## Purpose

When the user resizes the window, automatically propagate the new framebuffer size to the
Vulkan swapchain and to the layout engine so the next frame renders correctly at the new
dimensions — without any action required from application code.

## What to build

### How resize is detected

GLFW fires `glfwSetFramebufferSizeCallback` when the framebuffer changes. This is distinct
from the window-size callback: the framebuffer callback delivers pixel dimensions, which is
what Vulkan and the layout engine both need.

Two detection paths exist and must both be handled:

1. **Callback path**: `glfwSetFramebufferSizeCallback` fires during `glfwPollEvents` with the
   new size. Store the new size in a `pending_resize: ?Extent2D` field on `App`.
2. **Out-of-date path**: `VulkanBackend.beginFrame()` returns `false` when the swapchain is
   out of date. `App.run` already skips that frame (`continue`). On the next iteration, the
   size callback will have fired (or `Platform.framebufferSize()` reflects the new size) and
   the resize can proceed.

Both paths converge at the same point: at the top of each frame, check whether a resize is
pending.

### Frame loop change

In `App.run`, immediately after `platform.pollEvents()` and before `backend.beginFrame()`:

```
if (self.pending_resize) |new_size| {
    backend.onResize(new_size);               // recreate swapchain — module 01
    scene.elements.layout.setViewport(new_size.width, new_size.height);  // module 04
    self.pending_resize = null;
}
```

`LayoutEngine.setViewport(w, h)` — see module 04 API below. This invalidates all computed
layout so the next `layout.solve()` call re-runs with the new root constraint.

### New method on `Platform`

Add to `src/01/types.zig`:

```zig
// Install a framebuffer-resize callback. `user_data` is stored via glfwSetWindowUserPointer
// and passed to `callback`. Called once after init.
pub fn setFramebufferSizeCallback(
    self: *Platform,
    user_data: *anyopaque,
    callback: *const fn (user_data: *anyopaque, size: Extent2D) void,
) void
```

`App.init` registers this callback with `user_data = self` and a function that writes
`new_size` into `self.pending_resize`.

If `setEventQueue` is already using `glfwSetWindowUserPointer` for the event queue pointer,
then `user_data` here is a pointer to an `App`-level callback context struct that holds both
the `EventQueue *` and the `pending_resize *?Extent2D`. This avoids having two
`glfwSetWindowUserPointer` calls overwrite each other.

**Implementation note:** GLFW allows only one user pointer per window. The implementation
must pack all callback state into a single context struct pointed to by `glfwSetWindowUserPointer`.
This is an implementation detail, not part of the public contract.

### Module 04 addition: `setViewport`

Module 04's `LayoutEngine` (or the `ElementStore.layout` root node) needs a way to update the
root viewport dimensions. Add:

```zig
// Set the available width and height for the root layout pass.
// Called once at init and again on every resize.
pub fn setViewport(self: *LayoutEngine, width: u32, height: u32) void
```

The current module 04 implementation initializes the root constraint from a fixed size. This
method replaces that with a mutable field. If `LayoutEngine` already has such a mechanism,
use it and update the call site in `App`.

### Zero-size guard

When the window is minimized on some platforms, the framebuffer may have width=0 or height=0.
In that case:

- Do NOT call `backend.onResize({0, 0})` — a zero-extent swapchain is invalid.
- Do NOT call `layout.solve()` with a zero viewport.
- Skip the entire frame (the `beginFrame()` → `endFrame()` round) until the framebuffer has
  non-zero dimensions.

Add the guard at the top of the frame loop, before the resize check:

```
const fb = platform.framebufferSize();
if (fb.width == 0 or fb.height == 0) continue;
```

## Module location

No new files. Changes are in:

```
src/01/types.zig     — Platform.setFramebufferSizeCallback (new method)
src/04/types.zig     — LayoutEngine.setViewport (new method, or verify existing)
src/app/app.zig      — pending_resize field + resize handling in run loop
```

## Non-goals (DO NOT implement — INV-5.4)

- NO animated / eased resize transitions.
- NO minimum window size enforcement — the OS or GLFW handles that.
- NO per-element resize callbacks or notifications — layout solve covers all elements.
- NO DPI-change handling — post-v1.

## Acceptance criteria

1. Resizing the window during `App.run()` renders correctly at the new size within one frame.
2. Minimizing the window (zero-size framebuffer) does not crash or produce Vulkan validation
   errors; the app resumes correctly when restored.
3. `backend.validationIssueCount() == 0` after a resize cycle (swapchain recreation must be
   clean).
4. The layout engine re-solves with the new root constraint: elements that previously filled
   the window still fill it after resize.
5. Checklist fully ticked.

## Open questions

None. The swapchain recreation path already exists in module 01's `onResize`. If module 04
has no `setViewport` equivalent, add it as described — it is a backwards-compatible addition
to `LayoutEngine`.
