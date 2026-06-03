//! R78 — Gregorian calendar helpers for the date picker widget.
//!
//! Public API for the app layer. DateValue is re-exported from module 07.

const std = @import("std");
const comp_mod = @import("../07/types.zig");

pub const DateValue = comp_mod.DateValue;

/// Return the number of days in `month` (1–12) of `year`.
/// Handles Gregorian leap years: divisible by 4, except centuries unless divisible by 400.
pub fn daysInMonth(year: u16, month: u8) u8 {
    return switch (month) {
        1, 3, 5, 7, 8, 10, 12 => 31,
        4, 6, 9, 11 => 30,
        2 => if (isLeapYear(year)) 29 else 28,
        else => 30,
    };
}

fn isLeapYear(year: u16) bool {
    return (year % 4 == 0 and year % 100 != 0) or (year % 400 == 0);
}

/// Return the day-of-week of the first day of `month`/`year`.
/// 0 = Sunday (matches task spec; ISO would use 0=Monday but task says 0=Sunday).
pub fn firstWeekday(year: u16, month: u8) u8 {
    // Tomohiko Sakamoto's algorithm (returns 0=Sunday).
    const t = [_]u32{ 0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4 };
    var y: u32 = year;
    const m: u32 = month;
    const d: u32 = 1;
    if (m < 3) y -= 1;
    return @intCast((y + y / 4 - y / 100 + y / 400 + t[m - 1] + d) % 7);
}

/// Format `v` as "YYYY-MM-DD" into `buf[0..10]`. Returns the slice.
pub fn formatDate(v: DateValue, buf: *[10]u8) []const u8 {
    _ = std.fmt.bufPrint(buf, "{d:0>4}-{d:0>2}-{d:0>2}", .{ v.year, v.month, v.day }) catch {};
    return buf[0..10];
}

/// Parse "YYYY-MM-DD" from `s`. Returns null if malformed.
pub fn parseDate(s: []const u8) ?DateValue {
    if (s.len != 10) return null;
    if (s[4] != '-' or s[7] != '-') return null;
    const year = std.fmt.parseInt(u16, s[0..4], 10) catch return null;
    const month = std.fmt.parseInt(u8, s[5..7], 10) catch return null;
    const day = std.fmt.parseInt(u8, s[8..10], 10) catch return null;
    if (month < 1 or month > 12) return null;
    if (day < 1 or day > 31) return null;
    return DateValue{ .year = year, .month = month, .day = day };
}
