# R51 — M5-02: Missing Tailwind classes

> Roadmap item: M5-02  
> Depends on: module 06 (`resolveClasses` / `applyClass`), module 03 (`LayoutNode`)  
> Read `00_constitution.md` before this file.

## Purpose

Extend `resolveClasses` with the utility classes that are needed to build real layouts but
were deferred from the M0 Tailwind subset. No new types, no new structs — only additions to
the `applyClass` dispatch table and the corresponding `LayoutNode` / `ComputedStyle` fields
where they do not already exist.

## What to build

All changes live in `src/06/types.zig` `applyClass`, except where new `LayoutNode` fields
are needed (those go in `src/03/types.zig` and `docs/specs/03.types.zig`).

---

### Group A — Visibility

#### `hidden`

Sets `display = .none` on `LayoutNode`. A hidden element is removed from layout and
produces no draw commands.

Add `none` to the `Display` enum in [03.types.zig](../specs/03.types.zig):

```zig
pub const Display = enum { block, flex, grid, none };  // none is NEW
```

In `applyClass`:

```zig
} else if (std.mem.eql(u8, cls, "hidden")) {
    r.layout.display = .none;
```

The layout engine (`solve`) treats a node with `display = .none` as having `computed =
{0, 0, 0, 0}` and does not recurse into its children. The serializer emits zero draw
commands for it (existing `w == 0` guard already handles this).

---

### Group B — Overflow

#### `overflow-hidden`

Sets `overflow = .hidden` on `LayoutNode`. Already supported by `LayoutNode.overflow` (added
in M4-03). Only the class resolver entry is missing:

```zig
} else if (std.mem.eql(u8, cls, "overflow-hidden")) {
    r.layout.overflow = .hidden;
```

---

### Group C — Sizing constraints

#### `min-w-{n}`, `max-w-{n}`, `min-h-{n}`, `max-h-{n}`

Maps to `LayoutNode.min_size` / `max_size`. Uses the fixed `n*4` px scale (spacing rule
from module 06 spec). `n` is any non-negative integer.

Special aliases:
- `min-w-0` → `min_size.w = 0`
- `max-w-none` → `max_size.w = std.math.inf(f32)` (unbounded)
- `min-h-0` → `min_size.h = 0`
- `max-h-none` → `max_size.h = std.math.inf(f32)`

```zig
} else if (std.mem.startsWith(u8, cls, "min-w-")) {
    if (parseUint(cls[6..])) |n| r.layout.min_size.w = @as(f32, @floatFromInt(n)) * 4.0;
} else if (std.mem.startsWith(u8, cls, "max-w-")) {
    if (std.mem.eql(u8, cls[6..], "none")) {
        r.layout.max_size.w = std.math.inf(f32);
    } else if (parseUint(cls[6..])) |n| {
        r.layout.max_size.w = @as(f32, @floatFromInt(n)) * 4.0;
    }
} else if (std.mem.startsWith(u8, cls, "min-h-")) {
    if (parseUint(cls[6..])) |n| r.layout.min_size.h = @as(f32, @floatFromInt(n)) * 4.0;
} else if (std.mem.startsWith(u8, cls, "max-h-")) {
    if (std.mem.eql(u8, cls[6..], "none")) {
        r.layout.max_size.h = std.math.inf(f32);
    } else if (parseUint(cls[6..])) |n| {
        r.layout.max_size.h = @as(f32, @floatFromInt(n)) * 4.0;
    }
```

#### `w-{n}`, `h-{n}` (fixed pixel sizes)

Maps to `LayoutNode.width` / `height` as `.px` dimensions. The existing `w-full` / `h-full`
cases use `.percent`; the numeric variants use `.px`:

```zig
} else if (std.mem.startsWith(u8, cls, "w-")) {
    if (std.mem.eql(u8, cls[2..], "full")) {
        r.layout.width = .{ .percent = 100 };
    } else if (std.mem.eql(u8, cls[2..], "auto")) {
        r.layout.width = .auto;
    } else if (parseUint(cls[2..])) |n| {
        r.layout.width = .{ .px = @as(f32, @floatFromInt(n)) * 4.0 };
    }
} else if (std.mem.startsWith(u8, cls, "h-")) {
    if (std.mem.eql(u8, cls[2..], "full")) {
        r.layout.height = .{ .percent = 100 };
    } else if (std.mem.eql(u8, cls[2..], "auto")) {
        r.layout.height = .auto;
    } else if (parseUint(cls[2..])) |n| {
        r.layout.height = .{ .px = @as(f32, @floatFromInt(n)) * 4.0 };
    }
```

(The existing `w-full` / `h-full` cases in the current `applyClass` are absorbed into these
new `startsWith` branches; remove the old `eql` entries to avoid duplicate handling.)

---

### Group D — Margin / horizontal centering

#### `mx-auto`

Centers an element horizontally by setting `margin.left = margin.right = auto`. Requires
`auto` as a margin value. Add to `LayoutNode`:

```zig
pub const Margin = struct {
    top:    MarginValue = .zero,
    right:  MarginValue = .zero,
    bottom: MarginValue = .zero,
    left:   MarginValue = .zero,
};

pub const MarginValue = union(enum) {
    zero,         // 0 px
    px: f32,      // fixed pixel amount
    auto,         // fill remaining space (used for centering)
};
```

**Note:** `LayoutNode` already has `margin: Insets`, which uses a flat `f32`. The `mx-auto`
feature requires `auto` margins, which `Insets` cannot represent. **Replace `margin: Insets`
with `margin: Margin` in `LayoutNode`** (a backward-compatible struct change since `Insets`
defaults are all zero, matching `MarginValue.zero`). This also requires the layout engine
(module 04) to interpret `MarginValue.auto` on the main and cross axes.

In `applyClass`:

```zig
} else if (std.mem.eql(u8, cls, "mx-auto")) {
    r.layout.margin.left  = .auto;
    r.layout.margin.right = .auto;
```

Layout engine changes for `mx-auto`: in block layout, after computing the child width,
distribute equal halves of remaining horizontal space to `auto` left/right margins. This is
a targeted addition to `solveBlock` in module 04. No changes to flex layout (flex uses
`justify-content`/`align-items` for centering, not margins).

#### `m-{n}`, `mx-{n}`, `my-{n}`, `mt-{n}`, `mr-{n}`, `mb-{n}`, `ml-{n}`

Fixed pixel margins using the `n*4` scale:

```zig
} else if (std.mem.startsWith(u8, cls, "m-")) {
    if (parseUint(cls[2..])) |n| {
        const v = @as(f32, @floatFromInt(n)) * 4.0;
        r.layout.margin = .{ .top = .{ .px = v }, .right = .{ .px = v },
                              .bottom = .{ .px = v }, .left = .{ .px = v } };
    }
// ... mx-, my-, mt-, mr-, mb-, ml- follow the same pattern as padding
```

---

### Group E — Flex modifiers

#### `shrink-0`, `grow-0`

Disable default flex shrinking / growing:

```zig
} else if (std.mem.eql(u8, cls, "shrink-0")) {
    r.layout.flex_shrink = 0;
} else if (std.mem.eql(u8, cls, "grow-0")) {
    r.layout.flex_grow = 0;
} else if (std.mem.eql(u8, cls, "grow")) {
    r.layout.flex_grow = 1;
} else if (std.mem.eql(u8, cls, "shrink")) {
    r.layout.flex_shrink = 1;
```

#### `self-start`, `self-center`, `self-end`, `self-stretch`, `self-auto`

Per-element `align-self` override. Requires a new field on `LayoutNode`:

```zig
pub const AlignSelf = enum { auto, start, center, end, stretch };

pub const LayoutNode = struct {
    // ...existing fields...
    align_self: AlignSelf = .auto,  // NEW: overrides parent's align_items for this child
};
```

In `applyClass`:

```zig
} else if (std.mem.eql(u8, cls, "self-auto"))    { r.layout.align_self = .auto;    }
} else if (std.mem.eql(u8, cls, "self-start"))   { r.layout.align_self = .start;   }
} else if (std.mem.eql(u8, cls, "self-center"))  { r.layout.align_self = .center;  }
} else if (std.mem.eql(u8, cls, "self-end"))     { r.layout.align_self = .end;     }
} else if (std.mem.eql(u8, cls, "self-stretch")) { r.layout.align_self = .stretch; }
```

The flex layout engine (module 04) must respect `align_self` when it is not `.auto`: use
the child's `align_self` in place of the parent's `align_items` for that child's cross-axis
placement.

---

### Group F — Grid span

#### `col-span-{n}`, `row-span-{n}`

Already modeled as `col_span: u16` / `row_span: u16` on `LayoutNode`. Only the class
resolver entries are missing:

```zig
} else if (std.mem.startsWith(u8, cls, "col-span-")) {
    if (parseUint(cls[9..])) |n| r.layout.col_span = @intCast(@min(n, 12));
} else if (std.mem.startsWith(u8, cls, "row-span-")) {
    if (parseUint(cls[9..])) |n| r.layout.row_span = @intCast(@min(n, 12));
```

---

### Group G — M4 style classes (added by M4-05, M4-06, M4-07)

These three families were specified in their respective M4 requirements but their resolver
entries are consolidated here for bookkeeping:

- `truncate` → `style.truncate = true` (M4-05)
- `opacity-{0|25|50|75|100}` → `style.opacity = {0.0|0.25|0.5|0.75|1.0}` (M4-06)
- `shadow-{sm|md|lg|xl|none}` → shadow fields (M4-07)

If these entries were already added when their respective M4 items shipped, this group is
a no-op. If not, add them here.

---

### Summary of `LayoutNode` changes

New fields:

