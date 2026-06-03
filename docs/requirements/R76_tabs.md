# R76 — M7-07: Tabs

> Roadmap item: M7-07  
> Depends on: M2-01 (Signal — for active tab state), M4-01 (pseudo-state styling)  
> Read `00_constitution.md` before this file.

## Purpose

A `<Tabs>` container manages a row of tab buttons and a single visible content panel. The
active tab index is stored in `TabsState` (parallel array). Switching tabs marks the
container and affected panel elements dirty. Content panels use the `if=` conditional
rendering (M5-03) or the `hidden` mechanism directly.

## What to build

### Widget kind

```zig
pub const WidgetKind = enum { /* ...existing... */ tabs, tab_item };

// tagToKind: "Tabs" → .tabs, "TabItem" → .tab_item
// defaultLayoutFor: .tabs → flex column
// defaultLayoutFor: .tab_item → flex row (for label + optional icon)
```

### `TabsState`

```zig
pub const TabsState = struct {
    active_idx:  u32 = 0,   // index among tab_item children
    tab_count:   u32 = 0,   // set during instantiate
};

pub const Scene = struct {
    _tabs_state: std.ArrayListUnmanaged(TabsState) = .empty,

    pub fn tabsStateOf(self: *Scene, idx: u32) *TabsState

    /// Switch to tab `tab_idx` within the `<Tabs>` container at `container_idx`.
    /// Marks all tab_item children and the container dirty.
    /// Hides non-active panels via setHidden (M5-03).
    pub fn selectTab(self: *Scene, container_idx: u32, tab_idx: u32) void
};
```

### Markup structure

```html
<Tabs>
    <TabItem label="Profile">
        <Text text="Profile content" />
    </TabItem>
    <TabItem label="Settings">
        <Text text="Settings content" />
    </TabItem>
</Tabs>
```

During `instantiate`, the `<Tabs>` element:

1. Iterates its `<TabItem>` children.
2. Creates a horizontal tab bar (a `<Row>` child) containing one `<Button>` per `<TabItem>`
   label — these are auto-generated during instantiation.
3. Sets `TabsState.tab_count` to the number of `<TabItem>` children.
4. Hides all `<TabItem>` panels except index 0.

The tab bar buttons are auto-generated internal elements. They fire `selectTab` via callbacks
(using the `CallbackFn` mechanism from R31).

### Tab button visual

Active tab button: `background = tokens.bg_raised`, `border_bottom_width = 2` (bottom
border only — handled as a positioned `filled_rect` at the bottom of the button rect since
`ComputedStyle` has no per-side border in v1), `text_color = tokens.text_body`.

Inactive tab button: `background = transparent`, `text_color = tokens.text_muted`.

Bottom border for the active tab: emit an extra `filled_rect` at
`{ x: btn.x, y: btn.y + btn.h - 2, w: btn.w, h: 2, color: tokens.accent }`.

### Input handling

Tab buttons use the existing button click mechanism (R31 `CallbackFn`). The callback calls
`selectTab(tabs_idx, i)`. Keyboard navigation of tabs: Left/Right arrows move between tab
button focuses; selecting a tab with Enter/Space calls `selectTab`.

### `selectTab` implementation

```zig
pub fn selectTab(self: *Scene, container_idx: u32, tab_idx: u32) void {
    const ts = self.tabsStateOf(container_idx);
    if (ts.active_idx == tab_idx) return;
    ts.active_idx = tab_idx;

    // Show/hide panels: iterate tab_item children, hide all but active.
    var child = self.elements.first_child.items[container_idx];
    var item_i: u32 = 0;
    while (child != NONE) : (child = self.elements.next_sibling.items[child]) {
        if (self._kind.items[child] != .tab_item) continue;
        self.setHidden(child, item_i != tab_idx);
        item_i += 1;
    }
    self.elements.dirty.set(container_idx);
}
```

### Module location

```
src/07/types.zig   — WidgetKind.tabs/.tab_item, TabsState, tabsStateOf, selectTab
src/09/types.zig   — active tab bottom-border rect in buildDrawList
src/app/app.zig    — tab button callbacks call selectTab
docs/requirements/R76_tabs.md
```

## Non-goals (DO NOT implement — INV-5.4)

- **No vertical tabs** — horizontal tab bar only.
- **No closeable tabs** — fixed tab set; no × button per tab.
- **No scrollable tab bar** — all tabs visible; overflow is clipped.
- **No animated panel transitions** — instant panel swap.
- **No tab addition/removal at runtime** — tab set is fixed after instantiate.

## Acceptance criteria

1. `zig build test-07` passes. `<Tabs>` with two `<TabItem>` children: after instantiate,
   first panel is visible, second hidden. `selectTab(0, 1)` hides first, shows second.
2. Integration: click tab buttons, panels swap. Active tab has accent bottom border.
   Keyboard: Tab to tab button, Left/Right to navigate. Checklist ticked.
