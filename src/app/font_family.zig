//! R60 — FontFamily: a three-slot font container (regular, bold, italic).
//! face() returns the best-matching Font pointer with fallback to regular.
//! Each Font has its .variant field set at init time so atlas keys are correct.

const std = @import("std");
const text = @import("../02/types.zig");

pub const FontFamily = struct {
    regular: text.Font,
    bold: ?text.Font,
    italic: ?text.Font,
    gpa: std.mem.Allocator,

    /// Load up to three TTF faces.  `regular_ttf` is required; bold/italic are optional.
    /// Variants are tagged at init time — face() never mutates.
    pub fn init(
        gpa: std.mem.Allocator,
        regular_ttf: []const u8,
        bold_ttf: ?[]const u8,
        italic_ttf: ?[]const u8,
    ) text.FontError!FontFamily {
        var regular = try text.Font.initFromBytes(gpa, regular_ttf);
        regular.variant = .regular;
        errdefer regular.deinit();

        var bold: ?text.Font = null;
        if (bold_ttf) |b| {
            var bf = try text.Font.initFromBytes(gpa, b);
            bf.variant = .bold;
            bold = bf;
        }
        errdefer if (bold) |*b| b.deinit();

        var italic: ?text.Font = null;
        if (italic_ttf) |it| {
            var itf = try text.Font.initFromBytes(gpa, it);
            itf.variant = .italic;
            italic = itf;
        }

        return FontFamily{
            .regular = regular,
            .bold = bold,
            .italic = italic,
            .gpa = gpa,
        };
    }

    pub fn deinit(self: *FontFamily) void {
        self.regular.deinit();
        if (self.bold) |*b| b.deinit();
        if (self.italic) |*it| it.deinit();
    }

    /// Return a pointer to the best-matching font face.
    /// bold+italic → bold (no synthesised bold-italic yet), fallback to regular.
    /// Variant field on the returned font is already set correctly from init.
    pub fn face(self: *FontFamily, bold: bool, italic: bool) *text.Font {
        if (bold) {
            if (self.bold != null) return &self.bold.?;
            return &self.regular;
        }
        if (italic) {
            if (self.italic != null) return &self.italic.?;
            return &self.regular;
        }
        return &self.regular;
    }
};
