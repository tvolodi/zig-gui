# RC0 — M12-01: Absolute positioning

> Roadmap item: M12-01  
> Depends on: 04 (layout engine)  
> Read `00_constitution.md` before this file.

## Purpose

Add `position: absolute` support to the layout engine. An absolutely-positioned element is
removed from its parent's flex/grid flow and is placed at an explicit `(x, y)` offset relative
to its nearest positioned ancestor (an ancestor with `position != .static`). If no positioned
ancestor exists, the offset is relative to the root element.

This is the foundational positioning mode needed for overlay panels, floating toolbars, and
popups that don't live in the overlay layer.

## What to build

### `Position` enum and new fields in `LayoutNode` (module 03)

Add to `docs/specs/03.types.zig` and `src/03/types.zig` (the `LayoutNode` struct — no new types needed):

```zig
pub const Position = enum { static, absolute };

pub const LayoutNode = struct {
    // ... existing fields unchanged ...

    // M12 RC0 — positioning
    position: Position = .static,
    /// Offset from nearest positioned ancestor when position == .absolute.
    /// .auto means "not set" — the element is placed at its natural position
    /// (useful for setting only one axis).
    inset_top:    Dimension = .auto,
    inset_right:  Dimension = .auto,
    inset_bottom: Dimension = .auto,
    inset_left:   Dimension = .auto,
};
```

`inset_*` mirrors CSS `top`/`right`/`bottom`/`left`. Only `px` and `auto` values are
supported in v1 (`percent` is a non-goal — see below).

### Layout engine changes (module 04)

In `src/04/types.zig`, the `solve` function must:

1. **Skip absolutely-positioned children during normal flow.** When iterating a flex or block
   container's children, skip any child whose `layout.position == .absolute`. They do NOT
   consume main-axis space and do NOT affect parent sizing.

