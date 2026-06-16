# RN13 — UI component library (`src/app/ui/`)

> Status: `planned`.
> Provides composable NodeDesc-returning functions so screens can build shadcn-equivalent
> layouts in a few lines instead of hundreds of NodeDescs.
> Read `docs/specs/00_constitution.md` before this file.
> Use project-relative paths only.

## 1. Location and structure

```
src/app/ui/
  mod.zig          — re-exports all components; single import point
  badge.zig        — Badge: semantic pill (default/secondary/outline/destructive/ok/warn)
  button.zig       — Button: typed variant (primary/outline/ghost/destructive)
  card.zig         — Card: surface with optional header/content/footer sections
  input_field.zig  — InputField: labeled input with optional description
  label.zig        — Label: form label text
  separator.zig    — Separator: hr-style divider
  stat_card.zig    — StatCard: KPI card with icon slot + value + optional TrendBadge
  select.zig       — Select: labeled dropdown
  switch_field.zig — SwitchField: labeled checkbox (matches shadcn Switch appearance)
```

## 2. Contract

Each component is a function:
```zig
pub fn badgeNode(opts: BadgeOpts) NodeDesc
pub fn buttonNode(opts: ButtonOpts) NodeDesc
pub fn cardNode(opts: CardOpts, children: []const NodeDesc) NodeDesc
...
```

Functions return a `NodeDesc` (comptime-composed from `src/06/types.zig`). Opts structs
use comptime-known fields with defaults so callers can omit most.

All color references use semantic class strings only (INV-4.3):
- Variant colors encoded as class names: `"bg-accent text-accent"`, `"bg-raised"`, etc.
- No inline hex or raw token field references in NodeDesc attrs.

## 3. Component specifications

### Badge
```zig
pub const BadgeVariant = enum { default, secondary, outline, ok, warn, err };
pub const BadgeOpts = struct {
    text: []const u8,
    variant: BadgeVariant = .default,
};
// Renders: Card with rounded-full + variant background/text classes + Text label
// default   → bg-accent text-accent rounded-full px-2 py-0.5 text-xs font-bold
// secondary → bg-raised  text-body  rounded-full px-2 py-0.5 text-xs
// outline   → bg-canvas  border     rounded-full px-2 py-0.5 text-xs
// ok        → bg-ok text-accent rounded-full …
// warn      → bg-warn …
// err       → bg-err text-accent …
```

### Button
```zig
pub const ButtonVariant = enum { primary, outline, ghost, destructive };
pub const ButtonOpts = struct {
    text: []const u8,
    variant: ButtonVariant = .primary,
    disabled: bool = false,
    full_width: bool = false,
};
// primary     → Button tag with accent bg (handled by renderer)
// outline     → Button tag with bg-canvas + border classes
// ghost       → Button tag with transparent bg, text-body
// destructive → Button tag with bg-err, text-accent
```

### Card
```zig
pub const CardOpts = struct {
    padding: bool = true,   // adds p-4 when true
    shadow: bool = true,    // adds shadow when true
    border: bool = true,    // adds border class
};
// Returns: Card tag with shadow + rounded-lg + optional p-4
```

### InputField
```zig
pub const InputFieldOpts = struct {
    label: []const u8,
    placeholder: []const u8 = "",
    description: []const u8 = "",  // shown below input in text-muted text-sm
};
// Returns Column:
//   Label (Text font-bold text-sm)
//   Input
//   [optional] Text text-sm text-muted (description)
```

### StatCard
```zig
pub const StatCardOpts = struct {
    label: []const u8,
    value: []const u8,
    trend_value: ?f32 = null,     // set after instantiation via setTrendValue
    icon_char: []const u8 = "",   // single char or short string for icon placeholder
};
// Returns Card p-4 shadow:
//   Row items-center justify-between:
//     Column:
//       Text label text-sm text-muted
//       Text value text-xl font-bold
//     Card w-10 h-10 rounded-full bg-raised [icon_char]
//   [if trend_value] Row items-center gap-1:
//     TrendBadge w-16 h-5
//     Text "vs last month" text-xs text-muted
```

## 4. `mod.zig` exports

```zig
pub const badge     = @import("badge.zig");
pub const button    = @import("button.zig");
pub const card      = @import("card.zig");
pub const input_f   = @import("input_field.zig");
pub const label     = @import("label.zig");
pub const separator = @import("separator.zig");
pub const stat_card = @import("stat_card.zig");
pub const select    = @import("select.zig");
```

## 5. Demo screen: `src/demo/screens/components.zig`

A new "Components" screen (Screen 13, sidebar button "Components") that shows a
shadcn-equivalent component gallery. Sections:

1. **Typography** — heading sizes, body, muted, disabled, code style
2. **Buttons** — primary, outline, ghost, destructive (in a Row)
3. **Badges** — all variants in a Row
4. **Form controls** — InputField + Checkbox + Radio group + Slider + Dropdown
5. **Cards** — default card with header/content, stat card
6. **Separators** — horizontal

## 6. Acceptance criteria

- `zig build` exits 0.
- All component functions compile and return valid NodeDesc values.
- Components screen is accessible via sidebar button 13.
- Visual test: Components screen screenshot shows clean zinc-palette widgets.
