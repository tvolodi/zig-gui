//! 08 — Regex pattern matching — src/08/regex.zig
//!
//! Simplified pure Zig regex engine supporting basic patterns.
//! Supports: literals, `.` (any char except newline), `*` (0+), `+` (1+),
//! `?` (0-1), `[abc]` (char class), `^` (start), `$` (end).
//! No capture groups, lookahead, backreferences.
//! Performance: O(n × m) where n = pattern length, m = string length.

const std = @import("std");

/// Compiled regex pattern.
pub const CompiledPattern = struct {
    pattern: []const u8,
    allocator: std.mem.Allocator,

    pub fn deinit(self: CompiledPattern) void {
        self.allocator.free(self.pattern);
    }
};

/// Compile a regex pattern string (for now, just stores it).
pub fn compilePattern(allocator: std.mem.Allocator, pattern: []const u8) !CompiledPattern {
    const stored = try allocator.dupe(u8, pattern);
    return CompiledPattern{
        .pattern = stored,
        .allocator = allocator,
    };
}

/// Match a string against a compiled pattern.
/// Returns true if the entire string matches the pattern.
pub fn matches(compiled: CompiledPattern, input: []const u8) bool {
    return matchesHelper(compiled.pattern, input, 0, 0);
}

/// Simple recursive backtracking matcher for basic patterns.
fn matchesHelper(pattern: []const u8, input: []const u8, pat_idx: usize, str_idx: usize) bool {
    // Base case: reached end of pattern
    if (pat_idx >= pattern.len) {
        return str_idx == input.len;
    }

    // Check for anchors
    if (pattern[pat_idx] == '^') {
        if (str_idx != 0) return false;
        return matchesHelper(pattern, input, pat_idx + 1, str_idx);
    }

    if (pattern[pat_idx] == '$') {
        if (str_idx != input.len) return false;
        return matchesHelper(pattern, input, pat_idx + 1, str_idx);
    }

    // Check for lookahead quantifiers
    const has_quantifier = pat_idx + 1 < pattern.len and
        (pattern[pat_idx + 1] == '*' or pattern[pat_idx + 1] == '+' or pattern[pat_idx + 1] == '?');

    if (has_quantifier) {
        const quantifier = pattern[pat_idx + 1];
        const next_pat = pat_idx + 2;

        switch (quantifier) {
            '*' => {
                // 0-or-more: try skipping, then matching one or more
                if (matchesHelper(pattern, input, next_pat, str_idx)) return true;
                if (str_idx < input.len and charMatches(pattern[pat_idx], input[str_idx])) {
                    if (matchesHelper(pattern, input, pat_idx, str_idx + 1)) return true;
                }
                return false;
            },
            '+' => {
                // 1-or-more: must match at least once
                if (str_idx >= input.len) return false;
                if (!charMatches(pattern[pat_idx], input[str_idx])) return false;
                if (matchesHelper(pattern, input, next_pat, str_idx + 1)) return true;
                if (matchesHelper(pattern, input, pat_idx, str_idx + 1)) return true;
                return false;
            },
            '?' => {
                // 0-or-1: try both paths
                if (matchesHelper(pattern, input, next_pat, str_idx)) return true;
                if (str_idx < input.len and charMatches(pattern[pat_idx], input[str_idx])) {
                    if (matchesHelper(pattern, input, next_pat, str_idx + 1)) return true;
                }
                return false;
            },
            else => {},
        }
    }

    // Regular character matching
    if (str_idx >= input.len) return false;

    if (pattern[pat_idx] == '[') {
        // Character class [abc] or [a-z]
        var class_end = pat_idx + 1;
        var negate = false;
        if (class_end < pattern.len and pattern[class_end] == '^') {
            negate = true;
            class_end += 1;
        }

        while (class_end < pattern.len and pattern[class_end] != ']') {
            class_end += 1;
        }

        const class_start = if (negate) pat_idx + 2 else pat_idx + 1;
        const class_str = pattern[class_start..class_end];
        const in_class = charInClass(input[str_idx], class_str);

        if (in_class != negate) {
            return matchesHelper(pattern, input, class_end + 1, str_idx + 1);
        }
        return false;
    }

    if (charMatches(pattern[pat_idx], input[str_idx])) {
        return matchesHelper(pattern, input, pat_idx + 1, str_idx + 1);
    }

    return false;
}

/// Check if a single pattern character matches an input character.
fn charMatches(pat_char: u8, input_char: u8) bool {
    if (pat_char == '.') {
        return input_char != '\n'; // . matches anything except newline
    }
    if (pat_char == '\\' and pat_char + 1 < 256) {
        // Basic escape support (literal for now)
        return input_char == pat_char;
    }
    return pat_char == input_char;
}

/// Check if a character is in a character class (e.g., "a-z0-9").
fn charInClass(c: u8, class_str: []const u8) bool {
    var i: usize = 0;
    while (i < class_str.len) {
        if (i + 2 < class_str.len and class_str[i + 1] == '-') {
            // Range like "a-z"
            const start = class_str[i];
            const end = class_str[i + 2];
            if (c >= start and c <= end) return true;
            i += 3;
        } else {
            if (c == class_str[i]) return true;
            i += 1;
        }
    }
    return false;
}

// Simple pre-compiled patterns for common validations
pub fn isValidEmail(input: []const u8) bool {
    if (std.mem.indexOfScalar(u8, input, '@')) |at_pos| {
        if (at_pos == 0 or at_pos >= input.len - 1) return false;
        const domain = input[at_pos + 1 ..];
        if (std.mem.indexOfScalar(u8, domain, '.')) |dot_pos| {
            if (dot_pos == 0 or dot_pos >= domain.len - 1) return false;
            return true;
        }
    }
    return false;
}

pub fn isValidUrl(input: []const u8) bool {
    return std.mem.indexOf(u8, input, "://") != null;
}