2. **Collect and place absolutely-positioned children in a second pass.** After normal flow
   is placed, iterate children again looking for `position == .absolute` nodes. For each:
   a. Find the **containing block** — the nearest ancestor with `position == .absolute`
      (or the root if none). The containing block's `computed` rect is already resolved
      at this point because it was placed in normal flow.
   b. Resolve `inset_left`/`inset_right`/`inset_top`/`inset_bottom`:
      - `.auto` → use 0 (unset; element positioned at containing block's top-left by default).
      - `.px(v)` → that many pixels from the respective edge of the containing block.
   c. Resolve `width`/`height`:
      - If `width` is `.auto` and both `inset_left` and `inset_right` are non-auto px:
        `w = containing_block.w - inset_left - inset_right`.
      - If `width` is `.auto` and only one horizontal inset is set: use `measured.w` if
        available, else 0.
      - If `width` is `.px(v)`: use `v`.
      - Same logic for height.
   d. Set `computed.x = containing_block.x + inset_left_px`.
      Set `computed.y = containing_block.y + inset_top_px`.
      Set `computed.w` and `computed.h` per step (c).
   e. Recurse into the child's own layout (it may have flex children).

3. **Containing block lookup is depth-first, upward.** The solver already processes
   elements in tree order; by the time a child's absolute placement is computed, the
   ancestor chain is already placed.

### Tailwind class resolver changes (module 06)

Add new class patterns to `src/06/types.zig` (the `resolveClasses` function or equivalent):

| Class | Effect on LayoutNode |
|---|---|
| `absolute` | `position = .absolute` |
| `static` | `position = .static` (explicit reset) |
| `inset-0` | all four insets → `.px(0)` |
| `inset-{n}` (n = 0,1,2,3,4,5,6,8,10,12,16,20,24,32,40,48,64) | all four insets → `.px(n * 4)` |
| `top-0` / `top-{n}` | `inset_top = .px(n * 4)` |
| `right-0` / `right-{n}` | `inset_right = .px(n * 4)` |
| `bottom-0` / `bottom-{n}` | `inset_bottom = .px(n * 4)` |
| `left-0` / `left-{n}` | `inset_left = .px(n * 4)` |

Same `n` set as the existing `p-{n}`/`m-{n}` spacing scale (0, 1, 2, 3, 4, 5, 6, 8, 10, 12, 16, 20, 24, 32, 40, 48, 64).

### Demo app coverage

Add a screen to the Showcase app (`src/demo/`) demonstrating absolute positioning:
- A `<Card>` container with `relative` (or simply `position: .static` as the default) parent.
- Inside it, a `<Text>` element with `class="absolute top-0 right-0"` showing "TOP-RIGHT".
- A second `<Text>` with `class="absolute bottom-0 left-0"` showing "BOTTOM-LEFT".
- The parent card must have a fixed height so the absolute children are visible.

## Module location

```
src/03/types.zig         — Position enum, inset_* fields on LayoutNode
docs/specs/03.types.zig  — same
src/04/types.zig         — absolute child skip + second-pass placement in solve()
src/06/types.zig         — absolute, static, inset-*, top-*, right-*, bottom-*, left-* classes
docs/specs/06.types.zig  — updated class table
docs/requirements/RC0_absolute_positioning.md
```

## Public API changes

```zig
// Module 03
pub const Position = enum { static, absolute };

// LayoutNode gains:
position: Position = .static,
inset_top:    Dimension = .auto,
inset_right:  Dimension = .auto,
inset_bottom: Dimension = .auto,
inset_left:   Dimension = .auto,
```

## Behavioral contract

| Situation | Behavior |
|---|---|
| `position = .static` | No change from current behavior |
| `position = .absolute`, both inset_left and inset_right are `.auto` | Element positioned at `(containing_block.x + 0, y)` |
| `position = .absolute`, `inset_left = .px(8)` | Left edge 8 px from containing block left |
| `position = .absolute`, `inset_right = .px(8)` | Right edge 8 px from containing block right; `x = cb.x + cb.w - 8 - w` |
| Absolute element, `width = .auto`, both horizontal insets set | Width stretches to fill: `w = cb.w - left - right` |
| Absolute element nested in another absolute element | Inner's inset is relative to outer's `computed` rect |
| Absolute element with no explicit size and no `measured` | Width and height default to 0 |

## Non-goals (DO NOT implement — INV-5.4)

- **No `position: relative`** — `relative` shifts the element visually but it stays in flow; this requires tracking the "natural position" separately. Deferred to a future milestone.
- **No `position: fixed`** — viewport-relative fixed positioning.
- **No `position: sticky`** — that is M12-02, a separate requirement.
- **No `percent` insets** — `top: 50%` etc. deferred to post-v1.
- **No negative insets** — `top: -8px` for outset positioning is a non-goal.
- **No stacking context** — absolute elements are painted in document order; z-ordering above siblings is M12-05.
- **No `inset-x-*` / `inset-y-*` shorthand classes** — too rare to justify the resolver complexity.

## Acceptance criteria

1. `zig build` passes after all changes.

2. Unit tests in `src/04/04_test.zig` (or new `src/04/absolute_test.zig`) cover:
   - A `position: .static` parent with two `position: .absolute` children is solved:
     - Children are NOT included in the parent's flex layout size calculation.
     - Child A with `inset_left=.px(10), inset_top=.px(5)` → `computed.x = parent.x + 10`,
       `computed.y = parent.y + 5`.
     - Child B with `inset_right=.px(0), inset_bottom=.px(0)` and fixed `width=.px(40)`,
       `height=.px(20)` → bottom-right corner of parent.
   - When no positioned ancestor exists, the root element acts as the containing block.
   - An absolutely-positioned element with `width=.auto`, `inset_left=.px(10)`,
     `inset_right=.px(10)` inside a 200 px wide parent → `computed.w = 180`.

3. Unit tests in `src/06/06_test.zig` cover:
   - `absolute` class → `position = .absolute`.
   - `top-4` → `inset_top = .px(16)`.
   - `inset-0` → all four insets = `.px(0)`.

4. `zig build test-04` and `zig build test-06` pass with 0 failures.

5. Demo app screen is added and visible (no blank area).

6. Existing layout tests are unaffected (zero regressions).
