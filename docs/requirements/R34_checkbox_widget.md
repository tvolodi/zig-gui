# R34 — M3-05: Checkbox widget

> Roadmap item: M3-05  
> Depends on: M1-02 (event delivery), M3-01 (focus model), M2-01 (signals)  
> Read `00_constitution.md` before this file.

## Purpose

A `checkbox` widget is a boolean toggle that can be checked or unchecked. It responds to mouse
click and Space key when focused. The checked state is stored in parallel arrays in `Scene`
(INV-3.1) and can be bound to a `Signal(bool)` via the binding system (M2-04). Checkboxes
replace the dropdown workaround currently used in schema forms (module 08).

Note: `checkbox` is a new `WidgetKind` not yet in the module 07 spec. This requirement
adds it.

## What to build

### Checkbox widget kind

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
    checkbox,  // NEW
};

pub fn tagToKind(tag: []const u8) ?WidgetKind {
    // ... existing cases ...
    if (eql(u8, tag, "Checkbox")) return .checkbox;
    // ...
}

pub fn defaultLayoutFor(kind: WidgetKind) LayoutNode {
    return switch (kind) {
        // ... existing cases ...
        .checkbox => .{ .display = .block },  // NEW
        // ...
    };
}
```

### Checkbox state storage in `Scene`

Extend [07.types.zig](../specs/07.types.zig) `Scene` struct:

```zig
pub const CheckboxState = struct {
    /// true if the checkbox is checked.
    checked: bool = false,
    
    /// true if the checkbox is disabled (does not respond to input).
    disabled: bool = false,
    
    /// true if the mouse is currently over this checkbox's layout rect.
    hovered: bool = false,
    
    /// true if the mouse button is pressed while hovering this checkbox.
    pressed: bool = false,
};

