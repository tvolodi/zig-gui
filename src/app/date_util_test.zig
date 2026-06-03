//! R78 — Gregorian calendar helpers unit tests.
//! All tests are deterministic; no allocator, no GPU, no GLFW required.

const std = @import("std");
const testing = std.testing;
const date_util = @import("date_util.zig");
const DateValue = date_util.DateValue;

// ---------------------------------------------------------------------------
// daysInMonth
// ---------------------------------------------------------------------------

test "daysInMonth: leap year February has 29 days" {
    try testing.expectEqual(@as(u8, 29), date_util.daysInMonth(2024, 2));
}

test "daysInMonth: non-leap year February has 28 days" {
    try testing.expectEqual(@as(u8, 28), date_util.daysInMonth(2023, 2));
}

test "daysInMonth: century year (not 400) is not a leap year" {
    try testing.expectEqual(@as(u8, 28), date_util.daysInMonth(1900, 2));
}

test "daysInMonth: 400-multiple century year is a leap year" {
    try testing.expectEqual(@as(u8, 29), date_util.daysInMonth(2000, 2));
}

test "daysInMonth: January has 31 days" {
    try testing.expectEqual(@as(u8, 31), date_util.daysInMonth(2024, 1));
}

test "daysInMonth: April has 30 days" {
    try testing.expectEqual(@as(u8, 30), date_util.daysInMonth(2024, 4));
}

test "daysInMonth: all 31-day months return 31" {
    for ([_]u8{ 1, 3, 5, 7, 8, 10, 12 }) |m| {
        try testing.expectEqual(@as(u8, 31), date_util.daysInMonth(2024, m));
    }
}

test "daysInMonth: all 30-day months return 30" {
    for ([_]u8{ 4, 6, 9, 11 }) |m| {
        try testing.expectEqual(@as(u8, 30), date_util.daysInMonth(2024, m));
    }
}

// ---------------------------------------------------------------------------
// firstWeekday
// ---------------------------------------------------------------------------

// Jan 1, 2024 is a Monday (weekday 1 in 0=Sunday scheme).
test "firstWeekday: Jan 1 2024 is Monday (1)" {
    try testing.expectEqual(@as(u8, 1), date_util.firstWeekday(2024, 1));
}

// Mar 1, 2024 is a Friday (weekday 5 in 0=Sunday scheme).
test "firstWeekday: Mar 1 2024 is Friday (5)" {
    try testing.expectEqual(@as(u8, 5), date_util.firstWeekday(2024, 3));
}

// Jan 1, 2023 is a Sunday (weekday 0).
test "firstWeekday: Jan 1 2023 is Sunday (0)" {
    try testing.expectEqual(@as(u8, 0), date_util.firstWeekday(2023, 1));
}

// Result is always in [0, 6].
test "firstWeekday: result always in 0..6" {
    const months = [_]u8{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12 };
    for (months) |m| {
        const wd = date_util.firstWeekday(2024, m);
        try testing.expect(wd <= 6);
    }
}

// ---------------------------------------------------------------------------
// formatDate
// ---------------------------------------------------------------------------

test "formatDate: formats 2024-03-15 correctly" {
    var buf: [10]u8 = undefined;
    const result = date_util.formatDate(DateValue{ .year = 2024, .month = 3, .day = 15 }, &buf);
    try testing.expectEqualSlices(u8, "2024-03-15", result);
}

test "formatDate: zero-pads single-digit month and day" {
    var buf: [10]u8 = undefined;
    const result = date_util.formatDate(DateValue{ .year = 2025, .month = 1, .day = 5 }, &buf);
    try testing.expectEqualSlices(u8, "2025-01-05", result);
}

test "formatDate: returns exactly 10 characters" {
    var buf: [10]u8 = undefined;
    const result = date_util.formatDate(DateValue{ .year = 2000, .month = 12, .day = 31 }, &buf);
    try testing.expectEqual(@as(usize, 10), result.len);
}

// ---------------------------------------------------------------------------
// parseDate
// ---------------------------------------------------------------------------

test "parseDate: parses valid date 2024-03-15" {
    const v = date_util.parseDate("2024-03-15");
    try testing.expect(v != null);
    try testing.expectEqual(@as(u16, 2024), v.?.year);
    try testing.expectEqual(@as(u8, 3), v.?.month);
    try testing.expectEqual(@as(u8, 15), v.?.day);
}

test "parseDate: returns null for invalid string" {
    try testing.expect(date_util.parseDate("invalid") == null);
}

test "parseDate: returns null for wrong separator" {
    try testing.expect(date_util.parseDate("2024/03/15") == null);
}

test "parseDate: returns null for too-short string" {
    try testing.expect(date_util.parseDate("2024-03") == null);
}

test "parseDate: returns null for too-long string" {
    try testing.expect(date_util.parseDate("2024-03-15X") == null);
}

test "parseDate: returns null for invalid month 0" {
    try testing.expect(date_util.parseDate("2024-00-15") == null);
}

test "parseDate: returns null for invalid month 13" {
    try testing.expect(date_util.parseDate("2024-13-01") == null);
}

test "parseDate: returns null for invalid day 0" {
    try testing.expect(date_util.parseDate("2024-03-00") == null);
}

// Note: day=30 for Feb-2024 is accepted by parseDate (range check is 1–31 only).
// More precise calendar validation (e.g. Feb 30) is the caller's responsibility.
// We verify days above 31 are rejected:
test "parseDate: returns null for day > 31" {
    try testing.expect(date_util.parseDate("2024-03-32") == null);
}

test "parseDate: round-trip with formatDate" {
    const original = DateValue{ .year = 2025, .month = 7, .day = 4 };
    var buf: [10]u8 = undefined;
    const formatted = date_util.formatDate(original, &buf);
    const parsed = date_util.parseDate(formatted);
    try testing.expect(parsed != null);
    try testing.expectEqual(original.year, parsed.?.year);
    try testing.expectEqual(original.month, parsed.?.month);
    try testing.expectEqual(original.day, parsed.?.day);
}

test "parseDate: empty string returns null" {
    try testing.expect(date_util.parseDate("") == null);
}

test "parseDate: non-numeric digits return null" {
    try testing.expect(date_util.parseDate("YYYY-MM-DD") == null);
}
