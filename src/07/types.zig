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
    return null;
}

/// Per-kind default layout. Row/Column are flex containers; ScrollView clips; everything else is block.
pub fn defaultLayoutFor(kind: WidgetKind) LayoutNode {
    return switch (kind) {
        .row => .{ .display = .flex, .direction = .row },
        .column => .{ .display = .flex, .direction = .column },
        .scrollview => .{ .display = .block, .overflow = .hidden },
        else => .{ .display = .block },
    };
}

/// Per-kind default style, wired to module 05's component builders.
pub fn defaultStyleFor(kind: WidgetKind, tokens: Tokens) ComputedStyle {
    return switch (kind) {
        .button => theme.buttonPrimary(tokens),
        .card => theme.cardSurface(tokens),
        .input, .dropdown => theme.inputDefault(tokens),
        .text, .row, .column, .checkbox, .scrollview, .image, .icon => ComputedStyle{},
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
    selection_start: u32 = 0,
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
        self.elements.deinit();
    }

    pub fn reset(self: *Scene) void {
        for (self._input_state.items) |*inp| inp.text.deinit(self.gpa);
        for (self._dropdown_state.items) |*dd| dd.options.deinit(self.gpa);
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
                .button, .input, .dropdown, .checkbox => {
                    self.focusable_indices.append(self.gpa, @as(u32, @intCast(i))) catch {};
                },
                else => {},
            }
        }
        return id;
    }

    /// Measure every text-bearing element and fill its LayoutNode.measured.
    /// R60: accepts FontFamily so each element uses the correct bold/italic face.
    pub fn measurePass(self: *Scene, family: *font_family_mod.FontFamily, atlas: *text.GlyphAtlas) text.FontError!void {
        for (self._text.items, 0..) |maybe_str, i| {
            const str = maybe_str orelse continue;
            const style = self._style.items[i];
            const font = family.face(style.font_bold, style.font_italic);
            const para = try text.layoutParagraph(self.gpa, font, atlas, str, style.font_size, 1e6);
            defer self.gpa.free(para.glyphs);
            self.elements.layout.items[i].measured = .{ .w = para.extent.w, .h = para.extent.h };
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
        const NONE = std.math.maxInt(u32);
        const old_idx = self.focused_idx;

        // Deactivate old element.
        if (old_idx != NONE and old_idx < self._kind.items.len) {
            const old_kind = self._kind.items[old_idx];
            if (old_kind == .input and old_idx < self._input_state.items.len)
                self._input_state.items[old_idx].active = false;
            if (old_kind == .dropdown and old_idx < self._dropdown_state.items.len)
                self._dropdown_state.items[old_idx].open = false;
            if (old_idx < self.elements.dirty.bit_length)
                self.elements.dirty.set(old_idx);
        }

        self.focused_idx = idx;

        // Activate new element.
        if (idx != NONE and idx < self._kind.items.len) {
            if (self._kind.items[idx] == .input and idx < self._input_state.items.len)
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
        inp.selection_start = inp.cursor;
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
    // Children management (R53)
    // -----------------------------------------------------------------------

    /// Remove all direct children of `parent_idx` (and their subtrees) from the scene.
    /// Recycles element indices. Called before re-instantiating a `for=` list.
    pub fn removeChildren(self: *Scene, parent_idx: u32) void {
        const parent_id = ElementId{
            .index = parent_idx,
            .gen   = self.elements.gen.items[parent_idx],
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
            .gen   = self.elements.gen.items[idx],
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
        if (!std.meta.eql(rm.top, emm.top))    final_layout.margin.top    = rm.top;
        if (!std.meta.eql(rm.right, emm.right)) final_layout.margin.right  = rm.right;
        if (!std.meta.eql(rm.bottom, emm.bottom)) final_layout.margin.bottom = rm.bottom;
        if (!std.meta.eql(rm.left, emm.left))   final_layout.margin.left   = rm.left;

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
                .bind    => continue, // bind paths are not evaluated during instantiate
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

        // Apply if= hidden state after element is registered
        if (start_hidden) {
            self.setHidden(id.index, true);
        }

        // --- Recurse into children ---
        for (desc.children) |child| {
            _ = try self.instantiateNode(child, tokens, id);
        }

        return id;
    }
};
