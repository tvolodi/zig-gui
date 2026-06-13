# RL3 — M25-04: Markup migration and compatibility

> Roadmap item: M25-04
> Depends on: RL0, RL1, RL2, 06 (markup), DEMO_APP
> Read `RL1_cascade_specificity_resolver.md` and `RL2_inheritance.md` before this file.

## Purpose

Guarantee that adding the cascade does not break the existing utility-class authoring surface,
and define the migration path. INV-4.2-v2 notes the cascade is the one v2 change that *can*
break existing markup; this requirement makes the non-breakage explicit and testable, and
documents when to reach for selectors vs utilities.

## What to build

### Compatibility guarantee (the gate)

**With no rule blocks present, the cascade is identity over the v1 utility resolver.** A
screen authored entirely with utility classes and inline `style:` attributes must produce a
byte-identical baked `ComputedStyle` set before and after modules 12 land. This is enforced as
a regression test over the entire v1 demo app (DEMO_APP.md).

### Specificity placement of utilities

Utility classes sit at tier 1 (class tier) in RL1's ladder. This means a `.style` *class*
rule and a utility class on the same node and property are resolved by **source order**, with
utility classes treated as appearing at the node (inline-adjacent in source order, but below
inline `style:`). The HOW_TO_USE guidance documents this single interaction rule.

### Authoring guidance (docs)

Add a HOW_TO_USE section: use utilities for one-off, per-node styling (unchanged from v1); use
`.style` rules for (a) styling many descendants from a container, (b) shared component themes,
(c) the six inherited properties. Do not mix a utility and a selector rule that set the same
property on the same node — prefer one source.

### Migration

No forced migration: v1 screens keep working untouched. The demo app gains *one* new screen
demonstrating descendant selectors + inheritance (so DEMO_APP covers the feature, per the
ROADMAP "done" rule), authored with a `.style` block.

## Module location

```
docs/HOW_TO_USE.md          — cascade vs utilities authoring guidance, the source-order rule
docs/requirements/DEMO_APP.md — new "Cascade" showcase screen entry
docs/requirements/RL3_markup_migration.md
src/12/                      — compatibility (identity-when-no-rules) path
```

## Public API changes

None — this requirement is compatibility, tests, and documentation over RL0–RL2.

## Behavioral contract

| Situation | Behavior |
|---|---|
| v1 utility-only screen, modules 12 present, no rule blocks | Baked ComputedStyle byte-identical to v1 |
| Utility `p-4` + `.style` rule setting padding, same node | Source-order resolution; documented |
| New cascade showcase screen | Renders descendant-styled + inherited content correctly |
| Inline `style:` + any rule | Inline wins (tier 3, RL1) — unchanged from R50 precedence |

## Non-goals (DO NOT implement — INV-5.4)

- **No removal of utility classes** — they remain first-class (tier 1).
- **No auto-migration tool** converting utilities to rules.
- **No deprecation of inline `style:`** (R50).
- **No change to runtime behavior** — all differences are build-time.

## Acceptance criteria

1. Regression test: every v1 demo screen produces byte-identical baked `ComputedStyle` with
   modules 12 present and no rule blocks (the compatibility gate).
2. The new Cascade showcase screen renders correctly and is covered in DEMO_APP.md.
3. HOW_TO_USE documents the utilities-vs-selectors guidance and the source-order interaction
   rule.
4. The utility + selector same-property interaction resolves per the documented source-order
   rule (unit test).
