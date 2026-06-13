# RG1 — M17-01: Accessibility tree

> Roadmap item: M17-01
> Depends on: Module 07 (components, Scene)
> Read `00_constitution.md` before this file.

## Purpose

Establish a parallel `AccessNode` tree alongside the element tree in `Scene`. Each live element gets one `AccessNode` containing semantic information that accessibility tools (screen readers, narrator) can interrogate: role (button, text, list, etc.), name (label text or `aria-label` attribute), and state (checked, disabled, expanded, etc.). The accessibility tree is built during `Scene.instantiate()` and kept in sync with the element tree by the element store's dirty-scan mechanism.

## What to build

### `AccessRole` enum — `src/07/types.zig`

```zig
pub const AccessRole = enum(u8) {
    none,           // element has no semantic role (e.g. a generic container)
    text,           // static text, not interactive
    button,         // clickable button
    link,           // hyperlink (navigation)
    checkbox,       // boolean toggle
    radio,          // one-of-many selection
    combobox,       // dropdown selection widget
    listbox,        // list of selectable items
    option,         // item within a list or combo
    slider,         // continuous range input
    spinbutton,     // numeric input with +/- spinners
    textbox,        // single-line text input
    textarea,       // multi-line text input
    list,           // container for list items (role=list in markup)
    listitem,       // child of a list (role=listitem in markup)
    tab,            // tab header in a tablist
    tablist,        // container of tabs
    tabpanel,       // content area of an active tab
    menu,           // context menu or app menu
    menuitem,       // item within a menu
    menuitemcheckbox, // togglable menu item
    menuitemradio,  // radio-style menu item
    dialog,         // modal dialog overlay
    progressbar,    // progress indicator
    tooltip,        // hover-triggered info popup
    img,            // image / icon element
    region,         // semantic region (e.g. main, footer, aside)
};
```

### `AccessState` packed struct — `src/07/types.zig`

```zig
pub const AccessState = packed struct(u8) {
    /// Whether the element is currently disabled and cannot be interacted with
    disabled: bool = false,
    /// Whether a checkbox/radio/toggle is in the checked/selected/on state
    checked: bool = false,
    /// Whether the element currently has keyboard focus
    focused: bool = false,
    /// Whether an expandable element (accordion, details, menu) is open
    expanded: bool = false,
    /// Whether the element is hidden from the accessibility tree and UI
    hidden: bool = false,
    /// Whether the element is selected (e.g. in a listbox or tabs)
    selected: bool = false,
    /// Whether the element has invalid input (form validation error)
    invalid: bool = false,
    /// Padding for u8 alignment
    _padding: u1 = 0,
};
```

### `AccessNode` struct — `src/07/types.zig`

```zig
pub const AccessNode = struct {
    /// Semantic role of this element (e.g. button, text, list)
    role: AccessRole = .none,
    
    /// Human-readable name (from aria-label, label child, or text content)
    /// Owned by the Scene arena; may be empty string if unnamed
    name: []const u8 = "",
    
    /// Optional description or long-form label (aria-description attribute)
    /// Owned by the Scene arena; may be empty string if not set
    description: []const u8 = "",
    
    /// Semantic state flags (disabled, checked, focused, expanded, hidden, selected, invalid)
    state: AccessState = .{},
    
    /// For checkbox/radio/toggle: current value (true = checked, false = unchecked)
    /// For slider/spinbutton: current numeric value as f32
    /// For text input: not used (name field carries the content)
    /// For combobox/listbox: index of selected item (or NONE if no selection)
    value: f32 = 0.0,
    
    /// For rangeable elements (slider, progress bar): minimum value
    value_min: f32 = 0.0,
    
    /// For rangeable elements: maximum value
    value_max: f32 = 100.0,
};
```

### Parallel array in `Scene` — `src/07/types.zig`

Extend `Scene` struct:

```zig
pub const Scene = struct {
    // ... existing fields ...
    
    /// Parallel array of AccessNode entries, one per live element.
    /// Indexed by element index, same as kind[], style[], text[], etc.
    /// Populated during instantiate(); kept in sync with element tree.
    /// Owned by the Scene arena.
    _access_nodes: std.ArrayListUnmanaged(AccessNode) = .empty,
};
```

### Public API methods — `src/07/types.zig`

Add to `Scene`:

```zig
pub fn accessNodeOf(self: *Scene, idx: u32) *AccessNode
    // Return mutable pointer to the AccessNode for element at idx.
    // Does NOT check bounds; caller must ensure idx is valid.

pub fn setAccessRole(self: *Scene, idx: u32, role: AccessRole) void
    // Set the semantic role for element idx. Mark element dirty (accessibility tree has changed).

pub fn setAccessName(self: *Scene, idx: u32, name: []const u8) void
    // Set the human-readable name for element idx. Allocate into arena if needed.
    // Mark element dirty.

pub fn setAccessDescription(self: *Scene, idx: u32, desc: []const u8) void
    // Set the description / long-form label for element idx.

pub fn setAccessState(self: *Scene, idx: u32, state: AccessState) void
    // Set the state flags for element idx. Mark element dirty.

pub fn setAccessValue(self: *Scene, idx: u32, value: f32) void
    // Set the numeric/index value for element idx (slider, spinner, radio index, etc.).

pub fn setAccessValueRange(self: *Scene, idx: u32, min: f32, max: f32) void
    // Set min/max range for a rangeable element (slider, progress bar, spinbutton).
```

### Initialization during `Scene.instantiate()`

When an element is instantiated, the corresponding `AccessNode` is allocated and configured based on:

1. **Element kind → default role:** `AccessRole.button` for `.button`, `.checkbox` for `.checkbox`, `.textbox` for `.input`, etc. (see mapping table below).
2. **Markup attributes:** `role=` (if present, overrides kind-based default); `aria-label=` (sets name); `aria-description=` (sets description).
3. **Text content:** If no `aria-label` is present, use the element's text content as the name (for buttons, labels, etc.).
4. **Label child:** For elements with a `label` slot child (checkbox, radio), use that child's text as the name if no `aria-label` is present.
5. **Widget state:** `AccessState` flags are set based on widget state (disabled, checked, focused, expanded, hidden).

### Kind → AccessRole mapping — `src/07/types.zig`

Add a module-level helper function:

```zig
pub fn defaultAccessRoleFor(kind: WidgetKind) AccessRole
    // Return the default AccessRole for a given WidgetKind.
    // Example mapping:
    //   .text → .text
    //   .button → .button
    //   .input → .textbox
    //   .checkbox → .checkbox
    //   .radio → .radio
    //   .dropdown → .combobox
    //   .scrollview → .none
    //   .card → .none
    //   .row → .none
    //   .column → .none
    //   .textarea → .textarea
    //   .slider → .slider
    //   .progress_bar → .progressbar
    //   .spinner → .progressbar
    //   .tabs → .tablist
    //   .tab_item → .tabpanel
    //   .accordion → .region
    //   .date_picker → .combobox
    //   .avatar → .img
    //   .badge → .text
    //   .separator → .none
    //   .tooltip → .tooltip
    //   .icon → .img
    //   .image → .img
    //   .data_table → .none
```

### Keeping AccessNode in sync

When the element tree changes:

- **Element added:** A new `AccessNode` is allocated in the parallel array at the same index. Default role is set from `defaultAccessRoleFor(kind)`. Name/description/state are set from markup attributes.
- **Element removed:** The corresponding `AccessNode` entry is cleared (or kept as a zero-initialized stub if array reuse is in use).
- **Element state changes (dirty scan):** When a button is pressed, a checkbox is toggled, or an input is focused, the corresponding `AccessNode.state` flags are updated by the renderer or input handler in `app.zig` via `Scene.setAccessState()`.
- **Text content changes:** When an element's text is updated, the accessibility tree's name field should also be updated if the element has no explicit `aria-label`.

### Module location

```
src/07/types.zig                  — AccessRole, AccessState, AccessNode structs
src/07/types.zig                  — Scene._access_nodes parallel array
src/07/types.zig                  — Scene accessor methods (accessNodeOf, setAccessRole, etc.)
src/07/types.zig                  — defaultAccessRoleFor helper
src/07/accessibility.zig          — Optional: pure helper functions for accessibility-tree building
```

The accessibility tree is not rendered or exposed outside `Scene` in this R-file. The bridge to AT-SPI (Linux) and UIA (Windows) is handled in RG2 and RG3.

## Non-goals (DO NOT implement — INV-5.4)

- **No dynamic role changes via markup.** Once an element is instantiated, its role does NOT change if a signal bound to its `role=` attribute changes. Roles are static per element. (This is acceptable because roles are typically design-time fixed; if needed, it becomes a post-v1 feature.)
- **No aria-live / aria-atomic regions.** Announcement regions that fire when content changes are post-v1.
- **No aria-expanded descendants.** Do NOT automatically infer expanded state from hidden child counts — use only the explicit `state.expanded` flag.
- **No automatic name computation from child text.** Use `aria-label`, label slots, or element text content only — do NOT traverse children to synthesize a name.
- **No caching of tree snapshots.** The accessibility tree is live — screen readers query it directly each frame, not a cached snapshot.
- **No macOS or other platform support.** Windows and Linux only (INV-1.2).

## Acceptance criteria

1. `AccessRole` enum is defined with at least 25 semantic roles (text, button, checkbox, list, listitem, …).
2. `AccessState` packed struct holds seven boolean flags + one padding bit, fits in one u8.
3. `AccessNode` struct is defined with fields: role, name, description, state, value, value_min, value_max.
4. `Scene._access_nodes` is a parallel array allocated alongside other element arrays.
5. `Scene.instantiate()` allocates one `AccessNode` per element and sets default role based on kind.
6. The `role=` markup attribute (parsed in module 06) overrides the default role during instantiation.
7. The `aria-label=` attribute sets the AccessNode.name; if absent, the element's text content is used as name.
8. The `aria-description=` attribute sets the AccessNode.description.
9. `Scene.setAccessRole()`, `setAccessName()`, `setAccessDescription()`, `setAccessState()`, `setAccessValue()`, `setAccessValueRange()` all work and mark elements dirty.
10. When a button is focused, `AccessState.focused` is true. When a checkbox is checked, `AccessState.checked` is true, etc.
11. When an element is hidden via `setHidden()`, `AccessState.hidden` is true.
12. `Scene.reset()` clears the `_access_nodes` array.
13. Unit tests cover:
    - Default role mapping for each `WidgetKind`.
    - Markup attribute parsing (role=, aria-label=, aria-description=) during instantiation.
    - State synchronization (focused, checked, disabled, expanded, hidden) when widget state changes.
    - Name computation from element text when aria-label is absent.
    - Text arena ownership (names are allocated from the Scene arena, not stack-allocated).
14. No Zig compiler errors or warnings.
15. Module 06 (markup) has been extended to parse `role=`, `aria-label=`, and `aria-description=` attributes and store them in `NodeDesc` so module 07 can read them during instantiation (see RG4).

## Open questions

None. The accessibility tree is scoped: it is a passive data structure built from the element tree, with no automatic announcement or screen-reader integration. The bridges to the OS accessibility APIs (AT-SPI, UIA) are separate requirements (RG2, RG3).
