//! M15 — Locale and date formatting unit tests (RE0 + RE1).
//! Pure Zig, no allocator, no GPU, no GLFW required.

const std = @import("std");
const testing = std.testing;
const locale = @import("locale.zig");
const Locale = locale.Locale;
const DateOrder = locale.DateOrder;
const DateValue = locale.DateValue;

// ---------------------------------------------------------------------------
// RE0 — Number formatting
// ---------------------------------------------------------------------------

test "formatInt: basic formatting en-US" {
    var buf: [64]u8 = undefined;
    const result = locale.formatInt(&buf, 42, Locale.en_US);
    try testing.expectEqualSlices(u8, "42", result.?);
}

test "formatInt: thousands separator en-US" {
    var buf: [64]u8 = undefined;
    const result = locale.formatInt(&buf, 1234, Locale.en_US);
    try testing.expectEqualSlices(u8, "1,234", result.?);
}

test "formatInt: multiple thousands separators" {
    var buf: [64]u8 = undefined;
    const result = locale.formatInt(&buf, 1234567, Locale.en_US);
    try testing.expectEqualSlices(u8, "1,234,567", result.?);
}

test "formatInt: negative number de-DE" {
    var buf: [64]u8 = undefined;
    const result = locale.formatInt(&buf, -1000, Locale.de_DE);
    try testing.expectEqualSlices(u8, "-1.000", result.?);
}

test "formatInt: zero" {
    var buf: [64]u8 = undefined;
    const result = locale.formatInt(&buf, 0, Locale.en_US);
    try testing.expectEqualSlices(u8, "0", result.?);
}

test "formatInt: negative one" {
    var buf: [64]u8 = undefined;
    const result = locale.formatInt(&buf, -1, Locale.en_US);
    try testing.expectEqualSlices(u8, "-1", result.?);
}

test "formatInt: minInt i32" {
    var buf: [64]u8 = undefined;
    const result = locale.formatInt(&buf, std.math.minInt(i32), Locale.en_US);
    try testing.expectEqualSlices(u8, "-2,147,483,648", result.?);
}

test "formatInt: buffer too small returns null" {
    var buf: [2]u8 = undefined;
    const result = locale.formatInt(&buf, 1234, Locale.en_US);
    try testing.expect(result == null);
}

test "formatInt: unsigned integer" {
    var buf: [64]u8 = undefined;
    const result = locale.formatInt(&buf, @as(u32, 1234567), Locale.en_US);
    try testing.expectEqualSlices(u8, "1,234,567", result.?);
}

test "formatFloat: basic en-US" {
    var buf: [64]u8 = undefined;
    const result = locale.formatFloat(&buf, @as(f64, 3.14), Locale.en_US);
    try testing.expectEqualSlices(u8, "3.14", result.?);
}

test "formatFloat: decimal separator replacement de-DE" {
    var buf: [64]u8 = undefined;
    const result = locale.formatFloat(&buf, @as(f64, 3.14), Locale.de_DE);
    try testing.expectEqualSlices(u8, "3,14", result.?);
}

test "formatFloat: whole number (no decimal part)" {
    var buf: [64]u8 = undefined;
    const result = locale.formatFloat(&buf, @as(f64, 1000.0), Locale.en_US);
    try testing.expectEqualSlices(u8, "1000", result.?);
}

test "formatFloat: negative value" {
    var buf: [64]u8 = undefined;
    const result = locale.formatFloat(&buf, @as(f64, -0.5), Locale.en_US);
    try testing.expectEqualSlices(u8, "-0.5", result.?);
}

test "formatFloat: NaN returns null" {
    var buf: [64]u8 = undefined;
    const result = locale.formatFloat(&buf, std.math.nan(f64), Locale.en_US);
    try testing.expect(result == null);
}

test "formatFloat: inf returns null" {
    var buf: [64]u8 = undefined;
    const result = locale.formatFloat(&buf, std.math.inf(f64), Locale.en_US);
    try testing.expect(result == null);
}

test "formatFloat: negative zero returns '0'" {
    var buf: [64]u8 = undefined;
    const result = locale.formatFloat(&buf, @as(f64, -0.0), Locale.en_US);
    try testing.expectEqualSlices(u8, "0", result.?);
}

test "formatFloat: fr-FR decimal separator" {
    var buf: [64]u8 = undefined;
    const result = locale.formatFloat(&buf, @as(f64, 3.14), Locale.fr_FR);
    try testing.expectEqualSlices(u8, "3,14", result.?);
}

