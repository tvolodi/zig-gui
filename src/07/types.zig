//! 07 — Components — src/07/types.zig
//!
//! Full implementation of module 07 (Components). Turns a NodeDesc tree (from module 06
//! parser) into a live element tree in the ElementStore. Owns parallel presentation arrays
//! (_kind, _style, _text) index-aligned with the store's layout[].
//!
//! Imports:
//!   02 — text (Font, GlyphAtlas, layoutParagraph)
//!   03 — element store (ElementStore, ElementId, LayoutNode)
//!   05 — theme (Tokens, ComputedStyle, buttonPrimary, etc.)
//!   06 — markup (NodeDesc, resolveClasses, Resolved)

const std = @import("std");
const text = @import("../02/types.zig");
const store_mod = @import("../03/types.zig");
const theme = @import("../05/types.zig");
const markup = @import("../06/types.zig");
const font_family_mod = @import("../app/font_family.zig");
const debug = @import("debug.zig");

// ---------------------------------------------------------------------------
// Re-exports used by the acceptance test
// ---------------------------------------------------------------------------

pub const ElementId = store_mod.ElementId;
pub const ElementStore = store_mod.ElementStore;
pub const LayoutNode = store_mod.LayoutNode;
pub const Tokens = theme.Tokens;
pub const ComputedStyle = theme.ComputedStyle;
pub const NodeDesc = markup.NodeDesc;

/// R60 — Re-export FontFamily so callers only need to import this module.
pub const FontFamily = font_family_mod.FontFamily;

// ---------------------------------------------------------------------------
// Widget kinds + registry
// ---------------------------------------------------------------------------

/// Sentinel value used by R75, R7C, R7D to indicate "no element".
pub const NONE: u32 = std.math.maxInt(u32);

pub const WidgetKind = enum { text, button, input, card, row, column, dropdown, checkbox, scrollview, image, icon, textarea, separator, radio, slider, progress_bar, spinner, tabs, tab_item, accordion, date_picker, avatar, badge, data_table };

/// R40 — Pseudo-state flags for interactive widgets.
pub const PseudoState = packed struct {
    hover: bool = false,
    focus: bool = false,
    active: bool = false,
    disabled: bool = false,
};

/// ImageId — opaque handle to a registered image in the ImageAtlas (R43).
pub const ImageId = u16;

/// Per-element image state (R43).
pub const ImageState = struct {
    image_id: ImageId = 0,
    tint: theme.Color = .{ .r = 255, .g = 255, .b = 255, .a = 255 },
};

/// Map a markup tag to a widget kind. Unknown tag → null.
pub fn tagToKind(tag: []const u8) ?WidgetKind {
    const eql = std.mem.eql;
    if (eql(u8, tag, "Text")) return .text;
    if (eql(u8, tag, "Button")) return .button;
    if (eql(u8, tag, "Input")) return .input;
    if (eql(u8, tag, "Card")) return .card;
    if (eql(u8, tag, "Row")) return .row;
    if (eql(u8, tag, "Column")) return .column;
    if (eql(u8, tag, "Dropdown")) return .dropdown;
    if (eql(u8, tag, "Checkbox")) return .checkbox;
    if (eql(u8, tag, "ScrollView")) return .scrollview;
    if (eql(u8, tag, "Image")) return .image;
    if (eql(u8, tag, "Icon")) return .icon;
    if (eql(u8, tag, "Textarea")) return .textarea;
    if (eql(u8, tag, "Separator")) return .separator;
    if (eql(u8, tag, "Radio")) return .radio;
    if (eql(u8, tag, "Slider")) return .slider;
    if (eql(u8, tag, "ProgressBar")) return .progress_bar;
    if (eql(u8, tag, "Spinner")) return .spinner;
    if (eql(u8, tag, "Tabs")) return .tabs;
    if (eql(u8, tag, "TabItem")) return .tab_item;
    if (eql(u8, tag, "Accordion")) return .accordion;
    if (eql(u8, tag, "DatePicker")) return .date_picker;
    if (eql(u8, tag, "Avatar")) return .avatar;
    if (eql(u8, tag, "Badge")) return .badge;
    if (eql(u8, tag, "DataTable")) return .data_table;
    return null;
}

/// Per-kind default layout. Row/Column are flex containers; ScrollView clips; everything else is block.
pub fn defaultLayoutFor(kind: WidgetKind) LayoutNode {
    return switch (kind) {
        .row => .{ .display = .flex, .direction = .row },
        .column => .{ .display = .flex, .direction = .column },
        .card => .{ .display = .flex, .direction = .column },
        .scrollview => .{ .display = .block, .overflow = .hidden },
        .textarea => .{ .display = .block, .overflow = .hidden },
        .separator => .{ .display = .block, .width = .{ .percent = 100 }, .height = .{ .px = 4 }, .flex_shrink = 0, .min_size = .{ .h = 4 } },
        .checkbox => .{ .display = .block, .height = .{ .px = 24 }, .flex_shrink = 0, .min_size = .{ .h = 24 } },
        .radio => .{ .display = .block, .height = .{ .px = 24 }, .flex_shrink = 0, .min_size = .{ .h = 24 } },
        .slider => .{ .display = .block, .height = .{ .px = 24 }, .flex_shrink = 0, .min_size = .{ .h = 24 } },
        .progress_bar => .{ .display = .block, .height = .{ .px = 8 }, .flex_shrink = 0, .min_size = .{ .h = 8 } },
        .spinner => .{ .display = .block, .width = .{ .px = 24 }, .height = .{ .px = 24 } },
        .tabs => .{ .display = .flex, .direction = .column },
        .tab_item => .{ .display = .block },
        .accordion => .{ .display = .block },
        .date_picker => .{ .display = .flex, .direction = .row, .align_items = .center },
        .avatar => .{ .display = .block, .width = .{ .px = 40 }, .height = .{ .px = 40 } },
        .badge => .{ .display = .block, .width = .{ .px = 32 }, .height = .{ .px = 20 }, .flex_shrink = 0 },
        .data_table => .{ .display = .block, .overflow = .hidden },
        .button => .{ .display = .block, .flex_shrink = 0 }, // no shrink
        else => .{ .display = .block },
    };
}

/// Per-kind default style, wired to module 05's component builders.
pub fn defaultStyleFor(kind: WidgetKind, tokens: Tokens) ComputedStyle {
    return switch (kind) {
        .button => theme.buttonPrimary(tokens),
        .card => theme.cardSurface(tokens),
        .input, .dropdown, .textarea => theme.inputDefault(tokens),
        .separator => ComputedStyle{ .background = tokens.border_strong },
        .text => ComputedStyle{ .text_color = tokens.text_body, .font_size = tokens.text_base },
        .checkbox, .radio => ComputedStyle{ .text_color = tokens.text_body },
        .row, .column, .scrollview, .image, .icon, .slider, .progress_bar, .spinner, .tabs, .tab_item, .accordion, .date_picker, .avatar, .badge, .data_table => ComputedStyle{},
    };
}

// ---------------------------------------------------------------------------
// Focus ring color token (B1 — INV-4.3: no hex literals in rendering code)
// ---------------------------------------------------------------------------

/// Named constant for the focus ring border color.
/// Referenced by name in rendering code; never as a hex literal.
pub const FOCUS_RING_COLOR: theme.Color = .{ .r = 0, .g = 0x66, .b = 0xFF, .a = 255 };

// ---------------------------------------------------------------------------
// Per-widget state types (INV-3.1 — parallel arrays, not per-widget heap objects)
// ---------------------------------------------------------------------------

/// Type-erased callback fired at frame-end. NOT a reactivity path (INV-3.3).
pub const CallbackFn = struct {
    ptr: *anyopaque,
    call: *const fn (*anyopaque) void,
};

pub const ButtonState = struct {
    hovered: bool = false,
    pressed: bool = false,
    disabled: bool = false,
    on_click: ?CallbackFn = null,
};

pub const InputState = struct {
    text: std.ArrayListUnmanaged(u8) = .empty,
    cursor: u32 = 0,
    active: bool = false,
};

pub const DropdownOption = struct {
    label: []const u8,
    value: *anyopaque,
};

pub const DropdownState = struct {
    options: std.ArrayListUnmanaged(DropdownOption) = .empty,
    selected_idx: u32 = 0,
    open: bool = false,
    highlight_idx: u32 = 0,
};

pub const CheckboxState = struct {
    checked: bool = false,
    disabled: bool = false,
    hovered: bool = false,
    pressed: bool = false,
    on_change: ?CallbackFn = null,
};

// ---------------------------------------------------------------------------
// R71 — Radio group state
// ---------------------------------------------------------------------------

pub const RadioState = struct {
    group_id: u16 = 0,
    value_str: []const u8 = "",
    selected: bool = false,
    disabled: bool = false,
    hovered: bool = false,
    pressed: bool = false,
};

// ---------------------------------------------------------------------------
// R72 — Slider state
// ---------------------------------------------------------------------------

pub const SliderState = struct {
    value: f32 = 0,
    min: f32 = 0,
    max: f32 = 100,
    step: f32 = 1,
    dragging: bool = false,
    hovered: bool = false,
    disabled: bool = false,
};

// ---------------------------------------------------------------------------
// R73 — Progress bar / spinner state
// ---------------------------------------------------------------------------

pub const ProgressState = struct {
    value: f32 = 0,
    indeterminate: bool = false,
};

// ---------------------------------------------------------------------------
// R76 — Tabs state
// ---------------------------------------------------------------------------

pub const TabsState = struct {
    active_idx: u32 = 0,
    tab_count: u32 = 0,
};

// ---------------------------------------------------------------------------
// R77 — Accordion state
// ---------------------------------------------------------------------------

pub const AccordionState = struct {
    open: bool = false,
    hovered: bool = false,
    disabled: bool = false,
    /// Index of the body child element (NONE if not yet resolved).
    body_idx: u32 = std.math.maxInt(u32),
};

// ---------------------------------------------------------------------------
// R78 — Date picker state
// ---------------------------------------------------------------------------

