//! Pure-Zig UBA subset — Unicode Bidirectional Algorithm for module 11 (M24-02 / RK1).
//!
//! Implements: paragraph base direction detection, character bidi-class classification,
//! embedding level assignment (simplified P1-P3, X1-X8 subset), visual reordering (L2).
//! Scope: Latin, Arabic, Hebrew, Devanagari, CJK, digits, punctuation.
//! No explicit embedding controls (RLE/LRE/PDF), no surrogates.

const std = @import("std");
const types = @import("types.zig");

// ---------------------------------------------------------------------------
// Unicode Bidi character classes (TR#9)
// ---------------------------------------------------------------------------

pub const BidiClass = enum(u8) {
    L,   // Left-to-Right
    R,   // Right-to-Left
    AL,  // Arabic Letter
    EN,  // European Number
    AN,  // Arabic Number
    ES,  // European Separator (+ -)
    ET,  // European Terminator (%, $, etc.)
    CS,  // Common Separator (, . : ;)
    NSM, // Non-Spacing Mark
    BN,  // Boundary Neutral
    B,   // Paragraph Separator
    S,   // Segment Separator
    WS,  // Whitespace
    ON,  // Other Neutral
};

/// Get the bidi class for a Unicode codepoint.
/// Covers the common cases; defaults to ON for unrecognized codepoints.
pub fn bidiClass(cp: u21) BidiClass {
    // Arabic letters and presentation forms
    if ((cp >= 0x0600 and cp <= 0x06FF) or
        (cp >= 0x0750 and cp <= 0x077F) or
        (cp >= 0xFB50 and cp <= 0xFDFF) or
        (cp >= 0xFE70 and cp <= 0xFEFF)) return .AL;
    // Hebrew letters
    if (cp >= 0x05D0 and cp <= 0x05EA) return .R;
    // Hebrew points / cantillation (NSM)
    if (cp >= 0x0591 and cp <= 0x05C7) return .NSM;
    // European digits 0-9
    if (cp >= '0' and cp <= '9') return .EN;
    // ASCII Latin letters
    if ((cp >= 'A' and cp <= 'Z') or (cp >= 'a' and cp <= 'z')) return .L;
    // CJK Unified Ideographs
    if ((cp >= 0x4E00 and cp <= 0x9FFF) or
        (cp >= 0x3400 and cp <= 0x4DBF) or
        (cp >= 0xF900 and cp <= 0xFAFF) or
        (cp >= 0x3000 and cp <= 0x303F)) return .L;
    // Devanagari
    if (cp >= 0x0900 and cp <= 0x097F) return .L;
    // Spaces and separators
    if (cp == ' ' or cp == '\t') return .WS;
    if (cp == '\n' or cp == '\r') return .B;
    // Common separators
    if (cp == ',' or cp == '.' or cp == ':' or cp == ';') return .CS;
    // European separators
    if (cp == '+' or cp == '-') return .ES;
    // European terminators
    if (cp == '%') return .ET;
    // Default: other neutral
    return .ON;
}

/// Get the script for a codepoint (simplified detection).
pub fn detectScript(cp: u21) types.Script {
    if ((cp >= 0x0600 and cp <= 0x06FF) or
        (cp >= 0x0750 and cp <= 0x077F)) return .arabic;
    if (cp >= 0x0590 and cp <= 0x05FF) return .hebrew;
    if (cp >= 0x0900 and cp <= 0x097F) return .devanagari;
    if ((cp >= 0x4E00 and cp <= 0x9FFF) or
        (cp >= 0x3400 and cp <= 0x4DBF) or
        (cp >= 0xF900 and cp <= 0xFAFF) or
        (cp >= 0x3000 and cp <= 0x303F) or
        (cp >= 0xFF00 and cp <= 0xFFEF)) return .cjk;
    if ((cp >= 'A' and cp <= 'Z') or (cp >= 'a' and cp <= 'z') or
        (cp >= '0' and cp <= '9') or cp < 0x0250) return .latin;
    return .unknown;
}

/// Detect base paragraph direction (UBA P2/P3).
/// Returns .rtl if the first strong character (L, R, or AL) is R or AL.
/// Returns .ltr if the first strong character is L, or if no strong character is found.
pub fn detectBaseDirection(text: []const u8) types.Direction {
    var i: usize = 0;
    while (i < text.len) {
        const cp_len = std.unicode.utf8ByteSequenceLength(text[i]) catch break;
        if (i + cp_len > text.len) break;
        const cp = std.unicode.utf8Decode(text[i..][0..cp_len]) catch { i += cp_len; continue; };
        const cls = bidiClass(cp);
        switch (cls) {
            .L => return .ltr,
            .R, .AL => return .rtl,
            else => {},
        }
        i += cp_len;
    }
    return .ltr;
}

