# R7D — M7-14: Context menu

> Roadmap item: M7-14  
> Depends on: M4-02 (overlay z-layer), M1-02 (event delivery — right-click, keyboard)  
> Read `00_constitution.md` before this file.

## Purpose

A context menu appears on right-click over any element that has registered menu items. It
renders an overlay panel of labeled action items. Clicking an item fires a `CallbackFn`
(R31 mechanism) and dismisses the menu. Clicking outside or pressing Escape also dismisses.

## What to build

### `ContextMenuManager` on `App`

Context menus are not scene elements — they are managed by a `ContextMenuManager` that
builds overlay draw commands directly, identical in pattern to `ToastManager`.

```zig
pub const ContextMenuItem = struct {
    label:    [64]u8 = .{0} ** 64,
    label_len: u8 = 0,
    disabled: bool = false,
    on_click: ?CallbackFn = null,
    separator: bool = false,  // if true, render as a divider; label ignored
};

pub const MAX_MENU_ITEMS: u8 = 16;

pub const ContextMenu = struct {
    items:    [MAX_MENU_ITEMS]ContextMenuItem = .{.{}} ** MAX_MENU_ITEMS,
    count:    u8 = 0,
    visible:  bool = false,
    /// Pixel position of the top-left of the menu panel.
    pos:      Vec2 = .{ .x = 0, .y = 0 },
    overlay_id: OverlayId = 0,
    /// Index of the highlighted item (keyboard navigation). NONE = no highlight.
    highlight: u8 = 0xFF,
};

pub const ContextMenuManager = struct {
    menu: ContextMenu = .{},
    gpa:  std.mem.Allocator,

    pub fn init(gpa: std.mem.Allocator, overlay: *OverlayLayer) ContextMenuManager
    pub fn deinit(self: *ContextMenuManager) void

    /// Register a context menu for element `target_idx` in the scene.
    /// The registration persists until `unregister` is called.
    pub fn register(
        self: *ContextMenuManager,
        target_idx: u32,
        items: []const ContextMenuItem,
    ) !void

    /// Open the context menu at `pos`. Called when right-click lands on a registered element.
    pub fn openAt(self: *ContextMenuManager, pos: Vec2,
                  overlay: *OverlayLayer, tokens: Tokens,
                  family: *const FontFamily, glyph_atlas: *GlyphAtlas,
                  alloc: std.mem.Allocator) !void

    /// Dismiss the menu without firing any action.
    pub fn dismiss(self: *ContextMenuManager, overlay: *OverlayLayer) void

    /// Fire the highlighted item's callback (if any) and dismiss.
    pub fn activate(self: *ContextMenuManager, overlay: *OverlayLayer,
                    queued_callbacks: *std.ArrayListUnmanaged(CallbackFn),
                    gpa: std.mem.Allocator) void
};
```

### Per-element context menu registration

Elements are associated with context menus via a parallel optional array in `Scene`:

```zig
pub const Scene = struct {
    _context_menu_idx: std.ArrayListUnmanaged(u8) = .empty,
    // u8: index into ContextMenuManager.registered_menus, or 0xFF = none
    // (max 255 distinct context menu definitions)
};
```

Markup:

```html
<Text context_menu="file_actions" text="readme.txt" />
```

The `context_menu="file_actions"` attr stores a string name. The application registers the
menu under that name:

```zig
try context_menu_mgr.registerNamed("file_actions", &[_]ContextMenuItem{
    .{ .label = "Open",   .on_click = open_callback },
    .{ .label = "Rename", .on_click = rename_callback },
    .{ .separator = true },
    .{ .label = "Delete", .on_click = delete_callback, .disabled = false },
});
```

### Input handling in `App.run()`

**Right-click detection:**

```zig
if (platform.mouseButton(.right) == .press) {
    const mouse = platform.mousePosition();
    // Find the topmost element with a context menu registration under the cursor.
    // Iterate in reverse DFS order (topmost = last-painted).
    var found: bool = false;
    var i: u32 = scene.elements.layout.items.len;
    while (i > 0) : (i -= 1) {
        const idx = i - 1;
        if (scene._context_menu_idx.items[idx] == 0xFF) continue;
        if (!scene.elements.layout.items[idx].computed.containsPoint(mouse)) continue;
        context_menu_mgr.openAt(mouse, &overlay, tokens, ...) catch {};
        found = true;
        break;
    }
    if (!found and context_menu_mgr.menu.visible) {
        context_menu_mgr.dismiss(&overlay);
    }
}
```

**Keyboard navigation (while menu is open):**

