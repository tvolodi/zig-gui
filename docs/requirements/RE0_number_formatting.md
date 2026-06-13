# RE0 — M15-01: Number formatting

> Roadmap item: M15-01
> Depends on: nothing new — standalone utility
> Read `00_constitution.md` before this file.

## Purpose

Provide locale-aware number formatting helpers for internationalized UI content.
`formatInt(n, locale)` and `formatFloat(n, locale)` produce strings with the correct
thousands separator, decimal separator, and grouping rules for a given locale config.

## Locale config

A small, compile-time-constructable struct that captures the formatting rules for one locale:

```zig
pub const Locale = struct {
    /// Thousands separator character (e.g. ',' for en-US, ' ' or '.' for many European locales).
    thousands_sep: u8 = ',',
    /// Decimal separator character (e.g. '.' for en-US, ',' for many European locales).
    decimal_sep: u8 = '.',
    /// Number of digits between thousands separators. Typically 3 for most locales.
    /// Some locales use 2 (e.g. for certain Indian numbering groups), but 3 is the v1 default.
    grouping: u8 = 3,
};
```

Four built-in locale constants:

```zig
pub const Locale = struct {
    /// en-US: 1,234.56
    pub const en_US: Locale = .{};
    /// de-DE: 1.234,56
    pub const de_DE: Locale = .{ .thousands_sep = '.', .decimal_sep = ',' };
    /// fr-FR: 1 234,56 (non-breaking space as thousands separator)
    pub const fr_FR: Locale = .{ .thousands_sep = ' ', .decimal_sep = ',' };
    /// ru-RU: 1 234,56
    pub const ru_RU: Locale = .{ .thousands_sep = ' ', .decimal_sep = ',' };
};
```

## FormatInt

```zig
/// Format an integer with locale-aware thousands separators.
/// Writes to buf and returns the slice used. Returns null if buf is too small.
pub fn formatInt(buf: []u8, n: anytype, locale: Locale) ?[]const u8;
```

Behavior:
- Takes any signed or unsigned integer type (comptime `anytype`).
- Formats the absolute value of `n` in decimal.
- Inserts `locale.thousands_sep` every `locale.grouping` digits from the right.
- Prepends `'-'` when `n < 0`.
- Returns the written slice, or `null` if `buf` is too small (including for the negative sign).

### Examples

| Input | Locale | Output |
|---|---|---|
| `formatInt(buf, 42, en_US)` | en-US | `"42"` |
| `formatInt(buf, 1234, en_US)` | en-US | `"1,234"` |
| `formatInt(buf, -1000, de_DE)` | de-DE | `"-1.000"` |
| `formatInt(buf, 1234567, en_US)` | en-US | `"1,234,567"` |
| `formatInt(buf, 0, en_US)` | en-US | `"0"` |

### Edge cases

| Input | Output | Reason |
|---|---|---|
| `formatInt(buf, -1, en_US)` | `"-1"` | Negative sign |
| `formatInt(buf, std.math.minInt(i32), en_US)` | correct negated value | Max negative fits in buffer |
| Buffer too small | `null` | No partial writes |

## FormatFloat

```zig
/// Format a float with locale-aware decimal separator.
/// Writes to buf and returns the slice used. Returns null if buf is too small.
pub fn formatFloat(buf: []u8, n: anytype, locale: Locale) ?[]const u8;
```

Behavior:
- Takes `f16`, `f32`, or `f64`.
- Uses Zig's `std.fmt.formatFloat` internally to produce the shortest round-trip representation.
- Replaces `'.'` in the Zig output with `locale.decimal_sep`.
- Does NOT add thousands separators by default (Zig's float formatting doesn't support them easily).
  This is a v1 limitation.
- Returns `"0"` for `-0.0`.
- Returns `null` for NaN and inf (not representable with locale-aware formatting).

### Examples

| Input | Locale | Output |
|---|---|---|
| `formatFloat(buf, 3.14, en_US)` | en-US | `"3.14"` |
| `formatFloat(buf, 3.14, de_DE)` | de-DE | `"3,14"` |
| `formatFloat(buf, 1000.0, en_US)` | en-US | `"1000"` |
| `formatFloat(buf, -0.5, en_US)` | en-US | `"-0.5"` |

### Module location

```
src/app/locale.zig       — Locale, en_US, de_DE, fr_FR, ru_RU, formatInt, formatFloat
src/app/locale_test.zig  — unit tests
build.zig                — test-locale step (if not rolled into test-app)
```

## Non-goals (DO NOT implement — INV-5.4)

- **No currency formatting** — symbol placement, ISO 4217 codes, and rounding are post-v1.
- **No percentage formatting** — `"12%"` is trivial; locale-aware `"12 %"` (fr-FR) is post-v1.
- **No ordinal formatting** — `"1st"`, `"2nd"` etc. are language-specific and post-v1.
- **No compact/short formatting** — `"1.2K"` is post-v1.
- **No Unicode CLDR data** — locale constants are hand-authored for v1.
- **No thousands separators in `formatFloat`** — the standard Zig float-to-string path produces
  the shortest representation; adding thousands separators to the fractional side would require
  custom formatting and is post-v1.

## Acceptance criteria

1. `formatInt(buf, 42, Locale.en_US)` returns `"42"`.
2. `formatInt(buf, 1234, Locale.en_US)` returns `"1,234"`.
3. `formatInt(buf, 1234567, Locale.en_US)` returns `"1,234,567"`.
4. `formatInt(buf, -1000, Locale.de_DE)` returns `"-1.000"`.
5. `formatInt(buf, 0, Locale.en_US)` returns `"0"`.
6. `formatInt` returns `null` when `buf` is too small.
7. `formatFloat(buf, 3.14, Locale.en_US)` returns `"3.14"`.
8. `formatFloat(buf, 3.14, Locale.de_DE)` returns `"3,14"`.
9. `formatFloat(buf, -0.5, Locale.en_US)` returns `"-0.5"`.
10. `formatFloat` returns `null` for NaN and inf.
11. All built-in locale constants have distinct values.