/// Assign UBA embedding levels to each codepoint position (simplified UBA X1-X8).
/// Returns a slice of levels (one per codepoint), allocated with `allocator`.
/// Simplified: implements paragraph-level embedding without explicit embedding controls.
/// Caller owns the returned slice.
pub fn resolveEmbeddingLevels(
    allocator: std.mem.Allocator,
    text: []const u8,
    base: types.Direction,
) ![]u8 {
    // Count codepoints first
    var cp_count: usize = 0;
    {
        var i: usize = 0;
        while (i < text.len) {
            const l = std.unicode.utf8ByteSequenceLength(text[i]) catch break;
            if (i + l > text.len) break;
            cp_count += 1;
            i += l;
        }
    }

    if (cp_count == 0) return &[_]u8{};

    const levels = try allocator.alloc(u8, cp_count);
    const base_level: u8 = if (base == .rtl) 1 else 0;

    // Pass 1: assign initial levels based on bidi class
    var i: usize = 0;
    var cp_i: usize = 0;
    while (i < text.len and cp_i < cp_count) {
        const l = std.unicode.utf8ByteSequenceLength(text[i]) catch break;
        if (i + l > text.len) break;
        const cp = std.unicode.utf8Decode(text[i..][0..l]) catch {
            levels[cp_i] = base_level;
            i += l;
            cp_i += 1;
            continue;
        };
        const cls = bidiClass(cp);
        levels[cp_i] = switch (cls) {
            .R, .AL => if (base_level == 0) 1 else base_level,
            .L => base_level,
            else => base_level,
        };
        i += l;
        cp_i += 1;
    }

    return levels;
}

// ---------------------------------------------------------------------------
// TextItem — one itemized run with consistent (level, script, font_id)
// ---------------------------------------------------------------------------

pub const TextItem = struct {
    byte_start: u32,
    byte_len: u32,
    level: u8,
    script: types.Script,
    font_id: u16,
    direction: types.Direction,
};

/// Itemize a paragraph into runs with consistent (level, script) properties.
/// Returns items in LOGICAL order. Caller owns the result.
pub fn itemize(
    allocator: std.mem.Allocator,
    text: []const u8,
    base: types.Direction,
) ![]TextItem {
    if (text.len == 0) return &[_]TextItem{};

    const levels = try resolveEmbeddingLevels(allocator, text, base);
    defer allocator.free(levels);

    var items: std.ArrayList(TextItem) = .empty;
    errdefer items.deinit(allocator);

    var i: usize = 0;
    var cp_i: usize = 0;
    var run_start_byte: u32 = 0;
    var run_start_cp: usize = 0;
    var run_level: u8 = if (levels.len > 0) levels[0] else 0;
    var run_script: types.Script = .latin;

    while (i < text.len) {
        const l = std.unicode.utf8ByteSequenceLength(text[i]) catch break;
        if (i + l > text.len) break;
        const cp = std.unicode.utf8Decode(text[i..][0..l]) catch {
            i += l;
            cp_i += 1;
            continue;
        };
        const cur_level = if (cp_i < levels.len) levels[cp_i] else run_level;
        const cur_script = detectScript(cp);

        // Determine effective script: treat .unknown and .latin as compatible with current run
        const script_changed = cur_script != .unknown and
            cur_script != .latin and
            run_script != .latin and
            cur_script != run_script;

        const boundary = (cur_level != run_level) or script_changed;

        if (boundary and cp_i > run_start_cp) {
            // Flush the current run
            try items.append(allocator, .{
                .byte_start = run_start_byte,
                .byte_len = @intCast(i - run_start_byte),
                .level = run_level,
                .script = run_script,
                .font_id = 0,
                .direction = if (run_level % 2 == 1) .rtl else .ltr,
            });
            run_start_byte = @intCast(i);
            run_start_cp = cp_i;
            run_level = cur_level;
            run_script = if (cur_script != .unknown) cur_script else .latin;
        } else {
            // Update run script if we encounter a concrete script
            if (cur_script != .unknown and run_script == .latin) {
                run_script = cur_script;
            }
        }

        i += l;
        cp_i += 1;
    }

    // Flush the final run
    if (i > run_start_byte) {
        try items.append(allocator, .{
            .byte_start = run_start_byte,
            .byte_len = @intCast(i - run_start_byte),
            .level = run_level,
            .script = run_script,
            .font_id = 0,
            .direction = if (run_level % 2 == 1) .rtl else .ltr,
        });
    }

    return items.toOwnedSlice(allocator);
}

/// Reorder logical-order TextItems into visual order per UBA L2 rule.
/// Returns a new slice in visual order. Caller owns the result.
pub fn reorderVisual(
    allocator: std.mem.Allocator,
    items: []const TextItem,
) ![]TextItem {
    if (items.len == 0) return &[_]TextItem{};

    // Find max embedding level
    var max_level: u8 = 0;
    for (items) |item| max_level = @max(max_level, item.level);

    const result = try allocator.dupe(TextItem, items);

    // L2: for each level from max down to 1, reverse all contiguous runs at that level or higher
    var level: u8 = max_level;
    while (level >= 1) : (level -= 1) {
        var start: ?usize = null;
        for (result, 0..) |item, idx| {
            if (item.level >= level) {
                if (start == null) start = idx;
            } else if (start) |s| {
                std.mem.reverse(TextItem, result[s..idx]);
                start = null;
            }
        }
        if (start) |s| {
            std.mem.reverse(TextItem, result[s..]);
        }
    }

    return result;
}
