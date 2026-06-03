# R40 — M4-01: Pseudo-state styling

> Roadmap item: M4-01  
> Depends on: module 09 (renderer/buildDrawList), M3-01 (focus model), M3-02 (button interaction)  
> Read `00_constitution.md` before this file.

## Purpose

Apply visual style overrides when an interactive element is in a hover, focus, active, or
disabled state. Style variants are stored as token-derived `ComputedStyle` overrides on
`Scene`'s parallel style arrays; the serializer (`buildDrawList`) reads the active pseudo-state
and blends in the override before emitting draw commands. No new reactivity mechanism is
introduced — state changes already mark elements dirty via M3-01/M3-02.

## What to build

### Pseudo-state enum

Add to [07.types.zig](../specs/07.types.zig):

```zig
pub const PseudoState = packed struct {
    hover:    bool = false,
    focus:    bool = false,
    active:   bool = false,  // mouse pressed / key held
    disabled: bool = false,
};
```

`PseudoState` is a packed struct so it fits in a single byte and can be stored in a
contiguous parallel array without padding overhead.

### Per-element pseudo-state storage in `Scene`

Extend [07.types.zig](../specs/07.types.zig) `Scene` struct:

```zig
pub const Scene = struct {
    // ...existing fields...

    /// Parallel array of pseudo-states, indexed by ElementId.index.
    /// All four flags default to false.
    _pseudo: std.ArrayListUnmanaged(PseudoState) = .empty,

    /// Return a pointer to the pseudo-state for element `idx`.
    /// Caller may read or modify the flags; after modifying, caller must
    /// mark the element dirty (scene.elements.dirty.set(idx)).
    pub fn pseudoOf(self: *Scene, idx: u32) *PseudoState

    /// Convenience: set one or more pseudo-state flags and mark dirty.
    /// Replaces the entire PseudoState for `idx` with `state`.
    pub fn setPseudo(self: *Scene, idx: u32, state: PseudoState) void
};
```

`_pseudo` is allocated alongside the other parallel arrays in `instantiate()` and cleared in
`reset()`. Every element gets a slot regardless of widget kind (simplifies index math).

### Style-override storage in `Scene`

Pseudo-state styling uses a separate parallel array of optional override styles, one per
pseudo-state variant per widget kind. Rather than storing one override per element (which
would be expensive for large scenes), overrides are stored per widget kind and sourced from
the theme. The renderer calls a pure function to resolve the effective style.

Add to [05.types.zig](../specs/05.types.zig):

```zig
/// Style deltas applied when a widget is in a given pseudo-state.
/// Only fields that differ from the base style need to be set;
/// a null field means "inherit from base".
pub const PseudoOverride = struct {
    background:   ?Color = null,
    text_color:   ?Color = null,
    border_color: ?Color = null,
    border_width: ?f32   = null,
    radius:       ?f32   = null,
};

/// All pseudo-state overrides for one widget kind (button, input, etc.).
/// Built entirely from tokens (INV-4.3).
pub const PseudoStyleSet = struct {
    hover:    PseudoOverride = .{},
    focus:    PseudoOverride = .{},
    active:   PseudoOverride = .{},
    disabled: PseudoOverride = .{},
};
```

Add component-style builders to [05.types.zig](../specs/05.types.zig):

```zig
pub fn buttonPseudo(t: Tokens) PseudoStyleSet {
    return .{
        .hover    = .{ .background = t.accent_hover },
        .focus    = .{ .border_color = Color.hex(0x0066FF), .border_width = 2 },
        .active   = .{ .background = t.accent_hover },
        .disabled = .{ .background = t.bg_surface, .text_color = t.text_disabled },
    };
}

pub fn inputPseudo(t: Tokens) PseudoStyleSet {
    return .{
        .hover    = .{ .border_color = t.border_strong },
        .focus    = .{ .border_color = Color.hex(0x0066FF), .border_width = 2 },
        .active   = .{},
        .disabled = .{ .background = t.bg_canvas, .text_color = t.text_disabled },
    };
}

pub fn dropdownPseudo(t: Tokens) PseudoStyleSet {
    return .{
        .hover    = .{ .border_color = t.border_strong },
        .focus    = .{ .border_color = Color.hex(0x0066FF), .border_width = 2 },
        .active   = .{},
        .disabled = .{ .background = t.bg_canvas, .text_color = t.text_disabled },
    };
}

pub fn checkboxPseudo(t: Tokens) PseudoStyleSet {
    return .{
        .hover    = .{ .border_color = t.border_strong },
        .focus    = .{ .border_color = Color.hex(0x0066FF), .border_width = 2 },
        .active   = .{},
        .disabled = .{ .text_color = t.text_disabled },
    };
}
```

