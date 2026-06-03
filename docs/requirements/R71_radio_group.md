# R71 — M7-02: Radio group

> Roadmap item: M7-02  
> Depends on: M3-01 (focus model), M4-01 (pseudo-state styling), R70 (checkbox polished — visual pattern)  
> Read `00_constitution.md` before this file.

## Purpose

A radio group presents a set of mutually exclusive options. Exactly one option is selected at
all times. Each option is a `<Radio>` element (new `WidgetKind`). The group is formed by
sharing a `group_id: u16` across sibling `<Radio>` elements; selecting one deselects all
others in the same group. State is stored in parallel arrays in `Scene` (INV-3.1).

## What to build

### Widget kind

Add to [07.types.zig](../specs/07.types.zig):

```zig
pub const WidgetKind = enum {
    // ...existing...
    radio,  // NEW
};
pub fn tagToKind(tag: []const u8) ?WidgetKind {
    if (eql(u8, tag, "Radio")) return .radio;
    return null;
}
pub fn defaultLayoutFor(kind: WidgetKind) LayoutNode {
    return switch (kind) {
        .radio => .{ .display = .flex, .direction = .row, .align_items = .center },
        else => .{ .display = .block },
    };
}
```

### `RadioState` — parallel array in `Scene`

```zig
pub const RadioState = struct {
    group_id:  u16  = 0,     // all radios with the same group_id are mutually exclusive
    selected:  bool = false,
    disabled:  bool = false,
    hovered:   bool = false,
    pressed:   bool = false,
};

pub const Scene = struct {
    _radio_state: std.ArrayListUnmanaged(RadioState) = .empty,

    pub fn radioStateOf(self: *Scene, idx: u32) *RadioState

    /// Select `idx` and deselect all other radios with the same `group_id`.
    /// Marks all affected elements dirty.
    pub fn selectRadio(self: *Scene, idx: u32) void

    pub fn isRadioSelected(self: *Scene, idx: u32) bool
};
```

### Group management in `selectRadio`

```zig
pub fn selectRadio(self: *Scene, idx: u32) void {
    const gid = self.radioStateOf(idx).group_id;
    // Deselect all radios in the same group.
    var i: u32 = 0;
    while (i < self.elements.layout.items.len) : (i += 1) {
        if (self._kind.items[i] != .radio) continue;
        const rs = &self._radio_state.items[i];
        if (rs.group_id != gid) continue;
        const was = rs.selected;
        rs.selected = (i == idx);
        if (was != rs.selected) self.elements.dirty.set(i);
    }
}
```

This is O(elements) per selection. For the element counts in this framework (< 500), this is
negligible. No group registry; the scan is the simplest correct approach.

### Markup and `group_id` attribute

```html
<Column class="gap-2">
    <Radio group="payment" value="card" label="Credit card" />
    <Radio group="payment" value="bank" label="Bank transfer" />
    <Radio group="payment" value="cash" label="Cash" />
</Column>
```

The `group` attribute is a string name. During `instantiate`, a `group_name → u16` hash map
converts it to a numeric `group_id`. The map is ephemeral (lives in an arena during
instantiate) — only the numeric `group_id` is stored in `RadioState`.

`value` attribute stores a string literal in `RadioState.value_str`:

```zig
pub const RadioState = struct {
    group_id:   u16          = 0,
    value_str:  []const u8   = "",  // literal from the `value` attr; scene-arena-owned
    selected:   bool         = false,
    disabled:   bool         = false,
    hovered:    bool         = false,
    pressed:    bool         = false,
};
```

### Input handling in `App.run()`

Mouse click: same pattern as button/checkbox — hover detection, press on click, select on
release while hovered. Only non-disabled radios respond.

Keyboard (focused radio): Space or Enter → `selectRadio(focused_idx)`.

Arrow keys (Left/Right or Up/Down) navigate within the group:

```zig
// Find the previous/next radio with the same group_id in element order:
Key.right, Key.down => scene.selectNextInGroup(focused_idx),
Key.left,  Key.up   => scene.selectPrevInGroup(focused_idx),
```

`selectNextInGroup` / `selectPrevInGroup` scan the element array for the next/previous
`radio` with the same `group_id`, wrap around, and call `selectRadio` + `setFocus`.

### Visual rendering in `buildDrawList`

A radio button is a circle (approximated by a high-`radius` `filled_rect` with
`radius = S/2`):

```zig
// Outer ring (border):
try cmds.append(.{ .filled_rect = .{
    .rect   = circle_rect,
    .color  = effective_style.border_color,
    .radius = S / 2,
}});
// Inner fill (smaller circle):
const inner_rect = shrink(circle_rect, 2);  // 2 px inset
try cmds.append(.{ .filled_rect = .{
    .rect   = inner_rect,
    .color  = effective_style.background,
    .radius = (S - 4) / 2,
}});
// Dot (if selected):
if (state.selected) {
    const dot_rect = shrink(circle_rect, S * 0.3);
    try cmds.append(.{ .filled_rect = .{
        .rect   = dot_rect,
        .color  = tokens.accent,
        .radius = dot_rect.w / 2,
    }});
}
```

`shrink(rect, px)` returns `rect` inset by `px` on all sides.

### Label auto-child

Same pattern as R70 checkbox: if the `label` attr is present, instantiate a child `<Text>`
element.

### Module location

```
src/07/types.zig   — WidgetKind.radio, RadioState, selectRadio, selectNextInGroup, selectPrevInGroup
src/09/types.zig   — radio rendering in buildDrawList
src/app/app.zig    — radio input handling (click + keyboard)
docs/requirements/R71_radio_group.md
```

## Non-goals (DO NOT implement — INV-5.4)

- **No `RadioGroup` container widget** — grouping is by shared `group_id`; no wrapper.
- **No programmatic "get selected value" convenience** — use `radioStateOf(idx).value_str`
  for each radio in the group.
- **No radio-change callbacks** — INV-3.3; use signals.
- **No keyboard focus auto-advance on selection** — focus stays where it is; arrow keys both
  advance focus and select.

## Acceptance criteria

1. `zig build test-07` passes: three `<Radio group="g">` elements instantiated; `selectRadio`
   on one deselects the others; `selectNextInGroup` wraps correctly.
2. Integration: Tab to a radio, Space selects it. Arrow keys navigate the group. Only one is
   selected at a time. Label renders to the right. Checklist ticked.
