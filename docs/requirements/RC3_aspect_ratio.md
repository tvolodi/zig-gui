# RC3 — M12-04: Aspect-ratio constraint

> Roadmap item: M12-04  
> Depends on: 04 (layout engine)  
> Read `00_constitution.md` before this file.

## Purpose

Add an aspect-ratio constraint to the layout engine. When set, the element's height is derived
from its computed width (or vice versa) to maintain a fixed width-to-height ratio. This is
essential for image containers, video placeholders, map tiles, and any content that must not
distort.

## What to build

### New field on `LayoutNode` (module 03)

Add to `docs/specs/03.types.zig` and `src/03/types.zig`:

```zig
pub const LayoutNode = struct {
    // ... existing fields unchanged ...

    // M12 RC3 — aspect ratio. 0 = no constraint; otherwise h = w / aspect_ratio.
    aspect_ratio: f32 = 0,
};
```

`0` (the default) means no constraint. Positive values set the width-to-height ratio. For
example, `aspect_ratio = 1.0` means square; `aspect_ratio = 16.0 / 9.0` means widescreen.

### Layout engine changes (module 04)

After computing `computed.w` for an element (whether from an explicit `width` setting, flex
grow, or parent constraints), if `node.aspect_ratio > 0` and `node.height == .auto`:

```
computed.h = computed.w / node.aspect_ratio
```

If both `width` and `height` are explicit (non-auto), `aspect_ratio` is ignored — explicit
dimensions win over the ratio constraint (this avoids surprising overrides of intentional
sizing).

If `width` is `.auto` and `aspect_ratio > 0`:
- Use `computed.w` as determined by normal flex/block rules.
- Then apply `computed.h = computed.w / aspect_ratio` as above.

This must happen **before** children are laid out inside the element, because the element's
height is needed as the children's cross-axis constraint.

### Tailwind class resolver changes (module 06)

| Class | Effect on LayoutNode |
|---|---|
| `aspect-square` | `aspect_ratio = 1.0` |
| `aspect-video` | `aspect_ratio = 16.0 / 9.0` |
| `aspect-auto` | `aspect_ratio = 0` (explicit reset) |

These three classes cover the standard Tailwind subset. Arbitrary ratios (e.g., `aspect-[4/3]`)
are a non-goal.

## Module location

```
src/03/types.zig         — aspect_ratio: f32 field on LayoutNode
docs/specs/03.types.zig  — same
src/04/types.zig         — aspect-ratio application in the layout solver
src/06/types.zig         — aspect-square, aspect-video, aspect-auto classes
docs/specs/06.types.zig  — updated class table
docs/requirements/RC3_aspect_ratio.md
```

## Public API changes

```zig
// LayoutNode gains:
aspect_ratio: f32 = 0,  // 0 = no constraint; positive = width / height ratio
```

## Behavioral contract

| Situation | Behavior |
|---|---|
| `aspect_ratio = 0` (default) | No change from current layout behavior |
| `aspect_ratio = 1.0`, `width = .px(100)`, `height = .auto` | `computed.h = 100` |
| `aspect_ratio = 16.0/9.0`, `width = .px(160)`, `height = .auto` | `computed.h = 90` |
| `aspect_ratio = 1.0`, both width and height are explicit | Aspect ratio ignored |
| `aspect_ratio > 0`, `width = .auto` | Width from flex/block rules, then height derived |
| `aspect_ratio > 0`, `height` is explicit | Aspect ratio ignored for height axis |

## Non-goals (DO NOT implement — INV-5.4)

- **No height-to-width derivation** — only `h = w / ratio` is supported, not `w = h * ratio`.
- **No arbitrary ratio syntax** (`aspect-[4/3]`).
- **No intrinsic image ratio** — images do not automatically inherit their source image's aspect ratio.
- **No `aspect-ratio` in grid tracks**.

## Acceptance criteria

1. `zig build` passes after all changes.

2. Unit tests in `src/04/04_test.zig` cover:
   - Element `width = .px(200)`, `height = .auto`, `aspect_ratio = 2.0` → `computed.h = 100`.
   - Element `width = .px(100)`, `height = .auto`, `aspect_ratio = 1.0` → `computed.h = 100`.
   - Element `width = .px(160)`, `height = .auto`, `aspect_ratio = 16.0/9.0` → `computed.h ≈ 90` (within 0.5 px).
   - Element with explicit `width` and `height`, `aspect_ratio = 1.0` → `height` unchanged.
   - Element `aspect_ratio = 0` → behavior identical to having no aspect ratio field.

3. Unit tests in `src/06/06_test.zig` cover:
   - `aspect-square` → `aspect_ratio = 1.0`.
   - `aspect-video` → `aspect_ratio ≈ 1.778` (16/9, within float tolerance).
   - `aspect-auto` → `aspect_ratio = 0`.

4. `zig build test-04` and `zig build test-06` pass with 0 failures.

5. Demo app: add at least one `aspect-square` image placeholder or card. Visually verify
   it maintains its ratio when the window is resized.

6. Existing layout tests are unaffected (zero regressions).
