# R74 — M7-05: Toast / notification

> Roadmap item: M7-05  
> Depends on: M4-02 (overlay z-layer — `OverlayLayer`), M1-04 (frame pacing — for auto-dismiss timer)  
> Read `00_constitution.md` before this file.

## Purpose

A toast is a brief, timed notification rendered in a corner of the window above all other
content. Toasts are not elements in the scene; they are managed by a `ToastManager` that
owns a small queue and writes draw commands directly into an `OverlayLayer` slot each frame.
Auto-dismiss happens via a `u64` timestamp compared to `App.frame_time_ms`.

## What to build

### `Toast` and `ToastManager`

Add `src/app/toast.zig`:

```zig
pub const ToastKind = enum { info, success, warning, @"error" };

pub const Toast = struct {
    message:     [128]u8 = .{0} ** 128,  // null-terminated; max 127 chars
    message_len: u8      = 0,
    kind:        ToastKind = .info,
    /// Monotonic ms timestamp when the toast was created.
    created_ms:  u64 = 0,
    /// Duration before auto-dismiss (ms). 0 = never auto-dismiss.
    duration_ms: u32 = 3000,
};

pub const MAX_TOASTS: u8 = 4;

pub const ToastManager = struct {
    toasts:     [MAX_TOASTS]Toast = .{.{}} ** MAX_TOASTS,
    count:      u8 = 0,
    overlay_id: OverlayId = 0,
    gpa:        std.mem.Allocator,

    pub fn init(gpa: std.mem.Allocator, overlay: *OverlayLayer) !ToastManager

    pub fn deinit(self: *ToastManager) void

    /// Add a toast to the queue. Drops the oldest if the queue is full.
    pub fn show(
        self: *ToastManager,
        message: []const u8,
        kind: ToastKind,
        duration_ms: u32,
        now_ms: u64,
    ) void

    /// Remove expired toasts and rebuild the overlay slot draw commands.
    /// Call once per frame. `now_ms` is `App.frame_time_ms`.
    pub fn tick(
        self: *ToastManager,
        now_ms: u64,
        window_w: f32,
        window_h: f32,
        tokens: Tokens,
        family: *const FontFamily,
        glyph_atlas: *GlyphAtlas,
        overlay: *OverlayLayer,
        alloc: std.mem.Allocator,
    ) !void

    pub fn dismiss(self: *ToastManager, index: u8) void
};
```

`App` gains `toast_manager: ToastManager`. `tick` is called in `App.run()` once per frame.

### Toast positioning

Toasts stack vertically from the bottom-right corner:

```
window_w - TOAST_W - MARGIN  →  x
window_h - (i+1)*(TOAST_H + GAP) - MARGIN  →  y_i
```

Constants: `TOAST_W = 280 px`, `TOAST_H = 56 px`, `MARGIN = 16 px`, `GAP = 8 px`.

### `tick` — build overlay draw commands

```zig
pub fn tick(self: *ToastManager, now_ms: u64, ...) !void {
    // 1. Expire old toasts.
    var i: u8 = 0;
    while (i < self.count) {
        const t = &self.toasts[i];
        if (t.duration_ms > 0 and now_ms - t.created_ms >= t.duration_ms) {
            // Remove toast at i (shift remaining left).
            self.dismiss(i);
        } else {
            i += 1;
        }
    }

    // 2. Build draw commands for remaining toasts.
    var cmds = std.ArrayList(DrawCommand).init(alloc);
    errdefer cmds.deinit();

    for (self.toasts[0..self.count], 0..) |t, ti| {
        const toast_rect = Rect{
            .x = window_w - TOAST_W - MARGIN,
            .y = window_h - @as(f32, @floatFromInt(ti + 1)) * (TOAST_H + GAP) - MARGIN,
            .w = TOAST_W, .h = TOAST_H,
        };
        const bg = toastBg(t.kind, tokens);
        // Background:
        try cmds.append(.{ .filled_rect = .{
            .rect = toast_rect, .color = bg, .radius = tokens.radius_md } });
        // Border:
        try cmds.append(.{ .border_rect = .{
            .rect = toast_rect, .color = toastBorder(t.kind, tokens),
            .width = 1, .radius = tokens.radius_md } });
        // Message text (via layoutParagraph):
        const msg = self.toasts[ti].message[0..self.toasts[ti].message_len];
        const text_rect = Rect{
            .x = toast_rect.x + 12, .y = toast_rect.y + 8,
            .w = TOAST_W - 24, .h = TOAST_H - 16,
        };
        const para = try layoutParagraph(alloc, family.face(false, false), glyph_atlas,
                                         msg, tokens.text_base, text_rect.w, .regular, null);
        for (para.glyphs) |g| {
            try cmds.append(.{ .glyph = .{
                .dst   = .{ .x = text_rect.x + g.dest_x, .y = text_rect.y + g.dest_y,
                            .w = g.dest_w, .h = g.dest_h },
                .uv    = g.uv,
                .color = tokens.text_body,
            }});
        }
    }

    overlay.setSlot(self.overlay_id, try cmds.toOwnedSlice());
}
```

### Toast background/border color

```zig
fn toastBg(kind: ToastKind, t: Tokens) Color {
    return switch (kind) {
        .info    => t.bg_raised,
        .success => Color{ .r = t.ok_400.r,   ... .a = 230 },
        .warning => Color{ .r = t.warn_400.r, ... .a = 230 },
        .@"error"=> Color{ .r = t.err_400.r,  ... .a = 230 },
    };
}
```

### `App.frame_time_ms`

Add `frame_time_ms: u64` to `App`, updated each frame using `std.time.milliTimestamp()`.
`has_animated_elements` (from R73) should also return `true` when `toastManager.count > 0`
so the frame loop stays active during auto-dismiss.

### Module location

```
src/app/toast.zig   — ToastManager, Toast, ToastKind
src/app/app.zig     — App.toast_manager, frame_time_ms, tick call
docs/requirements/R74_toast_notification.md
```

## Non-goals (DO NOT implement — INV-5.4)

- **No close button on toast** — auto-dismiss only; `dismiss` API available for programmatic
  removal but no × rendered.
- **No toast stacking animations** — instant position updates.
- **No progress bar inside toast** — duration shown only by auto-disappearance.
- **No toast-click callbacks** — INV-3.3.

## Acceptance criteria

1. Unit tests: `show` adds a toast; expired toast is removed in `tick`; queue caps at 4.
2. Integration: call `toast_manager.show("Saved!", .success, 2000, now)`. Toast appears
   bottom-right, disappears after 2 seconds. Four simultaneous toasts stack correctly.
3. Checklist ticked.