### Style resolution in the serializer

In `src/09/types.zig` add a pure helper function:

```zig
/// Resolve the effective ComputedStyle for an element by layering pseudo-state
/// overrides on top of the base style. Priority: active > hover > focus > base.
/// Disabled overrides everything else.
/// This function is called by buildDrawList for every element; it is pure (no side effects).
pub fn resolveStyle(
    base: ComputedStyle,
    overrides: PseudoStyleSet,
    state: PseudoState,
) ComputedStyle {
    var out = base;
    if (state.focus) {
        if (overrides.focus.background)   |v| out.background   = v;
        if (overrides.focus.text_color)   |v| out.text_color   = v;
        if (overrides.focus.border_color) |v| out.border_color = v;
        if (overrides.focus.border_width) |v| out.border_width = v;
        if (overrides.focus.radius)       |v| out.radius       = v;
    }
    if (state.hover) {
        if (overrides.hover.background)   |v| out.background   = v;
        if (overrides.hover.text_color)   |v| out.text_color   = v;
        if (overrides.hover.border_color) |v| out.border_color = v;
        if (overrides.hover.border_width) |v| out.border_width = v;
        if (overrides.hover.radius)       |v| out.radius       = v;
    }
    if (state.active) {
        if (overrides.active.background)   |v| out.background   = v;
        if (overrides.active.text_color)   |v| out.text_color   = v;
        if (overrides.active.border_color) |v| out.border_color = v;
        if (overrides.active.border_width) |v| out.border_width = v;
        if (overrides.active.radius)       |v| out.radius       = v;
    }
    if (state.disabled) {
        if (overrides.disabled.background)   |v| out.background   = v;
        if (overrides.disabled.text_color)   |v| out.text_color   = v;
        if (overrides.disabled.border_color) |v| out.border_color = v;
        if (overrides.disabled.border_width) |v| out.border_width = v;
        if (overrides.disabled.radius)       |v| out.radius       = v;
    }
    return out;
}
```

### Integration in `buildDrawList`

In `src/09/types.zig` `buildDrawList()`, replace the direct style read with:

```zig
// For each element:
const base_style = scene.styleOf(idx).*;
const pseudo = scene.pseudoOf(idx).*;

const overrides: PseudoStyleSet = switch (scene.kindOf(idx)) {
    .button   => buttonPseudo(tokens),
    .input    => inputPseudo(tokens),
    .dropdown => dropdownPseudo(tokens),
    .checkbox => checkboxPseudo(tokens),
    else      => .{},  // no overrides for text, card, row, column, scrollview
};

const effective_style = resolveStyle(base_style, overrides, pseudo);
// Use effective_style for all draw commands for this element.
```

`buildDrawList` must receive the active `Tokens` (or `Theme`) so it can build the
`PseudoStyleSet` per element. Update the signature:

```zig
pub fn buildDrawList(
    alloc: std.mem.Allocator,
    scene: *Scene,
    atlas: *GlyphAtlas,
    tokens: Tokens,
) error{OutOfMemory}![]DrawCommand
```

### Integration with M3-01 (focus ring)

R30 hardcoded a `#0066ff` focus ring drawn as a separate `border_rect` overlay. With M4-01
in place, the focus ring moves into `inputPseudo`/`buttonPseudo` `focus.border_color` and
`focus.border_width`. The R30 hardcoded ring drawing code in `buildDrawList` is removed; the
pseudo-state override produces the same visual result through the normal border draw path.

### Integration with M3-02 (button interaction)

R31 called `applyPseudoStateOverrides(style, .hover/.active/.disabled)` as a stub. That stub
is replaced by this implementation: `buildDrawList` reads `scene.pseudoOf(idx)` (which M3-02's
input handler already populates for button elements via `setPseudo`) and calls `resolveStyle`.

The `ButtonState.hovered`, `ButtonState.pressed`, and `ButtonState.disabled` flags from R31
are the authoritative inputs that drive `PseudoState` for buttons. In `App.run()`, after
updating `ButtonState`, sync to `PseudoState`:

```zig
// After each button state update:
const bs = scene.buttonStateOf(idx);
scene.setPseudo(idx, .{
    .hover    = bs.hovered and !bs.disabled,
    .active   = bs.pressed,
    .disabled = bs.disabled,
    .focus    = scene.getFocus() == idx,
});
```

### Behavioral contract

| Condition | Effective style |
|---|---|
| No flags set | Base `ComputedStyle` unchanged |
| `focus = true` | Focus border-color/width applied over base |
| `hover = true` | Hover background applied; overwrites focus if both set |
| `active = true` | Active background applied; overwrites hover if both set |
| `disabled = true` | Disabled colors applied; overwrites all other flags |
| Non-interactive kinds (text, card, row, column) | `PseudoStyleSet{}` (empty); no overrides |

Priority: **disabled > active > hover > focus** (applied in that order, each layer
overwrites the previous).

### Module location

```
src/app/types.zig             — PseudoState (added to Scene parallel array)
docs/specs/07.types.zig       — PseudoState, pseudoOf, setPseudo
src/05/types.zig              — PseudoOverride, PseudoStyleSet, buttonPseudo, inputPseudo, ...
docs/specs/05.types.zig       — PseudoOverride, PseudoStyleSet added
src/09/types.zig              — resolveStyle helper, buildDrawList signature update
docs/specs/09.types.zig       — resolveStyle, buildDrawList signature update
src/app/app.zig               — PseudoState sync after button/input state updates
```

## Public API

New types in module 05:

```zig
pub const PseudoOverride = struct { background, text_color, border_color, border_width, radius }
pub const PseudoStyleSet = struct { hover, focus, active, disabled: PseudoOverride }
pub fn buttonPseudo(t: Tokens) PseudoStyleSet
pub fn inputPseudo(t: Tokens) PseudoStyleSet
pub fn dropdownPseudo(t: Tokens) PseudoStyleSet
pub fn checkboxPseudo(t: Tokens) PseudoStyleSet
```

New in module 07:

```zig
pub const PseudoState = packed struct { hover, focus, active, disabled: bool }
pub fn pseudoOf(self: *Scene, idx: u32) *PseudoState
pub fn setPseudo(self: *Scene, idx: u32, state: PseudoState) void
```

New in module 09:

```zig
pub fn resolveStyle(base: ComputedStyle, overrides: PseudoStyleSet, state: PseudoState) ComputedStyle
// buildDrawList gains a `tokens: Tokens` parameter
```

## Non-goals (DO NOT implement — INV-5.4)

- **No CSS `:visited` / `:checked` / `:placeholder` pseudo-states** — only hover, focus,
  active, disabled.
- **No per-element custom pseudo overrides** — application code cannot register its own
  pseudo-state style; overrides are built from tokens by widget kind.
- **No animated transitions** — style changes are instantaneous (animations are post-v1).
- **No specificity / cascade resolution** — the four-state priority order is fixed
  (INV-4.2).
- **No pseudo-state for container widgets** (card, row, column, scrollview) — only
  interactive widgets get overrides.
- **No `:nth-child` or structural pseudo-classes** — those require the CSS cascade (INV-4.2).

## Acceptance criteria

1. `zig build test-09` and `zig build test-09-unit` pass.  New test cases must cover:
   - `resolveStyle` with no flags returns the base style unchanged.
   - `resolveStyle` with `hover = true` applies hover background.
   - `resolveStyle` with `active = true` overwrites hover when both set.
   - `resolveStyle` with `disabled = true` overwrites everything.
   - `resolveStyle` with non-interactive widget kind (empty `PseudoStyleSet`) returns base.
   - `buildDrawList` with a hovered button produces a draw command with `accent_hover`
     background (verified by inspecting the returned `[]DrawCommand`).

2. `zig build test-scene` passes. New test cases:
   - `setPseudo(idx, state)` marks the element dirty.
   - `pseudoOf(idx)` returns a pointer to the correct element's state.
   - After `reset()`, all pseudo-state entries are cleared.

3. Integration: run the app, hover over a button, and observe the background change.
   Tab to focus an input and observe the focus border. Click a button and observe active
   state. No Vulkan validation errors.

4. The R30 hardcoded focus ring drawing code is removed; focus styling is now driven by
   `inputPseudo`/`buttonPseudo`.

5. No per-frame allocations in `resolveStyle` or the pseudo-state lookup path.

6. Checklist fully ticked.

## Open questions

None. The four pseudo-states are fixed. Priority order (disabled > active > hover > focus)
mirrors browser conventions for the same four states.
