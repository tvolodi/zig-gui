# R33 — M3-04: Dropdown open/close

> Roadmap item: M3-04  
> Depends on: M1-02 (event delivery), M3-01 (focus model), M4-02 (overlay z-layer)  
> Read `00_constitution.md` before this file.

## Purpose

A `dropdown` widget displays a trigger button (showing the selected item) and, when opened,
an overlay list of options. The user selects an option with keyboard (arrow keys + Enter) or
mouse click. The open/close state and selected value are stored in parallel arrays in `Scene`
(INV-3.1). List navigation and value selection mark elements dirty so the renderer can update
the dropdown's appearance and the overlay's visibility.

## What to build

### Dropdown state storage in `Scene`

Extend [07.types.zig](../specs/07.types.zig) `Scene` struct:

```zig
pub const DropdownOption = struct {
    /// Human-readable display label.
    label: []const u8,
    
    /// Opaque value associated with this option.
    /// Stored as a type-erased pointer; the owning application owns the data.
    value: *anyopaque,
};

pub const DropdownState = struct {
    /// All available options for this dropdown.
    options: std.ArrayListUnmanaged(DropdownOption) = .empty,
    
    /// Index into `options` of the currently selected option.
    /// Valid range: [0, options.len). If options is empty, this is undefined.
    selected_idx: u32 = 0,
    
    /// true if the dropdown list is open (overlay visible).
    open: bool = false,
    
    /// If open, the index (in `options`) currently highlighted by keyboard navigation.
    /// When the list opens, this is set to `selected_idx`.
    /// Arrow keys change this; Enter selects.
    highlight_idx: u32 = 0,
};

pub const Scene = struct {
    // ...existing fields...
    
    /// Parallel array of dropdown states, indexed by ElementId.index.
    /// Only meaningful for elements with WidgetKind.dropdown.
    _dropdown_state: std.ArrayListUnmanaged(DropdownState) = .empty,
    
    /// Get the dropdown state for element `idx` (only valid if kindOf(idx) == .dropdown).
    pub fn dropdownStateOf(self: *Scene, idx: u32) *DropdownState
    
    /// Initialize dropdown `idx` with the given options.
    /// `options` is copied; ownership of values remains with the caller.
    pub fn setDropdownOptions(
        self: *Scene,
        idx: u32,
        options: []const DropdownOption,
    ) !void
    
    /// Set the currently selected option to `option_idx`.
    /// If the dropdown is open, closes it.
    /// Marks the element dirty.
    pub fn selectDropdownOption(self: *Scene, idx: u32, option_idx: u32) !void
    
    /// Open the dropdown list and reset highlight to the current selection.
    /// Marks the element dirty.
    pub fn openDropdown(self: *Scene, idx: u32) void
    
    /// Close the dropdown list.
    /// Marks the element dirty.
    pub fn closeDropdown(self: *Scene, idx: u32) void
    
    /// Toggle open/close state of the dropdown.
    /// Marks the element dirty.
    pub fn toggleDropdown(self: *Scene, idx: u32) void
    
    /// Get the currently selected value (opaque pointer).
    /// Valid only if the dropdown has at least one option.
    pub fn getDropdownValue(self: *Scene, idx: u32) *anyopaque
};
```

### Integration into focus and input handling

When a dropdown receives focus (via R30 `setFocus`):

```zig
// In Scene.setFocus:
pub fn setFocus(self: *Scene, idx: u32) void {
    var old_idx = self.focused_idx
    self.focused_idx = idx
    
    // ... deactivate old input (R32) ...
    
    // NEW: If old focused element was a dropdown, close it.
    if (old_idx < self.count() and self.kindOf(old_idx) == .dropdown) {
        self.closeDropdown(old_idx)
    }
    
    // ... mark focusable elements dirty ...
}
```

When a dropdown is focused and receives Space or Enter key, open it:

```zig
// In App.run() input handling section:
if (scene.getFocus() < scene.count() and scene.kindOf(scene.getFocus()) == .dropdown) {
    const dropdown_idx = scene.getFocus()
    
    while (event_queue.next()) |event| {
        if (event.key == Key.space or event.key == Key.enter) {
            if (event.action == Action.press) {
                scene.toggleDropdown(dropdown_idx)
            }
        } else if (event.key == Key.up and event.action == Action.press) {
            const state = scene.dropdownStateOf(dropdown_idx)
            if (state.open) {
                state.highlight_idx = if (state.highlight_idx > 0)
                    state.highlight_idx - 1
                else
                    @intCast(state.options.items.len - 1)
                scene.elements.dirty.set(dropdown_idx)
            }
        } else if (event.key == Key.down and event.action == Action.press) {
            const state = scene.dropdownStateOf(dropdown_idx)
            if (state.open) {
                state.highlight_idx = if (state.highlight_idx + 1 < state.options.items.len)
                    state.highlight_idx + 1
                else
                    0
                scene.elements.dirty.set(dropdown_idx)
            }
        } else if (event.key == Key.enter and event.action == Action.press) {
            const state = scene.dropdownStateOf(dropdown_idx)
            if (state.open) {
                scene.selectDropdownOption(dropdown_idx, state.highlight_idx) catch {}
            }
        } else if (event.key == Key.escape and event.action == Action.press) {
            scene.closeDropdown(dropdown_idx)
        }
    }
}
```

### Mouse handling for dropdown

When the dropdown is open, the overlay list is interactive:

```zig
// In App.run(), in the mouse event handling section:
var idx: u32 = 0
while (idx < scene.count()) : (idx += 1) {
    if (scene.kindOf(idx) != .dropdown) continue
    const state = scene.dropdownStateOf(idx)
    if (!state.open) continue
    
    // Compute overlay rect (below the trigger button)
    const trigger_rect = scene.elements.layout[idx].rect
    const option_height = 32  // arbitrary; should be configurable per theme
    const overlay_rect = Rect{
        .x = trigger_rect.x,
        .y = trigger_rect.y + trigger_rect.height,
        .width = trigger_rect.width,
        .height = option_height * state.options.items.len,
    }
    
    // Check mouse over each option
    if (overlay_rect.containsPoint(platform.mousePosition())) {
        const relative_y = platform.mousePosition().y - overlay_rect.y
        const option_idx = @intCast(u32, relative_y / option_height)
        if (option_idx < state.options.items.len) {
            state.highlight_idx = option_idx
            scene.elements.dirty.set(idx)
            
            // Click = select
            if (platform.mouseButton(MouseButton.left) == Action.release) {
                scene.selectDropdownOption(idx, option_idx) catch {}
            }
        }
    } else if (platform.mouseButton(MouseButton.left) == Action.press) {
        // Click outside dropdown = close
        scene.closeDropdown(idx)
    }
}
```

### Rendering the overlay

In `src/app/renderer.zig` `buildDrawList()`, after drawing the main scene:

1. For each open dropdown, draw the overlay list (M4-02 z-layer).
2. For each option in the list:
   - Draw a background rect (using the option's token style or a base color).
   - If the option is highlighted, apply a highlight color override.
   - Draw the option label text (centered vertically in the option rect).
3. Overlay order: highest z-index (rendered last) so it appears on top.

### Behavioral contract

| Event | Behavior |
|---|---|
| Dropdown receives focus | No automatic open (user must press Space/Enter) |
| Space or Enter pressed on focused dropdown | Toggle open/close |
| Arrow Up pressed while open | Move highlight backward, wrap to last |
| Arrow Down pressed while open | Move highlight forward, wrap to first |
| Enter pressed while open | Select highlighted option, close dropdown |
| Escape pressed | Close dropdown |
| Mouse moves over option in open overlay | Highlight that option |
| Mouse clicks option in open overlay | Select it, close dropdown |
| Mouse clicks outside open overlay | Close dropdown |
| `selectDropdownOption()` called | `selected_idx` updated, dropdown closed, element marked dirty |
| `openDropdown()` called | `open = true`, `highlight_idx = selected_idx`, element marked dirty |
| `closeDropdown()` called | `open = false`, element marked dirty |

### Module location

```
src/app/types.zig                 — DropdownOption, DropdownState, Scene extensions
docs/specs/07.spec.md             — dropdownStateOf, setDropdownOptions, selectDropdownOption, etc.
docs/specs/07.types.zig           — DropdownState struct, Scene._dropdown_state field
docs/requirements/R33_dropdown_open_close.md
src/app/app.zig                   — Dropdown input and mouse handling
src/app/renderer.zig              — Overlay rendering (M4-02 integration)
```

## Public API

New `Scene` methods and types:

```zig
pub const DropdownOption = struct { label, value }
pub const DropdownState = struct { options, selected_idx, open, highlight_idx }
pub fn dropdownStateOf(self: *Scene, idx: u32) *DropdownState
pub fn setDropdownOptions(self: *Scene, idx: u32, options: []const DropdownOption) !void
pub fn selectDropdownOption(self: *Scene, idx: u32, option_idx: u32) !void
pub fn openDropdown(self: *Scene, idx: u32) void
pub fn closeDropdown(self: *Scene, idx: u32) void
pub fn toggleDropdown(self: *Scene, idx: u32) void
pub fn getDropdownValue(self: *Scene, idx: u32) *anyopaque
```

## Non-goals (DO NOT implement — INV-5.4)

- **No multi-select dropdown** — single selection only.
- **No searchable/filterable dropdown** — full list is always shown when open.
- **No custom option rendering** — each option is a label string, no rich content.
- **No grouped options** — flat list only.
- **No lazy loading** — all options are in memory.
- **No dropdown-value-change callback** — changing selection does not fire a signal or callback; the value is read via `getDropdownValue()` (INV-3.3).
- **No option-hover callbacks** — hover is visual only; no application-code hooks.
- **No animated open/close** — instant state toggle.
- **No virtual scrolling in list** — list renders all options (post-v1 optimization).

## Acceptance criteria

1. Unit tests in `src/app/dropdown_test.zig` (or added to existing test file) cover:
   - After instantiate, dropdown has empty options, closed, selected_idx = 0.
   - `setDropdownOptions()` populates the option list.
   - `openDropdown()` sets `open = true`, `highlight_idx = selected_idx`.
   - Arrow keys navigate highlight forward/backward with wrapping.
   - Enter while open selects the highlighted option and closes.
   - Escape closes the dropdown without selecting.
   - `selectDropdownOption()` updates `selected_idx`, closes the dropdown.
   - `getDropdownValue()` returns the selected option's value pointer.

2. Integration test with a simple form:
   - Run the app, Tab to a dropdown, press Space to open.
   - Use arrow keys to navigate options, press Enter to select.
   - Verify the trigger button updates to show the new selection.
   - Click an option in the overlay (mouse interaction).
   - Click outside to close.

3. No memory leaks:
   - Dropdowns created and destroyed do not leak.
   - Options list does not leak when replaced.

4. Overlay rendering:
   - Open dropdown shows list below the trigger button.
   - List is rendered above other elements (z-order M4-02).
   - Options are clickable.

5. Checklist fully ticked.

## Open questions

None. Dropdown is scoped: single-select, keyboard + mouse, simple string labels, no virtual
scrolling.
