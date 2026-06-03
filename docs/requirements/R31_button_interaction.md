# R31 — M3-02: Button interaction

> Roadmap item: M3-02  
> Depends on: M1-02 (event delivery), M3-01 (focus model), M4-01 (pseudo-state styling) in rendering pipeline  
> Read `00_constitution.md` before this file.

## Purpose

Buttons respond to input: hover, pressed, and disabled visual states. An `on_click` callback
is stored per-button and fired when the user releases the mouse over a focused/hovering button.
All state is stored in parallel arrays in `Scene` (INV-3.1). Visual state changes mark elements
dirty so the renderer applies pseudo-state overrides (M4-01).

## What to build

### Button state storage in `Scene`

Extend [07.types.zig](../specs/07.types.zig) `Scene` struct:

```zig
pub const ButtonState = struct {
    /// true if the mouse is currently over this button's layout rect.
    hovered: bool = false,
    
    /// true if the mouse button is pressed while hovering this button.
    pressed: bool = false,
    
    /// true if this button is disabled (does not respond to input).
    disabled: bool = false,
    
    /// Callback to invoke when button is clicked.
    /// Type-erased pointer + function for the callback.
    /// Do NOT fire during input processing; queue for execution after events.
    on_click: ?CallbackFn = null,
};

/// Type-erased callback: `ptr` is opaque, `call` invokes the callback.
pub const CallbackFn = struct {
    ptr: *anyopaque,
    call: *const fn (*anyopaque) void,
};

pub const Scene = struct {
    // ...existing fields...
    
    /// Parallel array of button states, indexed by ElementId.index.
    /// Only meaningful for elements with WidgetKind.button.
    /// Allocated and resized alongside other presentation arrays.
    _button_state: std.ArrayListUnmanaged(ButtonState) = .empty,
    
    /// Queued callbacks to fire at the end of the frame.
    /// Populated during mouse-press/release handling.
    _queued_callbacks: std.ArrayListUnmanaged(CallbackFn) = .empty,
    
    /// Set or update the on_click callback for element `idx`.
    /// Does not mark dirty; the callback fires at frame end.
    pub fn setButtonCallback(self: *Scene, idx: u32, callback: CallbackFn) !void
    
    /// Get the button state for element `idx` (only valid if kindOf(idx) == .button).
    pub fn buttonStateOf(self: *Scene, idx: u32) *ButtonState
    
    /// Fire all queued callbacks. Called once per frame, after input processing,
    /// before layout. Clears the queue afterward.
    pub fn fireQueuedCallbacks(self: *Scene) void
};
```

### Input handling in `App.run()`

After event polling and focus navigation (R30), add mouse-over and click detection:

```zig
while (!platform.shouldClose()) {
    platform.pollEvents()
    
    // Focus navigation (R30)
    // ...
    
    // NEW: Button interaction
    const mouse_pos = platform.mousePosition()
    var idx: u32 = 0
    while (idx < scene.count()) : (idx += 1) {
        if (scene.kindOf(idx) != .button) continue
        
        const rect = scene.elements.layout[idx].rect  // RenderObject.rect from layout
        const was_hovered = scene.buttonStateOf(idx).hovered
        const is_hovered = rect.containsPoint(mouse_pos)
        
        if (is_hovered != was_hovered) {
            scene.buttonStateOf(idx).hovered = is_hovered
            scene.elements.dirty.set(idx)  // Mark dirty for renderer
        }
    }
    
    // Handle mouse button press
    if (platform.mouseButton(MouseButton.left) == Action.press) {
        idx = 0
        while (idx < scene.count()) : (idx += 1) {
            if (scene.kindOf(idx) != .button) continue
            const state = scene.buttonStateOf(idx)
            if (state.hovered and !state.disabled) {
                state.pressed = true
                scene.elements.dirty.set(idx)
            }
        }
    }
    
    // Handle mouse button release
    if (platform.mouseButton(MouseButton.left) == Action.release) {
        idx = 0
        while (idx < scene.count()) : (idx += 1) {
            if (scene.kindOf(idx) != .button) continue
            const state = scene.buttonStateOf(idx)
            if (state.pressed) {
                state.pressed = false
                scene.elements.dirty.set(idx)
                if (state.hovered and !state.disabled and state.on_click != null) {
                    // Queue callback for execution after frame
                    try scene._queued_callbacks.append(gpa, state.on_click.?)
                }
            }
        }
    }
    
    // ... layout, render ...
    
    // NEW: Fire queued callbacks before rendering
    scene.fireQueuedCallbacks()
    
    // ... rest of frame loop ...
}
```

