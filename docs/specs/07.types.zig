//! 07 — Components — types.zig
//!
//! Contract (INV-5.1). `WidgetKind`, the `Scene` public method set, and the registry are the
//! contract. `tagToKind` and `defaultLayoutFor` are implemented here (data/wiring);
//! `defaultStyleFor`, `Scene.instantiate`, and `Scene.measurePass` are the real work and are
//! stubbed. Match signatures exactly; implement per spec.md.
//!
//! Imports modules 02/03/05/06 — all lower-numbered (INV-3.4), so legal. Scene owns the
//! ElementStore and the parallel presentation arrays (see spec.md build-order consequence).

const std = @import("std");
const text = @import("../02_text/types.zig");
const store = @import("../03_element_store/types.zig");
const theme = @import("../05_theme/types.zig");
const markup = @import("../06_markup_style/types.zig");

pub const ElementId = store.ElementId;
pub const ElementStore = store.ElementStore;
pub const LayoutNode = store.LayoutNode;
pub const Display = store.Display;
pub const Tokens = theme.Tokens;
pub const ComputedStyle = theme.ComputedStyle;
pub const NodeDesc = markup.NodeDesc;

// ---------------------------------------------------------------------------
// Widget kinds + registry
// ---------------------------------------------------------------------------

pub const WidgetKind = enum { text, button, input, card, row, column, dropdown, checkbox, scrollview, image, icon };

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

/// Map a markup tag to a widget kind. Unknown tag → null (instantiate turns that into an
/// error). Implemented here to pin the exact tag spellings.
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
    return null;
}

/// Per-kind default layout. Row/Column are flex containers; everything else is block.
/// Implemented here (simple/definitional).
pub fn defaultLayoutFor(kind: WidgetKind) LayoutNode {
    return switch (kind) {
        .row => .{ .display = .flex, .direction = .row },
        .column => .{ .display = .flex, .direction = .column },
        .scrollview => .{ .display = .block, .overflow = .hidden },
        else => .{ .display = .block },
    };
}

/// Per-kind default style, wired to module 05's component builders (button→buttonPrimary,
/// card→cardSurface, input/dropdown→inputDefault, others→empty). Stubbed — implement per
/// spec.md.
pub fn defaultStyleFor(kind: WidgetKind, tokens: Tokens) ComputedStyle {
    _ = kind;
    _ = tokens;
    @compileError("not implemented — implement per spec.md; do not change this signature");
}

// ---------------------------------------------------------------------------
// Focus ring color token (B1 — INV-4.3: no hex literals in rendering code)
// ---------------------------------------------------------------------------

/// Named constant for the focus ring border color.
/// Referenced by name in rendering code; never as a literal.
pub const FOCUS_RING_COLOR: ComputedStyle.ColorT = undefined; // implementation-defined placeholder

// ---------------------------------------------------------------------------
// Per-widget state types (INV-3.1 — parallel arrays, not per-widget heap objects)
// ---------------------------------------------------------------------------

/// Type-erased callback fired at frame-end when a button is activated.
/// NOT a reactivity path (INV-3.3). Only fires from fireQueuedCallbacks().
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
    text: std.ArrayListUnmanaged(u8) = .{},
    cursor: u32 = 0,
    selection_start: u32 = 0,
    active: bool = false,
};

pub const DropdownOption = struct {
    label: []const u8,
    value: *anyopaque,
};

pub const DropdownState = struct {
    options: std.ArrayListUnmanaged(DropdownOption) = .{},
    selected_idx: u32 = 0,
    open: bool = false,
    highlight_idx: u32 = 0,
};

