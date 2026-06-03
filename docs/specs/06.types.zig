//! 06 — Markup + style — types.zig
//!
//! Contract (INV-5.1). The descriptor struct shapes (NodeDesc, Attr, AttrValue) and the
//! public signatures are the contract — match them exactly. `parse` and `resolveClasses` are
//! the real work; implemented per spec.md. Do not change signatures.
//!
//! Depends on std + module 03 (LayoutNode/geometry) + module 05 (Tokens/ComputedStyle).
//! All lower-numbered in the corrected build order, so these imports are legal (INV-3.4).

const std = @import("std");
const store = @import("../03_element_store/types.zig");
const theme = @import("../05_theme/types.zig");

pub const LayoutNode = store.LayoutNode;
pub const Tokens = theme.Tokens;
pub const ComputedStyle = theme.ComputedStyle;

// ---------------------------------------------------------------------------
// Markup descriptor tree (output of parse)
// ---------------------------------------------------------------------------

/// An attribute value is either a literal string or a binding path captured from
/// `{bind path}`. Binding paths are recorded only — never evaluated here (spec non-goal).
pub const AttrValue = union(enum) {
    literal: []const u8,
    bind: []const u8, // e.g. "user.name" from text="{bind user.name}"
};

pub const Attr = struct {
    name: []const u8,
    value: AttrValue,
};

/// A parsed markup node. Slices are owned by the allocator passed to `parse`.
pub const NodeDesc = struct {
    tag: []const u8,
    classes: []const u8 = "", // value of class="..." ("" if absent)
    attrs: []const Attr = &.{}, // every attribute except class
    children: []const NodeDesc = &.{},
};

/// Error variants returned by `parse` on failure.
/// Also used as the error-kind field in ParseDiagnostic.
pub const ParseError = error{
    UnexpectedToken,
    UnclosedTag,
    MismatchedTag,
    MalformedAttribute,
    OutOfMemory,
};

/// Error kind enum for ParseDiagnostic (mirrors ParseError variants). (R54)
pub const ParseErrorKind = enum {
    UnexpectedToken,
    UnclosedTag,
    MismatchedTag,
    MalformedAttribute,
};

/// Source location within a `.ui` file (1-based, matching editor conventions). (R54)
pub const SourceLoc = struct {
    line:   u32,  // 1-based line number
    column: u32,  // 1-based byte column on that line
};

/// Diagnostic emitted by `parse` on failure. (R54)
pub const ParseDiagnostic = struct {
    err:     ParseErrorKind,
    loc:     SourceLoc,
    /// A human-readable description of the error. Points into static string storage (no allocation).
    message: []const u8,
};

// ---------------------------------------------------------------------------
// Parser — recursive descent over bytes
// ---------------------------------------------------------------------------

/// Internal parse error set used only within the parser.
const InternalParseError = error{ UnexpectedToken, UnclosedTag, MismatchedTag, MalformedAttribute, OutOfMemory };