```zig
pub const Display = enum { block, flex, grid, none };   // none added
pub const AlignSelf = enum { auto, start, center, end, stretch };  // new type
pub const MarginValue = union(enum) { zero, px: f32, auto };       // new type
pub const Margin = struct { top, right, bottom, left: MarginValue = .zero }; // new type

pub const LayoutNode = struct {
    // ...existing fields, with:
    align_self: AlignSelf = .auto,   // NEW
    margin: Margin = .{},            // CHANGED from Insets to Margin
};
```

### Summary of layout engine changes (module 04)

1. **`display = .none`**: in `solveNode`, if `node.display == .none`, set
   `computed = .{}` (zero rect) and return immediately without recursing into children.
2. **`mx-auto` block centering**: in `solveBlock`, after computing child width, check if
   `child.margin.left == .auto and child.margin.right == .auto`; if so, offset the child's
   x by `(container_content_w - child_w) / 2`.
3. **`align_self`**: in `solveFlex`, for each child, use `child.align_self` instead of the
   parent's `align_items` when `child.align_self != .auto`.
4. **Fixed pixel margins** (`MarginValue.px`): in both block and flex layout, subtract
   margin from available space before placing children, add margin offsets to child position.

### Module location

```
src/03/types.zig          — Display.none, AlignSelf, MarginValue, Margin, LayoutNode changes
docs/specs/03.types.zig   — same (contract update)
src/04/types.zig          — layout engine changes for none/mx-auto/align_self/margins
src/06/types.zig          — applyClass additions for all groups A–G
docs/requirements/R51_missing_tailwind_classes.md
```

## Public API

Changes to module 03 contract:

```zig
pub const Display = enum { block, flex, grid, none }  // .none added
pub const AlignSelf = enum { auto, start, center, end, stretch }  // new
pub const MarginValue = union(enum) { zero, px: f32, auto }       // new
pub const Margin = struct { top, right, bottom, left: MarginValue }  // new
// LayoutNode gains: align_self: AlignSelf = .auto
// LayoutNode changes: margin: Insets → margin: Margin
```

## Non-goals (DO NOT implement — INV-5.4)

- **No responsive prefixes** (`md:`, `lg:`) — no breakpoint system; INV-4.2.
- **No arbitrary values** (`w-[123px]`) — only the `n*4` scale.
- **No `flex-wrap`** — single-line flex only for v1.
- **No `grid-rows-{n}`** (template rows) — only column templates; rows derive from content.
  `grid_template_rows` field exists but was not filled by the class resolver; leave it empty
  for now.
- **No `place-*` shorthands** (`place-items`, `place-content`, `place-self`) — too many
  combinations; the individual properties cover the common cases.
- **No negative margins** — `margin.px` is non-negative only; negative values are ignored.
- **No `basis-{n}`** — flex-basis is set only by `flex-1` in v1; a separate `basis-{n}`
  class is post-v1.
- **No `gap-x-{n}` / `gap-y-{n}`** — column and row gaps independently are post-v1; the
  existing `gap-{n}` sets both axes equally.

## Acceptance criteria

1. `zig build test-06` passes. New class resolver tests:
   - `"hidden"` → `layout.display = .none`.
   - `"overflow-hidden"` → `layout.overflow = .hidden`.
   - `"w-12"` → `layout.width = .{ .px = 48 }`.
   - `"h-auto"` → `layout.height = .auto`.
   - `"min-w-4"` → `layout.min_size.w = 16`.
   - `"max-w-none"` → `layout.max_size.w = inf`.
   - `"mx-auto"` → `layout.margin.left = .auto`, `layout.margin.right = .auto`.
   - `"m-2"` → all four margin sides = `{ .px = 8 }`.
   - `"shrink-0"` → `layout.flex_shrink = 0`.
   - `"self-center"` → `layout.align_self = .center`.
   - `"col-span-3"` → `layout.col_span = 3`.
   - `"row-span-2"` → `layout.row_span = 2`.

2. `zig build test-04` passes. New layout engine tests:
   - A node with `display = .none` has `computed = {0, 0, 0, 0}` after `solve`.
   - `mx-auto` on a block child centers it horizontally within its parent's content width.
   - `self-center` on a flex child overrides the parent's `align_items = .start` for that
     child only.
   - A fixed pixel margin shifts the child's position correctly.

3. `zig build test-07` (scene instantiation) passes — no regressions from `LayoutNode`
   struct changes (old `margin: Insets` zero values migrate to `Margin{}` zero defaults).

4. Checklist fully ticked.

## Open questions

One: replacing `margin: Insets` with `margin: Margin` in `LayoutNode` is a breaking change
to existing field access patterns (any code that does `node.margin.top = 4` will need
updating to `node.margin.top = .{ .px = 4 }`). Survey all existing references to
`LayoutNode.margin` in `src/` before implementing; the count should be small (mostly module
04 internals). Surface conflicts to the human before landing.
