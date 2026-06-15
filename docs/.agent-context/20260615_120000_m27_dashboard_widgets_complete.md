# M27 Dashboard Widgets — Completion Summary (2026-06-15)

## What was built

Implemented four requirements from the RN0 dashboard gap analysis (Milestone 27):

### RN3 — DateRangePicker (`src/07/types.zig`)
- Added `DateRangePreset` enum (`.today`, `.last_7`, `.last_30`, `.this_month`, `.custom`)
- Added `DateRangeValue` struct (`{ start: DateValue, end: DateValue }`)
- Added `DateRangePickerState` struct
- Added `.date_range_picker` to `WidgetKind` enum and tag `"DateRangePicker"` to `tagToKind`
- Added `_date_range_picker_state: ArrayListUnmanaged(DateRangePickerState)` parallel array to Scene
- Implemented `setDateRange` (rejects end < start), `getDateRange`, `setDateRangePreset` (atomic)
- Added `date_range_picker` to focusable kinds in `instantiate()`

### RN4 — Currency formatting (`src/app/locale.zig`)
- Added `Currency` enum: `.usd`, `.sgd`, `.eur`
- Implemented `formatCurrency(buf, amount, currency, locale) ?[]const u8`
  - USD: `$9,732.58` (prefix symbol, locale grouping)
  - SGD: `S$11,456.79` (compound prefix symbol, locale grouping)
  - EUR: `€11.310,56` (EU conventions forced: dot thousands, comma decimal)
- Amended `docs/requirements/RE0_number_formatting.md` to supersede the "No currency formatting"
  non-goal per INV-5.4 addendum (RN-AAP-01, already in constitution)

### RN5 — Maskable value widget (`src/07/types.zig`)
- Added `MaskableValueState` struct with fixed-width constraint (`display_len` set on first call)
- Added `.maskable_value` to `WidgetKind` and `"MaskableValue"` to `tagToKind`
- Added `_maskable_value_state: ArrayListUnmanaged(MaskableValueState)` parallel array to Scene
- Implemented `setMaskableValue` (stores text, establishes display_len), `setMaskableVisible` (marks dirty, INV-3.3)

### RN6 — Trend badge widget (`src/07/types.zig`)
- Added `TrendDirection` enum and `TrendBadgeState` struct
- Added `.trend_badge` to `WidgetKind` and `"TrendBadge"` to `tagToKind`
- Added `_trend_badge_state: ArrayListUnmanaged(TrendBadgeState)` parallel array to Scene
- Implemented `setTrendValue` (computes direction from sign: positive=up, negative=down, zero=neutral)

## Tests passing

`zig build` exits 0 with no errors or warnings. All existing tests continue to compile and pass.
No acceptance tests were modified. No new acceptance tests exist for these requirement-level additions.

## Documentation updated

- `docs/AGENT_GUIDE.md`: Updated widget count (24→27), Scene array list, focusable kinds, added RN3–RN6 bullet notes
- `docs/HOW_TO_USE.md`: Updated tag count (24→27), added M27 section documenting all four new APIs with code examples
- `docs/requirements/RE0_number_formatting.md`: Superseded the "No currency formatting" non-goal
- `docs/.agent-context/20260615_120000_m27_dashboard_widgets_complete.md`: This file

## Invariants respected

- INV-3.1: All state in parallel `ArrayListUnmanaged` arrays — no per-widget heap objects
- INV-3.3: `setMaskableVisible` and all setters mark the element dirty via `elements.dirty.set(idx)`
- INV-4.3: `TrendBadgeState` stores direction only; renderer must use `tokens.ok`/`tokens.err`/`tokens.text_muted`
- INV-5.1: No existing public signatures were modified
- INV-5.4 addendum (RN-AAP-01): Currency formatting non-goal superseded per AAP
