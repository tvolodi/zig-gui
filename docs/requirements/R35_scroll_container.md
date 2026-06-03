# R35 — M3-06: Scroll container

> Roadmap item: M3-06  
> Depends on: M1-02 (event delivery), M4-03 (overflow-hidden clipping)  
> Read `00_constitution.md` before this file.

## Purpose

A scroll container is a layout node that clips its children to its bounds and allows
scrolling the content vertically or horizontally via mouse wheel and dragging a scrollbar.
The scroll offset is stored in parallel arrays in `Scene` (INV-3.1) and persists across frames.
Clipping (scissor rect) is handled by the renderer (M4-03).

Note: `scrollview` or similar is a new `WidgetKind` to be added to module 07.

## What to build

### Scroll container widget kind

Update [07.types.zig](../specs/07.types.zig):

```zig
pub const WidgetKind = enum { 
    text, 
    button, 
    input, 
    card, 
    row, 
    column, 
    dropdown,
    checkbox,
    scrollview,  // NEW
};

pub fn tagToKind(tag: []const u8) ?WidgetKind {
    // ... existing cases ...
    if (eql(u8, tag, "ScrollView")) return .scrollview;
    // ...
}

pub fn defaultLayoutFor(kind: WidgetKind) LayoutNode {
    return switch (kind) {
        // ... existing cases ...
        .scrollview => .{ .display = .block, .overflow = .hidden },  // NEW
        // ...
    };
}
```

(Note: `overflow: hidden` is defined in M4-03. For now, assume `.overflow` field exists on
`LayoutNode`.)

### Scroll state storage in `Scene`

Extend [07.types.zig](../specs/07.types.zig) `Scene` struct:

```zig
pub const ScrollState = struct {
    /// Vertical scroll offset in pixels.
    /// 0 = content at top; positive = content scrolled down.
    scroll_y: f32 = 0,
    
    /// Horizontal scroll offset in pixels.
    /// 0 = content at left; positive = content scrolled right.
    scroll_x: f32 = 0,
    
    /// Total height of the content inside the scroll container.
    /// Set during layout (M4-04 layout engine responsibility).
    content_height: f32 = 0,
    
    /// Total width of the content inside the scroll container.
    /// Set during layout.
    content_width: f32 = 0,
    
    /// Height of the visible scroll container (from layout rect).
    /// Set during layout.
    container_height: f32 = 0,
    
    /// Width of the visible scroll container (from layout rect).
    /// Set during layout.
    container_width: f32 = 0,
    
    /// true if the user is currently dragging the vertical scrollbar.
    dragging_v_scrollbar: bool = false,
    
    /// true if the user is currently dragging the horizontal scrollbar.
    dragging_h_scrollbar: bool = false,
    
    /// Y position (in window coords) where vertical scrollbar drag started.
    drag_start_y: f32 = 0,
    
    /// X position (in window coords) where horizontal scrollbar drag started.
    drag_start_x: f32 = 0,
    
    /// scroll_y value when vertical drag started.
    drag_start_scroll_y: f32 = 0,
    
    /// scroll_x value when horizontal drag started.
    drag_start_scroll_x: f32 = 0,
};

pub const Scene = struct {
    // ...existing fields...
    
    /// Parallel array of scroll states, indexed by ElementId.index.
    /// Only meaningful for elements with WidgetKind.scrollview.
    _scroll_state: std.ArrayListUnmanaged(ScrollState) = .empty,
    
    /// Get the scroll state for element `idx` (only valid if kindOf(idx) == .scrollview).
    pub fn scrollStateOf(self: *Scene, idx: u32) *ScrollState
    
    /// Set the scroll offset for scroll container `idx`.
    /// Clamps offset to [0, max_offset] where max_offset depends on content/container size.
    /// Marks the element dirty.
    pub fn setScrollOffset(self: *Scene, idx: u32, offset_y: f32, offset_x: f32) void
    
    /// Get the current scroll offset.
    /// Returns { .y = scroll_y, .x = scroll_x }.
    pub fn getScrollOffset(self: *Scene, idx: u32) struct { y: f32, x: f32 }
};
```

### Input handling in `App.run()`

After other input handling, add mouse wheel and scrollbar drag:

```zig
while (!platform.shouldClose()) {
    platform.pollEvents()
    
    // ... focus, button, input, dropdown, checkbox handling ...
    
    // NEW: Scroll handling
    const mouse_pos = platform.mousePosition()
    const scroll_wheel = platform.getMouseWheel()  // Returns { .y: f32, .x: f32 }
    
    var idx: u32 = 0
    while (idx < scene.count()) : (idx += 1) {
        if (scene.kindOf(idx) != .scrollview) continue
        
        const scroll_state = scene.scrollStateOf(idx)
        const container_rect = scene.elements.layout[idx].rect
        
        // Mouse wheel scroll
        if (container_rect.containsPoint(mouse_pos) and scroll_wheel.y != 0) {
            const scroll_delta = scroll_wheel.y * 20  // arbitrary: 20px per wheel tick
            const max_scroll_y = @max(0, scroll_state.content_height - scroll_state.container_height)
            scene.setScrollOffset(
                idx,
                std.math.clamp(scroll_state.scroll_y - scroll_delta, 0, max_scroll_y),
                scroll_state.scroll_x,
            )
        }
        
        // Scrollbar drag
        const scrollbar_width = 12  // arbitrary
        const v_scrollbar_rect = Rect{
            .x = container_rect.x + container_rect.width - scrollbar_width,
            .y = container_rect.y,
            .width = scrollbar_width,
            .height = container_rect.height,
        }
        
        // Compute thumb position and height
        const scroll_ratio = scroll_state.scroll_y / 
            @max(1, scroll_state.content_height - scroll_state.container_height)
        const thumb_height = (scroll_state.container_height / scroll_state.content_height) * 
            container_rect.height
        const thumb_y = container_rect.y + (scroll_ratio * (container_rect.height - thumb_height))
        
        const thumb_rect = Rect{
            .x = v_scrollbar_rect.x,
            .y = thumb_y,
            .width = scrollbar_width,
            .height = thumb_height,
        }
        
        // Start drag
        if (thumb_rect.containsPoint(mouse_pos) and 
            platform.mouseButton(MouseButton.left) == Action.press) {
            scroll_state.dragging_v_scrollbar = true
            scroll_state.drag_start_y = mouse_pos.y
            scroll_state.drag_start_scroll_y = scroll_state.scroll_y
        }
        
        // Continue drag
        if (scroll_state.dragging_v_scrollbar) {
            const drag_delta = mouse_pos.y - scroll_state.drag_start_y
            const drag_ratio = drag_delta / (container_rect.height - thumb_height)
            const new_scroll_y = scroll_state.drag_start_scroll_y + 
                (drag_ratio * (scroll_state.content_height - scroll_state.container_height))
            const max_scroll_y = @max(0, scroll_state.content_height - scroll_state.container_height)
            scene.setScrollOffset(
                idx,
                std.math.clamp(new_scroll_y, 0, max_scroll_y),
                scroll_state.scroll_x,
            )
        }
        
        // End drag
        if (scroll_state.dragging_v_scrollbar and 
            platform.mouseButton(MouseButton.left) == Action.release) {
            scroll_state.dragging_v_scrollbar = false
        }
        
        // Similar logic for horizontal scrolling (post-v1 if needed)
    }
    
    // ... layout, render ...
}
```

### Layout integration

In module 04 layout engine `solve()`, after computing element rects:

```zig
// For each scroll container element:
// 1. Measure the total height/width of its children.
// 2. Store in scroll_state.content_height / content_width.
// 3. Store container_height / container_width from the container's computed rect.
// 4. Clamp scroll offsets if they exceed max.

for (scene.elements.layout, 0..) |layout_node, idx| {
    if (scene.kindOf(idx) != .scrollview) continue
    
    var content_height: f32 = 0
    var content_width: f32 = 0
    
    // Sum child heights
    const children = scene.elements.children[idx]
    for (children) |child_idx| {
        const child_rect = scene.elements.layout[child_idx].rect
        content_height += child_rect.height
        content_width = @max(content_width, child_rect.width)
    }
    
    const scroll_state = scene.scrollStateOf(idx)
    scroll_state.content_height = content_height
    scroll_state.content_width = content_width
    scroll_state.container_height = layout_node.rect.height
    scroll_state.container_width = layout_node.rect.width
    
    // Clamp offsets
    const max_scroll_y = @max(0, content_height - scroll_state.container_height)
    const max_scroll_x = @max(0, content_width - scroll_state.container_width)
    scroll_state.scroll_y = std.math.clamp(scroll_state.scroll_y, 0, max_scroll_y)
    scroll_state.scroll_x = std.math.clamp(scroll_state.scroll_x, 0, max_scroll_x)
}
```

