# RC4 — M12-05: Z-index on normal elements

> Roadmap item: M12-05  
> Depends on: 04 (layout engine), 09 (renderer)  
> Read `00_constitution.md` before this file.

## Purpose

Allow normal (non-overlay) elements to declare a z-order via a `z_index` field. Siblings with
a higher z-index are drawn on top of siblings with a lower z-index, without requiring the
overlay system. This is essential for hover cards, expanded dropdowns within a card, and any
UI where one sibling must visually overlap another within the same container.

This requirement does NOT implement stacking contexts (CSS `z-index` full spec) — it is a
simpler "draw-order override within siblings" model.

## What to build

### New field on `LayoutNode` (module 03)

Add to `docs/specs/03.types.zig` and `src/03/types.zig`:

```zig
pub const LayoutNode = struct {
    // ... existing fields unchanged ...

    // M12 RC4 — z-index within siblings. 0 = default (document order).
    // Higher values drawn on top. Negative values drawn behind.
    z_index: i16 = 0,
};
```

`i16` gives a range of −32768 to +32767, which is more than sufficient. The default `0`
preserves current document-order painting behavior.

### Renderer changes (module 09 / buildDrawList)

The `buildDrawList` function currently emits draw commands in element-store traversal order
(depth-first, child elements follow parent). With z-index:

1. When rendering a container's children, sort them by `z_index` before emitting their
   draw commands. Children with the same `z_index` retain their original document order
   (stable sort).

2. The sort is **per-container** — z-index only reorders siblings within the same parent.
   An element with `z_index = 100` in container A does NOT draw above an element with
   `z_index = 0` in container B if B is rendered after A in document order.

3. The sort is applied at draw time, not at layout time — `computed` rects are unaffected
   by `z_index`.

4. Implementation: before iterating a container's children in `buildDrawList`, build a
   temporary sorted index slice. Use a simple insertion sort (N is small — max children
   per container is typically < 20). Do NOT allocate per-frame; use a fixed-size stack
   buffer (max 256 children; if a container has more, skip the sort and use document order).

### Hit-test order (app layer — dispatchEvents)

The existing `hitTest` function scans elements in reverse index order (highest = topmost).
With z-index, a higher z-index sibling should be hit-tested BEFORE a lower z-index sibling
even if its index is lower.

Update `hitTestFocusable` and the general `hitTest` in `src/app/app.zig` to account for
z-index: for each container in the traversal, yield its children in descending z-index order
(ties broken by descending element index, preserving the "last drawn = topmost" semantic).

A practical approach: the existing reverse-index scan already works correctly for siblings in
document order. Extend it to first check if any same-parent sibling has a higher `z_index`
before returning a hit. This can be done with a simple O(n) scan over the sibling chain.

### Tailwind class resolver changes (module 06)

| Class | Effect on LayoutNode |
|---|---|
| `z-0` | `z_index = 0` |
| `z-10` | `z_index = 10` |
| `z-20` | `z_index = 20` |
| `z-30` | `z_index = 30` |
| `z-40` | `z_index = 40` |
| `z-50` | `z_index = 50` |

These are the standard Tailwind z-index utilities. Arbitrary values (`z-[100]`) are a non-goal.
Negative z-index (`-z-10`) is also a non-goal for v1.

## Module location

```
src/03/types.zig         — z_index: i16 field on LayoutNode
docs/specs/03.types.zig  — same
src/09/types.zig         — sibling sort by z_index in buildDrawList
src/app/app.zig          — z_index-aware hit-test order in hitTest / hitTestFocusable
src/06/types.zig         — z-0, z-10, z-20, z-30, z-40, z-50 classes
docs/specs/06.types.zig  — updated class table
docs/requirements/RC4_z_index.md
```

## Public API changes

```zig
// LayoutNode gains:
z_index: i16 = 0,
```

## Behavioral contract

| Situation | Behavior |
|---|---|
| All siblings have `z_index = 0` | Document-order painting, identical to current behavior |
| Sibling A: `z_index = 0`, Sibling B: `z_index = 10` | B drawn on top of A even if A has a higher element index |
| Siblings with equal non-zero z-index | Document order (stable sort) |
| Container A before container B in document order, A's children have `z_index = 100` | A's children still draw before B and B's children (z-index is per-container only) |
| `z_index = 0` (default) | Identical to having no z-index field |
| Hit-testing: two overlapping siblings, higher z_index on top | Higher z_index sibling hit first |

## Non-goals (DO NOT implement — INV-5.4)

- **No stacking contexts** — `z_index` does not create a new stacking context (CSS full spec behavior). Z-ordering is strictly per-container/siblings-only.
- **No negative z-index** — drawing elements behind their parent background is a non-goal.
- **No cross-container z-ordering** — an element in container A cannot draw above an element in container B by setting a large z-index.
- **No `z-auto`** — `z_index = 0` is the default and is equivalent to `z-auto`.
- **No arbitrary z-index values** (`z-[999]`).

## Acceptance criteria

1. `zig build` passes after all changes.

2. Unit tests in `src/09/09_test.zig` (or new `src/09/z_index_test.zig`) cover:
   - Two siblings A (index 0, z_index 0) and B (index 1, z_index 10):
     draw-command list for B appears AFTER A's draw commands.
   - Two siblings A (index 0, z_index 20) and B (index 1, z_index 0):
     draw-command list for A appears AFTER B's.
   - Three siblings with z-indices [0, 10, 5]: draw order is [0-z, 5-z, 10-z].
   - Container with `> 256` children: sort skipped, document order used (no crash).

3. Unit tests in `src/06/06_test.zig` cover:
   - `z-10` class → `z_index = 10`.
   - `z-50` class → `z_index = 50`.
   - `z-0` class → `z_index = 0`.

4. `zig build test-09` and `zig build test-06` pass with 0 failures.

5. Demo app: add a hover card or tooltip-like element using z-index to overlap a sibling.
   Visually verify the higher z-index element appears on top.

6. Existing rendering tests are unaffected (zero regressions).