pub const Scene = struct {
    // ...existing fields...
    
    /// Parallel array of checkbox states, indexed by ElementId.index.
    /// Only meaningful for elements with WidgetKind.checkbox.
    _checkbox_state: std.ArrayListUnmanaged(CheckboxState) = .empty,
    
    /// Get the checkbox state for element `idx` (only valid if kindOf(idx) == .checkbox).
    pub fn checkboxStateOf(self: *Scene, idx: u32) *CheckboxState
    
    /// Set the checked state of checkbox `idx`.
    /// Marks the element dirty.
    pub fn setCheckboxChecked(self: *Scene, idx: u32, checked: bool) void
    
    /// Get the checked state of checkbox `idx`.
    pub fn isCheckboxChecked(self: *Scene, idx: u32) bool
};
```

### Input handling in `App.run()`

After other input handling, add checkbox click detection:

```zig
while (!platform.shouldClose()) {
    platform.pollEvents()
    
    // ... focus, button, input, dropdown handling ...
    
    // NEW: Checkbox interaction
    const mouse_pos = platform.mousePosition()
    var idx: u32 = 0
    while (idx < scene.count()) : (idx += 1) {
        if (scene.kindOf(idx) != .checkbox) continue
        
        const rect = scene.elements.layout[idx].rect
        const was_hovered = scene.checkboxStateOf(idx).hovered
        const is_hovered = rect.containsPoint(mouse_pos)
        
        if (is_hovered != was_hovered) {
            scene.checkboxStateOf(idx).hovered = is_hovered
            scene.elements.dirty.set(idx)
        }
    }
    
    // Handle mouse button press
    if (platform.mouseButton(MouseButton.left) == Action.press) {
        idx = 0
        while (idx < scene.count()) : (idx += 1) {
            if (scene.kindOf(idx) != .checkbox) continue
            const state = scene.checkboxStateOf(idx)
            if (state.hovered and !state.disabled) {
                state.pressed = true
                scene.elements.dirty.set(idx)
            }
        }
    }
    
    // Handle mouse button release + toggle
    if (platform.mouseButton(MouseButton.left) == Action.release) {
        idx = 0
        while (idx < scene.count()) : (idx += 1) {
            if (scene.kindOf(idx) != .checkbox) continue
            const state = scene.checkboxStateOf(idx)
            if (state.pressed) {
                state.pressed = false
                if (state.hovered and !state.disabled) {
                    state.checked = !state.checked
                    // Mark dirty so renderer updates the checked appearance
                    scene.elements.dirty.set(idx)
                }
                scene.elements.dirty.set(idx)
            }
        }
    }
    
    // NEW: Keyboard toggle (Space key on focused checkbox)
    if (scene.getFocus() < scene.count() and 
        scene.kindOf(scene.getFocus()) == .checkbox) {
        const checkbox_idx = scene.getFocus()
        const state = scene.checkboxStateOf(checkbox_idx)
        
        while (event_queue.next()) |event| {
            if (event.key == Key.space and event.action == Action.press and !state.disabled) {
                state.checked = !state.checked
                scene.elements.dirty.set(checkbox_idx)
            }
        }
    }
    
    // ... layout, render ...
}
```

### Checkbox rendering

In `src/app/renderer.zig` `buildDrawList()`, for each checkbox element:

1. Draw a small square box (checkbox container).
2. If checked, draw a checkmark (Unicode ✓ or a small rect) inside the box.
3. If hovered (but not pressed), apply a subtle background highlight.
4. If pressed, apply a pressed-state highlight.
5. If disabled, apply a disabled appearance (grayed out).
6. Draw the label text to the right of the checkbox (if provided).

Use token-driven colors from the theme (M5-02 should define checkbox colors).

### Binding checkbox to Signal(bool)

The binding system (M2-04) is extended to support checkbox binding in module 08 schema forms.
This requirement does not add new binding APIs; it just ensures checkboxes can be read/written
by the existing binding mechanism:

```zig
// In binding.zig, add support for checkbox:
pub fn bindCheckbox(
    set: *BindingSet,
    element_idx: u32,
    signal: *Signal(bool),
) !void {
    // Store a binding from the signal to the element.
    // On refresh, copy signal.get() → checkbox state.
    // On signal.set(), the dirty bit is already marked (R20).
}
```

(Exact implementation is module 08's job, but this R34 requirement ensures checkboxes
participate in the binding system.)

### Behavioral contract

| Event | Behavior |
|---|---|
| Mouse moves over checkbox | `hovered = true`, element marked dirty |
| Mouse leaves checkbox | `hovered = false`, element marked dirty |
| Mouse left-click pressed while hovering | `pressed = true`, element marked dirty |
| Mouse left-click released while `pressed` and hovering | `checked` toggled, element marked dirty |
| Space pressed on focused checkbox | `checked` toggled, element marked dirty |
| Checkbox is disabled | Does not respond to input; appears grayed out |
| `setCheckboxChecked(idx, val)` called | `checked` set to `val`, element marked dirty |
| `isCheckboxChecked(idx)` called | Returns current `checked` state |

### Module location

```
src/app/types.zig                 — CheckboxState, Scene extensions
docs/specs/07.spec.md             — checkboxStateOf, setCheckboxChecked, isCheckboxChecked
docs/specs/07.types.zig           — CheckboxState struct, Scene._checkbox_state field, WidgetKind.checkbox
docs/requirements/R34_checkbox_widget.md
src/app/app.zig                   — Checkbox input handling
src/app/renderer.zig              — Checkbox rendering
docs/specs/08.spec.md             — Integration with schema forms (module 08)
docs/specs/08.types.zig           — Schema form widget registry update
```

## Public API

New `Scene` methods and types:

```zig
pub const CheckboxState = struct { checked, disabled, hovered, pressed }
pub fn checkboxStateOf(self: *Scene, idx: u32) *CheckboxState
pub fn setCheckboxChecked(self: *Scene, idx: u32, checked: bool) void
pub fn isCheckboxChecked(self: *Scene, idx: u32) bool
```

New `WidgetKind`:

```zig
pub const WidgetKind = enum { ..., checkbox }
```

## Non-goals (DO NOT implement — INV-5.4)

- **No tri-state checkbox** — checked/unchecked only, no indeterminate state.
- **No checkbox groups** — individual checkboxes only (radio buttons are post-v1).
- **No label wrapping** — label is a single line (text truncation is M4-05).
- **No checkbox-change callbacks** — no event emitters (INV-3.3); use signals or schema forms.
- **No custom checkbox appearance** — appearance is theme-driven; no CSS-style customization.
- **No toggle switches** — checkbox widget only (switches are post-v1 UI variation).

## Acceptance criteria

1. Unit tests in `src/app/checkbox_test.zig` (or added to existing test file) cover:
   - After instantiate, checkbox has `checked = false`, `disabled = false`, not hovered, not pressed.
   - Mouse move over checkbox sets `hovered = true`, element marked dirty.
   - Mouse move away sets `hovered = false`, element marked dirty.
   - Mouse left-click pressed sets `pressed = true`.
   - Mouse left-click released while pressed and hovered toggles `checked`.
   - Space key on focused checkbox toggles `checked`.
   - Disabled checkboxes do not respond to input.
   - `setCheckboxChecked()` and `isCheckboxChecked()` work correctly.

2. Integration test with a simple form:
   - Run the app, Tab to a checkbox, press Space to toggle.
   - Click the checkbox with the mouse, see it toggle.
   - Verify the checkmark appears/disappears.
   - Verify hover/pressed states are visually distinct.

3. No memory leaks:
   - Checkboxes created and destroyed do not leak.

4. Integration with schema forms (module 08):
   - A schema form with a boolean field renders a checkbox.
   - Toggling the checkbox updates the form's `Value` tree.
   - The checkbox can be bound to a `Signal(bool)` if desired.

5. Checklist fully ticked.

## Open questions

None. Checkbox is scoped: boolean toggle, mouse + keyboard, no tri-state, no custom appearance
beyond theme tokens.
