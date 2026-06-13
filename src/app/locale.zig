//! M15 — Locale-aware number and date formatting.
//!
//! Standalone utility module with no framework dependencies.
//! Provides Locale struct with built-in constants (en_US, de_DE, fr_FR, ru_RU)
//! and helpers: formatInt, formatFloat, formatDate, formatDateLong, formatDateShort,
//! formatString (placeholder substitution).

const std = @import("std");

/// A key-value pair for placeholder substitution in formatString.
pub const StringParam = struct {
    key: []const u8,
    value: []const u8,
};

/// Substitute {key} markers in template with param values.
/// Unknown keys are left as-is (literal {key} in output).
/// Writes to buf, returns used slice or null if buf too small.
pub fn formatString(buf: []u8, template: []const u8, params: []const StringParam) ?[]const u8 {
    var pos: usize = 0;
    var i: usize = 0;
    while (i < template.len) {
        if (template[i] == '{') {
            const end = std.mem.indexOfScalar(u8, template[i + 1 ..], '}') orelse {
                // No closing brace: literal '{'
                if (pos >= buf.len) return null;
                buf[pos] = '{';
                pos += 1;
                i += 1;
                continue;
            };
            const key = template[i + 1 ..][0..end];
            // Try to match key in params.
            var replaced = false;
            for (params) |p| {
                if (std.mem.eql(u8, key, p.key)) {
                    if (pos + p.value.len > buf.len) return null;
                    @memcpy(buf[pos..][0..p.value.len], p.value);
                    pos += p.value.len;
                    replaced = true;
                    break;
                }
            }
            if (!replaced) {
                // Unknown key: emit original {key} literal.
                const len = 2 + key.len; // '{' + key + '}'
                if (pos + len > buf.len) return null;
                buf[pos] = '{';
                pos += 1;
                @memcpy(buf[pos..][0..key.len], key);
                pos += key.len;
                buf[pos] = '}';
                pos += 1;
            }
            i += 1 + end + 1; // skip '{' + key + '}'
        } else {
            if (pos >= buf.len) return null;
            buf[pos] = template[i];
            pos += 1;
            i += 1;
        }
    }
    return buf[0..pos];
}

/// Order of day, month, year components in a formatted date.
pub const DateOrder = enum {
    /// month/day/year — en-US
    mdy,
    /// day/month/year — de-DE, fr-FR, ru-RU
    dmy,
    /// year/month/day — ISO-8601, some East Asian conventions
    ymd,
};

/// Formatting rules for one locale: number separators, date order, month names.
pub const Locale = struct {
    /// Thousands separator character (e.g. ',' for en-US, '.' for de-DE).
    thousands_sep: u8 = ',',
    /// Decimal separator character (e.g. '.' for en-US, ',' for de-DE).
    decimal_sep: u8 = '.',
    /// Number of digits between thousands separators (typically 3).
    grouping: u8 = 3,

    /// Order of day, month, year components.
    date_order: DateOrder = .mdy,
    /// Separator between date components (e.g. '/' for en-US, '.' for de-DE).
    date_sep: u8 = '/',
    /// Names of months (1-based: index 0 unused, 1 = January ... 12 = December).
    month_names: [13][]const u8 = .{
        "", "January", "February", "March", "April", "May", "June",
        "July", "August", "September", "October", "November", "December",
    },
    /// Abbreviated month names (1-based). Same indexing as month_names.
    month_names_short: [13][]const u8 = .{
        "", "Jan", "Feb", "Mar", "Apr", "May", "Jun",
        "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
    },

    // ------------------------------------------------------------------
    // Built-in locale constants
    // ------------------------------------------------------------------

    /// en-US: 1,234.56, month/day/year
    pub const en_US: Locale = .{
        .date_order = .mdy,
        .date_sep = '/',
    };

    /// de-DE: 1.234,56, day.month.year
    pub const de_DE: Locale = .{
        .thousands_sep = '.',
        .decimal_sep = ',',
        .date_order = .dmy,
        .date_sep = '.',
        .month_names = .{
            "", "Januar", "Februar", "März", "April", "Mai", "Juni",
            "Juli", "August", "September", "Oktober", "November", "Dezember",
        },
        .month_names_short = .{
            "", "Jan", "Feb", "Mär", "Apr", "Mai", "Jun",
            "Jul", "Aug", "Sep", "Okt", "Nov", "Dez",
        },
    };

    /// fr-FR: 1 234,56, day/month/year
    pub const fr_FR: Locale = .{
        .thousands_sep = ' ',
        .decimal_sep = ',',
        .date_order = .dmy,
        .date_sep = '/',
        .month_names = .{
            "", "janvier", "février", "mars", "avril", "mai", "juin",
            "juillet", "août", "septembre", "octobre", "novembre", "décembre",
        },
        .month_names_short = .{
            "", "janv.", "févr.", "mars", "avr.", "mai", "juin",
            "juil.", "août", "sept.", "oct.", "nov.", "déc.",
        },
    };

    /// ru-RU: 1 234,56, day.month.year
    pub const ru_RU: Locale = .{
        .thousands_sep = ' ',
        .decimal_sep = ',',
        .date_order = .dmy,
        .date_sep = '.',
        .month_names = .{
            "", "января", "февраля", "марта", "апреля", "мая", "июня",
            "июля", "августа", "сентября", "октября", "ноября", "декабря",
        },
        .month_names_short = .{
            "", "янв", "фев", "мар", "апр", "май", "июн",
            "июл", "авг", "сен", "окт", "ноя", "дек",
        },
    };
};