pub const DateValue = struct {
    year: u16 = 0,
    month: u8 = 1,
    day: u8 = 1,
};

pub const DatePickerState = struct {
    value: DateValue = .{},
    nav_year: u16 = 2025,
    nav_month: u8 = 1,
    open: bool = false,
    disabled: bool = false,
};

// ---------------------------------------------------------------------------
// R7B — Avatar / badge state
// ---------------------------------------------------------------------------

pub const AvatarState = struct {
    image_id: ImageId = 0,
    initials: [2]u8 = .{ '?', 0 },
    size_px: f32 = 40,
};

pub const BadgeColor = enum { default, success, warning, error_c };

pub const BadgeState = struct {
    text: [8]u8 = .{0} ** 8,
    color: BadgeColor = .default,
};

// ---------------------------------------------------------------------------
// R79 — Data table state
// ---------------------------------------------------------------------------

pub const ColumnAlign = enum { left, center, right };
pub const SortDir = enum { none, asc, desc };
pub const MAX_COLUMNS: u8 = 16;
pub const MAX_TABLE_ROWS: u32 = 1000;

pub const DataColumn = struct {
    header: [64]u8 = [_]u8{0} ** 64,
    header_len: u8 = 0,
    width_px: f32 = 120,
    col_align: ColumnAlign = .left,
    sortable: bool = true,

    pub fn headerSlice(self: *const DataColumn) []const u8 {
        return self.header[0..self.header_len];
    }
};

/// Caller-owned callback to extract cell text from a row pointer.
/// Writes cell text into `buf` and returns the byte count.
/// `row_ptr` points to one element of the caller's row array.
pub const CellTextFn = *const fn (row_ptr: *anyopaque, col: u8, buf: []u8) u8;

pub const DataTableRows = struct {
    row_ptr: *anyopaque,
    row_size: usize,
    row_count: u32,
    cell_fn: CellTextFn,
};

pub const DataTableState = struct {
    columns: [MAX_COLUMNS]DataColumn = [_]DataColumn{.{}} ** MAX_COLUMNS,
    col_count: u8 = 0,
    sort_col: u8 = 0xFF,
    sort_dir: SortDir = .none,
    sorted_indices: std.ArrayListUnmanaged(u32) = .empty,
    scroll_y: f32 = 0,
    row_height: f32 = 32,
    rows: ?*const DataTableRows = null,
};

pub const ScrollState = struct {
    scroll_y: f32 = 0,
    scroll_x: f32 = 0,
    content_height: f32 = 0,
    content_width: f32 = 0,
    container_height: f32 = 0,
    container_width: f32 = 0,
    dragging_v_scrollbar: bool = false,
    dragging_h_scrollbar: bool = false,
    drag_start_y: f32 = 0,
    drag_start_x: f32 = 0,
    drag_start_scroll_y: f32 = 0,
    drag_start_scroll_x: f32 = 0,
};

// ---------------------------------------------------------------------------
// R62 — Text selection state
// ---------------------------------------------------------------------------

/// Byte-offset selection range for a text or input element.
/// `anchor` is where the selection started; `active` is where it currently ends.
/// When anchor == active the selection is collapsed (no visible highlight).
pub const TextSelection = struct {
    anchor: u32 = 0,
    active: u32 = 0,

    pub fn isEmpty(self: TextSelection) bool {
        return self.anchor == self.active;
    }

    pub fn range(self: TextSelection) struct { lo: u32, hi: u32 } {
        if (self.anchor <= self.active)
            return .{ .lo = self.anchor, .hi = self.active };
        return .{ .lo = self.active, .hi = self.anchor };
    }
};

// ---------------------------------------------------------------------------
// R63 — Textarea state
// ---------------------------------------------------------------------------

/// Extra per-element state for multi-line textarea widgets.
/// Shares the element's InputState (cursor, text buffer, active flag).
/// Both arrays are indexed by ElementId.index; non-textarea slots are zeroed (unused).
pub const TextareaState = struct {
    /// Byte position of each line's start in the text buffer.
    /// Index 0 is always 0. Rebuilt on every text mutation.
    line_starts: std.ArrayListUnmanaged(u32) = .empty,

    /// Vertical scroll offset within the textarea (pixels scrolled down).
    scroll_y: f32 = 0,

    /// Total content height in pixels (sum of all line heights).
    content_h: f32 = 0,

    /// Height of the visible textarea area (from layout rect).
    container_h: f32 = 0,
};

// ---------------------------------------------------------------------------
// Step-snapping helper (R72)
// ---------------------------------------------------------------------------

fn snapToStep(value: f32, min: f32, step: f32) f32 {
    if (step == 0) return value;
    return min + @round((value - min) / step) * step;
}

// ---------------------------------------------------------------------------
// Date parsing helper (R78)
// ---------------------------------------------------------------------------

/// Parse "YYYY-MM-DD" into DateValue. Returns null if malformed.
fn parseDateStr(s: []const u8) ?DateValue {
    if (s.len != 10) return null;
    if (s[4] != '-' or s[7] != '-') return null;
    const year = std.fmt.parseInt(u16, s[0..4], 10) catch return null;
    const month = std.fmt.parseInt(u8, s[5..7], 10) catch return null;
    const day = std.fmt.parseInt(u8, s[8..10], 10) catch return null;
    if (month < 1 or month > 12) return null;
    if (day < 1 or day > 31) return null;
    return DateValue{ .year = year, .month = month, .day = day };
}

// ---------------------------------------------------------------------------
// Group name → u16 hash helper (R71)
// ---------------------------------------------------------------------------

fn hashGroupName(name: []const u8) u16 {
    var hash: u32 = 5381;
    for (name) |c| {
        hash = hash *% 33 +% @as(u32, c);
    }
    return @truncate(hash);
}

// ---------------------------------------------------------------------------
// Color equality helper
// ---------------------------------------------------------------------------

fn colorEq(a: theme.Color, b: theme.Color) bool {
    return a.r == b.r and a.g == b.g and a.b == b.b and a.a == b.a;
}

// ---------------------------------------------------------------------------
// Dimension equality helper (tagged union)
// ---------------------------------------------------------------------------

fn dimensionEq(a: store_mod.Dimension, b: store_mod.Dimension) bool {
    return std.meta.eql(a, b);
}

// ---------------------------------------------------------------------------
// Scene — owns the ElementStore + parallel presentation arrays
// ---------------------------------------------------------------------------

pub const InstantiateError = error{
    UnknownTag,
    OutOfMemory,
};

