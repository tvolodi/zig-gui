# RL1 — M25-02: Cascade and specificity resolver

> Roadmap item: M25-02
> Depends on: RL0 (selector model), 06 (markup tree, resolveClasses), 05 (tokens)
> Read `RL0_selector_model.md` and `V2_ARCHITECTURE.md` §4 before this file.

## Purpose

Resolve, at build time, the winning set of declarations for each element by matching the RL0
rules against the baked markup tree, ordering by specificity then source order, and folding
the result together with the existing utility-class resolver into the single `ComputedStyle`
the renderer already consumes. No runtime cascade engine ships (INV-4.4).

## What to build

### Match + cascade (module 12, build-time)

For each element node in the baked tree:

1. Find all RL0 rules whose selector matches the node's position (type, classes, id, attrs,
   ancestor/parent chain).
2. Collect declarations from matched rules **plus** the node's own utility classes
   (`resolveClasses`, module 06) **plus** inline `style:` attributes (R50).
3. Order sources by the specificity ladder:

```
tier 0 (lowest):  type selectors
tier 1:           class / attribute selectors and utility classes (Tailwind subset)
tier 2:           id selectors
tier 3 (highest): inline style: attributes (R50)
within a tier:    later source order wins
```

4. Fold the winning declaration per property into a `ComputedStyle`. Emit it as a baked
   literal (same output shape as today's `resolveClasses` result).

### Dynamic variants

For properties that change at runtime (pseudo-states R40, conditional classes R52), the
resolver pre-bakes one `ComputedStyle` per reachable variant, exactly as pseudo-states are
baked today. RL1 defines the finite variant set: base × {hover, focus, active, disabled} ×
{each statically-known conditional class toggle on that node}. Unbounded dynamic class
combinations are rejected at build time with a clear message (keeps the baked set finite).

### `!important`

Not supported. An `!important` token is a build-time error (INV-4.2-v2). This is deliberate:
it removes the primary source of cascade pathology.

## Module location

```
src/12/types.zig          — matchRules(), cascade(), variant baking; emits ComputedStyle literals
tools/                    — build-time codegen integration (INV-4.4)
docs/requirements/RL1_cascade_specificity_resolver.md
```

## Public API changes

```zig
// Module 12 (build-time): matchRules(tree, rules), cascade(matches, utilities, inline) ComputedStyle
// Runtime: unchanged — renderer consumes baked ComputedStyle exactly as in v1.
```

## Behavioral contract

| Situation | Behavior |
|---|---|
| Element matched by `.toolbar Button` and has utility `p-2` | Class-tier conflict resolved by source order; both apply to non-conflicting props |
| `#save` id rule vs `.btn` class rule on same prop | Id (tier 2) wins over class (tier 1) |
| Inline `style:color` vs any selector rule | Inline (tier 3) wins |
| Two class rules set the same prop | Later source order wins |
| `:hover` variant | Baked as a separate ComputedStyle; renderer swaps on hover (R40 path) |
| `!important` present | Build-time error |
| Unbounded dynamic class combination | Build-time error naming the offending node |
| Screen with no rule blocks (utility-only) | Identical output to v1 `resolveClasses` (RL3 guarantee) |

## Non-goals (DO NOT implement — INV-5.4)

- **No runtime cascade** — all resolution at build time (INV-4.4).
- **No `!important`, no specificity hacks.**
- **No inheritance here** — that is RL2 (this requirement resolves directly-set properties).
- **No new runtime data structures** — output is the existing baked `ComputedStyle`.

## Acceptance criteria

1. Module 12 acceptance test: specificity ordering (type < class/utility < id < inline) and
   within-tier source-order tie-breaking both verified.
2. A mixed example (id rule + class rule + utility + inline on one node) resolves to the
   documented winner per property.
3. `!important` and unbounded dynamic class combos each produce a build-time error.
4. Pseudo-state variants bake correctly and the renderer swap path (R40) is unchanged.
5. RL3 compatibility test (utility-only screen identical to v1) passes against this resolver.
