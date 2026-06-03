# R50 — M5-01: Inline style attributes

> Roadmap item: M5-01  
> Depends on: module 06 (markup parser, `NodeDesc`, `Attr`), module 07 (`Scene.instantiate`)  
> Read `00_constitution.md` before this file.

## Purpose

Allow markup nodes to carry `style:*` attributes that override individual `ComputedStyle`
fields after class resolution. This is the escape hatch for dynamic content where a value
is not representable as a Tailwind class — e.g. a color computed at runtime, or a font
size from application data. Inline styles do not change the reactivity model: the attribute
value is a literal string (or a `{bind ...}` path that resolves at signal-refresh time).

## What to build

### Markup syntax

`style:*` attributes follow the same grammar as other attributes:

```
<Text style:color="#1DA1F2" text="Tweet" />
<Card style:background="{bind card.bg_color}" />
<Button style:radius="12" class="px-4 py-2" />
```

The parser already stores all non-`class` attributes in `NodeDesc.attrs`. No parser changes
are needed — the `style:` prefix is the namespacing convention and is interpreted entirely
by the instantiator (module 07).

### Supported inline style properties

Only the properties that correspond to fields of `ComputedStyle` are supported:

| Attribute name | `ComputedStyle` field | Value format |
|---|---|---|
| `style:background` | `background` | `#RRGGBB` or `#RRGGBBAA` hex string |
| `style:color` | `text_color` | `#RRGGBB` or `#RRGGBBAA` hex string |
| `style:border-color` | `border_color` | `#RRGGBB` or `#RRGGBBAA` hex string |
| `style:border-width` | `border_width` | Decimal float in pixels, e.g. `"2"` or `"1.5"` |
| `style:radius` | `radius` | Decimal float in pixels |
| `style:font-size` | `font_size` | Decimal float in pixels |
| `style:opacity` | `opacity` | Float `0.0`–`1.0`, e.g. `"0.5"` |
| `style:shadow-blur` | `shadow_blur` | Decimal float in pixels |

Unknown `style:*` attribute names are ignored (no error, consistent with unknown class
behavior). Malformed values (e.g. `style:radius="abc"`) are ignored; the class-derived
value (or the default) remains.

### Color parsing helper

Add to `src/06/types.zig` (or a shared util file):

```zig
/// Parse a #RRGGBB or #RRGGBBAA hex color string.
/// Returns null if the string is not a valid hex color.
pub fn parseHexColor(s: []const u8) ?theme.Color {
    if (s.len == 0 or s[0] != '#') return null;
    const digits = s[1..];
    switch (digits.len) {
        6 => {
            const rgb = std.fmt.parseInt(u24, digits, 16) catch return null;
            return theme.Color.hex(rgb);
        },
        8 => {
            const rgba = std.fmt.parseInt(u32, digits, 16) catch return null;
            return theme.Color{
                .r = @intCast((rgba >> 24) & 0xFF),
                .g = @intCast((rgba >> 16) & 0xFF),
                .b = @intCast((rgba >> 8)  & 0xFF),
                .a = @intCast(rgba & 0xFF),
            };
        },
        else => return null,
    }
}
```

### Float parsing helper

Add to the same file:

```zig
/// Parse a decimal float string (e.g. "12", "1.5"). Returns null on failure.
pub fn parseFloat(s: []const u8) ?f32 {
    return std.fmt.parseFloat(f32, s) catch null;
}
```

### Integration in `Scene.instantiate`

After class resolution and before storing the final `ComputedStyle`, scan the node's
`attrs` slice for any attribute whose `name` starts with `"style:"`. For each, parse the
value and apply it as a direct field write on the resolved `ComputedStyle`:

```zig
// In Scene.instantiate, after resolving the class-derived style:
var final_style = layered_style;  // already merged: base defaults + class overrides

for (desc.attrs) |attr| {
    if (!std.mem.startsWith(u8, attr.name, "style:")) continue;
    const prop = attr.name[6..];  // e.g. "background", "color", "radius"
    const raw_value: []const u8 = switch (attr.value) {
        .literal => |s| s,
        .bind    => |_| continue,  // bind paths are not evaluated during instantiate; skip
    };
    applyInlineStyle(prop, raw_value, &final_style);
}

// Store final_style as the element's ComputedStyle.
```

The `bind` case is skipped during `instantiate` because binding resolution happens at
refresh time (M2-04 / M5-03). A separate binding path is needed for inline style binds —
that is out of scope for M5-01; see Open questions.