pub const Scene = struct {
    elements: ElementStore,

    _kind: std.ArrayListUnmanaged(WidgetKind) = .empty,
    _style: std.ArrayListUnmanaged(ComputedStyle) = .empty,
    _text: std.ArrayListUnmanaged(?[]const u8) = .empty,

    // Focus state (R30)
    focused_idx: u32 = std.math.maxInt(u32),
    focusable_indices: std.ArrayListUnmanaged(u32) = .empty,

    // Per-widget state parallel arrays (INV-3.1)
    _button_state: std.ArrayListUnmanaged(ButtonState) = .empty,
    _queued_callbacks: std.ArrayListUnmanaged(CallbackFn) = .empty,
    _input_state: std.ArrayListUnmanaged(InputState) = .empty,
    _dropdown_state: std.ArrayListUnmanaged(DropdownState) = .empty,
    _checkbox_state: std.ArrayListUnmanaged(CheckboxState) = .empty,
    _scroll_state: std.ArrayListUnmanaged(ScrollState) = .empty,

    // R40 — Pseudo-state parallel array
    _pseudo: std.ArrayListUnmanaged(PseudoState) = .empty,

    // R43 — Image state parallel array
    _image_state: std.ArrayListUnmanaged(ImageState) = .empty,

    // R52 — Hidden state parallel arrays
    _hidden: std.ArrayListUnmanaged(bool) = .empty,
    _saved_display: std.ArrayListUnmanaged(store_mod.Display) = .empty,

    // R62 — Selection state parallel array
    _selection: std.ArrayListUnmanaged(TextSelection) = .empty,

    // R63 — Textarea state parallel array
    _textarea_state: std.ArrayListUnmanaged(TextareaState) = .empty,

    // R71 — Radio state parallel array
    _radio_state: std.ArrayListUnmanaged(RadioState) = .empty,

    // R72 — Slider state parallel array
    _slider_state: std.ArrayListUnmanaged(SliderState) = .empty,

    // R73 — Progress / spinner state parallel array
    _progress_state: std.ArrayListUnmanaged(ProgressState) = .empty,

    // R76 — Tabs state parallel array
    _tabs_state: std.ArrayListUnmanaged(TabsState) = .empty,

    // R77 — Accordion state parallel array
    _accordion_state: std.ArrayListUnmanaged(AccordionState) = .empty,

    // R78 — Date picker state parallel array
    _date_picker_state: std.ArrayListUnmanaged(DatePickerState) = .empty,

    // R7B — Avatar state parallel array
    _avatar_state: std.ArrayListUnmanaged(AvatarState) = .empty,

    // R7B — Badge state parallel array
    _badge_state: std.ArrayListUnmanaged(BadgeState) = .empty,

    // R7C — Tooltip text parallel array (null = no tooltip)
    _tooltip: std.ArrayListUnmanaged(?[]const u8) = .empty,

    // R7D — Context menu index parallel array (0xFF = no menu)
    _context_menu_idx: std.ArrayListUnmanaged(u8) = .empty,

    // R79 — Data table state parallel array
    _table_state: std.ArrayListUnmanaged(DataTableState) = .empty,

    // R93 — Class string parallel array for theme live-swap (one entry per element).
    // Stores the `NodeDesc.classes` slice (owned by the markup arena — no copy needed).
    // Used by rebuildStyles to re-run class resolution after a theme change.
    // NOTE: Inline style:* overrides are NOT preserved through a theme swap (v1 limitation).
    _classes: std.ArrayListUnmanaged([]const u8) = .empty,

    // R73 — Frame counter and timestamp for animation (updated each frame by app).
    frame_count: u64 = 0,
    frame_time_ms: u64 = 0,

    /// Optional: set by app.zig before calling measurePass/buildDrawList for bold/italic face
    /// selection (R60). When null, measurePass falls back to the `font` parameter directly.
    /// Acceptance tests leave this null — they pass a single *Font.
    font_family: ?*font_family_mod.FontFamily = null,

    gpa: std.mem.Allocator,

    pub fn init(gpa: std.mem.Allocator) Scene {
        return Scene{
            .gpa = gpa,
            .elements = ElementStore.init(gpa),
        };
    }

    pub fn deinit(self: *Scene) void {
        // Free text content in InputState items before clearing.
        for (self._input_state.items) |*inp| inp.text.deinit(self.gpa);
        for (self._dropdown_state.items) |*dd| dd.options.deinit(self.gpa);
        for (self._textarea_state.items) |*ts| ts.line_starts.deinit(self.gpa);
        self._kind.deinit(self.gpa);
        self._style.deinit(self.gpa);
        self._text.deinit(self.gpa);
        self.focusable_indices.deinit(self.gpa);
        self._button_state.deinit(self.gpa);
        self._queued_callbacks.deinit(self.gpa);
        self._input_state.deinit(self.gpa);
        self._dropdown_state.deinit(self.gpa);
        self._checkbox_state.deinit(self.gpa);
        self._scroll_state.deinit(self.gpa);
        self._pseudo.deinit(self.gpa);
        self._image_state.deinit(self.gpa);
        self._hidden.deinit(self.gpa);
        self._saved_display.deinit(self.gpa);
        self._selection.deinit(self.gpa);
        self._textarea_state.deinit(self.gpa);
        self._radio_state.deinit(self.gpa);
        self._slider_state.deinit(self.gpa);
        self._progress_state.deinit(self.gpa);
        self._tabs_state.deinit(self.gpa);
        self._accordion_state.deinit(self.gpa);
        self._date_picker_state.deinit(self.gpa);
        self._avatar_state.deinit(self.gpa);
        self._badge_state.deinit(self.gpa);
        self._tooltip.deinit(self.gpa);
        self._context_menu_idx.deinit(self.gpa);
        for (self._table_state.items) |*ts| ts.sorted_indices.deinit(self.gpa);
        self._table_state.deinit(self.gpa);
        self._classes.deinit(self.gpa);
        self.elements.deinit();
    }

    pub fn reset(self: *Scene) void {
        for (self._input_state.items) |*inp| inp.text.deinit(self.gpa);
        for (self._dropdown_state.items) |*dd| dd.options.deinit(self.gpa);
        for (self._textarea_state.items) |*ts| ts.line_starts.deinit(self.gpa);
        self._kind.clearRetainingCapacity();
        self._style.clearRetainingCapacity();
        self._text.clearRetainingCapacity();
        self.focusable_indices.clearRetainingCapacity();
        self._button_state.clearRetainingCapacity();
        self._queued_callbacks.clearRetainingCapacity();
        self._input_state.clearRetainingCapacity();
        self._dropdown_state.clearRetainingCapacity();
        self._checkbox_state.clearRetainingCapacity();
        self._scroll_state.clearRetainingCapacity();
        self._pseudo.clearRetainingCapacity();
        self._image_state.clearRetainingCapacity();
        self._hidden.clearRetainingCapacity();
        self._saved_display.clearRetainingCapacity();
        self._selection.clearRetainingCapacity();
        self._textarea_state.clearRetainingCapacity();
        self._radio_state.clearRetainingCapacity();
        self._slider_state.clearRetainingCapacity();
        self._progress_state.clearRetainingCapacity();
        self._tabs_state.clearRetainingCapacity();
        self._accordion_state.clearRetainingCapacity();
        self._date_picker_state.clearRetainingCapacity();
        self._avatar_state.clearRetainingCapacity();
        self._badge_state.clearRetainingCapacity();
        self._tooltip.clearRetainingCapacity();
        self._context_menu_idx.clearRetainingCapacity();
        self._table_state.clearRetainingCapacity();
        self._classes.clearRetainingCapacity();
        self.focused_idx = std.math.maxInt(u32);
        self.elements.reset();
    }

    /// Build the descriptor subtree into the store + presentation arrays (no font).
    /// Returns the root id. Unknown tag → InstantiateError.UnknownTag.
    /// Calls markAllDirty() after a successful instantiation so the first frame
    /// always runs the full layout + paint pipeline (R21 / M2-02).
    pub fn instantiate(self: *Scene, desc: NodeDesc, tokens: Tokens) InstantiateError!ElementId {
        const id = try self.instantiateNode(desc, tokens, null);
        self.elements.markAllDirty();
        // Rebuild focusable_indices (R30, B2: includes .checkbox).
        self.focusable_indices.clearRetainingCapacity();
        for (self._kind.items, 0..) |kind, i| {
            switch (kind) {
                .button, .input, .dropdown, .checkbox, .textarea, .radio, .slider, .accordion, .date_picker => {
                    self.focusable_indices.append(self.gpa, @as(u32, @intCast(i))) catch {};
                },
                else => {},
            }
        }
        return id;
    }

    // -----------------------------------------------------------------------
    // R91 — Scene dump (forwarding wrappers)
    // -----------------------------------------------------------------------

    /// Write a human-readable indented element tree to stderr (R91).
    pub fn debugPrint(self: *const Scene) void {
        debug.debugPrintScene(self);
    }

    /// Write a one-line summary (live/total/dirty/focused) to stderr (R91).
    pub fn debugPrintStats(self: *const Scene) void {
        debug.debugPrintSceneStats(self);
    }

    /// Measure every text-bearing element and fill its LayoutNode.measured.    /// `font` is the fallback face used when self.font_family is null (acceptance test path).
    /// When self.font_family is set (app path, R60), per-element bold/italic face is selected.
    pub fn measurePass(self: *Scene, font: *text.Font, atlas: *text.GlyphAtlas) text.FontError!void {
        for (self._text.items, 0..) |maybe_str, i| {
            const str = maybe_str orelse continue;
            const style = self._style.items[i];
            const effective_font = if (self.font_family) |fam|
                fam.face(style.font_bold, style.font_italic)
            else
                font;
            const para = try text.layoutParagraphEx(self.gpa, effective_font, atlas, str, style.font_size, 1e6, self.font_family);
            defer self.gpa.free(para.glyphs);
            self.elements.layout.items[i].measured = .{ .w = para.extent.w, .h = para.extent.h };
        }

        // Rasterize data_table column headers and first-row cell text so their glyphs
        // are in the atlas before buildDrawList calls emitGlyphs on them directly.
        for (self._table_state.items, 0..) |*ts, i| {
            if (i >= self._kind.items.len) break;
            if (self._kind.items[i] != .data_table) continue;
            const tbl_font = font;
            // Column headers (bold, 13px)
            for (ts.columns[0..ts.col_count]) |*col| {
                const hdr = col.headerSlice();
                if (hdr.len == 0) continue;
                const para = try text.layoutParagraphEx(self.gpa, tbl_font, atlas, hdr, 13.0, 1e6, self.font_family);
                defer self.gpa.free(para.glyphs);
            }
            // Warm the full printable ASCII range at 13px so all cell text renders
            // immediately without waiting multiple frames for glyph rasterization.
            {
                const ascii_chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789 .,_-()/%+";
                const para = try text.layoutParagraphEx(self.gpa, tbl_font, atlas, ascii_chars, 13.0, 1e6, self.font_family);
                defer self.gpa.free(para.glyphs);
            }
        }

        // Rasterize dropdown option labels so their glyphs are in the atlas before
        // the second-pass overlay renderer calls emitGlyphs on them.
        for (self._dropdown_state.items, 0..) |*dd, i| {
            if (dd.options.items.len == 0) continue;
            if (i >= self._style.items.len) break;
            const style = self._style.items[i];
            const effective_font = if (self.font_family) |fam|
                fam.face(style.font_bold, style.font_italic)
            else
                font;
            for (dd.options.items) |opt| {
                if (opt.label.len == 0) continue;
                const para = try text.layoutParagraphEx(self.gpa, effective_font, atlas, opt.label, style.font_size, 1e6, self.font_family);
                defer self.gpa.free(para.glyphs);
                // Side-effect only: rasterize glyphs into atlas. Measured size not needed here.
            }
        }
    }

    // --- accessors ---

    pub fn store(self: *Scene) *ElementStore {
        return &self.elements;
    }

    pub fn kindOf(self: *Scene, id: ElementId) WidgetKind {
        return self._kind.items[id.index];
    }

    /// Return the widget kind for a raw element index (C1 fix).
    pub fn kindOfIdx(self: *Scene, idx: u32) WidgetKind {
        return self._kind.items[idx];
    }

    pub fn styleOf(self: *Scene, id: ElementId) *ComputedStyle {
        return &self._style.items[id.index];
    }

    pub fn textOf(self: *Scene, id: ElementId) ?[]const u8 {
        if (id.index >= self._text.items.len) return null;
        return self._text.items[id.index];
    }

    /// Set the text for element at idx. Used by BindingSet.refresh() to push
    /// current signal values into the Scene's text array before measurePass.
    pub fn setText(self: *Scene, idx: u32, text_val: []const u8) void {
        self._text.items[idx] = text_val;
    }

    pub fn count(self: *Scene) u32 {
        return self.elements.live;
    }

    // -----------------------------------------------------------------------
    // Focus (R30)
    // -----------------------------------------------------------------------

    /// Move focus to element at `idx`. Pass std.math.maxInt(u32) to clear focus.
    /// Handles side-effects: deactivates old input, closes old dropdown, activates new input.
    pub fn setFocus(self: *Scene, idx: u32) void {
        const old_idx = self.focused_idx;

        // Deactivate old element.
        if (old_idx != NONE and old_idx < self._kind.items.len) {
            const old_kind = self._kind.items[old_idx];
            if ((old_kind == .input or old_kind == .textarea) and old_idx < self._input_state.items.len)
                self._input_state.items[old_idx].active = false;
            if (old_kind == .dropdown and old_idx < self._dropdown_state.items.len)
                self._dropdown_state.items[old_idx].open = false;
            if (old_idx < self.elements.dirty.bit_length)
                self.elements.dirty.set(old_idx);
        }

        self.focused_idx = idx;

        // Activate new element.
        if (idx != NONE and idx < self._kind.items.len) {
            if ((self._kind.items[idx] == .input or self._kind.items[idx] == .textarea) and idx < self._input_state.items.len)
                self._input_state.items[idx].active = true;
            if (idx < self.elements.dirty.bit_length)
                self.elements.dirty.set(idx);
        }

        // Mark all focusable widgets dirty so focus ring paints correctly.
        for (self.focusable_indices.items) |fi| {
            if (fi < self.elements.dirty.bit_length) self.elements.dirty.set(fi);
        }
    }

    pub fn getFocus(self: *Scene) u32 {
        return self.focused_idx;
    }

    pub fn isFocusable(self: *Scene, idx: u32) bool {
        for (self.focusable_indices.items) |fi| {
            if (fi == idx) return true;
        }
        return false;
    }

    pub fn focusNext(self: *Scene) void {
        if (self.focusable_indices.items.len == 0) return;
        const current = self.focused_idx;
        var found_idx: usize = self.focusable_indices.items.len; // default: not found
        for (self.focusable_indices.items, 0..) |fi, i| {
            if (fi == current) {
                found_idx = i;
                break;
            }
        }
        const next_i: usize = if (found_idx >= self.focusable_indices.items.len) 0 else (found_idx + 1) % self.focusable_indices.items.len;
        self.setFocus(self.focusable_indices.items[next_i]);
    }

    pub fn focusPrev(self: *Scene) void {
        if (self.focusable_indices.items.len == 0) return;
        const current = self.focused_idx;
        var found_idx: usize = 0; // default: wrap to last
        for (self.focusable_indices.items, 0..) |fi, i| {
            if (fi == current) {
                found_idx = i;
                break;
            }
        }
        const prev_i = if (found_idx == 0) self.focusable_indices.items.len - 1 else found_idx - 1;
        self.setFocus(self.focusable_indices.items[prev_i]);
    }

    // -----------------------------------------------------------------------
    // Button (R31)
    // -----------------------------------------------------------------------

    pub fn setButtonCallback(self: *Scene, idx: u32, callback: CallbackFn) !void {
        if (idx >= self._button_state.items.len) return error.OutOfMemory;
        self._button_state.items[idx].on_click = callback;
    }

    pub fn setCheckboxCallback(self: *Scene, idx: u32, callback: CallbackFn) !void {
        if (idx >= self._checkbox_state.items.len) return error.OutOfMemory;
        self._checkbox_state.items[idx].on_change = callback;
    }

    pub fn buttonStateOf(self: *Scene, idx: u32) *ButtonState {
        return &self._button_state.items[idx];
    }

    /// Fire all queued callbacks and clear the queue.
    /// Called by app.zig after layout solve (INV-3.3: not during event dispatch).
    pub fn fireQueuedCallbacks(self: *Scene) void {
        for (self._queued_callbacks.items) |cb| {
            cb.call(cb.ptr);
        }
        self._queued_callbacks.clearRetainingCapacity();
    }

    // -----------------------------------------------------------------------
    // Input (R32)
    // -----------------------------------------------------------------------

    pub fn inputStateOf(self: *Scene, idx: u32) *InputState {
        return &self._input_state.items[idx];
    }

    pub fn setInputText(self: *Scene, idx: u32, initial_text: []const u8) !void {
        var inp = &self._input_state.items[idx];
        inp.text.clearRetainingCapacity();
        try inp.text.appendSlice(self.gpa, initial_text);
        inp.cursor = @as(u32, @intCast(initial_text.len));
        // R62: sync selection to cursor position.
        if (idx < self._selection.items.len) {
            self._selection.items[idx] = .{ .anchor = inp.cursor, .active = inp.cursor };
        }
    }

    pub fn getInputText(self: *Scene, idx: u32) []const u8 {
        return self._input_state.items[idx].text.items;
    }

    // -----------------------------------------------------------------------
    // Dropdown (R33)
    // -----------------------------------------------------------------------

    pub fn dropdownStateOf(self: *Scene, idx: u32) *DropdownState {
        return &self._dropdown_state.items[idx];
    }

    pub fn setDropdownOptions(self: *Scene, idx: u32, options: []const DropdownOption) !void {
        var dd = &self._dropdown_state.items[idx];
        dd.options.clearRetainingCapacity();
        try dd.options.appendSlice(self.gpa, options);
        if (dd.selected_idx >= options.len) dd.selected_idx = 0;
    }

    pub fn selectDropdownOption(self: *Scene, idx: u32, option_idx: u32) !void {
        var dd = &self._dropdown_state.items[idx];
        if (option_idx >= dd.options.items.len) return error.OutOfMemory;
        dd.selected_idx = option_idx;
        dd.open = false;
        if (idx < self.elements.dirty.bit_length) self.elements.dirty.set(idx);
    }

    pub fn openDropdown(self: *Scene, idx: u32) void {
        self._dropdown_state.items[idx].highlight_idx = self._dropdown_state.items[idx].selected_idx;
        self._dropdown_state.items[idx].open = true;
        if (idx < self.elements.dirty.bit_length) self.elements.dirty.set(idx);
    }

    pub fn closeDropdown(self: *Scene, idx: u32) void {
        self._dropdown_state.items[idx].open = false;
        if (idx < self.elements.dirty.bit_length) self.elements.dirty.set(idx);
    }

    pub fn toggleDropdown(self: *Scene, idx: u32) void {
        const st = &self._dropdown_state.items[idx];
        if (!st.open) {
            st.highlight_idx = st.selected_idx;
        }
        st.open = !st.open;
        if (idx < self.elements.dirty.bit_length) self.elements.dirty.set(idx);
    }

    pub fn getDropdownValue(self: *Scene, idx: u32) *anyopaque {
        const dd = &self._dropdown_state.items[idx];
        return dd.options.items[dd.selected_idx].value;
    }

    // -----------------------------------------------------------------------
    // Checkbox (R34)
    // -----------------------------------------------------------------------

    pub fn checkboxStateOf(self: *Scene, idx: u32) *CheckboxState {
        return &self._checkbox_state.items[idx];
    }

    pub fn setCheckboxChecked(self: *Scene, idx: u32, checked: bool) void {
        self._checkbox_state.items[idx].checked = checked;
        if (idx < self.elements.dirty.bit_length) self.elements.dirty.set(idx);
    }

    pub fn isCheckboxChecked(self: *Scene, idx: u32) bool {
        return self._checkbox_state.items[idx].checked;
    }

    // -----------------------------------------------------------------------
    // Radio group (R71)
    // -----------------------------------------------------------------------

    pub fn radioStateOf(self: *Scene, idx: u32) *RadioState {
        return &self._radio_state.items[idx];
    }

    pub fn isRadioSelected(self: *Scene, idx: u32) bool {
        return self._radio_state.items[idx].selected;
    }

    /// Select `idx` and deselect all other radios with the same `group_id`.
    /// Marks all affected elements dirty.
    pub fn selectRadio(self: *Scene, idx: u32) void {
        if (idx >= self._radio_state.items.len) return;
        const gid = self._radio_state.items[idx].group_id;
        var i: u32 = 0;
        while (i < self._kind.items.len) : (i += 1) {
            if (i >= self._radio_state.items.len) break;
            if (self._kind.items[i] != .radio) continue;
            const rs = &self._radio_state.items[i];
            if (rs.group_id != gid) continue;
            const was = rs.selected;
            rs.selected = (i == idx);
            if (was != rs.selected) {
                if (i < self.elements.dirty.bit_length) self.elements.dirty.set(i);
            }
        }
    }

    /// Select the next radio in the same group (wraps around). Also moves focus.
    pub fn selectNextInGroup(self: *Scene, idx: u32) void {
        if (idx >= self._radio_state.items.len) return;
        const gid = self._radio_state.items[idx].group_id;
        // Collect group members in order.
        var group_buf: [256]u32 = undefined;
        var n: usize = 0;
        var i: u32 = 0;
        while (i < self._kind.items.len) : (i += 1) {
            if (i >= self._radio_state.items.len) break;
            if (self._kind.items[i] != .radio) continue;
            if (self._radio_state.items[i].group_id != gid) continue;
            if (n < group_buf.len) {
                group_buf[n] = i;
                n += 1;
            }
        }
        if (n == 0) return;
        // Find current position.
        var pos: usize = 0;
        for (group_buf[0..n], 0..) |gi, pi| {
            if (gi == idx) {
                pos = pi;
                break;
            }
        }
        const next_pos = (pos + 1) % n;
        const target = group_buf[next_pos];
        self.selectRadio(target);
        self.setFocus(target);
    }

    /// Select the previous radio in the same group (wraps around). Also moves focus.
    pub fn selectPrevInGroup(self: *Scene, idx: u32) void {
        if (idx >= self._radio_state.items.len) return;
        const gid = self._radio_state.items[idx].group_id;
        // Collect group members in order.
        var group_buf: [256]u32 = undefined;
        var n: usize = 0;
        var i: u32 = 0;
        while (i < self._kind.items.len) : (i += 1) {
            if (i >= self._radio_state.items.len) break;
            if (self._kind.items[i] != .radio) continue;
            if (self._radio_state.items[i].group_id != gid) continue;
            if (n < group_buf.len) {
                group_buf[n] = i;
                n += 1;
            }
        }
        if (n == 0) return;
        // Find current position.
        var pos: usize = 0;
        for (group_buf[0..n], 0..) |gi, pi| {
            if (gi == idx) {
                pos = pi;
                break;
            }
        }
        const prev_pos = if (pos == 0) n - 1 else pos - 1;
        const target = group_buf[prev_pos];
        self.selectRadio(target);
        self.setFocus(target);
    }

    // -----------------------------------------------------------------------
    // Slider (R72)
    // -----------------------------------------------------------------------

    pub fn sliderStateOf(self: *Scene, idx: u32) *SliderState {
        return &self._slider_state.items[idx];
    }

    pub fn getSliderValue(self: *Scene, idx: u32) f32 {
        return self._slider_state.items[idx].value;
    }

    /// Set slider value, clamped to [min, max], snapped to step, and mark dirty.
    pub fn setSliderValue(self: *Scene, idx: u32, value: f32) void {
        var st = &self._slider_state.items[idx];
        const clamped = std.math.clamp(value, st.min, st.max);
        const snapped = snapToStep(clamped, st.min, st.step);
        st.value = snapped;
        if (idx < self.elements.dirty.bit_length) self.elements.dirty.set(idx);
    }

    // -----------------------------------------------------------------------
    // Progress / Spinner (R73)
    // -----------------------------------------------------------------------

    pub fn progressStateOf(self: *Scene, idx: u32) *ProgressState {
        return &self._progress_state.items[idx];
    }

    pub fn setProgress(self: *Scene, idx: u32, value: f32) void {
        self._progress_state.items[idx].value = std.math.clamp(value, 0.0, 1.0);
        if (idx < self.elements.dirty.bit_length) self.elements.dirty.set(idx);
    }

    // -----------------------------------------------------------------------
    // Tabs (R76)
    // -----------------------------------------------------------------------

    pub fn tabsStateOf(self: *Scene, idx: u32) *TabsState {
        return &self._tabs_state.items[idx];
    }

    /// Switch the active tab to `tab_idx`, show that panel, hide the rest.
    pub fn selectTab(self: *Scene, container_idx: u32, tab_idx: u32) void {
        const ts = &self._tabs_state.items[container_idx];
        if (ts.active_idx == tab_idx) return;
        ts.active_idx = tab_idx;
        var child_idx = self.elements.first_child.items[container_idx];
        var item_i: u32 = 0;
        while (child_idx != NONE) : (child_idx = self.elements.next_sibling.items[child_idx]) {
            if (child_idx < self._kind.items.len and self._kind.items[child_idx] == .tab_item) {
                self.setHidden(child_idx, item_i != tab_idx);
                item_i += 1;
            }
        }
        if (container_idx < self.elements.dirty.bit_length) self.elements.dirty.set(container_idx);
    }

    // -----------------------------------------------------------------------
    // Accordion (R77)
    // -----------------------------------------------------------------------

    pub fn accordionStateOf(self: *Scene, idx: u32) *AccordionState {
        return &self._accordion_state.items[idx];
    }

    /// Toggle open/closed. Shows or hides the body child.
    pub fn toggleAccordion(self: *Scene, idx: u32) void {
        const state = &self._accordion_state.items[idx];
        state.open = !state.open;
        const body_idx = state.body_idx;
        if (body_idx != NONE) {
            self.setHidden(body_idx, !state.open);
        }
        if (idx < self.elements.dirty.bit_length) self.elements.dirty.set(idx);
    }

    pub fn isAccordionOpen(self: *Scene, idx: u32) bool {
        return self._accordion_state.items[idx].open;
    }

    // -----------------------------------------------------------------------
    // Date picker (R78)
    // -----------------------------------------------------------------------

    pub fn datePickerStateOf(self: *Scene, idx: u32) *DatePickerState {
        return &self._date_picker_state.items[idx];
    }

    pub fn setDateValue(self: *Scene, idx: u32, value: DateValue) void {
        self._date_picker_state.items[idx].value = value;
        if (idx < self.elements.dirty.bit_length) self.elements.dirty.set(idx);
    }

    pub fn getDateValue(self: *Scene, idx: u32) DateValue {
        return self._date_picker_state.items[idx].value;
    }

    pub fn openCalendar(self: *Scene, idx: u32) void {
        self._date_picker_state.items[idx].open = true;
        if (idx < self.elements.dirty.bit_length) self.elements.dirty.set(idx);
    }

    pub fn closeCalendar(self: *Scene, idx: u32) void {
        self._date_picker_state.items[idx].open = false;
        if (idx < self.elements.dirty.bit_length) self.elements.dirty.set(idx);
    }

    // -----------------------------------------------------------------------
    // Avatar / badge (R7B)
    // -----------------------------------------------------------------------

    pub fn avatarStateOf(self: *Scene, idx: u32) *AvatarState {
        return &self._avatar_state.items[idx];
    }

    pub fn setAvatarImage(self: *Scene, idx: u32, image_id: ImageId) void {
        self._avatar_state.items[idx].image_id = image_id;
        if (idx < self.elements.dirty.bit_length) self.elements.dirty.set(idx);
    }

    pub fn setAvatarInitials(self: *Scene, idx: u32, initials: [2]u8) void {
        self._avatar_state.items[idx].initials = initials;
        if (idx < self.elements.dirty.bit_length) self.elements.dirty.set(idx);
    }

    pub fn badgeStateOf(self: *Scene, idx: u32) *BadgeState {
        return &self._badge_state.items[idx];
    }

    // -----------------------------------------------------------------------
    // Tooltip (R7C)
    // -----------------------------------------------------------------------

    pub fn tooltipOf(self: *Scene, idx: u32) ?[]const u8 {
        if (idx >= self._tooltip.items.len) return null;
        return self._tooltip.items[idx];
    }

    pub fn setTooltip(self: *Scene, idx: u32, text_val: ?[]const u8) void {
        if (idx >= self._tooltip.items.len) return;
        self._tooltip.items[idx] = text_val;
    }

    // -----------------------------------------------------------------------
    // Context menu index (R7D)
    // -----------------------------------------------------------------------

    pub fn contextMenuIdxOf(self: *Scene, idx: u32) u8 {
        if (idx >= self._context_menu_idx.items.len) return 0xFF;
        return self._context_menu_idx.items[idx];
    }

    pub fn setContextMenuIdx(self: *Scene, idx: u32, menu_idx: u8) void {
        if (idx >= self._context_menu_idx.items.len) return;
        self._context_menu_idx.items[idx] = menu_idx;
    }

    // -----------------------------------------------------------------------
    // Data table (R79)
    // -----------------------------------------------------------------------

    pub fn tableStateOf(self: *Scene, idx: u32) *DataTableState {
        return &self._table_state.items[idx];
    }

    pub fn setTableData(self: *Scene, idx: u32, data: *const DataTableRows) void {
        const ts = &self._table_state.items[idx];
        ts.rows = data;
        // Rebuild sorted_indices (identity mapping initially).
        ts.sorted_indices.clearRetainingCapacity();
        var r: u32 = 0;
        while (r < @min(data.row_count, MAX_TABLE_ROWS)) : (r += 1) {
            ts.sorted_indices.append(self.gpa, r) catch break;
        }
        if (idx < self.elements.dirty.bit_length) self.elements.dirty.set(idx);
    }

    pub fn setTableColumns(self: *Scene, idx: u32, columns: []const DataColumn) void {
        const ts = &self._table_state.items[idx];
        const n = @min(columns.len, MAX_COLUMNS);
        ts.col_count = @intCast(n);
        for (0..n) |i| ts.columns[i] = columns[i];
        if (idx < self.elements.dirty.bit_length) self.elements.dirty.set(idx);
    }

    /// Sort by column `col_idx`. Cycles none → asc → desc → none.
    pub fn sortTable(self: *Scene, idx: u32, col_idx: u8) void {
        const ts = &self._table_state.items[idx];
        if (ts.sort_col == col_idx) {
            ts.sort_dir = switch (ts.sort_dir) {
                .none => .asc,
                .asc => .desc,
                .desc => .none,
            };
        } else {
            ts.sort_col = col_idx;
            ts.sort_dir = .asc;
        }

        const rows_data = ts.rows orelse return;
        if (ts.sort_dir == .none) {
            // Restore identity order.
            ts.sorted_indices.clearRetainingCapacity();
            var r: u32 = 0;
            while (r < @min(rows_data.row_count, MAX_TABLE_ROWS)) : (r += 1) {
                ts.sorted_indices.append(self.gpa, r) catch break;
            }
            if (idx < self.elements.dirty.bit_length) self.elements.dirty.set(idx);
            return;
        }

        // Sort using cell text comparison (stable-ish via std sort).
        const n = ts.sorted_indices.items.len;
        var buf_a: [128]u8 = undefined;
        var buf_b: [128]u8 = undefined;
        const col = col_idx;
        const ascending = ts.sort_dir == .asc;

        // Simple insertion sort (acceptable for <= 1000 rows).
        const row_base: [*]u8 = @ptrCast(rows_data.row_ptr);
        var i: usize = 1;
        while (i < n) : (i += 1) {
            const key = ts.sorted_indices.items[i];
            const key_row_ptr: *anyopaque = @ptrCast(row_base + @as(usize, key) * rows_data.row_size);
            const key_len = rows_data.cell_fn(key_row_ptr, col, &buf_a);
            const key_text = buf_a[0..key_len];
            var j: usize = i;
            while (j > 0) {
                const cmp_row = ts.sorted_indices.items[j - 1];
                const cmp_row_ptr: *anyopaque = @ptrCast(row_base + @as(usize, cmp_row) * rows_data.row_size);
                const cmp_len = rows_data.cell_fn(cmp_row_ptr, col, &buf_b);
                const cmp_text = buf_b[0..cmp_len];
                const less = std.mem.lessThan(u8, key_text, cmp_text);
                const should_swap = if (ascending) less else !less;
                if (!should_swap) break;
                ts.sorted_indices.items[j] = ts.sorted_indices.items[j - 1];
                j -= 1;
            }
            ts.sorted_indices.items[j] = key;
        }

        if (idx < self.elements.dirty.bit_length) self.elements.dirty.set(idx);
    }

    // -----------------------------------------------------------------------
    // Scroll (R35)
    // -----------------------------------------------------------------------

    pub fn scrollStateOf(self: *Scene, idx: u32) *ScrollState {
        return &self._scroll_state.items[idx];
    }

    pub fn setScrollOffset(self: *Scene, idx: u32, offset_y: f32, offset_x: f32) void {
        var st = &self._scroll_state.items[idx];
        const max_y = @max(0.0, st.content_height - st.container_height);
        const max_x = @max(0.0, st.content_width - st.container_width);
        st.scroll_y = if (max_y > 0.0) std.math.clamp(offset_y, 0.0, max_y) else @max(0.0, offset_y);
        st.scroll_x = if (max_x > 0.0) std.math.clamp(offset_x, 0.0, max_x) else @max(0.0, offset_x);
        if (idx < self.elements.dirty.bit_length) self.elements.dirty.set(idx);
    }

    pub fn getScrollOffset(self: *Scene, idx: u32) struct { y: f32, x: f32 } {
        const ss = &self._scroll_state.items[idx];
        return .{ .y = ss.scroll_y, .x = ss.scroll_x };
    }

    // -----------------------------------------------------------------------
    // Pseudo-state (R40)
    // -----------------------------------------------------------------------

    /// Return a pointer to the pseudo-state for element `idx`.
    pub fn pseudoOf(self: *Scene, idx: u32) *PseudoState {
        return &self._pseudo.items[idx];
    }

    /// Set pseudo-state for `idx` and mark the element dirty.
    pub fn setPseudo(self: *Scene, idx: u32, state: PseudoState) void {
        self._pseudo.items[idx] = state;
        if (idx < self.elements.dirty.bit_length) self.elements.dirty.set(idx);
    }

    // -----------------------------------------------------------------------
    // Image/icon state (R43)
    // -----------------------------------------------------------------------

    pub fn imageStateOf(self: *Scene, idx: u32) *ImageState {
        return &self._image_state.items[idx];
    }

    pub fn setImage(self: *Scene, idx: u32, id: ImageId) void {
        self._image_state.items[idx].image_id = id;
        if (idx < self.elements.dirty.bit_length) self.elements.dirty.set(idx);
    }

    pub fn setImageTint(self: *Scene, idx: u32, tint: theme.Color) void {
        self._image_state.items[idx].tint = tint;
        if (idx < self.elements.dirty.bit_length) self.elements.dirty.set(idx);
    }

    // -----------------------------------------------------------------------
    // Hidden state (R52)
    // -----------------------------------------------------------------------

    /// Return whether element `idx` is currently hidden.
    pub fn isHidden(self: *const Scene, idx: u32) bool {
        if (idx >= self._hidden.items.len) return false;
        return self._hidden.items[idx];
    }

    /// Set the hidden state for element `idx` and mark it dirty.
    /// When hidden, saves the current display value and sets display = .none.
    /// When shown, restores the original display value.
    pub fn setHidden(self: *Scene, idx: u32, hidden: bool) void {
        if (idx >= self._hidden.items.len) return;
        const was_hidden = self._hidden.items[idx];
        if (was_hidden == hidden) return;
        self._hidden.items[idx] = hidden;
        if (hidden) {
            self._saved_display.items[idx] = self.elements.layout.items[idx].display;
            self.elements.layout.items[idx].display = .none;
        } else {
            self.elements.layout.items[idx].display = self._saved_display.items[idx];
        }
        if (idx < self.elements.dirty.bit_length) self.elements.dirty.set(idx);
    }

    // -----------------------------------------------------------------------
    // Selection (R62)
    // -----------------------------------------------------------------------

    /// Return a pointer to the selection state for element `idx`.
    pub fn selectionOf(self: *Scene, idx: u32) *TextSelection {
        return &self._selection.items[idx];
    }

    /// Set selection for element `idx` and mark it dirty.
    pub fn setSelection(self: *Scene, idx: u32, anchor: u32, active: u32) void {
        self._selection.items[idx] = .{ .anchor = anchor, .active = active };
        if (idx < self.elements.dirty.bit_length) self.elements.dirty.set(idx);
    }

    /// Collapse selection for element `idx` and mark it dirty.
    pub fn clearSelection(self: *Scene, idx: u32) void {
        self._selection.items[idx] = .{};
        if (idx < self.elements.dirty.bit_length) self.elements.dirty.set(idx);
    }

    // -----------------------------------------------------------------------
    // Textarea (R63)
    // -----------------------------------------------------------------------

    /// Return a pointer to the textarea state for element `idx`.
    pub fn textareaStateOf(self: *Scene, idx: u32) *TextareaState {
        return &self._textarea_state.items[idx];
    }

    // -----------------------------------------------------------------------
    // Children management (R53)
    // -----------------------------------------------------------------------

    /// Remove all direct children of `parent_idx` (and their subtrees) from the scene.
    /// Recycles element indices. Called before re-instantiating a `for=` list.
    pub fn removeChildren(self: *Scene, parent_idx: u32) void {
        const parent_id = ElementId{
            .index = parent_idx,
            .gen = self.elements.gen.items[parent_idx],
        };
        // Collect all direct children first (iterator is invalidated by remove)
        var children_buf: [256]ElementId = undefined;
        var n: usize = 0;
        var it = self.elements.childrenOf(parent_id);
        while (it.next()) |child_id| {
            if (n < children_buf.len) {
                children_buf[n] = child_id;
                n += 1;
            }
        }
        // Remove each child subtree recursively
        for (children_buf[0..n]) |child_id| {
            self.removeSubtree(child_id.index);
        }
    }

    /// Recursively remove element `idx` and all its descendants.
    fn removeSubtree(self: *Scene, idx: u32) void {
        const id = ElementId{
            .index = idx,
            .gen = self.elements.gen.items[idx],
        };
        // Remove children first (depth-first)
        var children_buf: [256]ElementId = undefined;
        var n: usize = 0;
        var it = self.elements.childrenOf(id);
        while (it.next()) |child_id| {
            if (n < children_buf.len) {
                children_buf[n] = child_id;
                n += 1;
            }
        }
        for (children_buf[0..n]) |child_id| {
            self.removeSubtree(child_id.index);
        }
        // Now remove this element
        self.elements.remove(id);
    }

    /// Instantiate `desc` as a child of `parent_id`. Like `instantiate` but appends
    /// the result as a child of `parent_id` in the element store.
    pub fn instantiateUnder(
        self: *Scene,
        parent_id: ElementId,
        desc: NodeDesc,
        tokens: Tokens,
    ) InstantiateError!ElementId {
        return self.instantiateNode(desc, tokens, parent_id);
    }

    // --- private helpers ---

    /// Apply inline style:* attributes to a ComputedStyle. (R50)
    fn applyInlineStyle(prop: []const u8, value: []const u8, style: *ComputedStyle) void {
        const eql = std.mem.eql;
        if (eql(u8, prop, "background")) {
            if (markup.parseHexColor(value)) |c| style.background = c;
        } else if (eql(u8, prop, "color")) {
            if (markup.parseHexColor(value)) |c| style.text_color = c;
        } else if (eql(u8, prop, "border-color")) {
            if (markup.parseHexColor(value)) |c| style.border_color = c;
        } else if (eql(u8, prop, "border-width")) {
            if (markup.parseFloat(value)) |v| style.border_width = v;
        } else if (eql(u8, prop, "radius")) {
            if (markup.parseFloat(value)) |v| style.radius = v;
        } else if (eql(u8, prop, "font-size")) {
            if (markup.parseFloat(value)) |v| style.font_size = v;
        } else if (eql(u8, prop, "opacity")) {
            if (markup.parseFloat(value)) |v| style.opacity = std.math.clamp(v, 0.0, 1.0);
        } else if (eql(u8, prop, "shadow-blur")) {
            if (markup.parseFloat(value)) |v| style.shadow_blur = v;
        }
        // Unknown property: silently ignore.
    }

    fn instantiateNode(
        self: *Scene,
        desc: NodeDesc,
        tokens: Tokens,
        parent_id: ?ElementId,
    ) InstantiateError!ElementId {
        const kind = tagToKind(desc.tag) orelse return InstantiateError.UnknownTag;

        // Build merged layout and style using the spec merge rule:
        //   base     = defaultStyleFor/defaultLayoutFor(kind, tokens)
        //   resolved = resolveClasses(node.classes, tokens)
        //   empty    = resolveClasses("", tokens)
        //   final.field = if (resolved.field != empty.field) resolved.field else base.field
        const base_style = defaultStyleFor(kind, tokens);
        const base_layout = defaultLayoutFor(kind);
        const resolved = markup.resolveClasses(desc.classes, tokens);
        const empty = markup.resolveClasses("", tokens);

        // --- Merge style fields ---
        var final_style = base_style;

        if (!colorEq(resolved.style.background, empty.style.background))
            final_style.background = resolved.style.background;
        if (!colorEq(resolved.style.text_color, empty.style.text_color))
            final_style.text_color = resolved.style.text_color;
        if (!colorEq(resolved.style.border_color, empty.style.border_color))
            final_style.border_color = resolved.style.border_color;
        if (resolved.style.border_width != empty.style.border_width)
            final_style.border_width = resolved.style.border_width;
        if (resolved.style.radius != empty.style.radius)
            final_style.radius = resolved.style.radius;
        if (resolved.style.gap != empty.style.gap)
            final_style.gap = resolved.style.gap;
        if (resolved.style.font_size != empty.style.font_size)
            final_style.font_size = resolved.style.font_size;
        if (resolved.style.truncate != empty.style.truncate)
            final_style.truncate = resolved.style.truncate;
        if (resolved.style.opacity != empty.style.opacity)
            final_style.opacity = resolved.style.opacity;
        if (resolved.style.shadow_blur != empty.style.shadow_blur)
            final_style.shadow_blur = resolved.style.shadow_blur;
        if (resolved.style.shadow_offset_x != empty.style.shadow_offset_x)
            final_style.shadow_offset_x = resolved.style.shadow_offset_x;
        if (resolved.style.shadow_offset_y != empty.style.shadow_offset_y)
            final_style.shadow_offset_y = resolved.style.shadow_offset_y;
        if (!colorEq(resolved.style.shadow_color, empty.style.shadow_color))
            final_style.shadow_color = resolved.style.shadow_color;

        // Padding sub-fields
        if (resolved.style.padding.top != empty.style.padding.top)
            final_style.padding.top = resolved.style.padding.top;
        if (resolved.style.padding.right != empty.style.padding.right)
            final_style.padding.right = resolved.style.padding.right;
        if (resolved.style.padding.bottom != empty.style.padding.bottom)
            final_style.padding.bottom = resolved.style.padding.bottom;
        if (resolved.style.padding.left != empty.style.padding.left)
            final_style.padding.left = resolved.style.padding.left;

        // --- Merge layout fields ---
        var final_layout = base_layout;

        if (resolved.layout.display != empty.layout.display)
            final_layout.display = resolved.layout.display;
        if (resolved.layout.direction != empty.layout.direction)
            final_layout.direction = resolved.layout.direction;
        if (resolved.layout.justify_content != empty.layout.justify_content)
            final_layout.justify_content = resolved.layout.justify_content;
        if (resolved.layout.align_items != empty.layout.align_items)
            final_layout.align_items = resolved.layout.align_items;
        if (resolved.layout.gap != empty.layout.gap)
            final_layout.gap = resolved.layout.gap;
        if (resolved.layout.flex_grow != empty.layout.flex_grow)
            final_layout.flex_grow = resolved.layout.flex_grow;
        if (resolved.layout.flex_shrink != empty.layout.flex_shrink)
            final_layout.flex_shrink = resolved.layout.flex_shrink;
        if (!dimensionEq(resolved.layout.flex_basis, empty.layout.flex_basis))
            final_layout.flex_basis = resolved.layout.flex_basis;
        if (!dimensionEq(resolved.layout.width, empty.layout.width))
            final_layout.width = resolved.layout.width;
        if (!dimensionEq(resolved.layout.height, empty.layout.height))
            final_layout.height = resolved.layout.height;
        if (resolved.layout.col_span != empty.layout.col_span)
            final_layout.col_span = resolved.layout.col_span;
        if (resolved.layout.row_span != empty.layout.row_span)
            final_layout.row_span = resolved.layout.row_span;
        // grid_template_columns/rows: compare by length (empty has len 0)
        if (resolved.layout.grid_template_columns.len != empty.layout.grid_template_columns.len)
            final_layout.grid_template_columns = resolved.layout.grid_template_columns;
        if (resolved.layout.grid_template_rows.len != empty.layout.grid_template_rows.len)
            final_layout.grid_template_rows = resolved.layout.grid_template_rows;

        // R51: align_self
        if (resolved.layout.align_self != empty.layout.align_self)
            final_layout.align_self = resolved.layout.align_self;

        // R51: margin (compare each field)
        const emm = empty.layout.margin;
        const rm = resolved.layout.margin;
        if (!std.meta.eql(rm.top, emm.top)) final_layout.margin.top = rm.top;
        if (!std.meta.eql(rm.right, emm.right)) final_layout.margin.right = rm.right;
        if (!std.meta.eql(rm.bottom, emm.bottom)) final_layout.margin.bottom = rm.bottom;
        if (!std.meta.eql(rm.left, emm.left)) final_layout.margin.left = rm.left;

        // Sync layout padding from the resolved style (style padding drives layout spacing).
        // Only apply if the layout hasn't been explicitly set via a Tailwind class.
        if (resolved.layout.padding.top == empty.layout.padding.top)
            final_layout.padding.top = final_style.padding.top;
        if (resolved.layout.padding.right == empty.layout.padding.right)
            final_layout.padding.right = final_style.padding.right;
        if (resolved.layout.padding.bottom == empty.layout.padding.bottom)
            final_layout.padding.bottom = final_style.padding.bottom;
        if (resolved.layout.padding.left == empty.layout.padding.left)
            final_layout.padding.left = final_style.padding.left;

        // R50: Apply inline style:* attributes (override class-derived values)
        for (desc.attrs) |attr| {
            if (!std.mem.startsWith(u8, attr.name, "style:")) continue;
            const prop = attr.name[6..];
            const raw_value: []const u8 = switch (attr.value) {
                .literal => |s| s,
                .bind => continue, // bind paths are not evaluated during instantiate
            };
            applyInlineStyle(prop, raw_value, &final_style);
        }

        // --- Extract text attr ---
        var text_val: ?[]const u8 = null;
        // R52: check for if= attribute (start hidden until signal resolves)
        var start_hidden: bool = false;
        for (desc.attrs) |attr| {
            if (std.mem.eql(u8, attr.name, "text")) {
                text_val = switch (attr.value) {
                    .literal => |s| s,
                    .bind => |s| s,
                };
            } else if ((kind == .input or kind == .textarea) and std.mem.eql(u8, attr.name, "placeholder")) {
                // Store placeholder as the text slot; renderer shows it only when input is empty.
                text_val = switch (attr.value) {
                    .literal => |s| s,
                    .bind => |s| s,
                };
            } else if (kind == .tab_item and std.mem.eql(u8, attr.name, "label")) {
                // R76: store tab label in _text for use by the tab bar renderer.
                text_val = switch (attr.value) {
                    .literal => |s| s,
                    .bind => |s| s,
                };
            } else if ((kind == .checkbox or kind == .radio) and std.mem.eql(u8, attr.name, "label")) {
                // R70/R71: store checkbox/radio label text so the renderer can display it.
                text_val = switch (attr.value) {
                    .literal => |s| s,
                    .bind => |s| s,
                };
            } else if (std.mem.eql(u8, attr.name, "if")) {
                switch (attr.value) {
                    .literal => |s| {
                        if (!std.mem.eql(u8, s, "true")) {
                            start_hidden = true;
                        }
                    },
                    .bind => {
                        // Start hidden until CondBinding resolves the signal
                        start_hidden = true;
                    },
                }
            }
        }

        // --- Add element to the store ---
        const id: ElementId = if (parent_id) |pid|
            try self.elements.addChild(pid, final_layout)
        else
            try self.elements.addRoot(final_layout);

        // --- Extend parallel arrays to cover id.index ---
        const needed = id.index + 1;
        try self._kind.ensureTotalCapacity(self.gpa, needed);
        if (self._kind.items.len <= id.index) {
            self._kind.items.len = needed;
        }
        self._kind.items[id.index] = kind;

        try self._style.ensureTotalCapacity(self.gpa, needed);
        if (self._style.items.len <= id.index) {
            self._style.items.len = needed;
        }
        self._style.items[id.index] = final_style;

        try self._text.ensureTotalCapacity(self.gpa, needed);
        if (self._text.items.len <= id.index) {
            self._text.items.len = needed;
        }
        self._text.items[id.index] = text_val;

        // Extend per-widget state arrays.
        try self._button_state.ensureTotalCapacity(self.gpa, needed);
        if (self._button_state.items.len <= id.index) {
            self._button_state.items.len = needed;
        }
        self._button_state.items[id.index] = .{};

        try self._input_state.ensureTotalCapacity(self.gpa, needed);
        if (self._input_state.items.len <= id.index) {
            self._input_state.items.len = needed;
        }
        self._input_state.items[id.index] = .{};

        try self._dropdown_state.ensureTotalCapacity(self.gpa, needed);
        if (self._dropdown_state.items.len <= id.index) {
            self._dropdown_state.items.len = needed;
        }
        self._dropdown_state.items[id.index] = .{};

        try self._checkbox_state.ensureTotalCapacity(self.gpa, needed);
        if (self._checkbox_state.items.len <= id.index) {
            self._checkbox_state.items.len = needed;
        }
        self._checkbox_state.items[id.index] = .{};

        try self._scroll_state.ensureTotalCapacity(self.gpa, needed);
        if (self._scroll_state.items.len <= id.index) {
            self._scroll_state.items.len = needed;
        }
        self._scroll_state.items[id.index] = .{};

        try self._pseudo.ensureTotalCapacity(self.gpa, needed);
        if (self._pseudo.items.len <= id.index) {
            self._pseudo.items.len = needed;
        }
        self._pseudo.items[id.index] = .{};

        try self._image_state.ensureTotalCapacity(self.gpa, needed);
        if (self._image_state.items.len <= id.index) {
            self._image_state.items.len = needed;
        }
        self._image_state.items[id.index] = .{};

        // R52: hidden state arrays
        try self._hidden.ensureTotalCapacity(self.gpa, needed);
        if (self._hidden.items.len <= id.index) {
            self._hidden.items.len = needed;
        }
        self._hidden.items[id.index] = false;

        try self._saved_display.ensureTotalCapacity(self.gpa, needed);
        if (self._saved_display.items.len <= id.index) {
            self._saved_display.items.len = needed;
        }
        self._saved_display.items[id.index] = final_layout.display;

        // R62: selection state
        try self._selection.ensureTotalCapacity(self.gpa, needed);
        if (self._selection.items.len <= id.index) {
            self._selection.items.len = needed;
        }
        self._selection.items[id.index] = .{};

        // R63: textarea state
        try self._textarea_state.ensureTotalCapacity(self.gpa, needed);
        if (self._textarea_state.items.len <= id.index) {
            self._textarea_state.items.len = needed;
        }
        self._textarea_state.items[id.index] = .{};

        // R71: radio state
        try self._radio_state.ensureTotalCapacity(self.gpa, needed);
        if (self._radio_state.items.len <= id.index) {
            self._radio_state.items.len = needed;
        }
        self._radio_state.items[id.index] = .{};

        // R72: slider state
        try self._slider_state.ensureTotalCapacity(self.gpa, needed);
        if (self._slider_state.items.len <= id.index) {
            self._slider_state.items.len = needed;
        }
        self._slider_state.items[id.index] = .{};

        // R73: progress state
        try self._progress_state.ensureTotalCapacity(self.gpa, needed);
        if (self._progress_state.items.len <= id.index) {
            self._progress_state.items.len = needed;
        }
        self._progress_state.items[id.index] = .{};

        // R76: tabs state
        try self._tabs_state.ensureTotalCapacity(self.gpa, needed);
        if (self._tabs_state.items.len <= id.index) {
            self._tabs_state.items.len = needed;
        }
        self._tabs_state.items[id.index] = .{};

        // R77: accordion state
        try self._accordion_state.ensureTotalCapacity(self.gpa, needed);
        if (self._accordion_state.items.len <= id.index) {
            self._accordion_state.items.len = needed;
        }
        self._accordion_state.items[id.index] = .{};

        // R78: date picker state
        try self._date_picker_state.ensureTotalCapacity(self.gpa, needed);
        if (self._date_picker_state.items.len <= id.index) {
            self._date_picker_state.items.len = needed;
        }
        self._date_picker_state.items[id.index] = .{};

        // R7B: avatar state
        try self._avatar_state.ensureTotalCapacity(self.gpa, needed);
        if (self._avatar_state.items.len <= id.index) {
            self._avatar_state.items.len = needed;
        }
        self._avatar_state.items[id.index] = .{};

        // R7B: badge state
        try self._badge_state.ensureTotalCapacity(self.gpa, needed);
        if (self._badge_state.items.len <= id.index) {
            self._badge_state.items.len = needed;
        }
        self._badge_state.items[id.index] = .{};

        // R7C: tooltip
        try self._tooltip.ensureTotalCapacity(self.gpa, needed);
        if (self._tooltip.items.len <= id.index) {
            self._tooltip.items.len = needed;
        }
        self._tooltip.items[id.index] = null;

        // R7D: context menu index
        try self._context_menu_idx.ensureTotalCapacity(self.gpa, needed);
        if (self._context_menu_idx.items.len <= id.index) {
            self._context_menu_idx.items.len = needed;
        }
        self._context_menu_idx.items[id.index] = 0xFF;

        // R79: data table state
        try self._table_state.ensureTotalCapacity(self.gpa, needed);
        if (self._table_state.items.len <= id.index) {
            self._table_state.items.len = needed;
        }
        self._table_state.items[id.index] = .{};

        // R93: class string (for theme live-swap / rebuildStyles)
        try self._classes.ensureTotalCapacity(self.gpa, needed);
        if (self._classes.items.len <= id.index) {
            self._classes.items.len = needed;
        }
        self._classes.items[id.index] = desc.classes;

        // Parse input/textarea value= attribute to pre-populate the text buffer.
        if (kind == .input or kind == .textarea) {
            for (desc.attrs) |attr| {
                if (!std.mem.eql(u8, attr.name, "value")) continue;
                const attr_val: []const u8 = switch (attr.value) {
                    .literal => |s| s,
                    .bind => continue,
                };
                if (attr_val.len > 0) {
                    var inp = &self._input_state.items[id.index];
                    try inp.text.appendSlice(self.gpa, attr_val);
                    inp.cursor = @intCast(attr_val.len);

                    // Textarea requires line_starts to be populated; without it
                    // the renderer gates all text output on line_starts.len > 0.
                    if (kind == .textarea) {
                        var ts = &self._textarea_state.items[id.index];
                        try ts.line_starts.append(self.gpa, 0); // line 0 always starts at 0
                        for (attr_val, 0..) |byte, i| {
                            if (byte == '\n') {
                                try ts.line_starts.append(self.gpa, @intCast(i + 1));
                            }
                        }
                    }
                }
                break;
            }
        }

        // R71: parse radio attributes (group, value)
        if (kind == .radio) {
            var rs = &self._radio_state.items[id.index];
            for (desc.attrs) |attr| {
                const attr_val: []const u8 = switch (attr.value) {
                    .literal => |s| s,
                    .bind => continue,
                };
                if (std.mem.eql(u8, attr.name, "group")) {
                    rs.group_id = hashGroupName(attr_val);
                } else if (std.mem.eql(u8, attr.name, "value")) {
                    rs.value_str = attr_val;
                } else if (std.mem.eql(u8, attr.name, "selected")) {
                    rs.selected = std.mem.eql(u8, attr_val, "true");
                }
            }
        }

        // R72: parse slider attributes (min, max, step, value)
        if (kind == .slider) {
            var ss = &self._slider_state.items[id.index];
            for (desc.attrs) |attr| {
                const attr_val: []const u8 = switch (attr.value) {
                    .literal => |s| s,
                    .bind => continue,
                };
                if (std.mem.eql(u8, attr.name, "min")) {
                    if (markup.parseFloat(attr_val)) |v| ss.min = v;
                } else if (std.mem.eql(u8, attr.name, "max")) {
                    if (markup.parseFloat(attr_val)) |v| ss.max = v;
                } else if (std.mem.eql(u8, attr.name, "step")) {
                    if (markup.parseFloat(attr_val)) |v| ss.step = v;
                } else if (std.mem.eql(u8, attr.name, "value")) {
                    if (markup.parseFloat(attr_val)) |v| {
                        ss.value = std.math.clamp(v, ss.min, ss.max);
                    }
                }
            }
        }

        // R73: parse progress_bar attributes (value, indeterminate)
        if (kind == .progress_bar) {
            var ps = &self._progress_state.items[id.index];
            for (desc.attrs) |attr| {
                const attr_val: []const u8 = switch (attr.value) {
                    .literal => |s| s,
                    .bind => continue,
                };
                if (std.mem.eql(u8, attr.name, "value")) {
                    if (markup.parseFloat(attr_val)) |v| ps.value = std.math.clamp(v, 0.0, 1.0);
                } else if (std.mem.eql(u8, attr.name, "indeterminate")) {
                    ps.indeterminate = std.mem.eql(u8, attr_val, "true");
                }
            }
        }

        // R78: parse date_picker attributes (disabled, value)
        if (kind == .date_picker) {
            var dp = &self._date_picker_state.items[id.index];
            for (desc.attrs) |attr| {
                const attr_val: []const u8 = switch (attr.value) {
                    .literal => |s| s,
                    .bind => continue,
                };
                if (std.mem.eql(u8, attr.name, "disabled")) {
                    dp.disabled = std.mem.eql(u8, attr_val, "true");
                } else if (std.mem.eql(u8, attr.name, "value")) {
                    if (parseDateStr(attr_val)) |v| dp.value = v;
                }
            }
        }

        // R7B: parse avatar attributes (size, initials)
        if (kind == .avatar) {
            var av = &self._avatar_state.items[id.index];
            for (desc.attrs) |attr| {
                const attr_val: []const u8 = switch (attr.value) {
                    .literal => |s| s,
                    .bind => continue,
                };
                if (std.mem.eql(u8, attr.name, "size")) {
                    if (markup.parseFloat(attr_val)) |v| av.size_px = v;
                } else if (std.mem.eql(u8, attr.name, "initials") and attr_val.len >= 1) {
                    av.initials[0] = attr_val[0];
                    av.initials[1] = if (attr_val.len >= 2) attr_val[1] else 0;
                }
            }
        }

        // R7B: parse badge attributes (text, color)
        if (kind == .badge) {
            var bs = &self._badge_state.items[id.index];
            for (desc.attrs) |attr| {
                const attr_val: []const u8 = switch (attr.value) {
                    .literal => |s| s,
                    .bind => continue,
                };
                if (std.mem.eql(u8, attr.name, "text")) {
                    const copy_len = @min(attr_val.len, bs.text.len - 1);
                    @memcpy(bs.text[0..copy_len], attr_val[0..copy_len]);
                    bs.text[copy_len] = 0;
                } else if (std.mem.eql(u8, attr.name, "color")) {
                    if (std.mem.eql(u8, attr_val, "success")) bs.color = .success
                    else if (std.mem.eql(u8, attr_val, "warning")) bs.color = .warning
                    else if (std.mem.eql(u8, attr_val, "error")) bs.color = .error_c;
                }
            }
        }

        // R7C: parse tooltip attribute
        for (desc.attrs) |attr| {
            if (std.mem.eql(u8, attr.name, "tooltip")) {
                self._tooltip.items[id.index] = switch (attr.value) {
                    .literal => |s| s,
                    .bind => |s| s,
                };
                break;
            }
        }

        // Apply if= hidden state after element is registered
        if (start_hidden) {
            self.setHidden(id.index, true);
        }

        // --- Recurse into children ---
        for (desc.children) |child| {
            _ = try self.instantiateNode(child, tokens, id);
        }

        // R76: Post-process Tabs after children — count tab_items and hide all but first.
        if (kind == .tabs) {
            const ts = &self._tabs_state.items[id.index];
            var child_idx = self.elements.first_child.items[id.index];
            var tab_i: u32 = 0;
            while (child_idx != NONE) : (child_idx = self.elements.next_sibling.items[child_idx]) {
                if (child_idx < self._kind.items.len and self._kind.items[child_idx] == .tab_item) {
                    self.setHidden(child_idx, tab_i != 0);
                    tab_i += 1;
                }
            }
            ts.tab_count = tab_i;
        }

        // R77: Post-process Accordion after children — find body child and hide it initially.
        if (kind == .accordion) {
            const as_ = &self._accordion_state.items[id.index];
            var body_idx: u32 = NONE;

            // First pass: look for slot="body" attribute on a child.
            var child_idx = self.elements.first_child.items[id.index];
            var desc_i: usize = 0;
            while (child_idx != NONE and desc_i < desc.children.len) {
                const child_desc = desc.children[desc_i];
                var is_body = false;
                for (child_desc.attrs) |attr| {
                    if (std.mem.eql(u8, attr.name, "slot")) {
                        const val: []const u8 = switch (attr.value) {
                            .literal => |s| s,
                            .bind => "",
                        };
                        if (std.mem.eql(u8, val, "body")) {
                            is_body = true;
                            break;
                        }
                    }
                }
                if (is_body) {
                    body_idx = child_idx;
                    break;
                }
                child_idx = self.elements.next_sibling.items[child_idx];
                desc_i += 1;
            }

            // Fall back: second child is body if no slot="body" found.
            if (body_idx == NONE) {
                var ci: u32 = 0;
                child_idx = self.elements.first_child.items[id.index];
                while (child_idx != NONE) : (child_idx = self.elements.next_sibling.items[child_idx]) {
                    if (ci == 1) {
                        body_idx = child_idx;
                        break;
                    }
                    ci += 1;
                }
            }

            as_.body_idx = body_idx;
            // Accordion starts collapsed — hide the body.
            if (body_idx != NONE) self.setHidden(body_idx, true);
        }

        return id;
    }
};
