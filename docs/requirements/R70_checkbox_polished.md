# R70 — M7-01: Checkbox (polished, with label slot)

> Roadmap item: M7-01  
> Depends on: M3-05 (R34 — checkbox widget, `CheckboxState`), M4-01 (pseudo-state styling)  
> Read `00_constitution.md` before this file.

## Purpose

Upgrade the M3-05 checkbox from a bare widget state to a fully polished component with a
label slot, a custom checkmark drawn in the serializer, and token-driven sizing. The
`WidgetKind.checkbox` and `CheckboxState` from R34 are the foundation; this item adds the
visual polish layer and the label composition pattern.

## What to build

### Checkmark draw command

The checkmark is drawn as two `filled_rect` commands forming an "L + upward tick" shape —
no image required, no new command types:

```
┌──────┐
│  ✓   │
└──────┘
```

Specifically: two thin rects meeting at a bottom-left vertex at a roughly 45 ° angle. The
exact pixel geometry for a box of side `S` px:

```
// Vertical stroke of the tick (left leg):
tick_v = FilledRect{
    .rect  = { .x = box.x + S*0.25, .y = box.y + S*0.45,
               .w = S*0.15,          .h = S*0.45 },
    .color = tokens.accent_text,  // white on accent background
}
// Horizontal stroke (right leg, going up-right):
tick_h = FilledRect{
    .rect  = { .x = box.x + S*0.25, .y = box.y + S*0.45,
               .w = S*0.55,          .h = S*0.15 },
    .color = tokens.accent_text,
}
```

This is computed in `buildDrawList` for elements with `WidgetKind.checkbox` and
`checkboxStateOf(idx).checked == true`. All coordinates derive from the element's
`computed` rect; no hardcoded pixel sizes.

### Box sizing token

Add `checkbox_size` to `Tokens` in [05.types.zig](../specs/05.types.zig):

```zig
pub const Tokens = struct {
    // ...existing fields...
    checkbox_size: f32,  // NEW — side length of the checkbox square, e.g. 18 px
};
```

Set in `Tokens.light` and `Tokens.dark`:

```zig
.checkbox_size = 18,
```

`defaultLayoutFor(.checkbox)` uses this:

```zig
.checkbox => .{ .display = .flex, .direction = .row, .align_items = .center,
                .gap = 8,
                .width = .auto, .height = .auto },
```

Wait — `defaultLayoutFor` cannot read `Tokens` (it takes no `tokens` argument). Instead,
the checkbox uses `.display = .block` for the overall element with a fixed 18 px minimum
size, and the visual box is a sub-rect within the computed rect:

```zig
.checkbox => .{
    .display  = .flex,
    .direction = .row,
    .align_items = .center,
},
```

The checkbox element's `measured` size (set in `measurePass`) is `{ S + gap + label_w, S }`
where `S = style.font_size` (reused as the box side length — same scale as text). This
avoids adding a new token field.

**Revised decision:** use `style.font_size` as the box side length. This makes the checkbox
naturally scale with `text-sm` / `text-base` / `text-lg` at no extra cost. Default is
`tokens.text_base` (14 px).

### Label slot

The `<Checkbox>` element contains an optional `label` attribute (plain string):

```html
<Checkbox label="Enable notifications" />
<Checkbox class="text-sm" label="I agree to the terms" />
```

During `Scene.instantiate`, if the `label` attr is present, a child `<Text>` element is
automatically created and appended as a child of the checkbox element, using the label string
as its text. The layout (flex row, centered, gap 8) positions the box to the left and the
label to the right.

```zig
// In Scene.instantiate for .checkbox:
for (desc.attrs) |attr| {
    if (!std.mem.eql(u8, attr.name, "label")) continue;
    switch (attr.value) {
        .literal => |s| {
            var label_desc = NodeDesc{
                .tag   = "Text",
                .attrs = &.{ .{ .name = "text", .value = .{ .literal = s } } },
            };
            _ = try scene.instantiateUnder(checkbox_id, label_desc, tokens);
        },
        .bind => |path| {
            var label_desc = NodeDesc{
                .tag   = "Text",
                .attrs = &.{ .{ .name = "text", .value = .{ .bind = path } } },
            };
            _ = try scene.instantiateUnder(checkbox_id, label_desc, tokens);
        },
    }
    break;
}
```

### `buildDrawList` for checkbox

For each `checkbox` element in the DFS walk:

1. Emit the outer background (the theme `bg_surface` rect — base style).
2. Emit a border rect (1 px `border_default`).
3. If `checked`, emit the two-piece checkmark (using `accent` background, `accent_text`
   tick color).
4. Pseudo-state styling from M4-01 applies to the box's background/border as normal.
5. Children (the label text) are visited by the normal DFS walk.

```zig
// In buildDrawList, special case for .checkbox:
const S = effective_style.font_size;  // box side length
const box_rect = Rect{
    .x = layout_rect.x, .y = layout_rect.y + (layout_rect.h - S) / 2,
    .w = S, .h = S,
};
// Box background (accent when checked, surface when not)
const box_bg = if (state.checked) tokens.accent else effective_style.background;
try cmds.append(.{ .filled_rect = .{ .rect = box_rect, .color = box_bg } });
// Box border
try cmds.append(.{ .border_rect = .{ .rect = box_rect, .color = effective_style.border_color,
                                      .width = 1 } });
// Checkmark
if (state.checked) {
    try emitCheckmark(cmds, alloc, box_rect, tokens.accent_text, current_alpha);
}
```

`emitCheckmark` is a private helper in `src/09/types.zig`.

### Pseudo-state overrides for checkbox

R40 already defines `checkboxPseudo(tokens)` returning hover/focus/active/disabled overrides.
No changes needed here; M7-01 simply confirms they are correctly applied.

### Behavioral contract

| State | Box background | Border | Checkmark |
|---|---|---|---|
| Unchecked, default | `bg_surface` | `border_default` | None |
| Checked, default | `accent` | `accent` | White tick |
| Hovered (unchecked) | `bg_surface` + hover tint | `border_strong` | None |
| Focused | `border_default` → focus border | Focus ring border | — |
| Disabled | `bg_canvas` | `border_subtle` | Muted tick if checked |

### Module location

```
src/05/types.zig          — no change (uses font_size for box side)
src/07/types.zig          — defaultLayoutFor(.checkbox) → flex row; instantiate label auto-child
src/09/types.zig          — emitCheckmark helper, checkbox branch in buildDrawList
docs/requirements/R70_checkbox_polished.md
```

## Non-goals (DO NOT implement — INV-5.4)

- **No indeterminate state** — checked / unchecked only (R34 non-goal preserved).
- **No custom checkmark SVG** — two-rect approximation only.
- **No `label` wrapping** — single line; `truncate` class applies if text overflows.
- **No label-click activation** — only the checkbox box itself is the click target.

## Acceptance criteria

1. `zig build test-07` passes. New tests: `<Checkbox label="Agree"/>` instantiates with two
   elements (the checkbox + a child text). `<Checkbox/>` (no label) instantiates with one.

2. `zig build test-09-unit` passes. `buildDrawList` on a checked checkbox emits the box
   background, border, and exactly 2 `filled_rect` checkmark commands. On unchecked, emits
   box background and border only.

3. Integration: a checkbox labeled "Enable" renders correctly. Click toggles the checkmark.
   Tab focuses it; Space toggles. Disabled checkbox is visually grayed. Checklist ticked.