test "formatFloat: ru-RU decimal separator" {
    var buf: [64]u8 = undefined;
    const result = locale.formatFloat(&buf, @as(f64, 3.14), Locale.ru_RU);
    try testing.expectEqualSlices(u8, "3,14", result.?);
}

// ---------------------------------------------------------------------------
// RE1 — Date formatting
// ---------------------------------------------------------------------------

test "formatDate: en-US mdy" {
    var buf: [64]u8 = undefined;
    const dv = DateValue{ .year = 2024, .month = 3, .day = 15 };
    const result = locale.formatDate(&buf, dv, Locale.en_US);
    try testing.expectEqualSlices(u8, "3/15/2024", result.?);
}

test "formatDate: de-DE dmy" {
    var buf: [64]u8 = undefined;
    const dv = DateValue{ .year = 2024, .month = 3, .day = 15 };
    const result = locale.formatDate(&buf, dv, Locale.de_DE);
    try testing.expectEqualSlices(u8, "15.3.2024", result.?);
}

test "formatDate: fr-FR dmy" {
    var buf: [64]u8 = undefined;
    const dv = DateValue{ .year = 2024, .month = 3, .day = 15 };
    const result = locale.formatDate(&buf, dv, Locale.fr_FR);
    try testing.expectEqualSlices(u8, "15/3/2024", result.?);
}

test "formatDate: ru-RU dmy" {
    var buf: [64]u8 = undefined;
    const dv = DateValue{ .year = 2024, .month = 3, .day = 15 };
    const result = locale.formatDate(&buf, dv, Locale.ru_RU);
    try testing.expectEqualSlices(u8, "15.3.2024", result.?);
}

test "formatDate: unset date returns empty string" {
    var buf: [64]u8 = undefined;
    const dv = DateValue{ .year = 0, .month = 1, .day = 1 };
    const result = locale.formatDate(&buf, dv, Locale.en_US);
    try testing.expectEqualSlices(u8, "", result.?);
}

test "formatDate: ymd order" {
    var buf: [64]u8 = undefined;
    const dv = DateValue{ .year = 2024, .month = 3, .day = 15 };
    const custom = Locale{ .date_order = .ymd, .date_sep = '-' };
    const result = locale.formatDate(&buf, dv, custom);
    try testing.expectEqualSlices(u8, "2024-3-15", result.?);
}

test "formatDate: buffer too small returns null" {
    var buf: [4]u8 = undefined;
    const dv = DateValue{ .year = 2024, .month = 3, .day = 15 };
    const result = locale.formatDate(&buf, dv, Locale.en_US);
    try testing.expect(result == null);
}

test "formatDateLong: en-US full month name" {
    var buf: [64]u8 = undefined;
    const dv = DateValue{ .year = 2024, .month = 3, .day = 15 };
    const result = locale.formatDateLong(&buf, dv, Locale.en_US);
    try testing.expectEqualSlices(u8, "March 15, 2024", result.?);
}

test "formatDateLong: de-DE full month name" {
    var buf: [64]u8 = undefined;
    const dv = DateValue{ .year = 2024, .month = 3, .day = 15 };
    const result = locale.formatDateLong(&buf, dv, Locale.de_DE);
    try testing.expectEqualSlices(u8, "15. März 2024", result.?);
}

test "formatDateLong: fr-FR full month name" {
    var buf: [64]u8 = undefined;
    const dv = DateValue{ .year = 2024, .month = 3, .day = 15 };
    const result = locale.formatDateLong(&buf, dv, Locale.fr_FR);
    try testing.expectEqualSlices(u8, "15. mars 2024", result.?);
}

test "formatDateLong: ru-RU full month name" {
    var buf: [64]u8 = undefined;
    const dv = DateValue{ .year = 2024, .month = 3, .day = 15 };
    const result = locale.formatDateLong(&buf, dv, Locale.ru_RU);
    try testing.expectEqualSlices(u8, "15. марта 2024", result.?);
}

test "formatDateLong: unset date returns empty string" {
    var buf: [64]u8 = undefined;
    const dv = DateValue{ .year = 0, .month = 1, .day = 1 };
    const result = locale.formatDateLong(&buf, dv, Locale.en_US);
    try testing.expectEqualSlices(u8, "", result.?);
}

