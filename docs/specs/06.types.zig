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

pub const ParseError = error{
    UnexpectedToken,
    UnclosedTag,
    MismatchedTag,
    MalformedAttribute,
    OutOfMemory,
};

// ---------------------------------------------------------------------------
// Parser — recursive descent over bytes
// ---------------------------------------------------------------------------

/// Internal parser state.
const Parser = struct {
    src: []const u8,
    pos: usize,
    alloc: std.mem.Allocator,

    fn init(alloc: std.mem.Allocator, src: []const u8) Parser {
        return .{ .src = src, .pos = 0, .alloc = alloc };
    }

    /// Skip ASCII whitespace.
    fn skipWs(p: *Parser) void {
        while (p.pos < p.src.len and isWs(p.src[p.pos])) {
            p.pos += 1;
        }
    }

    fn peek(p: *Parser) ?u8 {
        if (p.pos >= p.src.len) return null;
        return p.src[p.pos];
    }

    fn consume(p: *Parser) ?u8 {
        if (p.pos >= p.src.len) return null;
        const c = p.src[p.pos];
        p.pos += 1;
        return c;
    }

    fn expect(p: *Parser, c: u8) ParseError!void {
        if (p.pos >= p.src.len or p.src[p.pos] != c) return ParseError.UnexpectedToken;
        p.pos += 1;
    }

    /// Read a NAME (tag name or attribute name): starts at current pos, ends at first
    /// character that is not alphanumeric, '-', '_', or '.'.
    fn readName(p: *Parser) ParseError![]const u8 {
        const start = p.pos;
        while (p.pos < p.src.len and isNameChar(p.src[p.pos])) {
            p.pos += 1;
        }
        if (p.pos == start) return ParseError.UnexpectedToken;
        return p.src[start..p.pos];
    }

    /// Parse the content of a double-quoted attribute value.
    /// Handles `{bind path}` as a bind value; everything else is literal.
    fn readAttrValue(p: *Parser) ParseError!AttrValue {
        try p.expect('"');
        const start = p.pos;
        // Find the closing quote
        while (p.pos < p.src.len and p.src[p.pos] != '"') {
            p.pos += 1;
        }
        const raw = p.src[start..p.pos];
        try p.expect('"');
        // Check for {bind ...}
        if (std.mem.startsWith(u8, raw, "{bind ") and std.mem.endsWith(u8, raw, "}")) {
            const path = raw[6 .. raw.len - 1];
            return AttrValue{ .bind = path };
        }
        return AttrValue{ .literal = raw };
    }

    /// Parse a single node starting from '<'. Returns the parsed NodeDesc.
    fn parseNode(p: *Parser) ParseError!NodeDesc {
        p.skipWs();
        try p.expect('<');

        const tag = try p.readName();
        p.skipWs();

        // Collect attributes
        var attrs_list: std.ArrayListUnmanaged(Attr) = .empty;
        var classes: []const u8 = "";

        while (true) {
            p.skipWs();
            const ch = p.peek() orelse return ParseError.UnclosedTag;
            if (ch == '/' or ch == '>') break;
            // Parse attribute: NAME '=' '"' value '"'
            const name = try p.readName();
            p.skipWs();
            try p.expect('=');
            p.skipWs();
            const val = try p.readAttrValue();
            if (std.mem.eql(u8, name, "class")) {
                // class attr: capture into classes; value must be literal
                switch (val) {
                    .literal => |s| classes = s,
                    .bind => |s| classes = s, // unlikely but handle gracefully
                }
            } else {
                try attrs_list.append(p.alloc, Attr{ .name = name, .value = val });
            }
        }

        const attrs = try attrs_list.toOwnedSlice(p.alloc);

        // Self-closing or container?
        if (p.peek() == '/') {
            // Self-closing: />
            p.pos += 1; // '/'
            try p.expect('>');
            return NodeDesc{
                .tag = tag,
                .classes = classes,
                .attrs = attrs,
                .children = &.{},
            };
        }

        // Container: '>' children* '</' TAG '>'
        try p.expect('>');

        var children_list: std.ArrayListUnmanaged(NodeDesc) = .empty;
        while (true) {
            p.skipWs();
            // Check for closing tag
            if (p.pos + 1 < p.src.len and p.src[p.pos] == '<' and p.src[p.pos + 1] == '/') {
                break;
            }
            if (p.pos >= p.src.len) return ParseError.UnclosedTag;
            const child = try p.parseNode();
            try children_list.append(p.alloc, child);
        }

        // Consume '</'
        try p.expect('<');
        try p.expect('/');
        const close_tag = try p.readName();
        p.skipWs();
        try p.expect('>');

        if (!std.mem.eql(u8, tag, close_tag)) return ParseError.MismatchedTag;

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
/// One function, two uses (spec refinement 1): run at build time by the codegen step to emit
/// baked struct literals, and at app runtime behind `-Dhot-reload` for live editing. Keep it
/// free of constructs that would prevent build-time use.
pub fn parse(allocator: std.mem.Allocator, source: []const u8) ParseError!NodeDesc {
    var p = Parser.init(allocator, source);
    p.skipWs();
    const node = try p.parseNode();
    return node;
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
    // --- Layout display ---
    if (std.mem.eql(u8, cls, "flex")) {
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

        // --- Sizing ---
    } else if (std.mem.eql(u8, cls, "w-full")) {
        r.layout.width = .{ .percent = 100 };
    } else if (std.mem.eql(u8, cls, "h-full")) {
        r.layout.height = .{ .percent = 100 };

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
    } else if (std.mem.eql(u8, cls, "text-sm")) {
        r.style.font_size = tokens.text_sm;
    } else if (std.mem.eql(u8, cls, "text-base")) {
        r.style.font_size = tokens.text_base;
    } else if (std.mem.eql(u8, cls, "text-lg")) {
        r.style.font_size = tokens.text_lg;

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
    }
    // Unknown classes: silently ignore (last-wins via sequential application)
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
