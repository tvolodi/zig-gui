# RL2 — M25-03: Inheritance and computed-value folding

> Roadmap item: M25-03
> Depends on: RL1 (cascade resolver), 05 (tokens), 06 (ComputedStyle)
> Read `RL1_cascade_specificity_resolver.md` before this file.

## Purpose

Add a **fixed, closed set** of inherited properties to the cascade, resolved at build time.
Inheritance is the second thing (after descendant selectors) that a flat utility model cannot
express and that real component theming needs — but full CSS inheritance is unbounded, so v2
inherits only a deliberately small list.

## What to build

### The inherited property set (closed)

```
color
font-family
font-size
line-height
text-align
direction          (base bidi direction, RK1 / RE3)
```

No other property inherits. This list is hardcoded (INV-1.1, INV-4.2-v2); it is not
configurable.

### Resolution (module 12, build-time)

After RL1 resolves directly-set declarations per node, walk the baked tree top-down. For each
node and each inherited property:

- If the property was set directly on the node (any tier from RL1), keep it.
- Else, copy the parent's computed value for that property.
- The root's defaults come from the theme's base tokens (INV-4.3), not a hardcoded literal.

A `inherit` keyword value on any property forces inheritance for that one property even if not
in the default set (the only escape hatch; still build-time, still bounded). An `initial`
keyword resets to the token default.

## Module location

```
src/12/types.zig          — INHERITED_PROPS constant, resolveInheritance(tree) pass
docs/requirements/RL2_inheritance.md
```

## Public API changes

```zig
// Module 12 (build-time): INHERITED_PROPS (closed list), resolveInheritance()
// Runtime: unchanged — final ComputedStyle still baked.
```

## Behavioral contract

| Situation | Behavior |
|---|---|
| Parent sets `color: text-primary`, child sets none | Child inherits `text-primary` |
| Parent sets `color`, child sets `color` directly | Child's own value wins (no inheritance) |
| Parent sets `padding` (not inherited), child none | Child does NOT inherit padding |
| Child `color: inherit` on a non-inherited-by-default prop | Forces inheritance of that prop |
| Child `color: initial` | Resets to the theme token default |
| Root node | Inherited props default to base theme tokens |
| Utility-only screen | No inheritance rules present → behavior identical to v1 (RL3) |

## Non-goals (DO NOT implement — INV-5.4)

- **No inheritance of layout/box properties** — only the six-item list inherits.
- **No configurable inheritance set** (INV-1.1).
- **No runtime inheritance resolution** — build-time only (INV-4.4).
- **No `unset`/`revert` CSS keywords** beyond `inherit` and `initial`.

## Acceptance criteria

1. Module 12 acceptance test: each of the six inherited properties propagates parent→child
   when unset on the child, and is overridden when set on the child.
2. A non-inherited property (e.g. padding) does not propagate.
3. `inherit` and `initial` keywords behave as documented.
4. Root defaults come from theme tokens, and a theme swap (R93) changes inherited roots
   correctly (since only palette layer changes, INV-4.3).
5. RL3 compatibility test passes (utility-only screen unchanged).