```zig
fn applyInlineStyle(prop: []const u8, value: []const u8, style: *ComputedStyle) void {
    const eql = std.mem.eql;
    if (eql(u8, prop, "background")) {
        if (parseHexColor(value)) |c| style.background = c;
    } else if (eql(u8, prop, "color")) {
        if (parseHexColor(value)) |c| style.text_color = c;
    } else if (eql(u8, prop, "border-color")) {
        if (parseHexColor(value)) |c| style.border_color = c;
    } else if (eql(u8, prop, "border-width")) {
        if (parseFloat(value)) |v| style.border_width = v;
    } else if (eql(u8, prop, "radius")) {
        if (parseFloat(value)) |v| style.radius = v;
    } else if (eql(u8, prop, "font-size")) {
        if (parseFloat(value)) |v| style.font_size = v;
    } else if (eql(u8, prop, "opacity")) {
        if (parseFloat(value)) |v| style.opacity = std.math.clamp(v, 0.0, 1.0);
    } else if (eql(u8, prop, "shadow-blur")) {
        if (parseFloat(value)) |v| style.shadow_blur = v;
    }
    // Unknown property: silently ignore.
}
```

### Override precedence

Inline style attributes have **higher precedence than class-derived values** and **lower
precedence than pseudo-state overrides (M4-01)**. The resolution order is:

```
per-kind default < class override < inline style:* < pseudo-state override (M4-01)
```

This matches web-familiar expectations (inline style beats class but loses to `:hover`).

### `{bind ...}` inline styles — deferred to M5-03

When `attr.value` is `.bind`, the inline style cannot be applied during `instantiate`
because the signal value is not yet known. Reactive inline styles require the binding
system (M2-04) to be extended. This is out of scope for M5-01. The `bind` case is silently
skipped; the class-derived (or default) value remains. A future item (`bindStyle`) can
wire this up.

### Module location

```
src/06/types.zig          — parseHexColor, parseFloat helpers (or a new src/06/util.zig)
src/07/types.zig          — applyInlineStyle called inside Scene.instantiate
docs/specs/06.types.zig   — parseHexColor, parseFloat exported
docs/requirements/R50_inline_style_attributes.md
```

No changes to the markup parser or `NodeDesc` — `style:*` attributes are already captured
in `NodeDesc.attrs` as regular `Attr` entries.

## Public API

New in module 06:

```zig
pub fn parseHexColor(s: []const u8) ?Color
pub fn parseFloat(s: []const u8) ?f32
```

Internal to module 07 (not exported):

```zig
fn applyInlineStyle(prop: []const u8, value: []const u8, style: *ComputedStyle) void
```

## Non-goals (DO NOT implement — INV-5.4)

- **No `style:padding-*` / `style:gap`** — padding and gap are already covered by Tailwind
  spacing classes; inline overrides for them are post-v1.
- **No `style:width` / `style:height`** — layout dimensions are not in `ComputedStyle`
  (they live in `LayoutNode`). Inline layout overrides are post-v1.
- **No reactive inline styles** — `style:color="{bind ...}"` is parsed but silently skipped
  during instantiate; binding-time application is post-M5-01.
- **No shorthand properties** — no `style:border="1px solid #ccc"` parsing; only the flat
  property names listed in the table above.
- **No CSS `calc()` or `var()`** — values are plain numbers or hex colors; no expressions.
- **No named color strings** (`"red"`, `"blue"`) — hex notation only.
- **No `style:display` / `style:flex-*`** — layout properties live on `LayoutNode`, not
  `ComputedStyle`. Inline layout overrides are out of scope.

## Acceptance criteria

1. `zig build test-07` (or `test-scene`) passes. New test cases:
   - A node with `style:background="#FF0000"` produces a `ComputedStyle.background` of
     `{255, 0, 0, 255}`.
   - A node with `style:opacity="0.5"` produces `ComputedStyle.opacity = 0.5`.
   - A node with an unknown `style:foo="bar"` attribute is ignored; style is unchanged.
   - A node with a malformed value `style:radius="abc"` is ignored; radius retains the
     class-derived value.
   - A node with `style:background="{bind ...}"` does not crash; background retains the
     class-derived value.
   - Inline style overrides the class value: `class="bg-canvas" style:background="#AABBCC"`
     produces `#AABBCC` background (not `bg_canvas` from tokens).

2. `parseHexColor` unit tests (in `src/06/` test file):
   - `"#FF0000"` → `Color{255, 0, 0, 255}`.
   - `"#FF000080"` → `Color{255, 0, 0, 128}`.
   - `""`, `"red"`, `"FF0000"`, `"#GGGGGG"` → `null`.

3. `parseFloat` unit tests:
   - `"12"` → `12.0`, `"1.5"` → `1.5`, `"abc"` → `null`, `""` → `null`.

4. No allocation in `applyInlineStyle` or the inline-style scan loop.

5. Checklist fully ticked.

## Open questions

One: reactive inline styles (`style:color="{bind ...}"`). In v1 this is silently skipped.
If the user later needs per-element reactive colors, a `bindStyle` entry in `BindingSet`
(analogous to `bindText`) is the correct mechanism. Surface this to the human when the need
arises rather than pre-implementing it now (INV-1.1).