/// DateValue struct matching the one in src/07/types.zig.
/// Defined locally to keep locale.zig dependency-free.
pub const DateValue = struct {
    year: u16 = 0,
    month: u8 = 1,
    day: u8 = 1,
};

/// Format an integer with locale-aware thousands separators.
/// Writes to buf and returns the slice used. Returns null if buf is too small.
pub fn formatInt(buf: []u8, n: anytype, locale: Locale) ?[]const u8 {
    const T = @TypeOf(n);
    const info = @typeInfo(T);
    const is_signed = switch (info) {
        .int => |int_info| int_info.signedness == .signed,
        .comptime_int => true,
        else => @compileError("formatInt expects an integer type"),
    };

    // Use std.fmt.bufPrint to get the base-10 signed representation.
    // For minInt(iN), bufPrint("{d}", .{n}) produces "-2147483648" which is fine.
    const fmt_result = std.fmt.bufPrint(buf, "{d}", .{n}) catch return null;

    // If no thousands separator needed (no grouping or number too short), return as-is.
    const grouping = locale.grouping;
    if (grouping == 0 or fmt_result.len <= grouping + @intFromBool(is_signed and n < 0)) {
        return fmt_result;
    }

    // Count digit-only characters (skip leading '-').
    const neg: u1 = @intFromBool(fmt_result.len > 0 and fmt_result[0] == '-');
    const digits_start: usize = neg;
    const digits_only = fmt_result[digits_start..];

    // Calculate how many separators we need.
    const digit_count = digits_only.len;
    const sep_count = (digit_count - 1) / grouping;
    const needed = fmt_result.len + sep_count;
    if (buf.len < needed) return null;

    // Write separators + digits from right to left, starting from the end of buf.
    // We write into buf[needed - digit_count - sep_count .. needed] which is the correct
    // region, then prepend the '-' sign if needed.
    var write_pos: usize = needed;
    var digit_idx: usize = digit_count;
    while (digit_idx > 0) {
        digit_idx -= 1;
        // Insert separator every 'grouping' digits from the right, but not at position 0.
        const sep_needed = (digit_count - digit_idx - 1) > 0 and (digit_count - digit_idx - 1) % grouping == 0;
        if (sep_needed) {
            write_pos -= 1;
            buf[write_pos] = locale.thousands_sep;
        }
        write_pos -= 1;
        buf[write_pos] = digits_only[digit_idx];
    }

    // Copy negative sign if present.
    if (neg > 0) {
        write_pos -= 1;
        buf[write_pos] = '-';
    }

    return buf[write_pos..needed];
}

/// Format a float with locale-aware decimal separator.
/// Uses std.fmt.bufPrint with {d} format, then replaces '.' with locale.decimal_sep.
/// Returns null for NaN and inf, or if buf is too small.
pub fn formatFloat(buf: []u8, n: anytype, locale: Locale) ?[]const u8 {
    const T = @TypeOf(n);
    switch (@typeInfo(T)) {
        .float => {},
        else => @compileError("formatFloat expects a float type (f16, f32, or f64)"),
    }

    // Handle special values.
    if (std.math.isNan(n) or std.math.isInf(n)) return null;

    // Use std.fmt.bufPrint with {d} for shortest round-trip.
    const raw = std.fmt.bufPrint(buf, "{d}", .{n}) catch return null;

    // Handle -0.0 -> "0" (Zig formats -0.0 as "-0").
    if (std.mem.eql(u8, raw, "-0")) {
        return "0";
    }

    // Replace '.' with locale.decimal_sep.
    if (locale.decimal_sep != '.') {
        if (std.mem.indexOfScalar(u8, raw, '.')) |dot_pos| {
            raw[dot_pos] = locale.decimal_sep;
        }
    }

    return raw;
}

