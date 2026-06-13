# RL0 — M25-01: Selector model and parser

> Roadmap item: M25-01
> Depends on: 06 (markup tree, ComputedStyle), 05 (theme/tokens)
> Blocked by ratification of `V2_constitution_amendment.md` (replaces INV-4.2 with
> INV-4.2-v2).
> Read `00_constitution.md` and `V2_ARCHITECTURE.md` §4 before this file.

## Purpose

Define the bounded selector language the v2 cascade supports, and a **build-time** parser that
turns rule blocks into matchable selectors. This is the input half of the cascade; RL1 does
the matching/specificity, RL2 does inheritance. Per INV-4.4 the parser runs only at build-time
codegen — the production binary contains no selector parser.

## What to build

### Supported selector grammar (the bounded subset)

```
selector      := compound ( combinator compound )*
combinator    := ' ' (descendant) | '>' (child)
compound      := ( type | class | id | attr )+
type          := IDENT                 e.g.  Button, Row
class         := '.' IDENT             e.g.  .toolbar
id            := '#' IDENT             e.g.  #main-nav
attr          := '[' IDENT ']'         e.g.  [disabled]   (presence only)
```

Pseudo-states (`:hover`, `:focus`, `:active`, `:disabled`) are accepted **only** as the
existing R40 pseudo-state set, mapping to the variant baking RL1 already performs. No other
pseudo-classes, no pseudo-elements, no attribute value matching, no sibling combinators.

### Rule block source

A `.style` file (or `<style>` blocks colocated with `.ui` markup) holds rule sets:

```
.toolbar Button { padding: 4 8; font-size: sm; }
#main-nav { background: surface-raised; }
[disabled] { opacity: 50; }
```

Property names and values resolve through the existing four-layer token model (INV-4.3): a
value like `surface-raised` is a semantic token, `sm` a type-scale token. Raw hex/px literals
are rejected the same way utility classes reject them (INV-4.3).

### Parser (module 12, build-time)

```zig
pub const Selector = struct {
    compounds: []const Compound,   // outermost-first
    combinators: []const Combinator,
    specificity: Specificity,      // (id_count, class_attr_count, type_count) — computed here
};
pub const Rule = struct { selector: Selector, decls: []const Decl, source_order: u32 };

/// Build-time only. Parse a .style source into rules with computed specificity.
pub fn parseStyles(gpa, src: []const u8) ParseError![]Rule;
```

## Module location

```
src/12/types.zig          — Selector, Compound, Combinator, Rule, Decl, Specificity, parseStyles
tools/                    — build-time invocation of parseStyles (codegen, INV-4.4)
docs/specs/12.types.zig   — spec mirror
docs/requirements/RL0_selector_model.md
```

## Public API changes

```zig
// Module 12 (new, build-time): Selector, Rule, Decl, Specificity, parseStyles()
// No runtime API; output feeds RL1's build-time resolver.
```

## Behavioral contract

| Situation | Behavior |
|---|---|
| `.toolbar Button { ... }` | Descendant selector: matches Button anywhere under a `.toolbar` |
| `.menu > Item { ... }` | Child selector: matches Item that is a direct child of `.menu` |
| `#id { ... }` | Id selector; highest specificity tier |
| `[disabled] { ... }` | Attribute-presence selector |
| `:hover` on a rule | Mapped to the R40 hover variant (baked, not runtime-matched) |
| Unknown pseudo-class / value-attr selector | Build-time error with line/column (per R54 style) |
| Raw hex value | Build-time error — values must be tokens (INV-4.3) |

## Non-goals (DO NOT implement — INV-5.4)

- **No `@media` / `@supports` / `@import`** — INV-4.2-v2 bounds the cascade.
- **No sibling (`+`, `~`) combinators, no `*`, no pseudo-elements.**
- **No attribute value or substring matching** — presence only.
- **No runtime selector parsing** — build-time codegen only (INV-4.4).
- **No `!important`** (handled — actually rejected — in RL1).

## Acceptance criteria

1. Module 12 acceptance test parses each supported selector form and computes the correct
   `(id, class/attr, type)` specificity triple.
2. Unsupported constructs (sibling combinator, `@media`, value-attr, hex literal) produce a
   build-time error with line and column.
3. Token-valued declarations resolve through the four-layer model; non-token values error.
4. Pseudo-state selectors map to the existing R40 variant set.