pub const CheckboxState = struct {
    checked: bool = false,
    disabled: bool = false,
    hovered: bool = false,
    pressed: bool = false,
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
// Scene — owns the ElementStore + parallel presentation arrays (INV-3.1)
// ---------------------------------------------------------------------------

pub const InstantiateError = error{
    UnknownTag,
    OutOfMemory,
};

pub const Scene = struct {
    // Scene owns the store. Element creation/removal funnels through Scene so the parallel
    // arrays stay index-aligned with the store's layout[] (spec.md "ownership rule").
    elements: ElementStore,

    // Parallel presentation arrays, indexed by ElementId.index (same index space as the
    // store). Implementation-defined backing (ArrayListUnmanaged etc.).
    _kind: std.ArrayListUnmanaged(WidgetKind) = .{},
    _style: std.ArrayListUnmanaged(ComputedStyle) = .{},
    _text: std.ArrayListUnmanaged(?[]const u8) = .{},

    // Focus state (R30)
    focused_idx: u32 = std.math.maxInt(u32),
    focusable_indices: std.ArrayListUnmanaged(u32) = .{},

    // Per-widget state parallel arrays (INV-3.1)
    _button_state: std.ArrayListUnmanaged(ButtonState) = .{},
    _queued_callbacks: std.ArrayListUnmanaged(CallbackFn) = .{},
    _input_state: std.ArrayListUnmanaged(InputState) = .{},
    _dropdown_state: std.ArrayListUnmanaged(DropdownState) = .{},
    _checkbox_state: std.ArrayListUnmanaged(CheckboxState) = .{},
    _scroll_state: std.ArrayListUnmanaged(ScrollState) = .{},
    _pseudo: std.ArrayListUnmanaged(PseudoState) = .{},
    _image_state: std.ArrayListUnmanaged(ImageState) = .{},

    // R52 — Hidden state parallel arrays
    _hidden: std.ArrayListUnmanaged(bool) = .{},
    _saved_display: std.ArrayListUnmanaged(Display) = .{},

    gpa: std.mem.Allocator,

    pub fn init(gpa: std.mem.Allocator) Scene {
        _ = gpa;
        @compileError("not implemented — implement per spec.md; do not change this signature");
    }

    pub fn deinit(self: *Scene) void {
        _ = self;
        @compileError("not implemented — implement per spec.md; do not change this signature");
    }

    pub fn reset(self: *Scene) void {
        _ = self;
        @compileError("not implemented — implement per spec.md; do not change this signature");
    }

    /// Build the descriptor subtree into the store + presentation arrays (no font). Resolves
    /// classes layered over per-kind defaults (spec.md "merge rule"). Returns the root id.
    /// Unknown tag → InstantiateError.UnknownTag.
    /// After instantiation, rebuilds focusable_indices (R30, B2: includes .checkbox).
    pub fn instantiate(self: *Scene, desc: NodeDesc, tokens: Tokens) InstantiateError!ElementId {
        _ = self;
        _ = desc;
        _ = tokens;
        @compileError("not implemented — implement per spec.md; do not change this signature");
    }

    /// Measure every text-bearing element and fill its LayoutNode.measured, ensuring glyphs
    /// are in the atlas. Font-dependent; run after instantiate, before layout.
    pub fn measurePass(self: *Scene, font: *text.Font, atlas: *text.GlyphAtlas) text.FontError!void {
        _ = self;
        _ = font;
        _ = atlas;
        @compileError("not implemented — implement per spec.md; do not change this signature");
    }

    // --- accessors ---

    pub fn store(self: *Scene) *ElementStore {
        _ = self;
        @compileError("not implemented — implement per spec.md; do not change this signature");
    }

    pub fn kindOf(self: *Scene, id: ElementId) WidgetKind {
        _ = self;
        _ = id;
        @compileError("not implemented — implement per spec.md; do not change this signature");
    }

    /// Return the widget kind for a raw element index (C1 fix).
    pub fn kindOfIdx(self: *Scene, idx: u32) WidgetKind {
        _ = self;
        _ = idx;
        @compileError("not implemented — implement per spec.md; do not change this signature");
    }

    pub fn styleOf(self: *Scene, id: ElementId) *ComputedStyle {
        _ = self;
        _ = id;
        @compileError("not implemented — implement per spec.md; do not change this signature");
    }

    pub fn textOf(self: *Scene, id: ElementId) ?[]const u8 {
        _ = self;
        _ = id;
        @compileError("not implemented — implement per spec.md; do not change this signature");
    }

    pub fn count(self: *Scene) u32 {
        _ = self;
        @compileError("not implemented — implement per spec.md; do not change this signature");
    }

    // --- focus (R30) ---

    pub fn setFocus(self: *Scene, idx: u32) void {
        _ = self;
        _ = idx;
        @compileError("not implemented — implement per spec.md; do not change this signature");
    }

    pub fn getFocus(self: *Scene) u32 {
        _ = self;
        @compileError("not implemented — implement per spec.md; do not change this signature");
    }

    pub fn isFocusable(self: *Scene, idx: u32) bool {
        _ = self;
        _ = idx;
        @compileError("not implemented — implement per spec.md; do not change this signature");
    }

    pub fn focusNext(self: *Scene) void {
        _ = self;
        @compileError("not implemented — implement per spec.md; do not change this signature");
    }

    pub fn focusPrev(self: *Scene) void {
        _ = self;
        @compileError("not implemented — implement per spec.md; do not change this signature");
    }

    // --- button (R31) ---

    pub fn setButtonCallback(self: *Scene, idx: u32, callback: CallbackFn) !void {
        _ = self;
        _ = idx;
        _ = callback;
        @compileError("not implemented — implement per spec.md; do not change this signature");
    }

    pub fn buttonStateOf(self: *Scene, idx: u32) *ButtonState {
        _ = self;
        _ = idx;
        @compileError("not implemented — implement per spec.md; do not change this signature");
    }

    pub fn fireQueuedCallbacks(self: *Scene) void {
        _ = self;
        @compileError("not implemented — implement per spec.md; do not change this signature");
    }

    // --- input (R32) ---

    pub fn inputStateOf(self: *Scene, idx: u32) *InputState {
        _ = self;
        _ = idx;
        @compileError("not implemented — implement per spec.md; do not change this signature");
    }

    pub fn setInputText(self: *Scene, idx: u32, initial_text: []const u8) !void {
        _ = self;
        _ = idx;
        _ = initial_text;
        @compileError("not implemented — implement per spec.md; do not change this signature");
    }

    pub fn getInputText(self: *Scene, idx: u32) []const u8 {
        _ = self;
        _ = idx;
        @compileError("not implemented — implement per spec.md; do not change this signature");
    }

    // --- dropdown (R33) ---

    pub fn dropdownStateOf(self: *Scene, idx: u32) *DropdownState {
        _ = self;
        _ = idx;
        @compileError("not implemented — implement per spec.md; do not change this signature");
    }

    pub fn setDropdownOptions(self: *Scene, idx: u32, options: []const DropdownOption) !void {
        _ = self;
        _ = idx;
        _ = options;
        @compileError("not implemented — implement per spec.md; do not change this signature");
    }

    pub fn selectDropdownOption(self: *Scene, idx: u32, option_idx: u32) !void {
        _ = self;
        _ = idx;
        _ = option_idx;
        @compileError("not implemented — implement per spec.md; do not change this signature");
    }

    pub fn openDropdown(self: *Scene, idx: u32) void {
        _ = self;
        _ = idx;
        @compileError("not implemented — implement per spec.md; do not change this signature");
    }

    pub fn closeDropdown(self: *Scene, idx: u32) void {
        _ = self;
        _ = idx;
        @compileError("not implemented — implement per spec.md; do not change this signature");
    }

    pub fn toggleDropdown(self: *Scene, idx: u32) void {
        _ = self;
        _ = idx;
        @compileError("not implemented — implement per spec.md; do not change this signature");
    }

    pub fn getDropdownValue(self: *Scene, idx: u32) *anyopaque {
        _ = self;
        _ = idx;
        @compileError("not implemented — implement per spec.md; do not change this signature");
    }

    // --- checkbox (R34) ---

    pub fn checkboxStateOf(self: *Scene, idx: u32) *CheckboxState {
        _ = self;
        _ = idx;
        @compileError("not implemented — implement per spec.md; do not change this signature");
    }

    pub fn setCheckboxChecked(self: *Scene, idx: u32, checked: bool) void {
        _ = self;
        _ = idx;
        _ = checked;
        @compileError("not implemented — implement per spec.md; do not change this signature");
    }

    pub fn isCheckboxChecked(self: *Scene, idx: u32) bool {
        _ = self;
        _ = idx;
        @compileError("not implemented — implement per spec.md; do not change this signature");
    }

    // --- scroll (R35) ---

    pub fn scrollStateOf(self: *Scene, idx: u32) *ScrollState {
        _ = self;
        _ = idx;
        @compileError("not implemented — implement per spec.md; do not change this signature");
    }

    pub fn setScrollOffset(self: *Scene, idx: u32, offset_y: f32, offset_x: f32) void {
        _ = self;
        _ = idx;
        _ = offset_y;
        _ = offset_x;
        @compileError("not implemented — implement per spec.md; do not change this signature");
    }

    pub fn getScrollOffset(self: *Scene, idx: u32) struct { y: f32, x: f32 } {
        _ = self;
        _ = idx;
        @compileError("not implemented — implement per spec.md; do not change this signature");
    }

    // --- pseudo-state (R40) ---

    pub fn pseudoOf(self: *Scene, idx: u32) *PseudoState {
        _ = self;
        _ = idx;
        @compileError("not implemented — implement per spec.md; do not change this signature");
    }

    pub fn setPseudo(self: *Scene, idx: u32, state: PseudoState) void {
        _ = self;
        _ = idx;
        _ = state;
        @compileError("not implemented — implement per spec.md; do not change this signature");
    }

    // --- image/icon (R43) ---

    pub fn imageStateOf(self: *Scene, idx: u32) *ImageState {
        _ = self;
        _ = idx;
        @compileError("not implemented — implement per spec.md; do not change this signature");
    }

    pub fn setImage(self: *Scene, idx: u32, id: ImageId) void {
        _ = self;
        _ = idx;
        _ = id;
        @compileError("not implemented — implement per spec.md; do not change this signature");
    }

    pub fn setImageTint(self: *Scene, idx: u32, tint: theme.Color) void {
        _ = self;
        _ = idx;
        _ = tint;
        @compileError("not implemented — implement per spec.md; do not change this signature");
    }

    // --- hidden state (R52) ---

    pub fn isHidden(self: *const Scene, idx: u32) bool {
        _ = self;
        _ = idx;
        @compileError("not implemented — implement per spec.md; do not change this signature");
    }

    pub fn setHidden(self: *Scene, idx: u32, hidden: bool) void {
        _ = self;
        _ = idx;
        _ = hidden;
        @compileError("not implemented — implement per spec.md; do not change this signature");
    }

    // --- children management (R53) ---

    pub fn removeChildren(self: *Scene, parent_idx: u32) void {
        _ = self;
        _ = parent_idx;
        @compileError("not implemented — implement per spec.md; do not change this signature");
    }

    pub fn instantiateUnder(
        self: *Scene,
        parent_id: ElementId,
        desc: NodeDesc,
        tokens: Tokens,
    ) InstantiateError!ElementId {
        _ = self;
        _ = parent_id;
        _ = desc;
        _ = tokens;
        @compileError("not implemented — implement per spec.md; do not change this signature");
    }
};