/// Internal parser state. (R54: adds line/column tracking)
const Parser = struct {
    src: []const u8,
    pos: usize,
    alloc: std.mem.Allocator,
    line: u32 = 1,   // NEW (R54): current line (1-based)
    column: u32 = 1, // NEW (R54): current byte column (1-based)

    fn init(alloc: std.mem.Allocator, src: []const u8) Parser {
        return .{ .src = src, .pos = 0, .alloc = alloc };
    }

    /// Skip ASCII whitespace. Goes through consume() for line/col tracking.
    fn skipWs(p: *Parser) void {
        while (p.pos < p.src.len and isWs(p.src[p.pos])) {
            _ = p.consume();
        }
    }

    fn peek(p: *Parser) ?u8 {
        if (p.pos >= p.src.len) return null;
        return p.src[p.pos];
    }

    /// Consume one byte, updating line/column. (R54)
    fn consume(p: *Parser) ?u8 {
        if (p.pos >= p.src.len) return null;
        const c = p.src[p.pos];
        p.pos += 1;
        if (c == '\n') {
            p.line   += 1;
            p.column  = 1;
        } else {
            p.column += 1;
        }
        return c;
    }

    fn expect(p: *Parser, c: u8, diag: ?*ParseDiagnostic) InternalParseError!void {
        if (p.pos >= p.src.len or p.src[p.pos] != c) {
            if (diag) |d| d.* = p.makeDiag(.UnexpectedToken,
                "unexpected character; expected '<', '/', '>', '=', or a name");
            return error.UnexpectedToken;
        }
        _ = p.consume();
    }

    /// Read a NAME (tag name or attribute name).
    fn readName(p: *Parser, diag: ?*ParseDiagnostic) InternalParseError![]const u8 {
        const start = p.pos;
        while (p.pos < p.src.len and isNameChar(p.src[p.pos])) {
            _ = p.consume();
        }
        if (p.pos == start) {
            if (diag) |d| d.* = p.makeDiag(.UnexpectedToken,
                "unexpected character; expected '<', '/', '>', '=', or a name");
            return error.UnexpectedToken;
        }
        return p.src[start..p.pos];
    }

    /// Parse the content of a double-quoted attribute value.
    fn readAttrValue(p: *Parser, diag: ?*ParseDiagnostic) InternalParseError!AttrValue {
        try p.expect('"', diag);
        const start = p.pos;
        // Find the closing quote
        while (p.pos < p.src.len and p.src[p.pos] != '"') {
            _ = p.consume();
        }
        const raw = p.src[start..p.pos];
        try p.expect('"', diag);
        // Check for {bind ...}
        if (std.mem.startsWith(u8, raw, "{bind ") and std.mem.endsWith(u8, raw, "}")) {
            const path = raw[6 .. raw.len - 1];
            return AttrValue{ .bind = path };
        }
        return AttrValue{ .literal = raw };
    }

    /// Construct a ParseDiagnostic from current parser state. (R54)
    fn makeDiag(p: *const Parser, err: ParseErrorKind, message: []const u8) ParseDiagnostic {
        return .{
            .err     = err,
            .loc     = .{ .line = p.line, .column = p.column },
            .message = message,
        };
    }

    /// Parse a single node starting from '<'. Returns the parsed NodeDesc.
    fn parseNode(p: *Parser, diag: ?*ParseDiagnostic) InternalParseError!NodeDesc {
        p.skipWs();
        try p.expect('<', diag);

        const tag = try p.readName(diag);
        p.skipWs();

        // Collect attributes
        var attrs_list: std.ArrayListUnmanaged(Attr) = .empty;
        var classes: []const u8 = "";

        while (true) {
            p.skipWs();
            const ch = p.peek() orelse {
                if (diag) |d| d.* = p.makeDiag(.UnclosedTag, "tag was opened but never closed");
                return error.UnclosedTag;
            };
            if (ch == '/' or ch == '>') break;
            // Parse attribute: NAME '=' '"' value '"'
            const name = try p.readName(diag);
            p.skipWs();
            try p.expect('=', diag);
            p.skipWs();
            const val = try p.readAttrValue(diag);
            if (std.mem.eql(u8, name, "class")) {
                switch (val) {
                    .literal => |s| classes = s,
                    .bind => |s| classes = s,
                }
            } else {
                try attrs_list.append(p.alloc, Attr{ .name = name, .value = val });
            }
        }

        const attrs = try attrs_list.toOwnedSlice(p.alloc);

        // Self-closing or container?
        if (p.peek() == '/') {
            _ = p.consume(); // '/'
            try p.expect('>', diag);
            return NodeDesc{
                .tag = tag,
                .classes = classes,
                .attrs = attrs,
                .children = &.{},
            };
        }

        // Container: '>' children* '</' TAG '>'
        try p.expect('>', diag);

        var children_list: std.ArrayListUnmanaged(NodeDesc) = .empty;
        while (true) {
            p.skipWs();
            // Check for closing tag
            if (p.pos + 1 < p.src.len and p.src[p.pos] == '<' and p.src[p.pos + 1] == '/') {
                break;
            }
            if (p.pos >= p.src.len) {
                if (diag) |d| d.* = p.makeDiag(.UnclosedTag, "tag was opened but never closed");
                return error.UnclosedTag;
            }
            const child = try p.parseNode(diag);
            try children_list.append(p.alloc, child);
        }

        // Consume '</'
        try p.expect('<', diag);
        try p.expect('/', diag);
        const close_tag = try p.readName(diag);
        p.skipWs();
        try p.expect('>', diag);

        if (!std.mem.eql(u8, tag, close_tag)) {
            if (diag) |d| d.* = p.makeDiag(.MismatchedTag, "closing tag does not match the opening tag");
            return error.MismatchedTag;
        }

        const children = try children_list.toOwnedSlice(p.alloc);
        return NodeDesc{
            .tag = tag,
            .classes = classes,
            .attrs = attrs,
            .children = children,
        };
    }
};

