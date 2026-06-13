# RE1 — M15-02: Date / time formatting

> Roadmap item: M15-02
> Depends on: M7-09 (DateValue, date_util.zig), M15-01 (Locale)
> Read `00_constitution.md` before this file.

## Purpose

Provide locale-aware date and time formatting for displaying dates in the UI. Builds on the
existing `DateValue` type and `date_util.zig` helper from R78 (Date picker). The formatter
accepts a `Locale` (from M15-01) and produces strings in the day-month-year order and with
the separators appropriate to that locale.

## What to build

### Extend `Locale` in `src/app/locale.zig`

Add date-formatting fields:

```zig
pub const DateOrder = enum {
    /// month/day/year — en-US
    mdy,
    /// day/month/year — de-DE, fr-FR, ru-RU
    dmy,
    /// year/month/day — ISO-8601, some East Asian conventions
    ymd,
};

pub const Locale = struct {
    // ...existing number-formatting fields...
    thousands_sep: u8 = ',',
    decimal_sep: u8 = '.',
    grouping: u8 = 3,

    // NEW: date-formatting fields.
    /// Order of day, month, year components.
    date_order: DateOrder = .mdy,
    /// Separator between date components (e.g. '/' for en-US, '.' for de-DE, '-' for ISO).
    date_sep: u8 = '/',
    /// Names of months (genitive or nominative form). First element is padding (index 0 unused).
    /// Index 1 = January, ... index 12 = December.
    month_names: [13][]const u8 = .{
        "", "January", "February", "March", "April", "May", "June",
        "July", "August", "September", "October", "November", "December",
    },
    /// Abbreviated month names (3-letter). Same 1-based indexing.
    month_names_short: [13][]const u8 = .{
        "", "Jan", "Feb", "Mar", "Apr", "May", "Jun",
        "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
    },
};
```

### Update built-in locale constants

```zig
pub const en_US = Locale{
    .date_order = .mdy,
    .date_sep = '/',
};
pub const de_DE = Locale{
    .thousands_sep = '.',
    .decimal_sep = ',',
    .date_order = .dmy,
    .date_sep = '.',
    .month_names = .{ "", "Januar", "Februar", "März", "April", "Mai", "Juni",
                      "Juli", "August", "September", "Oktober", "November", "Dezember" },
    .month_names_short = .{ "", "Jan", "Feb", "Mär", "Apr", "Mai", "Jun",
                            "Jul", "Aug", "Sep", "Okt", "Nov", "Dez" },
};
pub const fr_FR = Locale{
    .thousands_sep = ' ',
    .decimal_sep = ',',
    .date_order = .dmy,
    .date_sep = '/',
    .month_names = .{ "", "janvier", "février", "mars", "avril", "mai", "juin",
                      "juillet", "août", "septembre", "octobre", "novembre", "décembre" },
    .month_names_short = .{ "", "janv.", "févr.", "mars", "avr.", "mai", "juin",
                            "juil.", "août", "sept.", "oct.", "nov.", "déc." },
};
pub const ru_RU = Locale{
    .thousands_sep = ' ',
    .decimal_sep = ',',
    .date_order = .dmy,
    .date_sep = '.',
    .month_names = .{ "", "января", "февраля", "марта", "апреля", "мая", "июня",
                      "июля", "августа", "сентября", "октября", "ноября", "декабря" },
    .month_names_short = .{ "", "янв", "фев", "мар", "апр", "май", "июн",
                            "июл", "авг", "сен", "окт", "ноя", "дек" },
};
```

### FormatDate

```zig
/// Format a DateValue into buf with the given locale's conventions.
/// Returns the written slice, or null if buf is too small (max needed is ~64 bytes for long names).
pub fn formatDate(buf: []u8, dv: DateValue, locale: Locale) ?[]const u8;
```

Behavior:
- When `dv.year == 0` (unset), returns `""` (empty string).
- Produces a date string according to `locale.date_order` and `locale.date_sep`:
  - `.mdy`: `month date_sep day date_sep year` — e.g. `"3/15/2024"` (en-US)
  - `.dmy`: `day date_sep month date_sep year` — e.g. `"15.3.2024"` (de-DE)
  - `.ymd`: `year date_sep month date_sep day` — e.g. `"2024/3/15"` (ISO-like)
- Month and day are written as plain integers (no zero-padding needed, matching common
  European conventions). For ISO-format (ymd), optionally zero-pad month/day?

Design decision: For v1, keep it simple — numeric components, not zero-padded:
- en-US: `3/15/2024`
- de-DE: `15.3.2024`
- fr-FR: `15/3/2024`
- ru-RU: `15.3.2024`

```zig
/// Format a DateValue into buf with full month name, locale-aware.
/// e.g. "March 15, 2024" (en-US), "15. März 2024" (de-DE)
/// Returns the written slice, or null if buf is too small.
pub fn formatDateLong(buf: []u8, dv: DateValue, locale: Locale) ?[]const u8;

/// Format a DateValue into buf with abbreviated month name, locale-aware.
/// e.g. "Mar 15, 2024" (en-US), "15. Mär 2024" (de-DE)
pub fn formatDateShort(buf: []u8, dv: DateValue, locale: Locale) ?[]const u8;
```

`formatDateLong` and `formatDateShort` use `locale.month_names[m]` and
`locale.month_names_short[m]` respectively. The format follows the date order:
- `.mdy`: `month_name day, year` — e.g. `"March 15, 2024"`
- `.dmy`: `day. month_name year` — e.g. `"15. März 2024"`
- `.ymd`: `year month_name day` — e.g. `"2024 March 15"`

### DateValue now needs year==0 detection

`DateValue` in `src/07/types.zig` already has `year: u16 = 0, month: u8 = 1, day: u8 = 1`.
`year == 0` is an intentional "unset" sentinel. No change needed.

### Module location

```
src/app/locale.zig       — added DateOrder, date fields on Locale, formatDate, formatDateLong, formatDateShort
src/app/locale_test.zig  — expanded unit tests for date formatting
```

## Non-goals (DO NOT implement — INV-5.4)

- **No time formatting** — hours/minutes/seconds/AM-PM are post-v1.
- **No timezone handling** — all dates are timezone-naive.
- **No relative dates** — "yesterday", "2 days ago" are post-v1.
- **No calendar systems beyond Gregorian** — the existing `date_util.zig` is Gregorian-only.
- **No automatic locale detection** — the locale is explicitly passed by the caller.
- **No `strftime`-style format strings** — only the three built-in patterns (mdy/dmy/ymd).

## Acceptance criteria

1. `formatDate(buf, DateValue{2024,3,15}, Locale.en_US)` returns `"3/15/2024"`.
2. `formatDate(buf, DateValue{2024,3,15}, Locale.de_DE)` returns `"15.3.2024"`.
3. `formatDate(buf, DateValue{2024,3,15}, Locale.fr_FR)` returns `"15/3/2024"`.
4. `formatDate(buf, DateValue{0,1,1}, Locale.en_US)` returns `""` (unset date).
5. `formatDateLong(buf, DateValue{2024,3,15}, Locale.en_US)` returns `"March 15, 2024"`.
6. `formatDateLong(buf, DateValue{2024,3,15}, Locale.de_DE)` returns `"15. März 2024"`.
7. `formatDateShort(buf, DateValue{2024,3,15}, Locale.en_US)` returns `"Mar 15, 2024"`.
8. `formatDateShort(buf, DateValue{2024,3,15}, Locale.de_DE)` returns `"15. Mär 2024"`.
9. All three variants return `null` when `buf` is too small.
