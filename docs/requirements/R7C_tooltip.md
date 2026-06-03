# R7C — M7-13: Tooltip

> Roadmap item: M7-13  
> Depends on: M4-02 (overlay z-layer — `OverlayLayer`), M1-02 (event delivery — mouse position)  
> Read `00_constitution.md` before this file.

## Purpose

A tooltip is a small text popup that appears when the mouse hovers over a target element for
at least 500 ms. It renders above all other content via the overlay layer. Tooltip content
is a string set per-element via a `tooltip` attribute in markup or programmatically. Only one
tooltip is shown at a time.

## What to build

### `TooltipManager` on `App`

```zig
pub const TooltipManager = struct {
    /// Element index of the current hover target. NONE if none.
    hover_idx:        u32  = NONE,
    /// Monotonic ms when the current hover started.
    hover_start_ms:   u64  = 0,
    /// Whether the tooltip is currently visible.
    visible:          bool = false,
    overlay_id:       OverlayId = 0,
    gpa:              std.mem.Allocator,

    pub fn init(gpa: std.mem.Allocator, overlay: *OverlayLayer) TooltipManager
    pub fn deinit(self: *TooltipManager) void

    /// Update hover state. Called once per frame with current mouse position.
    /// Shows or hides the tooltip based on the 500 ms threshold.
    pub fn tick(
        self: *TooltipManager,
        scene: *const Scene,
        mouse_pos: Vec2,
        now_ms: u64,
        window_w: f32,
        tokens: Tokens,
        family: *const FontFamily,
        glyph_atlas: *GlyphAtlas,
        overlay: *OverlayLayer,
        alloc: std.mem.Allocator,
    ) !void
};
```

### Tooltip text storage in `Scene`

Rather than a new parallel array, tooltip strings are stored in `NodeDesc.attrs` and
transferred to a `_tooltip` parallel array during `instantiate`:

```zig
pub const Scene = struct {
    _tooltip: std.ArrayListUnmanaged(?[]const u8) = .empty,

    pub fn tooltipOf(self: *const Scene, idx: u32) ?[]const u8
    pub fn setTooltip(self: *Scene, idx: u32, text: []const u8) void
};
```

Markup:

```html
<Button text="Save" tooltip="Save the current document" />
<Icon image_id="42" tooltip="User avatar" />
```

During `instantiate`, scan `attrs` for `name == "tooltip"` and store the literal value in
`_tooltip[idx]`.

### `tick` — hover detection and popup timing

```zig
pub fn tick(self: *TooltipManager, scene: *const Scene, mouse_pos: Vec2,
            now_ms: u64, ...) !void {
    // Find hovered element with a tooltip string.
    var new_hover: u32 = NONE;
    var i: u32 = 0;
    while (i < scene.elements.layout.items.len) : (i += 1) {
        if (scene._tooltip.items[i] == null) continue;
        const rect = scene.elements.layout.items[i].computed;
        if (rect.containsPoint(mouse_pos)) { new_hover = i; break; }
    }

    if (new_hover != self.hover_idx) {
        self.hover_idx      = new_hover;
        self.hover_start_ms = now_ms;
        self.visible        = false;
        overlay.setSlot(self.overlay_id, &.{});  // hide immediately on move
    }

    if (new_hover != NONE and !self.visible
        and now_ms - self.hover_start_ms >= 500) {
        // Build and show tooltip.
        self.visible = true;
        const text = scene._tooltip.items[new_hover].?;
        try self.buildTooltip(text, mouse_pos, window_w, tokens, family,
                              glyph_atlas, overlay, alloc);
    }

    if (new_hover == NONE and self.visible) {
        self.visible = false;
        overlay.setSlot(self.overlay_id, &.{});
    }
}
```

### `buildTooltip` — draw commands for the popup

```zig
fn buildTooltip(self: *TooltipManager, text: []const u8,
                mouse: Vec2, window_w: f32, ...) !void {
    const TOOLTIP_MAX_W: f32 = 200;
    const PADDING: f32 = 6;

    var cmds = std.ArrayList(DrawCommand).init(alloc);
    errdefer cmds.deinit();

    const para = try layoutParagraph(alloc, family.face(false, false), glyph_atlas,
                                     text, tokens.text_sm, TOOLTIP_MAX_W, .regular, null);

    const box_w = @min(para.extent.w + PADDING * 2, TOOLTIP_MAX_W + PADDING * 2);
    const box_h = para.extent.h + PADDING * 2;

    // Position: just below and to the right of the cursor, clamp to window.
    var box_x = mouse.x + 12;
    var box_y = mouse.y + 20;
    if (box_x + box_w > window_w) box_x = window_w - box_w - 4;

    const box = Rect{ .x = box_x, .y = box_y, .w = box_w, .h = box_h };

    try cmds.append(.{ .filled_rect = .{ .rect = box, .color = tokens.bg_raised,
                                         .radius = tokens.radius_sm } });
    try cmds.append(.{ .border_rect = .{ .rect = box, .color = tokens.border_default,
                                         .width = 1, .radius = tokens.radius_sm } });
    for (para.glyphs) |g| {
        try cmds.append(.{ .glyph = .{
            .dst   = .{ .x = box_x + PADDING + g.dest_x,
                        .y = box_y + PADDING + g.dest_y,
                        .w = g.dest_w, .h = g.dest_h },
            .uv    = g.uv,
            .color = tokens.text_body,
        }});
    }

    overlay.setSlot(self.overlay_id, try cmds.toOwnedSlice());
}
```

### `has_animated_elements` update

When `tooltip_manager.hover_idx != NONE and !tooltip_manager.visible`, the 500 ms delay
is pending — the frame loop must keep running. Add this to `has_animated_elements`:

```zig
if (app.tooltip_manager.hover_idx != NONE and !app.tooltip_manager.visible) return true;
```

### Module location

```
src/app/tooltip.zig   — TooltipManager, tick, buildTooltip
src/app/app.zig       — App.tooltip_manager, tick call, has_animated_elements update
src/07/types.zig      — Scene._tooltip, tooltipOf, setTooltip; instantiate reads tooltip attr
docs/requirements/R7C_tooltip.md
```

## Non-goals (DO NOT implement — INV-5.4)

- **No tooltip on touch / keyboard focus** — hover only; touch is not supported (INV-1.2).
- **No rich content tooltips** — text only.
- **No tooltip delay customization** — hardcoded 500 ms.
- **No tooltip-dismiss callback** — INV-3.3.
- **No arrow / pointer indicator** — rectangular box only.

## Acceptance criteria

1. Unit tests: `tick` with mouse over tooltip element and `now - start >= 500` → `visible = true`.
   Mouse leaving → `visible = false`, overlay slot cleared.
2. Integration: hover over a `<Button tooltip="...">` for 0.5 s. Tooltip appears near cursor.
   Moving mouse hides it. Tooltip text wraps at 200 px. Checklist ticked.