fn isWs(c: u8) bool {
    return c == ' ' or c == '\t' or c == '\n' or c == '\r';
}

fn isNameChar(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '-' or c == '_' or c == '.';
}

/// Parse `.ui` markup into a descriptor tree rooted at the returned NodeDesc.
/// Backward-compatible 2-arg version (used by existing tests). Internally uses null diag.
pub fn parse(
    allocator: std.mem.Allocator,
    source:    []const u8,
) ParseError!NodeDesc {
    return parseWithDiag(allocator, source, null);
}

/// Parse `.ui` markup with error diagnostics. (R54)
/// On success returns the root NodeDesc. On failure, writes a ParseDiagnostic to
/// `*diag` (if non-null) and returns the ParseError variant.
/// One function, two uses: build-time codegen and hot-reload (INV-4.4).
pub fn parseWithDiag(
    allocator: std.mem.Allocator,
    source:    []const u8,
    diag:      ?*ParseDiagnostic,
) ParseError!NodeDesc {
    var p = Parser.init(allocator, source);
    p.skipWs();
    return p.parseNode(diag);
}

// ---------------------------------------------------------------------------
// Tailwind-subset resolver (classes -> style + layout)
// ---------------------------------------------------------------------------

/// The class string resolved into a style patch and a layout patch. Only class-derived
/// fields are set; everything else is left at struct defaults.
pub const Resolved = struct {
    style: ComputedStyle = .{},
    layout: LayoutNode = .{},
};

