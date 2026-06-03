# R77 — M7-08: Accordion / collapsible

> Roadmap item: M7-08  
> Depends on: M2-01 (Signal — for open state), M4-01 (pseudo-state styling), M5-03 (conditional rendering / setHidden)  
> Read `00_constitution.md` before this file.

## Purpose

An `<Accordion>` element has a clickable header and a collapsible body. Clicking the header
toggles the body visible/hidden. Multiple accordions can coexist independently (no exclusive
open policy in v1). State is `open: bool` in `AccordionState` (parallel array). The body is
hidden via `Scene.setHidden` (M5-03), which sets `display = .none` so it occupies no layout
space when collapsed.

## What to build

### Widget kind

```zig
pub const WidgetKind = enum { /* ...existing... */ accordion };

// tagToKind: "Accordion" → .accordion
// defaultLayoutFor: .accordion → { .display = .block }
```

### `AccordionState`

```zig
pub const AccordionState = struct {
    open:     bool = false,  // starts collapsed
    hovered:  bool = false,
    disabled: bool = false,
};

pub const Scene = struct {
    _accordion_state: std.ArrayListUnmanaged(AccordionState) = .empty,

    pub fn accordionStateOf(self: *Scene, idx: u32) *AccordionState

    /// Toggle open/close. Shows/hides the body child. Marks dirty.
    pub fn toggleAccordion(self: *Scene, idx: u32) void

    pub fn isAccordionOpen(self: *Scene, idx: u32) bool
};
```

### Markup structure

```html
<Accordion>
    <Text slot="header" text="Section title" class="font-bold" />
    <Column slot="body" class="p-4 gap-2">
        <Text text="Body content line 1" />
        <Text text="Body content line 2" />
    </Column>
</Accordion>
```

The `slot="header"` and `slot="body"` attrs tell the instantiator which child is which.
During `instantiate`, the `<Accordion>` looks for exactly these two children:
- `slot="header"` child: rendered as the clickable trigger area.
- `slot="body"` child: initially hidden (via `setHidden`). Shown on open.

If the two slots are absent, the first child is treated as header and the second as body.

### `toggleAccordion`

```zig
pub fn toggleAccordion(self: *Scene, idx: u32) void {
    const state = self.accordionStateOf(idx);
    state.open = !state.open;

    // Find the body child and show/hide it.
    const body_idx = self.findAccordionBody(idx);
    if (body_idx) |bi| {
        self.setHidden(bi, !state.open);
    }
    self.elements.dirty.set(idx);
}
```

`findAccordionBody` scans the accordion's children for the one tagged with `slot="body"` (or
the second child if no slot attr is used).

### Visual rendering in `buildDrawList`

The header area gets a right-facing chevron `▶` (or `▼` when open) drawn as two thin rects
meeting at a point, positioned to the right of the header content:

```zig
// Chevron indicator (right side of header row):
const chevron_x = header_rect.x + header_rect.w - 20;
const chevron_y = header_rect.y + header_rect.h / 2;
if (state.open) {
    // Down-pointing: two rects forming ∨
    try emitChevronDown(cmds, alloc, chevron_x, chevron_y, tokens.text_muted, alpha);
} else {
    // Right-pointing: two rects forming >
    try emitChevronRight(cmds, alloc, chevron_x, chevron_y, tokens.text_muted, alpha);
}
```

Both `emitChevronDown` and `emitChevronRight` emit two `filled_rect` commands. They are
private helpers in `src/09/types.zig`.

A subtle bottom border on the header area acts as a visual divider:

```zig
try cmds.append(.{ .filled_rect = .{
    .rect  = { .x = header_rect.x, .y = header_rect.y + header_rect.h - 1,
               .w = header_rect.w, .h = 1 },
    .color = tokens.border_subtle,
}});
```

### Input handling in `App.run()`

Mouse click on the accordion's header area calls `toggleAccordion(idx)`. The hit test checks
whether the click is within the header child's computed rect (not the full accordion rect).

Keyboard: Space or Enter on a focused accordion calls `toggleAccordion`.

### Module location

```
src/07/types.zig   — WidgetKind.accordion, AccordionState, toggleAccordion, isAccordionOpen
src/09/types.zig   — chevron helpers, accordion branch in buildDrawList
src/app/app.zig    — accordion click + keyboard handling
docs/requirements/R77_accordion.md
```

## Non-goals (DO NOT implement — INV-5.4)

- **No exclusive accordion group** (only-one-open policy) — each accordion manages itself.
- **No animated height transition** — instant show/hide via `setHidden`.
- **No nested accordions** — untested in v1.
- **No custom open/close icons** — chevron only.
- **No `open="true"` markup attribute** — starts closed; post-v1 if needed.

## Acceptance criteria

1. `zig build test-07` passes. `<Accordion>` with header + body: after instantiate, body is
   hidden. `toggleAccordion` shows body; second toggle hides it.
2. Integration: click header, body slides into view (instant). Click again to collapse.
   Space key on focused accordion toggles. Chevron rotates. Checklist ticked.
