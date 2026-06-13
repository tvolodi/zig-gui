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

/// Sentinel for "no element" — used in focused_idx and similar u32 index fields.
pub const NONE: u32 = std.math.maxInt(u32);

pub const WidgetKind = enum { text, button, input, card, row, column, dropdown, checkbox, scrollview, image, icon, textarea, separator, radio, slider };

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
    if (eql(u8, tag, "Textarea")) return .textarea;
    if (eql(u8, tag, "Separator")) return .separator;
    if (eql(u8, tag, "Radio")) return .radio;
    if (eql(u8, tag, "Slider")) return .slider;
    return null;
}

/// Per-kind default layout. Row/Column are flex containers; everything else is block.
/// Implemented here (simple/definitional).
pub fn defaultLayoutFor(kind: WidgetKind) LayoutNode {
    return switch (kind) {
        .row => .{ .display = .flex, .direction = .row },
        .column => .{ .display = .flex, .direction = .column },
        .scrollview => .{ .display = .block, .overflow = .hidden },
        .textarea => .{ .display = .block, .overflow = .hidden },
        .separator => .{ .display = .block, .width = .{ .percent = 100 }, .height = .{ .px = 1 } },
        .radio => .{ .display = .flex, .direction = .row, .align_items = .center },
        .slider => .{ .display = .block, .height = .{ .px = 24 } },
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

// M11 RB0 — OS cursor shapes (mirrors mod01.CursorShape).
pub const CursorShape = enum {
    arrow, text_beam, crosshair, hand, resize_ew, resize_ns, resize_all, not_allowed,
};

// M11 RB1 — drag-and-drop callback bundles.
pub const DragCallbacks = struct {
    /// Called when the drag deadzone is exceeded. Returns an opaque payload carried
    /// through subsequent drag events.
    on_drag_start: ?*const fn (idx: u32, x: f32, y: f32) u64 = null,
    on_drag_move: ?*const fn (idx: u32, x: f32, y: f32, payload: u64) void = null,
    on_drag_end:  ?*const fn (idx: u32, payload: u64) void = null,
};
pub const DropCallbacks = struct {
    on_drag_enter: ?*const fn (target_idx: u32, source_idx: u32) void = null,
    on_drag_leave: ?*const fn (target_idx: u32, source_idx: u32) void = null,
    on_drop:       ?*const fn (target_idx: u32, source_idx: u32, payload: u64) void = null,
};

// M11 RB5 — pinch callback type (called synchronously, not queued).
pub const PinchCallbackFn = *const fn (idx: u32, scale_delta: f32) void;

pub const ButtonState = struct {
    hovered: bool = false,
    pressed: bool = false,
    disabled: bool = false,
    on_click: ?CallbackFn = null,
};

pub const InputState = struct {
    text: std.ArrayListUnmanaged(u8) = .{},
    cursor: u32 = 0,
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
// R62 — Text selection state
// ---------------------------------------------------------------------------

/// Byte-offset selection range for a text or input element.
pub const TextSelection = struct {
    anchor: u32 = 0,
    active: u32 = 0,
    pub fn isEmpty(self: TextSelection) bool {
        return self.anchor == self.active;
    }
    pub fn range(self: TextSelection) struct { lo: u32, hi: u32 } {
        if (self.anchor <= self.active) return .{ .lo = self.anchor, .hi = self.active };
        return .{ .lo = self.active, .hi = self.anchor };
    }
};

// ---------------------------------------------------------------------------
// R63 — Textarea state
// ---------------------------------------------------------------------------

/// Extra per-element state for multi-line textarea widgets.
pub const TextareaState = struct {
    line_starts: std.ArrayListUnmanaged(u32) = .{},
    scroll_y: f32 = 0,
    content_h: f32 = 0,
    container_h: f32 = 0,
};

// ---------------------------------------------------------------------------
// R71 — Radio state / R72 — Slider state
// ---------------------------------------------------------------------------

/// Per-element state for radio widgets (R71).
pub const RadioState = struct {
    group_id: u16 = 0,
    value_str: []const u8 = "",
    selected: bool = false,
    disabled: bool = false,
    hovered: bool = false,
    pressed: bool = false,
};

/// Per-element state for slider widgets (R72).
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
// Scene — owns the ElementStore + parallel presentation arrays (INV-3.1)
// ---------------------------------------------------------------------------

pub const InstantiateError = error{
    UnknownTag,
    OutOfMemory,
};

pub const BadgeColor = enum { default, success, warning, error_c };

pub const BadgeState = struct {
    text: [8]u8 = .{0} ** 8,
    color: BadgeColor = .default,
};

pub const CellTextFn = *const fn (row_ptr: *anyopaque, col: u8, buf: []u8) u8;

pub const DataTableRows = struct {
    row_ptr: *anyopaque,
    row_size: usize,
    row_count: u32,
    cell_fn: CellTextFn,
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

    // R62 — Selection state parallel array
    _selection: std.ArrayListUnmanaged(TextSelection) = .{},

    // R63 — Textarea state parallel array
    _textarea_state: std.ArrayListUnmanaged(TextareaState) = .{},

    // R71 — Radio state parallel array
    _radio_state: std.ArrayListUnmanaged(RadioState) = .{},

    // R72 — Slider state parallel array
    _slider_state: std.ArrayListUnmanaged(SliderState) = .{},

    // M11 RB0 — Per-element cursor shape override (null = use defaultCursorFor).
    _cursor: std.ArrayListUnmanaged(?CursorShape) = .{},

    // M11 RB1 — Per-element drag/drop callback bundles.
    _drag: std.ArrayListUnmanaged(?DragCallbacks) = .{},
    _drop: std.ArrayListUnmanaged(?DropCallbacks) = .{},

    // M11 RB2 — Per-element right-click callback.
    _right_click: std.ArrayListUnmanaged(?CallbackFn) = .{},

    // M11 RB3 — Per-element double-click callback.
    _double_click: std.ArrayListUnmanaged(?CallbackFn) = .{},

    // M11 RB5 — Per-element pinch callback.
    _pinch: std.ArrayListUnmanaged(?PinchCallbackFn) = .{},

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

    // --- selection (R62) ---

    pub fn selectionOf(self: *Scene, idx: u32) *TextSelection {
        _ = self;
        _ = idx;
        @compileError("not implemented — implement per spec.md; do not change this signature");
    }

    pub fn setSelection(self: *Scene, idx: u32, anchor: u32, active: u32) void {
        _ = self;
        _ = idx;
        _ = anchor;
        _ = active;
        @compileError("not implemented — implement per spec.md; do not change this signature");
    }

    pub fn clearSelection(self: *Scene, idx: u32) void {
        _ = self;
        _ = idx;
        @compileError("not implemented — implement per spec.md; do not change this signature");
    }

    // --- textarea (R63) ---

    pub fn textareaStateOf(self: *Scene, idx: u32) *TextareaState {
        _ = self;
        _ = idx;
        @compileError("not implemented — implement per spec.md; do not change this signature");
    }

    // --- radio (R71) ---

    pub fn radioStateOf(self: *Scene, idx: u32) *RadioState {
        _ = self;
        _ = idx;
        @compileError("not implemented — implement per spec.md; do not change this signature");
    }

    pub fn isRadioSelected(self: *Scene, idx: u32) bool {
        _ = self;
        _ = idx;
        @compileError("not implemented — implement per spec.md; do not change this signature");
    }

    pub fn selectRadio(self: *Scene, idx: u32) void {
        _ = self;
        _ = idx;
        @compileError("not implemented — implement per spec.md; do not change this signature");
    }

    pub fn selectNextInGroup(self: *Scene, group_id: u16) void {
        _ = self;
        _ = group_id;
        @compileError("not implemented — implement per spec.md; do not change this signature");
    }

    pub fn selectPrevInGroup(self: *Scene, group_id: u16) void {
        _ = self;
        _ = group_id;
        @compileError("not implemented — implement per spec.md; do not change this signature");
    }

    // --- slider (R72) ---

    pub fn sliderStateOf(self: *Scene, idx: u32) *SliderState {
        _ = self;
        _ = idx;
        @compileError("not implemented — implement per spec.md; do not change this signature");
    }

    pub fn getSliderValue(self: *Scene, idx: u32) f32 {
        _ = self;
        _ = idx;
        @compileError("not implemented — implement per spec.md; do not change this signature");
    }

    pub fn setSliderValue(self: *Scene, idx: u32, value: f32) void {
        _ = self;
        _ = idx;
        _ = value;
        @compileError("not implemented — implement per spec.md; do not change this signature");
    }

    // --- M11 RB0: cursor shape ---

    pub fn cursorOf(self: *const Scene, idx: u32) ?CursorShape {
        _ = self; _ = idx;
        @compileError("not implemented — implement per spec.md; do not change this signature");
    }

    // --- M11 RB1: drag-and-drop ---

    pub fn setDragSource(self: *Scene, idx: u32, cbs: DragCallbacks) void {
        _ = self; _ = idx; _ = cbs;
        @compileError("not implemented — implement per spec.md; do not change this signature");
    }

    pub fn clearDragSource(self: *Scene, idx: u32) void {
        _ = self; _ = idx;
        @compileError("not implemented — implement per spec.md; do not change this signature");
    }

    pub fn setDropTarget(self: *Scene, idx: u32, cbs: DropCallbacks) void {
        _ = self; _ = idx; _ = cbs;
        @compileError("not implemented — implement per spec.md; do not change this signature");
    }

    pub fn clearDropTarget(self: *Scene, idx: u32) void {
        _ = self; _ = idx;
        @compileError("not implemented — implement per spec.md; do not change this signature");
    }

    // --- M11 RB2: right-click ---

    pub fn setRightClick(self: *Scene, idx: u32, cb: CallbackFn) void {
        _ = self; _ = idx; _ = cb;
        @compileError("not implemented — implement per spec.md; do not change this signature");
    }

    pub fn clearRightClick(self: *Scene, idx: u32) void {
        _ = self; _ = idx;
        @compileError("not implemented — implement per spec.md; do not change this signature");
    }

    pub fn rightClickOf(self: *const Scene, idx: u32) ?CallbackFn {
        _ = self; _ = idx;
        @compileError("not implemented — implement per spec.md; do not change this signature");
    }

    // --- M11 RB3: double-click ---

    pub fn setDoubleClick(self: *Scene, idx: u32, cb: CallbackFn) void {
        _ = self; _ = idx; _ = cb;
        @compileError("not implemented — implement per spec.md; do not change this signature");
    }

    pub fn clearDoubleClick(self: *Scene, idx: u32) void {
        _ = self; _ = idx;
        @compileError("not implemented — implement per spec.md; do not change this signature");
    }

    pub fn doubleClickOf(self: *const Scene, idx: u32) ?CallbackFn {
        _ = self; _ = idx;
        @compileError("not implemented — implement per spec.md; do not change this signature");
    }

    // --- M11 RB5: pinch gesture ---

    pub fn setPinch(self: *Scene, idx: u32, cb: PinchCallbackFn) void {
        _ = self; _ = idx; _ = cb;
        @compileError("not implemented — implement per spec.md; do not change this signature");
    }

    pub fn clearPinch(self: *Scene, idx: u32) void {
        _ = self; _ = idx;
        @compileError("not implemented — implement per spec.md; do not change this signature");
    }

    pub fn pinchOf(self: *const Scene, idx: u32) ?PinchCallbackFn {
        _ = self; _ = idx;
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