// Static fr-track arrays for grid-cols-{n} (1..12). Used to avoid heap allocation.
const fr1 = [1]store.TrackSize{.{ .fr = 1 }};
const fr2 = [2]store.TrackSize{ .{ .fr = 1 }, .{ .fr = 1 } };
const fr3 = [3]store.TrackSize{ .{ .fr = 1 }, .{ .fr = 1 }, .{ .fr = 1 } };
const fr4 = [4]store.TrackSize{ .{ .fr = 1 }, .{ .fr = 1 }, .{ .fr = 1 }, .{ .fr = 1 } };
const fr5 = [5]store.TrackSize{ .{ .fr = 1 }, .{ .fr = 1 }, .{ .fr = 1 }, .{ .fr = 1 }, .{ .fr = 1 } };
const fr6 = [6]store.TrackSize{ .{ .fr = 1 }, .{ .fr = 1 }, .{ .fr = 1 }, .{ .fr = 1 }, .{ .fr = 1 }, .{ .fr = 1 } };
const fr7 = [7]store.TrackSize{ .{ .fr = 1 }, .{ .fr = 1 }, .{ .fr = 1 }, .{ .fr = 1 }, .{ .fr = 1 }, .{ .fr = 1 }, .{ .fr = 1 } };
const fr8 = [8]store.TrackSize{ .{ .fr = 1 }, .{ .fr = 1 }, .{ .fr = 1 }, .{ .fr = 1 }, .{ .fr = 1 }, .{ .fr = 1 }, .{ .fr = 1 }, .{ .fr = 1 } };
const fr9 = [9]store.TrackSize{ .{ .fr = 1 }, .{ .fr = 1 }, .{ .fr = 1 }, .{ .fr = 1 }, .{ .fr = 1 }, .{ .fr = 1 }, .{ .fr = 1 }, .{ .fr = 1 }, .{ .fr = 1 } };
const fr10 = [10]store.TrackSize{ .{ .fr = 1 }, .{ .fr = 1 }, .{ .fr = 1 }, .{ .fr = 1 }, .{ .fr = 1 }, .{ .fr = 1 }, .{ .fr = 1 }, .{ .fr = 1 }, .{ .fr = 1 }, .{ .fr = 1 } };
const fr11 = [11]store.TrackSize{ .{ .fr = 1 }, .{ .fr = 1 }, .{ .fr = 1 }, .{ .fr = 1 }, .{ .fr = 1 }, .{ .fr = 1 }, .{ .fr = 1 }, .{ .fr = 1 }, .{ .fr = 1 }, .{ .fr = 1 }, .{ .fr = 1 } };
const fr12 = [12]store.TrackSize{ .{ .fr = 1 }, .{ .fr = 1 }, .{ .fr = 1 }, .{ .fr = 1 }, .{ .fr = 1 }, .{ .fr = 1 }, .{ .fr = 1 }, .{ .fr = 1 }, .{ .fr = 1 }, .{ .fr = 1 }, .{ .fr = 1 }, .{ .fr = 1 } };

/// Resolve a space-separated class string against theme tokens (see spec.md "Tailwind
/// subset"). Order-independent except last-wins on direct conflict. Unknown classes ignored.
/// Spacing/gap/sizing use the fixed n*4 px scale; color/radius/font-size use tokens.
pub fn resolveClasses(classes: []const u8, tokens: Tokens) Resolved {
    var result = Resolved{};
    var it = std.mem.tokenizeScalar(u8, classes, ' ');
    while (it.next()) |cls| {
        applyClass(cls, tokens, &result);
    }
    return result;
}