- `Down` / `Up` arrows: advance/retreat `highlight`, skipping separator items, wrapping.
- `Enter`: `activate`.
- `Escape`: `dismiss`.

**Left-click while menu is open:**

- Click inside menu panel: find item under cursor → `activate` if not disabled/separator.
- Click outside: `dismiss`.

### Menu rendering in `openAt`

```zig
const ITEM_H: f32 = 28;
const MENU_W: f32 = 180;
const SEP_H:  f32 = 1;

// Compute total menu height:
var total_h: f32 = 4;  // top+bottom padding
for (self.menu.items[0..self.menu.count]) |it| {
    total_h += if (it.separator) SEP_H + 4 else ITEM_H;
}

// Clamp position to window:
var mx = pos.x;
var my = pos.y;
// (clamping logic omitted for brevity)

var cmds = std.ArrayList(DrawCommand).init(alloc);

// Panel background:
const panel = Rect{ .x = mx, .y = my, .w = MENU_W, .h = total_h };
try cmds.append(.{ .filled_rect = .{ .rect = panel, .color = tokens.bg_raised,
                                      .radius = tokens.radius_sm } });
try cmds.append(.{ .border_rect = .{ .rect = panel, .color = tokens.border_default,
                                      .width = 1, .radius = tokens.radius_sm } });

// Items:
var cursor_y = my + 4;
for (self.menu.items[0..self.menu.count], 0..) |it, ii| {
    if (it.separator) {
        try cmds.append(.{ .filled_rect = .{
            .rect  = .{ .x = mx + 8, .y = cursor_y + 2, .w = MENU_W - 16, .h = 1 },
            .color = tokens.border_subtle,
        }});
        cursor_y += SEP_H + 4;
    } else {
        const item_rect = Rect{ .x = mx, .y = cursor_y, .w = MENU_W, .h = ITEM_H };
        const is_hl = ii == self.menu.highlight;
        if (is_hl and !it.disabled) {
            try cmds.append(.{ .filled_rect = .{
                .rect  = item_rect,
                .color = tokens.accent,
                .radius = tokens.radius_sm,
            }});
        }
        // Label text:
        const text_color = if (it.disabled) tokens.text_disabled
                           else if (is_hl)  tokens.accent_text
                           else              tokens.text_body;
        const para = try layoutParagraph(alloc, family.face(false, false), glyph_atlas,
                                         it.label[0..it.label_len], tokens.text_base,
                                         MENU_W - 24, .regular, null);
        for (para.glyphs) |g| {
            try cmds.append(.{ .glyph = .{
                .dst   = .{ .x = mx + 12 + g.dest_x, .y = cursor_y + 4 + g.dest_y,
                            .w = g.dest_w, .h = g.dest_h },
                .uv    = g.uv,
                .color = text_color,
            }});
        }
        cursor_y += ITEM_H;
    }
}

overlay.setSlot(self.menu.overlay_id, try cmds.toOwnedSlice());
```

### `activate`

```zig
pub fn activate(self: *ContextMenuManager, overlay: *OverlayLayer,
                queued_callbacks: *std.ArrayListUnmanaged(CallbackFn), gpa: std.mem.Allocator) void {
    const it = &self.menu.items[self.menu.highlight];
    if (!it.disabled and it.on_click != null) {
        queued_callbacks.append(gpa, it.on_click.?) catch {};
    }
    self.dismiss(overlay);
}
```

Callbacks are queued and fired at frame-end (same mechanism as button callbacks in R31).

### Module location

```
src/app/context_menu.zig  — ContextMenuManager, ContextMenu, ContextMenuItem
src/app/app.zig           — App.context_menu_mgr, right-click detection, keyboard nav
src/07/types.zig          — Scene._context_menu_idx, instantiate reads context_menu attr
docs/requirements/R7D_context_menu.md
```

## Non-goals (DO NOT implement — INV-5.4)

- **No submenus** (nested menus) — flat item list only.
- **No icons in menu items** — text only.
- **No keyboard shortcut hints** — no "Ctrl+S" display alongside items.
- **No menu-item-hover callbacks** — INV-3.3.
- **No animation** — instant show/hide.
- **No context menu on touch** — right-click only (INV-1.2).

## Acceptance criteria

1. Unit tests: `registerNamed` stores items. `openAt` builds draw commands with correct
   item count. `activate` queues callback and clears menu. Up/Down navigates highlight;
   separator items are skipped.
2. Integration: right-click on a text element with a registered menu. Menu appears at cursor.
   Click an item fires its callback. Escape dismisses. Click outside dismisses. Checklist ticked.