### Pseudo-state styling in renderer

In `src/app/renderer.zig` `buildDrawList()`, when drawing a button element:

```zig
// For each button element:
const button_state = scene.buttonStateOf(idx)
var style = scene.styleOf(idx).*  // Make a copy

if (!button_state.disabled) {
    if (button_state.pressed) {
        // Apply :active pseudo-state overrides (M4-01)
        style = applyPseudoStateOverrides(style, .active)
    } else if (button_state.hovered) {
        // Apply :hover pseudo-state overrides (M4-01)
        style = applyPseudoStateOverrides(style, .hover)
    }
} else {
    // Apply :disabled pseudo-state overrides (M4-01)
    style = applyPseudoStateOverrides(style, .disabled)
}

// Emit draw command with the resolved style
// ...
```

(The `applyPseudoStateOverrides` function is defined in M4-01. For now, this is a stub;
implement after M4-01 ships.)

### Behavioral contract

| Event | Behavior |
|---|---|
| Mouse moves over button | `hovered = true`, element marked dirty |
| Mouse leaves button | `hovered = false`, element marked dirty |
| Mouse left-click pressed while hovering | `pressed = true`, element marked dirty |
| Mouse left-click released while `pressed` | `pressed = false`, element marked dirty; if still hovered and not disabled, `on_click` is queued |
| Button is disabled | Does not respond to mouse input; `:disabled` style applied |
| Frame ends | All queued callbacks executed, queue cleared |

### Module location

```
src/app/types.zig                 — ButtonState, CallbackFn, Scene extensions
docs/specs/07.spec.md             — buttonStateOf, setButtonCallback, fireQueuedCallbacks
docs/specs/07.types.zig           — ButtonState struct, Scene._button_state field
docs/requirements/R31_button_interaction.md
src/app/app.zig                   — Input handling loop integration
src/app/renderer.zig              — Pseudo-state override application
```

## Public API

New `Scene` methods and types:

```zig
pub const ButtonState = struct { hovered, pressed, disabled, on_click }
pub const CallbackFn = struct { ptr, call }
pub fn setButtonCallback(self: *Scene, idx: u32, callback: CallbackFn) !void
pub fn buttonStateOf(self: *Scene, idx: u32) *ButtonState
pub fn fireQueuedCallbacks(self: *Scene) void
```

## Non-goals (DO NOT implement — INV-5.4)

- **No keyboard activation** — buttons activate on mouse click only (M3-01 focus does not auto-fire buttons; that is post-v1).
- **No double-click** — only left-click matters; no support for double-click or right-click.
- **No touch input** — GLFW mouse events only.
- **No drag-outside-release** — if the user presses on a button, drags outside, and releases, the button does not fire. Release must happen while hovered.
- **No button groups / radio buttons** — those are post-v1.
- **No accessibility callbacks** — no screen-reader announcements on click (INV-1.4).
- **No custom callback storage format** — `CallbackFn` is the only mechanism; no `Signal` triggers or observer patterns (INV-3.3).

## Acceptance criteria

1. Unit tests in `src/app/button_test.zig` (or added to existing test file) cover:
   - After instantiate, all buttons have default state (unhovered, not pressed, enabled, no callback).
   - Mouse move over button sets `hovered = true`, element marked dirty.
   - Mouse move away sets `hovered = false`, element marked dirty.
   - Mouse left-click pressed sets `pressed = true`.
   - Mouse left-click released while pressed and hovered fires callback and clears `pressed`.
   - Callback fires at frame end via `fireQueuedCallbacks()`, not immediately during input.
   - Disabled buttons do not respond to mouse input.
   - Multiple button clicks queue multiple callbacks; all fire in order.

2. Integration test with a simple app:
   - Run the app, hover over a button, see it change appearance (if pseudo-state styling is stubbed, at least verify `hovered` is true).
   - Click the button, see `pressed` state reflected (or stub message if M4-01 not yet shipped).
   - Click fires a callback (verified by logging or a test counter).

3. No memory leaks:
   - Buttons created and destroyed do not leak allocations.
   - `fireQueuedCallbacks()` clears the queue without leaking.

4. Checklist fully ticked.

## Open questions

None. Button interaction is scoped: single left-click, no keyboard, no double-click.