fn applyClass(cls: []const u8, tokens: Tokens, r: *Resolved) void {
    // --- R51 Group A: Visibility ---
    if (std.mem.eql(u8, cls, "hidden")) {
        r.layout.display = .none;

    // --- R51 Group B: Overflow ---
    } else if (std.mem.eql(u8, cls, "overflow-hidden")) {
        r.layout.overflow = .hidden;

    // --- Layout display ---
    } else if (std.mem.eql(u8, cls, "flex")) {
        r.layout.display = .flex;
    } else if (std.mem.eql(u8, cls, "grid")) {
        r.layout.display = .grid;
    } else if (std.mem.eql(u8, cls, "block")) {
        r.layout.display = .block;

        // --- Flex direction ---
    } else if (std.mem.eql(u8, cls, "flex-row")) {
        r.layout.direction = .row;
    } else if (std.mem.eql(u8, cls, "flex-col")) {
        r.layout.direction = .column;

        // --- Justify content ---
    } else if (std.mem.eql(u8, cls, "justify-start")) {
        r.layout.justify_content = .start;
    } else if (std.mem.eql(u8, cls, "justify-center")) {
        r.layout.justify_content = .center;
    } else if (std.mem.eql(u8, cls, "justify-end")) {
        r.layout.justify_content = .end;
    } else if (std.mem.eql(u8, cls, "justify-between")) {
        r.layout.justify_content = .space_between;

        // --- Align items ---
    } else if (std.mem.eql(u8, cls, "items-start")) {
        r.layout.align_items = .start;
    } else if (std.mem.eql(u8, cls, "items-center")) {
        r.layout.align_items = .center;
    } else if (std.mem.eql(u8, cls, "items-end")) {
        r.layout.align_items = .end;
    } else if (std.mem.eql(u8, cls, "items-stretch")) {
        r.layout.align_items = .stretch;

        // --- R51 Group C: Sizing constraints ---
    } else if (std.mem.startsWith(u8, cls, "min-w-")) {
        if (parseUint(cls[6..])) |n| r.layout.min_size.w = @as(f32, @floatFromInt(n)) * 4.0;
    } else if (std.mem.startsWith(u8, cls, "max-w-")) {
        if (std.mem.eql(u8, cls[6..], "none")) {
            r.layout.max_size.w = std.math.inf(f32);
        } else if (parseUint(cls[6..])) |n| {
            r.layout.max_size.w = @as(f32, @floatFromInt(n)) * 4.0;
        }
    } else if (std.mem.startsWith(u8, cls, "min-h-")) {
        if (parseUint(cls[6..])) |n| r.layout.min_size.h = @as(f32, @floatFromInt(n)) * 4.0;
    } else if (std.mem.startsWith(u8, cls, "max-h-")) {
        if (std.mem.eql(u8, cls[6..], "none")) {
            r.layout.max_size.h = std.math.inf(f32);
        } else if (parseUint(cls[6..])) |n| {
            r.layout.max_size.h = @as(f32, @floatFromInt(n)) * 4.0;
        }

        // --- Sizing: w-{n}, h-{n} (absorbs old w-full/h-full) ---
    } else if (std.mem.startsWith(u8, cls, "w-")) {
        if (std.mem.eql(u8, cls[2..], "full")) {
            r.layout.width = .{ .percent = 100 };
        } else if (std.mem.eql(u8, cls[2..], "auto")) {
            r.layout.width = .auto;
        } else if (parseUint(cls[2..])) |n| {
            r.layout.width = .{ .px = @as(f32, @floatFromInt(n)) * 4.0 };
        }
    } else if (std.mem.startsWith(u8, cls, "h-")) {
        if (std.mem.eql(u8, cls[2..], "full")) {
            r.layout.height = .{ .percent = 100 };
        } else if (std.mem.eql(u8, cls[2..], "auto")) {
            r.layout.height = .auto;
        } else if (parseUint(cls[2..])) |n| {
            r.layout.height = .{ .px = @as(f32, @floatFromInt(n)) * 4.0 };
        }

        // --- Flex shorthand ---
    } else if (std.mem.eql(u8, cls, "flex-1")) {
        r.layout.flex_grow = 1;
        r.layout.flex_basis = .{ .px = 0 };

        // --- Gap: gap-{n} ---
    } else if (std.mem.startsWith(u8, cls, "gap-")) {
        if (parseUint(cls[4..])) |n| {
            r.layout.gap = @as(f32, @floatFromInt(n)) * 4.0;
        }

        // --- Grid columns: grid-cols-{n} ---
    } else if (std.mem.startsWith(u8, cls, "grid-cols-")) {
        if (parseUint(cls[10..])) |n| {
            r.layout.grid_template_columns = switch (n) {
                1 => &fr1,
                2 => &fr2,
                3 => &fr3,
                4 => &fr4,
                5 => &fr5,
                6 => &fr6,
                7 => &fr7,
                8 => &fr8,
                9 => &fr9,
                10 => &fr10,
                11 => &fr11,
                12 => &fr12,
                else => &.{},
            };
        }

        // --- Padding ---
    } else if (std.mem.startsWith(u8, cls, "p-")) {
        if (parseUint(cls[2..])) |n| {
            const v = @as(f32, @floatFromInt(n)) * 4.0;
            r.style.padding.top = v;
            r.style.padding.right = v;
            r.style.padding.bottom = v;
            r.style.padding.left = v;
        }
    } else if (std.mem.startsWith(u8, cls, "px-")) {
        if (parseUint(cls[3..])) |n| {
            const v = @as(f32, @floatFromInt(n)) * 4.0;
            r.style.padding.left = v;
            r.style.padding.right = v;
        }
    } else if (std.mem.startsWith(u8, cls, "py-")) {
        if (parseUint(cls[3..])) |n| {
            const v = @as(f32, @floatFromInt(n)) * 4.0;
            r.style.padding.top = v;
            r.style.padding.bottom = v;
        }
    } else if (std.mem.startsWith(u8, cls, "pt-")) {
        if (parseUint(cls[3..])) |n| {
            r.style.padding.top = @as(f32, @floatFromInt(n)) * 4.0;
        }
    } else if (std.mem.startsWith(u8, cls, "pr-")) {
        if (parseUint(cls[3..])) |n| {
            r.style.padding.right = @as(f32, @floatFromInt(n)) * 4.0;
        }
    } else if (std.mem.startsWith(u8, cls, "pb-")) {
        if (parseUint(cls[3..])) |n| {
            r.style.padding.bottom = @as(f32, @floatFromInt(n)) * 4.0;
        }
    } else if (std.mem.startsWith(u8, cls, "pl-")) {
        if (parseUint(cls[3..])) |n| {
            r.style.padding.left = @as(f32, @floatFromInt(n)) * 4.0;
        }

        // --- R51 Group D: Margin / horizontal centering ---
    } else if (std.mem.eql(u8, cls, "mx-auto")) {
        r.layout.margin.left  = .auto;
        r.layout.margin.right = .auto;
    } else if (std.mem.startsWith(u8, cls, "m-")) {
        if (parseUint(cls[2..])) |n| {
            const v: store.MarginValue = .{ .px = @as(f32, @floatFromInt(n)) * 4.0 };
            r.layout.margin = .{ .top = v, .right = v, .bottom = v, .left = v };
        }
    } else if (std.mem.startsWith(u8, cls, "mx-")) {
        if (parseUint(cls[3..])) |n| {
            const v: store.MarginValue = .{ .px = @as(f32, @floatFromInt(n)) * 4.0 };
            r.layout.margin.left  = v;
            r.layout.margin.right = v;
        }
    } else if (std.mem.startsWith(u8, cls, "my-")) {
        if (parseUint(cls[3..])) |n| {
            const v: store.MarginValue = .{ .px = @as(f32, @floatFromInt(n)) * 4.0 };
            r.layout.margin.top    = v;
            r.layout.margin.bottom = v;
        }
    } else if (std.mem.startsWith(u8, cls, "mt-")) {
        if (parseUint(cls[3..])) |n| r.layout.margin.top    = .{ .px = @as(f32, @floatFromInt(n)) * 4.0 };
    } else if (std.mem.startsWith(u8, cls, "mr-")) {
        if (parseUint(cls[3..])) |n| r.layout.margin.right  = .{ .px = @as(f32, @floatFromInt(n)) * 4.0 };
    } else if (std.mem.startsWith(u8, cls, "mb-")) {
        if (parseUint(cls[3..])) |n| r.layout.margin.bottom = .{ .px = @as(f32, @floatFromInt(n)) * 4.0 };
    } else if (std.mem.startsWith(u8, cls, "ml-")) {
        if (parseUint(cls[3..])) |n| r.layout.margin.left   = .{ .px = @as(f32, @floatFromInt(n)) * 4.0 };

        // --- R51 Group E: Flex modifiers ---
    } else if (std.mem.eql(u8, cls, "shrink-0")) {
        r.layout.flex_shrink = 0;
    } else if (std.mem.eql(u8, cls, "grow-0")) {
        r.layout.flex_grow = 0;
    } else if (std.mem.eql(u8, cls, "grow")) {
        r.layout.flex_grow = 1;
    } else if (std.mem.eql(u8, cls, "shrink")) {
        r.layout.flex_shrink = 1;
    } else if (std.mem.eql(u8, cls, "self-auto"))    { r.layout.align_self = .auto;
    } else if (std.mem.eql(u8, cls, "self-start"))   { r.layout.align_self = .start;
    } else if (std.mem.eql(u8, cls, "self-center"))  { r.layout.align_self = .center;
    } else if (std.mem.eql(u8, cls, "self-end"))     { r.layout.align_self = .end;
    } else if (std.mem.eql(u8, cls, "self-stretch")) { r.layout.align_self = .stretch;

        // --- R51 Group F: Grid span ---
    } else if (std.mem.startsWith(u8, cls, "col-span-")) {
        if (parseUint(cls[9..])) |n| r.layout.col_span = @intCast(@min(n, 12));
    } else if (std.mem.startsWith(u8, cls, "row-span-")) {
        if (parseUint(cls[9..])) |n| r.layout.row_span = @intCast(@min(n, 12));

        // --- Background colors ---
    } else if (std.mem.eql(u8, cls, "bg-canvas")) {
        r.style.background = tokens.bg_canvas;
    } else if (std.mem.eql(u8, cls, "bg-surface")) {
        r.style.background = tokens.bg_surface;
    } else if (std.mem.eql(u8, cls, "bg-raised")) {
        r.style.background = tokens.bg_raised;
    } else if (std.mem.eql(u8, cls, "bg-accent")) {
        r.style.background = tokens.accent;
    } else if (std.mem.eql(u8, cls, "bg-transparent")) {
        r.style.background = theme.transparent;

        // --- Text colors ---
    } else if (std.mem.eql(u8, cls, "text-body")) {
        r.style.text_color = tokens.text_body;
    } else if (std.mem.eql(u8, cls, "text-muted")) {
        r.style.text_color = tokens.text_muted;
    } else if (std.mem.eql(u8, cls, "text-accent")) {
        r.style.text_color = tokens.accent;

        // --- Font sizes ---
    } else if (std.mem.eql(u8, cls, "text-xs")) {
        r.style.font_size = tokens.text_xs;
    } else if (std.mem.eql(u8, cls, "text-sm")) {
        r.style.font_size = tokens.text_sm;
    } else if (std.mem.eql(u8, cls, "text-base")) {
        r.style.font_size = tokens.text_base;
    } else if (std.mem.eql(u8, cls, "text-lg")) {
        r.style.font_size = tokens.text_lg;
    } else if (std.mem.eql(u8, cls, "text-xl")) {
        r.style.font_size = tokens.text_xl;

        // --- Font weight/style (R60) ---
    } else if (std.mem.eql(u8, cls, "font-bold")) {
        r.style.font_bold = true;
    } else if (std.mem.eql(u8, cls, "font-normal")) {
        r.style.font_bold = false;
    } else if (std.mem.eql(u8, cls, "font-italic") or std.mem.eql(u8, cls, "italic")) {
        r.style.font_italic = true;
    } else if (std.mem.eql(u8, cls, "not-italic")) {
        r.style.font_italic = false;

        // --- Borders ---
    } else if (std.mem.eql(u8, cls, "border")) {
        r.style.border_width = 1;
    } else if (std.mem.eql(u8, cls, "border-subtle")) {
        r.style.border_color = tokens.border_subtle;
    } else if (std.mem.eql(u8, cls, "border-default")) {
        r.style.border_color = tokens.border_default;
    } else if (std.mem.eql(u8, cls, "border-strong")) {
        r.style.border_color = tokens.border_strong;

        // --- Border radius ---
    } else if (std.mem.eql(u8, cls, "rounded-sm")) {
        r.style.radius = tokens.radius_sm;
    } else if (std.mem.eql(u8, cls, "rounded-md")) {
        r.style.radius = tokens.radius_md;
    } else if (std.mem.eql(u8, cls, "rounded-lg")) {
        r.style.radius = tokens.radius_lg;
    } else if (std.mem.eql(u8, cls, "rounded-full")) {
        r.style.radius = 9999;

        // --- Opacity (R45) ---
    } else if (std.mem.eql(u8, cls, "opacity-0")) {
        r.style.opacity = 0.0;
    } else if (std.mem.eql(u8, cls, "opacity-25")) {
        r.style.opacity = 0.25;
    } else if (std.mem.eql(u8, cls, "opacity-50")) {
        r.style.opacity = 0.5;
    } else if (std.mem.eql(u8, cls, "opacity-75")) {
        r.style.opacity = 0.75;
    } else if (std.mem.eql(u8, cls, "opacity-100")) {
        r.style.opacity = 1.0;

        // --- Text truncation (R44) ---
    } else if (std.mem.eql(u8, cls, "truncate")) {
        r.style.truncate = true;

        // --- Box shadow (R46) ---
    } else if (std.mem.eql(u8, cls, "shadow-sm")) {
        r.style.shadow_blur = 4;
        r.style.shadow_offset_x = 0;
        r.style.shadow_offset_y = 1;
        r.style.shadow_color = .{ .r = 0, .g = 0, .b = 0, .a = 20 };
    } else if (std.mem.eql(u8, cls, "shadow")) {
        r.style.shadow_blur = 6;
        r.style.shadow_offset_x = 0;
        r.style.shadow_offset_y = 2;
        r.style.shadow_color = .{ .r = 0, .g = 0, .b = 0, .a = 30 };
    } else if (std.mem.eql(u8, cls, "shadow-md")) {
        r.style.shadow_blur = 8;
        r.style.shadow_offset_x = 0;
        r.style.shadow_offset_y = 4;
        r.style.shadow_color = .{ .r = 0, .g = 0, .b = 0, .a = 45 };
    } else if (std.mem.eql(u8, cls, "shadow-lg")) {
        r.style.shadow_blur = 16;
        r.style.shadow_offset_x = 0;
        r.style.shadow_offset_y = 8;
        r.style.shadow_color = .{ .r = 0, .g = 0, .b = 0, .a = 50 };
    } else if (std.mem.eql(u8, cls, "shadow-xl")) {
        r.style.shadow_blur = 24;
        r.style.shadow_offset_x = 0;
        r.style.shadow_offset_y = 10;
        r.style.shadow_color = .{ .r = 0, .g = 0, .b = 0, .a = 55 };
    } else if (std.mem.eql(u8, cls, "shadow-none")) {
        r.style.shadow_blur = 0;
        r.style.shadow_offset_x = 0;
        r.style.shadow_offset_y = 0;
        r.style.shadow_color = .{ .r = 0, .g = 0, .b = 0, .a = 0 };
    }
    // Unknown classes: silently ignore (last-wins via sequential application)
}

