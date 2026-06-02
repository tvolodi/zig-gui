# R13 — M1-04: Frame pacing

> Roadmap item: M1-04  
> Depends on: module 01 (VulkanBackend/swapchain), M1-01 (App main loop)  
> Read `00_constitution.md` before this file.

## Purpose

Select an appropriate Vulkan present mode so the app does not spin at 100% CPU when idle,
and so rendered frames are paced to the display's refresh rate (vsync) by default.

## What to build

### Present mode selection

The swapchain present mode is set during `VulkanBackend.init` (and recreated on resize via
`onResize`). The selection priority is:

1. **`VK_PRESENT_MODE_FIFO_KHR`** (vsync, always available per the Vulkan spec) — preferred.
2. **`VK_PRESENT_MODE_MAILBOX_KHR`** (triple-buffer, lower latency, not always available) —
   used only if explicitly opted into via `AppOptions.prefer_low_latency = true`.

For v1, always use `FIFO`. It is guaranteed available, provides vsync, and prevents busy-
waiting. `MAILBOX` support is a named constant and a comment in the code — do not implement
the `prefer_low_latency` option yet (that would be a config option violating `INV-1.1`).

**Action**: verify that the current module 01 implementation uses `FIFO_KHR`. If it uses
`IMMEDIATE_KHR` or picks the first available mode, fix it to prefer `FIFO_KHR`.

### CPU idle behavior

With `FIFO_KHR`, `vkQueuePresentKHR` blocks until the display's vertical blanking interval.
This means the CPU sleeps inside the Vulkan driver during present — no explicit `sleep` call
is needed in the frame loop. The loop naturally runs at the display's refresh rate.

Do NOT add `std.time.sleep` or any explicit frame limiter. The present-mode selection IS the
frame pacer.

### Validation

`VulkanBackend.validationIssueCount()` must remain 0 after switching to `FIFO_KHR`. If the
previous implementation used a different present mode and that caused no validation issues,
this change is straightforward.

### Swapchain recreation on resize

`onResize` recreates the swapchain. It must preserve the same present mode that was selected
at init time. Do NOT re-query present modes on resize; re-use the mode stored from init.

Add a field to `VulkanBackend`'s internal state:

```zig
present_mode: vk.PresentModeKHR,  // set in init, reused in onResize
```

### Frame loop impact

No change to the `App.run` loop structure from M1-01. `FIFO_KHR` present mode is transparent
to the frame loop — `endFrame` simply blocks until the GPU is ready to present, then returns.

## Module location

Changes are in `src/01/types.zig` (implementation) only. No new files. No public API changes.

## Non-goals (DO NOT implement — INV-5.4)

- NO configurable present mode via `AppOptions`.
- NO adaptive vsync (`VK_PRESENT_MODE_FIFO_RELAXED_KHR`) — unnecessary complexity.
- NO frame-time measurement or FPS counter — that is M9-03.
- NO explicit sleep / frame limiter — present-mode blocking is sufficient.
- NO separate render thread — rendering stays synchronous on the main thread.

## Acceptance criteria

1. The running app does not peg a CPU core at 100% when the window is visible and nothing is
   changing on screen.
2. `VulkanBackend` internal state uses `VK_PRESENT_MODE_FIFO_KHR`.
3. `validationIssueCount() == 0` after 100 frames.
4. After a window resize (swapchain recreation), the present mode is still `FIFO_KHR`.
5. Checklist fully ticked.

## Open questions

None. `FIFO_KHR` is mandatory per the Vulkan spec — it is always available. No capability
query needed.
