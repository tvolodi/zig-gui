# R7A — M7-11: Separator / divider

> Roadmap item: M7-11  
> Depends on: module 09 (renderer — `buildDrawList`, `FilledRect`)  
> Read `00_constitution.md` before this file.

## Purpose

A `<Separator>` widget renders a single 1 px horizontal or vertical line drawn from
`tokens.border_default`. It has no state, no interaction, and no children. It is the
simplest new widget kind: one new tag, one layout default, and one `filled_rect` command in
the serializer.

## What to build

### Widget kind

Add to [07.types.zig](../specs/07.types.zig):

```zig
pub const WidgetKind = enum {
    // ...existing kinds...
    separator,  // NEW
};

pub fn tagToKind(tag: []const u8) ?WidgetKind {
    // ...
    if (eql(u8, tag, "Separator")) return .separator;
    return null;
}

pub fn defaultLayoutFor(kind: WidgetKind) LayoutNode {
    return switch (kind) {
        // ...
        .separator => .{ .display = .block, .width = .{ .percent = 100 }, .height = .{ .px = 1 } },
        else => .{ .display = .block },
    };
}
```

For a vertical separator, the author overrides height/width via Tailwind classes
(e.g. `class="w-px h-full"`).

### Default style

`defaultStyleFor(.separator, tokens)` returns:

```zig
ComputedStyle{
    .background   = tokens.border_default,
    .border_width = 0,
    .radius       = 0,
}
```

The line is painted as a `filled_rect` with the element's layout rect (typically 100 % wide
× 1 px tall). Inline style `style:background` overrides the color per the R50 mechanism.

### Serializer

In `buildDrawList`, the separator is drawn as a standard background `filled_rect`. No special
case is needed — the existing "emit background if `a > 0`" path handles it. No glyph, no
border, no text.

### Markup usage

```html
<!-- Horizontal rule between sections -->
<Column class="gap-4">
    <Text text="Section A" />
    <Separator />
    <Text text="Section B" />
</Column>

<!-- Vertical separator inside a flex row -->
<Row class="gap-4 items-stretch">
    <Text text="Left" />
    <Separator class="w-px h-full" />
    <Text text="Right" />
</Row>
```

### Behavioral contract

| Situation | Behavior |
|---|---|
| Default separator | 100 % width × 1 px height; `border_default` color |
| `class="w-px h-full"` | 1 px wide × 100 % height (vertical) |
| `style:background="#FF0000"` | Red separator (inline style override) |
| No children, no interaction | Zero-cost element; no state arrays allocated |

### Module location

```
src/07/types.zig          — WidgetKind.separator, tagToKind, defaultLayoutFor, defaultStyleFor
docs/specs/07.types.zig   — same
docs/requirements/R7A_separator.md
```

No changes to `app.zig` (no input handling), `buildDrawList` (uses existing background path),
or any state arrays.

## Public API

```zig
// WidgetKind gains: .separator
// tagToKind: "Separator" → .separator
// defaultLayoutFor: .separator → { .display = .block, .width = percent 100, .height = px 1 }
// defaultStyleFor: .separator → background = tokens.border_default
```

## Non-goals (DO NOT implement — INV-5.4)

- **No decorative styles** (dashed, dotted) — solid filled rect only.
- **No text label in separator** — plain line only; a labeled separator is two text elements
  plus two separators arranged in a flex row.
- **No gradient separator** — flat color only.
- **No `hr` role / accessibility** — INV-1.4.

## Acceptance criteria

1. `zig build test-07` passes. New test: `<Separator/>` instantiates with `WidgetKind.separator`;
   `defaultLayoutFor(.separator).width == .{ .percent = 100 }`; `defaultLayoutFor(.separator).height == .{ .px = 1 }`.

2. `zig build test-09-unit` passes. New test: `buildDrawList` on a scene with one separator element
   emits exactly one `filled_rect` command with `color == tokens.border_default`.

3. Integration: a `<Column>` with two text elements and a `<Separator>` between them renders
   a 1 px horizontal line.

4. Checklist fully ticked.