/// Format a DateValue with locale-aware date order and separator.
/// Returns "" when dv.year == 0 (unset date).
/// Returns null if buf is too small.
pub fn formatDate(buf: []u8, dv: DateValue, locale: Locale) ?[]const u8 {
    if (dv.year == 0) return "";

    const year_len = countDigits(dv.year);
    const month_len = countDigits(dv.month);
    const day_len = countDigits(dv.day);
    // Two separators between three components.
    const needed = year_len + month_len + day_len + 2;
    if (buf.len < needed) return null;

    var pos: usize = 0;

    switch (locale.date_order) {
        .mdy => {
            pos += formatUint(buf[pos..], dv.month);
            buf[pos] = locale.date_sep; pos += 1;
            pos += formatUint(buf[pos..], dv.day);
            buf[pos] = locale.date_sep; pos += 1;
            pos += formatUint(buf[pos..], dv.year);
        },
        .dmy => {
            pos += formatUint(buf[pos..], dv.day);
            buf[pos] = locale.date_sep; pos += 1;
            pos += formatUint(buf[pos..], dv.month);
            buf[pos] = locale.date_sep; pos += 1;
            pos += formatUint(buf[pos..], dv.year);
        },
        .ymd => {
            pos += formatUint(buf[pos..], dv.year);
            buf[pos] = locale.date_sep; pos += 1;
            pos += formatUint(buf[pos..], dv.month);
            buf[pos] = locale.date_sep; pos += 1;
            pos += formatUint(buf[pos..], dv.day);
        },
    }

    return buf[0..pos];
}

/// Format a DateValue with full month name, locale-aware.
/// e.g. "March 15, 2024" (en-US), "15. März 2024" (de-DE)
/// Returns null if buf is too small.
pub fn formatDateLong(buf: []u8, dv: DateValue, locale: Locale) ?[]const u8 {
    return formatDateWithMonth(buf, dv, locale, locale.month_names);
}

/// Format a DateValue with abbreviated month name, locale-aware.
/// e.g. "Mar 15, 2024" (en-US), "15. Mär 2024" (de-DE)
/// Returns null if buf is too small.
pub fn formatDateShort(buf: []u8, dv: DateValue, locale: Locale) ?[]const u8 {
    return formatDateWithMonth(buf, dv, locale, locale.month_names_short);
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

/// Helper for formatDateLong and formatDateShort.
fn formatDateWithMonth(buf: []u8, dv: DateValue, locale: Locale, month_names: [13][]const u8) ?[]const u8 {
    if (dv.year == 0) return "";

    const month_name = month_names[dv.month];
    const year_len = countDigits(dv.year);
    const day_len = countDigits(dv.day);
    // Spaces: mdy needs ", " between month_name and day; dmy needs ". " between day and month_name; ymd needs space between year and month_name.
    // mdy: month_name + " " + day + ", " + year
    // dmy: day + ". " + month_name + " " + year
    // ymd: year + " " + month_name + " " + day
    var needed: usize = 0;
    switch (locale.date_order) {
        .mdy => {
            needed = month_name.len + 1 + day_len + 2 + year_len;
        },
        .dmy => {
            needed = day_len + 2 + month_name.len + 1 + year_len;
        },
        .ymd => {
            needed = year_len + 1 + month_name.len + 1 + day_len;
        },
    }
    if (buf.len < needed) return null;

    var pos: usize = 0;

    switch (locale.date_order) {
        .mdy => {
            @memcpy(buf[pos..][0..month_name.len], month_name);
            pos += month_name.len;
            buf[pos] = ' '; pos += 1;
            pos += formatUint(buf[pos..], dv.day);
            buf[pos] = ','; pos += 1;
            buf[pos] = ' '; pos += 1;
            pos += formatUint(buf[pos..], dv.year);
        },
        .dmy => {
            pos += formatUint(buf[pos..], dv.day);
            buf[pos] = '.'; pos += 1;
            buf[pos] = ' '; pos += 1;
            @memcpy(buf[pos..][0..month_name.len], month_name);
            pos += month_name.len;
            buf[pos] = ' '; pos += 1;
            pos += formatUint(buf[pos..], dv.year);
        },
        .ymd => {
            pos += formatUint(buf[pos..], dv.year);
            buf[pos] = ' '; pos += 1;
            @memcpy(buf[pos..][0..month_name.len], month_name);
            pos += month_name.len;
            buf[pos] = ' '; pos += 1;
            pos += formatUint(buf[pos..], dv.day);
        },
    }

    return buf[0..pos];
}

/// Count decimal digits of an unsigned integer (at least 1).
fn countDigits(val: anytype) usize {
    var v = val;
    var count: usize = 0;
    if (v == 0) return 1;
    while (v > 0) : (v /= 10) {
        count += 1;
    }
    return count;
}

/// Format an unsigned integer into buf, returning the number of bytes written.
fn formatUint(buf: []u8, val: anytype) usize {
    const count = countDigits(val);
    var v = val;
    var pos = count;
    while (pos > 0) {
        pos -= 1;
        buf[pos] = @as(u8, @intCast(v % 10)) + '0';
        v /= 10;
    }
    return count;
}
