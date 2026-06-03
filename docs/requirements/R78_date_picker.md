# R78 — M7-09: Date picker

> Roadmap item: M7-09  
> Depends on: M3-03 (text input — `InputState`), R75 (modal dialog — `DialogManager`), M4-01 (pseudo-state)  
> Read `00_constitution.md` before this file.

## Purpose

A `<DatePicker>` widget shows a text input displaying the selected date (ISO-8601 format
`YYYY-MM-DD`) and an icon button that opens a calendar grid in a modal dialog. The user
navigates months with arrow buttons and selects a day by clicking. The selected date is
stored as three `u16` fields (`year`, `month`, `day`).

## What to build

### Widget kind and state

```zig
pub const WidgetKind = enum { /* ...existing... */ date_picker };

// tagToKind: "DatePicker" → .date_picker
// defaultLayoutFor: .date_picker → { .display = .flex, .direction = .row, .align_items = .center }

pub const DateValue = struct {
    year:  u16 = 0,   // 0 = unset
    month: u8  = 1,   // 1–12
    day:   u8  = 1,   // 1–31
};

pub const DatePickerState = struct {
    value:       DateValue = .{},
    nav_year:    u16 = 2025,  // currently displayed month/year in the calendar
    nav_month:   u8  = 1,
    open:        bool = false,
    disabled:    bool = false,
};

pub const Scene = struct {
    _date_picker_state: std.ArrayListUnmanaged(DatePickerState) = .empty,

    pub fn datePickerStateOf(self: *Scene, idx: u32) *DatePickerState

    /// Set the date value and update the display text in the associated input.
    pub fn setDateValue(self: *Scene, idx: u32, value: DateValue) void

    pub fn getDateValue(self: *Scene, idx: u32) DateValue
};
```

### Calendar grid (modal content)

When the calendar icon is clicked, the dialog opens with a pre-instantiated calendar grid
subtree. The grid consists of:

1. A navigation row: `<` (prev month), `Month Year` text, `>` (next month).
2. A row of day-of-week headers: `Mo Tu We Th Fr Sa Su`.
3. A 6×7 grid of day buttons (some empty for days before the 1st).

The calendar content is a `NodeDesc` subtree that the `DatePicker` widget instantiates
into the scene's calendar sub-arena the first time the picker is opened. Day buttons use
the existing `ButtonState` mechanism; their `CallbackFn` calls `setDateValue`.

### Gregorian helpers

Add `src/app/date_util.zig`:

```zig
/// Return the number of days in `month` (1–12) of `year`.
pub fn daysInMonth(year: u16, month: u8) u8

/// Return the day-of-week of the first day of `month`/`year`.
/// 0 = Monday … 6 = Sunday (ISO week convention).
pub fn firstWeekday(year: u16, month: u8) u8

/// Format `v` as "YYYY-MM-DD" into `buf[0..10]`. Returns the slice.
pub fn formatDate(v: DateValue, buf: *[10]u8) []const u8

/// Parse "YYYY-MM-DD" from `s`. Returns null if malformed.
pub fn parseDate(s: []const u8) ?DateValue
```

`daysInMonth` handles leap years (Gregorian: divisible by 4, except centuries unless
divisible by 400).

### Display text

After `setDateValue`, the text shown in the input field is updated:

```zig
pub fn setDateValue(self: *Scene, idx: u32, value: DateValue) void {
    self.datePickerStateOf(idx).value = value;
    if (value.year != 0) {
        var buf: [10]u8 = undefined;
        const s = date_util.formatDate(value, &buf);
        self.setInputText(idx, s) catch {};
    } else {
        self.setInputText(idx, "") catch {};
    }
    self.closeCalendar(idx);
    self.elements.dirty.set(idx);
}
```

### Keyboard input

The user can also type directly into the text field. On Tab-away or Enter, the text is
parsed:

```zig
const parsed = date_util.parseDate(scene.getInputText(idx));
if (parsed) |d| {
    scene.datePickerStateOf(idx).value = d;
} else {
    // Revert to previous date value (don't corrupt state with garbage input).
    scene.setDateValue(idx, current_value);
}
```

### Navigation buttons

`<` and `>` buttons in the calendar header decrement/increment `nav_month`, wrapping year:

```zig
fn prevMonth(state: *DatePickerState) void {
    if (state.nav_month == 1) { state.nav_month = 12; state.nav_year -|= 1; }
    else state.nav_month -= 1;
}
fn nextMonth(state: *DatePickerState) void {
    if (state.nav_month == 12) { state.nav_month = 1; state.nav_year +|= 1; }
    else state.nav_month += 1;
}
```

Clicking a day cell calls `setDateValue` and closes the calendar.

### Module location

```
src/app/date_util.zig          — daysInMonth, firstWeekday, formatDate, parseDate
src/07/types.zig               — WidgetKind.date_picker, DateValue, DatePickerState
src/app/app.zig                — calendar open/close integration (reuses DialogManager)
docs/requirements/R78_date_picker.md
```

## Non-goals (DO NOT implement — INV-5.4)

- **No `<TimePicker>`** — date only in v1.
- **No date range selection** — single date.
- **No locale-aware month/day names** — hardcoded English (INV-1.3).
- **No min/max date constraint** — any valid Gregorian date.
- **No date-change callbacks** — INV-3.3; read via `getDateValue`.
- **No animated month transition** — instant swap.

## Acceptance criteria

1. Unit tests: `daysInMonth(2024, 2) == 29` (leap). `daysInMonth(1900, 2) == 28` (century).
   `firstWeekday(2025, 1)` returns correct weekday. `formatDate`/`parseDate` round-trip.
2. Integration: open date picker, navigate months, click a day, see the input display update.
   Type a date manually and Tab away — value parsed and displayed. Checklist ticked.
