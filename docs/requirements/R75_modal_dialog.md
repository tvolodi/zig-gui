# R75 — M7-06: Modal dialog

> Roadmap item: M7-06  
> Depends on: M4-02 (overlay z-layer — `OverlayLayer`), M3-01 (focus model — focus trapping), M5-03 (conditional rendering)  
> Read `00_constitution.md` before this file.

## Purpose

A modal dialog is a blocking overlay that captures keyboard focus until dismissed. It
renders a semi-transparent backdrop over the entire window plus a centered content panel.
The dialog's content is a normal `Scene` subtree (pre-instantiated). Opening and closing
controls focus trapping.

## What to build

### `DialogState` and management

Modals are managed by a `DialogManager` on `App`, not as `WidgetKind` elements in the main
scene. This is because modals contain arbitrary content trees that are instantiated
separately from the main screen.

```zig
pub const DialogState = struct {
    visible:     bool = false,
    /// Root ElementId of the dialog's content subtree in the scene.
    content_idx: u32  = NONE,
    overlay_id:  OverlayId = 0,
    /// Element index to restore focus to when the dialog closes.
    return_focus_idx: u32 = NONE,
};

pub const DialogManager = struct {
    state:   DialogState = .{},
    gpa:     std.mem.Allocator,

    pub fn init(gpa: std.mem.Allocator, overlay: *OverlayLayer) DialogManager

    pub fn deinit(self: *DialogManager) void

    /// Open the dialog, showing the content subtree rooted at `content_idx`.
    /// Saves current focus and sets focus to the first focusable element inside the dialog.
    pub fn open(self: *DialogManager, content_idx: u32, scene: *Scene) void

    /// Close the dialog and restore the saved focus.
    pub fn close(self: *DialogManager, scene: *Scene) void

    /// Rebuild the overlay slot. Call once per frame when visible.
    /// The backdrop covers the window; the content panel is centered.
    pub fn buildOverlay(
        self: *DialogManager,
        scene: *Scene,
        window_w: f32,
        window_h: f32,
        tokens: Tokens,
        family: *const FontFamily,
        glyph_atlas: *GlyphAtlas,
        image_atlas: *const ImageAtlas,
        overlay: *OverlayLayer,
        alloc: std.mem.Allocator,
    ) !void
};
```

### Focus trapping

When a dialog is open, Tab and Shift+Tab navigation in `App.run()` is constrained to
elements whose index falls within the dialog content subtree. Before the normal focus-
navigation code runs, check `dialog_manager.state.visible` and restrict the focusable set:

```zig
if (app.dialog_manager.state.visible) {
    // Replace the full focusable_indices with only those inside the dialog subtree.
    const dialog_root = app.dialog_manager.state.content_idx;
    // Re-run Tab/Shift+Tab using only elements that are descendants of dialog_root.
    // ...
} else {
    // Normal focus navigation.
}
```

`isDescendantOf(scene, candidate_idx, ancestor_idx)` — O(depth) parent chain walk.

Escape key closes the dialog:

```zig
if (dialog_manager.state.visible and event.key == Key.escape) {
    dialog_manager.close(&scene);
}
```

### Backdrop and panel rendering in `buildOverlay`

```zig
// 1. Semi-transparent backdrop:
try cmds.append(.{ .filled_rect = .{
    .rect  = .{ .x = 0, .y = 0, .w = window_w, .h = window_h },
    .color = .{ .r = 0, .g = 0, .b = 0, .a = 128 },  // 50 % black
}});

// 2. Centered panel background:
const PANEL_W: f32 = @min(window_w * 0.9, 480);
const PANEL_H: f32 = content_measured_h + tokens.sp_xl * 2;
const panel_rect = Rect{
    .x = (window_w - PANEL_W) / 2,
    .y = (window_h - PANEL_H) / 2,
    .w = PANEL_W, .h = PANEL_H,
};
try cmds.append(.{ .filled_rect = .{
    .rect   = panel_rect,
    .color  = tokens.bg_raised,
    .radius = tokens.radius_lg,
}});
try cmds.append(.{ .border_rect = .{
    .rect   = panel_rect,
    .color  = tokens.border_subtle,
    .width  = 1,
    .radius = tokens.radius_lg,
}});
// 3. Content: run buildDrawList on the dialog content subtree only.
//    The content subtree is already in the scene; re-use buildDrawList with a root override.
const content_cmds = try buildDialogContent(alloc, scene, content_idx,
                                            panel_rect, tokens, family,
                                            glyph_atlas, image_atlas, frame_count);
try cmds.appendSlice(content_cmds);
```

`buildDialogContent` is a targeted variant of `buildDrawList` that walks only the subtree
rooted at `content_idx` and offsets all rect coordinates to `panel_rect`.

### Markup pattern (application code)

```zig
// Instantiate a dialog content subtree (separate from the main scene):
const confirm_desc = NodeDesc{
    .tag      = "Column",
    .classes  = "gap-4 p-6",
    .children = &.{
        NodeDesc{ .tag = "Text", .attrs = &.{.{ .name = "text",
            .value = .{ .literal = "Are you sure?" } } } },
        NodeDesc{ .tag = "Row", .classes = "gap-2 justify-end", .children = &.{
            NodeDesc{ .tag = "Button", .attrs = &.{.{ .name = "text",
                .value = .{ .literal = "Cancel" } } } },
            NodeDesc{ .tag = "Button", .classes = "bg-accent text-body", .attrs = &.{
                .{ .name = "text", .value = .{ .literal = "Confirm" } } } },
        }},
    },
};
const dialog_root = try scene.instantiate(confirm_desc, tokens);

// Open:
app.dialog_manager.open(dialog_root.index, &scene);

// Close (from button callback):
app.dialog_manager.close(&scene);
```

### Module location

```
src/app/dialog.zig   — DialogManager, DialogState, open, close, buildOverlay
src/app/app.zig      — App.dialog_manager, focus-trap integration, Escape key handling, buildOverlay call
docs/requirements/R75_modal_dialog.md
```

## Non-goals (DO NOT implement — INV-5.4)

- **No dialog-specific widget kind** — content is any scene subtree.
- **No multiple simultaneous modals** — one dialog at a time; second `open()` replaces the first.
- **No `<Dialog>` markup tag** — dialogs are opened programmatically.
- **No animated backdrop fade** — instant show/hide.
- **No click-backdrop-to-close** — only Escape key or explicit `close()` call.
- **No dialog resize** — fixed centered panel sizing.

## Acceptance criteria

1. Unit tests: `open` saves current focus and sets dialog visible. `close` restores focus.
   Focus trapping: Tab stays within dialog subtree. Escape closes.
2. Integration: open a confirm dialog. Tab cycles through Cancel/Confirm buttons only.
   Escape closes. Main UI is non-interactive while dialog is open. Checklist ticked.