### Renderer integration

In `src/app/renderer.zig` `buildDrawList()`:

1. For each scroll container, set a scissor rect to its bounds (M4-03).
2. Apply scroll offset to all child draw commands (translate by `-scroll_state.scroll_y`, etc.).
3. Draw scrollbars (thin rects on the edges):
   - Vertical scrollbar track: right edge of container.
   - Vertical scrollbar thumb: computed from scroll position.
   - Colors: theme-driven (M5-02).

### Behavioral contract

| Event | Behavior |
|---|---|
| Mouse wheel over scroll container | Content scrolls (scroll_y updated), element marked dirty |
| Mouse drags scrollbar thumb | Scroll offset updated continuously during drag |
| Content height changes (layout) | scroll_state.content_height updated, scroll offset clamped |
| `setScrollOffset()` called | scroll_y and scroll_x updated and clamped, element marked dirty |
| `getScrollOffset()` called | Returns current scroll_y and scroll_x |

### Module location

```
src/app/types.zig                 — ScrollState, Scene extensions
docs/specs/07.spec.md             — scrollStateOf, setScrollOffset, getScrollOffset
docs/specs/07.types.zig           — ScrollState struct, Scene._scroll_state field, WidgetKind.scrollview
docs/requirements/R35_scroll_container.md
src/app/app.zig                   — Scroll input handling
src/app/renderer.zig              — Scrollbar rendering, scissor rect application
docs/specs/04.spec.md             — Layout engine scroll state update
```

## Public API

New `Scene` methods and types:

```zig
pub const ScrollState = struct { scroll_y, scroll_x, content_height, content_width, ... }
pub fn scrollStateOf(self: *Scene, idx: u32) *ScrollState
pub fn setScrollOffset(self: *Scene, idx: u32, offset_y: f32, offset_x: f32) void
pub fn getScrollOffset(self: *Scene, idx: u32) struct { y: f32, x: f32 }
```

New `WidgetKind`:

```zig
pub const WidgetKind = enum { ..., scrollview }
```

## Non-goals (DO NOT implement — INV-5.4)

- **No horizontal scrolling (v1)** — vertical scrolling only; horizontal is post-v1.
- **No smooth/animated scrolling** — instant offset application.
- **No scroll-to-element** — no `scrollIntoView()` method (post-v1).
- **No nested scrolling** — scrollview inside scrollview is untested; post-v1 if needed.
- **No momentum/inertia scrolling** — stops immediately when drag ends.
- **No touch scrolling** — mouse wheel and scrollbar drag only (INV-1.2 desktop only).
- **No overflow visible / auto** — scrollview always clips (overflow = hidden only).
- **No custom scrollbar appearance** — theme-driven appearance; no custom styling.
- **No scroll events / callbacks** — scroll is internal state; no application hooks (INV-3.3).

## Acceptance criteria

1. Unit tests in `src/app/scroll_test.zig` (or added to existing test file) cover:
   - After instantiate, scroll container has `scroll_y = 0`, `scroll_x = 0`.
   - `setScrollOffset()` updates scroll position and clamps to valid range.
   - `getScrollOffset()` returns current offset.
   - Clamping works: setting a negative offset clamps to 0.
   - Clamping works: setting offset > max content clamps to max.
   - Layout engine updates `content_height` and `container_height`.
   - Mouse wheel over container scrolls content.
   - Scrollbar drag updates scroll offset continuously.

2. Integration test with a scrollable form:
   - Run the app with a scrollable container containing many items.
   - Mouse wheel scrolls the content.
   - Content is clipped to container bounds (no overflow).
   - Scrollbar appears on the right edge and is draggable.
   - Scrollbar thumb size reflects content/container ratio.

3. No memory leaks:
   - Scroll containers created and destroyed do not leak.

4. Checklist fully ticked.

## Open questions

None. Scroll container is scoped: vertical scrolling only for v1, mouse wheel + drag, no
nested scrolling, theme-driven appearance.