// ---------------------------------------------------------------------------
// R50 — Inline style helpers
// ---------------------------------------------------------------------------

/// Parse a #RRGGBB or #RRGGBBAA hex color string.
/// Returns null if the string is not a valid hex color.
pub fn parseHexColor(s: []const u8) ?theme.Color {
    if (s.len == 0 or s[0] != '#') return null;
    const digits = s[1..];
    switch (digits.len) {
        6 => {
            const rgb = std.fmt.parseInt(u24, digits, 16) catch return null;
            return theme.Color.hex(rgb);
        },
        8 => {
            const rgba = std.fmt.parseInt(u32, digits, 16) catch return null;
            return theme.Color{
                .r = @intCast((rgba >> 24) & 0xFF),
                .g = @intCast((rgba >> 16) & 0xFF),
                .b = @intCast((rgba >> 8)  & 0xFF),
                .a = @intCast(rgba & 0xFF),
            };
        },
        else => return null,
    }
}

/// Parse a decimal float string (e.g. "12", "1.5"). Returns null on failure.
pub fn parseFloat(s: []const u8) ?f32 {
    return std.fmt.parseFloat(f32, s) catch null;
}

/// Parse an unsigned integer from a string. Returns null on failure.
fn parseUint(s: []const u8) ?u32 {
    if (s.len == 0) return null;
    var result: u32 = 0;
    for (s) |c| {
        if (!std.ascii.isDigit(c)) return null;
        result = result * 10 + (c - '0');
    }
    return result;
}
