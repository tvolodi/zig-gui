# RC2 — M12-03: Wrapping flex rows

> Roadmap item: M12-03  
> Depends on: 04 (layout engine)  
> Read `00_constitution.md` before this file.

## Purpose

Add `flex-wrap` support to the layout engine. Currently all flex containers are single-line
(non-wrapping). With `flex_wrap = true`, children that don't fit on the main axis spill onto
a new line, enabling responsive grid-like layouts with natural word-wrap semantics.

This is one of the most commonly needed layout features missing from the current engine.

## What to build

### New field on `LayoutNode` (module 03)

Add to `docs/specs/03.types.zig` and `src/03/types.zig`:

```zig
pub const LayoutNode = struct {
    // ... existing fields unchanged ...

    // M12 RC2 — flex wrapping
    flex_wrap: bool = false,
};
```

A single boolean is sufficient for v1 (`flex-wrap: nowrap` vs `flex-wrap: wrap`). The
`wrap-reverse` variant is a non-goal.

### Layout engine changes (module 04)

When `node.display == .flex` and `node.flex_wrap == true`:

1. **Line-breaking pass:** Iterate children in order. Track the current line's main-axis
   extent. When adding the next child would exceed the container's main-axis size (after
   accounting for gap), break to a new line. A child always starts a new line if its own
   minimum size already exceeds the available width.

2. **Per-line sizing:** Each line is an independent flex container with the same `align_items`
   setting. Compute each line's cross-axis size as the max cross-axis size of its children
   (with `flex_grow`/`flex_shrink` applied within the line, NOT across lines).

3. **Cross-axis placement:** Lines are stacked in the cross direction. The gap between lines
   uses the container's `gap` value (same gap as between items).

4. **Main-axis overflow behavior:** When `flex_wrap == false` (the current behavior), children
   that overflow are clipped at the parent boundary as before — no change.

5. **Container cross-axis size:** When the container's cross-axis dimension is `auto`, it
   grows to fit all lines. When it has an explicit size, lines may overflow and be clipped.

Implementation note: the existing `solveFlexLine` helper (or equivalent) should be called once
per line. Wrap support is additive — the non-wrap path must remain unchanged.

### Tailwind class resolver changes (module 06)

| Class | Effect on LayoutNode |
|---|---|
| `flex-wrap` | `flex_wrap = true` |
| `flex-nowrap` | `flex_wrap = false` (explicit reset) |

## Module location

```
src/03/types.zig         — flex_wrap: bool field on LayoutNode
docs/specs/03.types.zig  — same
src/04/types.zig         — wrapping flex solver
src/06/types.zig         — flex-wrap, flex-nowrap classes
docs/specs/06.types.zig  — updated class table
docs/requirements/RC2_flex_wrap.md
```

## Public API changes

```zig
// LayoutNode gains:
flex_wrap: bool = false,
```

## Behavioral contract

| Situation | Behavior |
|---|---|
| `flex_wrap = false` (default) | Identical to current behavior — no change |
| `flex_wrap = true`, children fit in one line | Identical to `flex_wrap = false` |
| `flex_wrap = true`, children overflow | Extra children start a new line |
| Wrapping row with gap | `gap` applied between items AND between lines |
| Child with `flex_grow > 0` in a wrapped container | Grows within its line only |
| Container `height = .auto`, multiple lines | Container height = sum of line heights + gaps |
| Container with explicit height, children overflow lines | Extra lines are clipped |

## Non-goals (DO NOT implement — INV-5.4)

- **No `flex-wrap: wrap-reverse`** — lines stacked in reverse cross direction.
- **No `align-content`** — multi-line cross-axis alignment (`space-between` lines etc.).
- **No wrapping grid** — this requirement is flex-only.
- **No per-line `justify-content` override** — all lines use the container's `justify_content`.
- **No wrap in column direction** — `flex_wrap` with `direction = .column` is a non-goal (wrapping columns produce unexpected layouts and are very rarely needed).

## Acceptance criteria

1. `zig build` passes after all changes.

2. Unit tests in `src/04/04_test.zig` (or new `src/04/flex_wrap_test.zig`) cover:
   - Row container 200 px wide, three children each 80 px wide, `gap = 4`:
     - First two children on line 1 (80 + 4 + 80 = 164 ≤ 200).
     - Third child on line 2.
     - Container height = 2 × child_height + gap.
   - Row container 200 px wide, one child 300 px wide:
     - Single child on its own line; `computed.w = 300` (overflow is not clipped by layout).
   - `flex_wrap = false`, same input → all three children on one line, no height expansion.
   - Wrapping row with `flex_grow = 1` on all children → each child fills its line evenly.

3. Unit tests in `src/06/06_test.zig` cover:
   - `flex-wrap` class → `flex_wrap = true`.
   - `flex-nowrap` class → `flex_wrap = false`.

4. `zig build test-04` and `zig build test-06` pass with 0 failures.

5. Demo app: add a wrapping tag-cloud row (`flex-wrap`) with 10–15 items. Visually verify
   items wrap onto multiple rows.

6. Existing non-wrap layout tests are unaffected (zero regressions).
