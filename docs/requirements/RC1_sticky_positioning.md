# RC1 — M12-02: Sticky positioning

> Roadmap item: M12-02  
> Depends on: M3-06 (scroll container), RC0 (absolute positioning)  
> Read `00_constitution.md` before this file.

## Purpose

Add `position: sticky` to the layout engine and scroll path. A sticky element participates in
normal flow until its scroll container scrolls past a threshold, at which point it "sticks" to
the specified edge of the container's viewport. This is the standard pattern for sticky table
headers, section labels, and navigation bars within a scrollview.

## What to build

### `Position` enum extension (module 03)

Extend the `Position` enum added by RC0:

```zig
pub const Position = enum { static, absolute, sticky };
```

The `inset_*` fields from RC0 are reused: for a sticky element, `inset_top` sets how far from
the container's top edge the element "sticks" when scrolling down. Only `inset_top` and
`inset_bottom` are supported in v1 (horizontal sticky is a non-goal).

### Layout changes (module 04)

Sticky elements participate in normal flow sizing identically to `position: .static`. They are
NOT removed from the flow. The layout engine's `solve()` function:

1. Treats `position: .sticky` elements exactly like `position: .static` during the normal
   flow pass — they contribute to parent size, consume flex/grid tracks, etc.
2. Does NOT apply any offset during `solve()`. The "sticking" is a rendering / scroll-offset
   concern handled in the app layer (see below).
3. Records the element's **natural computed rect** (where it would sit without sticking).

### Sticky offset applied in the app layer (src/app/app.zig)

The sticky behavior is implemented in the draw-list path, not in the layout engine, because it
depends on the runtime scroll offset which is unknown at layout time.

In `buildDrawList` (module 09 / app layer), for each element with `position == .sticky`:

1. Read the element's nearest scroll-container ancestor's current `scroll_y` offset from
   `scene._scroll_state`.
2. Compute the "sticky clamped y":
   ```
   natural_y = computed.y - scroll_offset_of_container.y  // relative to container viewport top
   inset_top_px = inset_top value (or 0 if .auto)
   sticky_y = max(natural_y, inset_top_px)
   ```
3. Apply the delta as a draw-time translate: the element is drawn at `(computed.x, container.y + sticky_y)` instead of its `computed` position.
4. The element's **hit-test rect** must also use the sticky-adjusted position, not the
   `computed` rect. A separate `sticky_offset_y: f32` parallel array stores the delta so
   hit-testing in `dispatchEvents` can account for it.

### New parallel array in `Scene` (module 07)

```zig
// M12 RC1 — per-element sticky draw-time y-offset (0 = not sticky or not active).
_sticky_offset_y: std.ArrayListUnmanaged(f32) = .{},
```

This array is grown in `instantiateNode`, cleared in `reset()`, and freed in `deinit()`.

The app layer sets `scene._sticky_offset_y.items[idx]` each frame in `buildDrawList`
before emitting draw commands for the sticky element. The hit-test path in `dispatchEvents`
reads this to offset the hit rect.

### Tailwind class resolver changes (module 06)

| Class | Effect on LayoutNode |
|---|---|
| `sticky` | `position = .sticky` |
| `top-0` / `top-{n}` | `inset_top = .px(n * 4)` (shared with RC0) |

The `top-*` classes are already added by RC0. No additional resolver changes are needed
beyond `sticky`.

## Module location

```
src/03/types.zig         — Position enum gains .sticky variant
docs/specs/03.types.zig  — same
src/04/types.zig         — sticky elements treated as static in solve()
src/07/types.zig         — _sticky_offset_y parallel array
docs/specs/07.types.zig  — same
src/09/types.zig         — sticky draw-time offset applied in buildDrawList
src/app/app.zig          — sticky hit-test offset in dispatchEvents
src/06/types.zig         — sticky class
docs/requirements/RC1_sticky_positioning.md
```

## Public API changes

```zig
// Module 03 — Position enum gains:
sticky,

// Scene gains:
_sticky_offset_y: std.ArrayListUnmanaged(f32) = .{},
```

## Behavioral contract

| Situation | Behavior |
|---|---|
| `position = .sticky`, `inset_top = .px(0)`, scrolled past element | Element sticks to top of its scroll container |
| `position = .sticky`, `inset_top = .px(16)`, scrolled past | Element sticks 16 px below the container top |
| `position = .sticky`, not yet scrolled past | Renders at natural computed position |
| `position = .static` / `.absolute` | No sticky behavior; `_sticky_offset_y = 0` |
| Sticky element inside a non-scrolling container | No sticking (scroll_y always 0) |

## Non-goals (DO NOT implement — INV-5.4)

- **No `inset_bottom` sticky** — sticking to the bottom edge on upward scroll is a non-goal.
- **No horizontal sticky** — `left-*` / `right-*` sticky is a non-goal.
- **No sticky within grid containers** — sticky is only supported inside scrollview containers.
- **No sticky stacking** — multiple sticky elements don't push each other down.
- **No CSS `position: sticky` on non-scrolling overflow** — if there's no scroll container, the behavior is identical to `static`.

## Acceptance criteria

1. `zig build` passes after all changes.

2. Unit tests in `src/04/04_test.zig` cover:
   - A `sticky` element participates in normal flow sizing — the parent's height includes the sticky child.
   - A `sticky` element's `computed` rect is its natural position (no offset applied by the layout engine).

3. Unit tests in `src/07/07_test.zig` cover:
   - After `instantiateNode`, `_sticky_offset_y.items[idx] == 0`.

4. Integration test (manual or via demo app):
   - A scrollview with a sticky header: as the container scrolls, the header stays at the top.

5. `zig build test-04`, `zig build test-07` pass with 0 failures.

6. Existing tests are unaffected (zero regressions).