test "formatDateLong: ymd order" {
    var buf: [64]u8 = undefined;
    const dv = DateValue{ .year = 2024, .month = 3, .day = 15 };
    const custom = Locale{ .date_order = .ymd, .month_names = locale.Locale.en_US.month_names, .month_names_short = locale.Locale.en_US.month_names_short };
    const result = locale.formatDateLong(&buf, dv, custom);
    try testing.expectEqualSlices(u8, "2024 March 15", result.?);
}

test "formatDateLong: buffer too small returns null" {
    var buf: [5]u8 = undefined;
    const dv = DateValue{ .year = 2024, .month = 3, .day = 15 };
    const result = locale.formatDateLong(&buf, dv, Locale.en_US);
    try testing.expect(result == null);
}

test "formatDateShort: en-US abbreviated month" {
    var buf: [64]u8 = undefined;
    const dv = DateValue{ .year = 2024, .month = 3, .day = 15 };
    const result = locale.formatDateShort(&buf, dv, Locale.en_US);
    try testing.expectEqualSlices(u8, "Mar 15, 2024", result.?);
}

test "formatDateShort: de-DE abbreviated month" {
    var buf: [64]u8 = undefined;
    const dv = DateValue{ .year = 2024, .month = 3, .day = 15 };
    const result = locale.formatDateShort(&buf, dv, Locale.de_DE);
    try testing.expectEqualSlices(u8, "15. Mär 2024", result.?);
}

test "formatDateShort: fr-FR abbreviated month" {
    var buf: [64]u8 = undefined;
    const dv = DateValue{ .year = 2024, .month = 3, .day = 15 };
    const result = locale.formatDateShort(&buf, dv, Locale.fr_FR);
    try testing.expectEqualSlices(u8, "15. mars 2024", result.?);
}

test "formatDateShort: ru-RU abbreviated month" {
    var buf: [64]u8 = undefined;
    const dv = DateValue{ .year = 2024, .month = 3, .day = 15 };
    const result = locale.formatDateShort(&buf, dv, Locale.ru_RU);
    try testing.expectEqualSlices(u8, "15. мар 2024", result.?);
}

test "formatDateShort: unset date returns empty string" {
    var buf: [64]u8 = undefined;
    const dv = DateValue{ .year = 0, .month = 1, .day = 1 };
    const result = locale.formatDateShort(&buf, dv, Locale.en_US);
    try testing.expectEqualSlices(u8, "", result.?);
}

test "formatDateShort: ymd order" {
    var buf: [64]u8 = undefined;
    const dv = DateValue{ .year = 2024, .month = 3, .day = 15 };
    const custom = Locale{ .date_order = .ymd, .month_names_short = locale.Locale.en_US.month_names_short };
    const result = locale.formatDateShort(&buf, dv, custom);
    try testing.expectEqualSlices(u8, "2024 Mar 15", result.?);
}

test "formatDateShort: buffer too small returns null" {
    var buf: [5]u8 = undefined;
    const dv = DateValue{ .year = 2024, .month = 3, .day = 15 };
    const result = locale.formatDateShort(&buf, dv, Locale.en_US);
    try testing.expect(result == null);
}

// ---------------------------------------------------------------------------
// Locale constants — distinct values
// ---------------------------------------------------------------------------

test "locale constants: en_US has correct defaults" {
    try testing.expectEqual(@as(u8, ','), Locale.en_US.thousands_sep);
    try testing.expectEqual(@as(u8, '.'), Locale.en_US.decimal_sep);
    try testing.expectEqual(@as(u8, 3), Locale.en_US.grouping);
    try testing.expectEqual(.mdy, Locale.en_US.date_order);
    try testing.expectEqual(@as(u8, '/'), Locale.en_US.date_sep);
}

test "locale constants: de_DE has correct separators" {
    try testing.expectEqual(@as(u8, '.'), Locale.de_DE.thousands_sep);
    try testing.expectEqual(@as(u8, ','), Locale.de_DE.decimal_sep);
    try testing.expectEqual(.dmy, Locale.de_DE.date_order);
    try testing.expectEqual(@as(u8, '.'), Locale.de_DE.date_sep);
}

test "locale constants: fr_FR has correct separators" {
    try testing.expectEqual(@as(u8, ' '), Locale.fr_FR.thousands_sep);
    try testing.expectEqual(@as(u8, ','), Locale.fr_FR.decimal_sep);
    try testing.expectEqual(.dmy, Locale.fr_FR.date_order);
    try testing.expectEqual(@as(u8, '/'), Locale.fr_FR.date_sep);
}

test "locale constants: ru_RU has correct separators" {
    try testing.expectEqual(@as(u8, ' '), Locale.ru_RU.thousands_sep);
    try testing.expectEqual(@as(u8, ','), Locale.ru_RU.decimal_sep);
    try testing.expectEqual(.dmy, Locale.ru_RU.date_order);
    try testing.expectEqual(@as(u8, '.'), Locale.ru_RU.date_sep);
}

test "locale constants: all distinct" {
    // At minimum, en_US and de_DE must differ.
    try testing.expect(Locale.en_US.thousands_sep != Locale.de_DE.thousands_sep);
    try testing.expect(Locale.en_US.date_sep != Locale.de_DE.date_sep);
    try testing.expect(Locale.en_US.date_order != Locale.de_DE.date_order);
}

test "locale constants: German month names" {
    try testing.expectEqualSlices(u8, "Januar", Locale.de_DE.month_names[1]);
    try testing.expectEqualSlices(u8, "März", Locale.de_DE.month_names[3]);
    try testing.expectEqualSlices(u8, "Dezember", Locale.de_DE.month_names[12]);
    try testing.expectEqualSlices(u8, "Mär", Locale.de_DE.month_names_short[3]);
}

test "locale constants: French month names" {
    try testing.expectEqualSlices(u8, "janvier", Locale.fr_FR.month_names[1]);
    try testing.expectEqualSlices(u8, "mars", Locale.fr_FR.month_names[3]);
    try testing.expectEqualSlices(u8, "décembre", Locale.fr_FR.month_names[12]);
}

test "locale constants: Russian month names" {
    try testing.expectEqualSlices(u8, "января", Locale.ru_RU.month_names[1]);
    try testing.expectEqualSlices(u8, "марта", Locale.ru_RU.month_names[3]);
    try testing.expectEqualSlices(u8, "декабря", Locale.ru_RU.month_names[12]);
    try testing.expectEqualSlices(u8, "мар", Locale.ru_RU.month_names_short[3]);
}

// ---------------------------------------------------------------------------
// RE2 — formatString placeholder substitution
// ---------------------------------------------------------------------------

test "formatString: basic substitution" {
    var buf: [64]u8 = undefined;
    const params = [_]locale.StringParam{
        .{ .key = "name", .value = "World" },
    };
    const result = locale.formatString(&buf, "Hello, {name}!", &params);
    try testing.expectEqualSlices(u8, "Hello, World!", result.?);
}

test "formatString: multiple params" {
    var buf: [64]u8 = undefined;
    const params = [_]locale.StringParam{
        .{ .key = "a", .value = "1" },
        .{ .key = "b", .value = "2" },
    };
    const result = locale.formatString(&buf, "{a} and {b}", &params);
    try testing.expectEqualSlices(u8, "1 and 2", result.?);
}

test "formatString: missing key leaves placeholder as-is" {
    var buf: [64]u8 = undefined;
    const params = [_]locale.StringParam{};
    const result = locale.formatString(&buf, "Hello, {name}!", &params);
    try testing.expectEqualSlices(u8, "Hello, {name}!", result.?);
}

test "formatString: buffer too small returns null" {
    var buf: [4]u8 = undefined;
    const params = [_]locale.StringParam{
        .{ .key = "name", .value = "World" },
    };
    const result = locale.formatString(&buf, "Hello, {name}!", &params);
    try testing.expect(result == null);
}

test "formatString: malformed braces (open brace without close)" {
    var buf: [64]u8 = undefined;
    const params = [_]locale.StringParam{};
    const result = locale.formatString(&buf, "{{test}}", &params);
    try testing.expectEqualSlices(u8, "{{test}}", result.?);
}

test "formatString: empty template" {
    var buf: [64]u8 = undefined;
    const params = [_]locale.StringParam{};
    const result = locale.formatString(&buf, "", &params);
    try testing.expectEqualSlices(u8, "", result.?);
}

test "formatString: literal text with no placeholders" {
    var buf: [64]u8 = undefined;
    const params = [_]locale.StringParam{};
    const result = locale.formatString(&buf, "plain text", &params);
    try testing.expectEqualSlices(u8, "plain text", result.?);
}
