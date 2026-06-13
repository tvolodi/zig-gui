//! state.zig — Signals, conditional rendering, list rendering (Screen 8).
//!
//! The spec requires Signal(T) and Computed(T). Those live in the app layer
//! and need heap allocation. This screen demonstrates the visible patterns
//! (counter, conditional, list) using static widget state wired to button
//! callbacks — the same reactive-repaint mechanism the Signal path uses.

const std = @import("std");
const mod07 = @import("../07/types.zig");
const mod05 = @import("../05/types.zig");
const mod06 = @import("../06/types.zig");

const Scene = mod07.Scene;
const Tokens = mod05.Tokens;
const NodeDesc = mod06.NodeDesc;
const Attr = mod06.Attr;
const CallbackFn = mod07.CallbackFn;

const shared = @import("../shared/types.zig");
const sidebar = @import("../shared/sidebar.zig");

pub const StateCtx = struct {
    global: *shared.GlobalState,
};

// ---------------------------------------------------------------------------
// 8a. Counter state (module-level, program lifetime)
// ---------------------------------------------------------------------------

var _counter: i32 = 0;

// Text display for the counter value — updated in callbacks.
// The text node at a fixed scene index is mutated via scene.setText.
// We store a scene pointer across callbacks via the callback context struct.

// Persistent buffer for counter value text — lives for the duration of the screen.
var _counter_buf: [16]u8 = undefined;

const CounterCb = struct {
    scene:     *Scene,
    delta:     i32,
    value_idx: u32,   // index of the Text node showing the number
    label_idx: u32,   // index of the Text node showing Even/Odd

    pub fn onClick(ptr: *anyopaque) void {
        const self: *CounterCb = @ptrCast(@alignCast(ptr));
        _counter += self.delta;
        if (_counter < 0) _counter = 0;

        // Update counter value text — use module-level buffer so the slice stays valid.
        const s = std.fmt.bufPrint(&_counter_buf, "{d}", .{_counter}) catch return;
        self.scene.setText(self.value_idx, s);
        if (self.value_idx < self.scene.elements.dirty.bit_length)
            self.scene.elements.dirty.set(self.value_idx);

        // Update Even/Odd label
        const parity: []const u8 = if (@mod(_counter, 2) == 0) "Even" else "Odd";
        self.scene.setText(self.label_idx, parity);
        if (self.label_idx < self.scene.elements.dirty.bit_length)
            self.scene.elements.dirty.set(self.label_idx);
    }
};

var _cb_inc: CounterCb = undefined;
var _cb_dec: CounterCb = undefined;

// ---------------------------------------------------------------------------
// 8b. Conditional rendering callback
// ---------------------------------------------------------------------------

const CondCb = struct {
    scene:       *Scene,
    checkbox_idx: u32,
    detail_idx:  u32,

    pub fn onChange(ptr: *anyopaque) void {
        const self: *CondCb = @ptrCast(@alignCast(ptr));
        const checked = self.scene.isCheckboxChecked(self.checkbox_idx);
        self.scene.setHidden(self.detail_idx, !checked);
    }
};

var _cb_cond: CondCb = undefined;

// ---------------------------------------------------------------------------
// build
// ---------------------------------------------------------------------------

pub fn build(
    scene: *Scene,
    tokens: Tokens,
    app: *anyopaque,
    ctx: ?*anyopaque,
) anyerror!void {
    _ = app;
    const c: *StateCtx = @ptrCast(@alignCast(ctx.?));
    _counter = 0;

    const h_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "State & Reactivity" } }};
    const heading = NodeDesc{ .tag = "Text", .classes = "text-xl", .attrs = &h_attrs };
    const sep = NodeDesc{ .tag = "Separator" };

    // -----------------------------------------------------------------------
    // 8a. Counter
    // -----------------------------------------------------------------------
    const ctr_h_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Counter" } }};
    const ctr_h = NodeDesc{ .tag = "Text", .classes = "font-bold", .attrs = &ctr_h_attrs };

    const dec_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "\xe2\x88\x92" } }};
    const inc_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "+" } }};
    const val_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "0" } }};

    const btn_dec  = NodeDesc{ .tag = "Button", .classes = "w-12 h-12 text-xl", .attrs = &dec_attrs };
    const ctr_val  = NodeDesc{ .tag = "Text",   .classes = "text-xl w-16", .attrs = &val_attrs };
    const btn_inc  = NodeDesc{ .tag = "Button", .classes = "w-12 h-12 text-xl", .attrs = &inc_attrs };

    const ctr_row_children = [3]NodeDesc{ btn_dec, ctr_val, btn_inc };
    const ctr_row = NodeDesc{ .tag = "Row", .classes = "gap-4 items-center", .children = &ctr_row_children };

    const parity_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Even" } }};
    const parity_lbl = NodeDesc{ .tag = "Text", .classes = "text-muted text-sm", .attrs = &parity_attrs };

    const ctr_sect_children = [3]NodeDesc{ ctr_h, ctr_row, parity_lbl };
    const ctr_sect = NodeDesc{ .tag = "Card", .classes = "p-4 gap-3", .children = &ctr_sect_children };

    // -----------------------------------------------------------------------
    // 8b. Conditional rendering demo
    // -----------------------------------------------------------------------
    const cond_h_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Conditional rendering" } }};
    const cond_h = NodeDesc{ .tag = "Text", .classes = "font-bold", .attrs = &cond_h_attrs };

    const cb_attrs = [1]Attr{.{ .name = "label", .value = .{ .literal = "Show detail panel" } }};
    const cond_cb = NodeDesc{ .tag = "Checkbox", .attrs = &cb_attrs };

    const detail_txt_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "This element is conditionally rendered via checkbox state." } }};
    const detail_card = NodeDesc{ .tag = "Card", .classes = "p-3", .children = &[1]NodeDesc{
        NodeDesc{ .tag = "Text", .classes = "text-sm text-muted", .attrs = &detail_txt_attrs },
    } };

    const cond_sect_children = [3]NodeDesc{ cond_h, cond_cb, detail_card };
    const cond_sect = NodeDesc{ .tag = "Card", .classes = "p-4 gap-3", .children = &cond_sect_children };

    // -----------------------------------------------------------------------
    // 8c. List rendering demo
    // -----------------------------------------------------------------------
    const list_h_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "List rendering" } }};
    const list_h = NodeDesc{ .tag = "Text", .classes = "font-bold", .attrs = &list_h_attrs };

    const list_note_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Dynamic list: use the Forms screen to see add/remove widgets." } }};
    const list_note = NodeDesc{ .tag = "Text", .classes = "text-sm text-muted", .attrs = &list_note_attrs };

    // Static example list (shows the visual pattern)
    const li1_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "\xe2\x80\xa2 Item Alpha" } }};
    const li2_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "\xe2\x80\xa2 Item Beta" } }};
    const li3_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "\xe2\x80\xa2 Item Gamma" } }};
    const li1 = NodeDesc{ .tag = "Text", .attrs = &li1_attrs };
    const li2 = NodeDesc{ .tag = "Text", .attrs = &li2_attrs };
    const li3 = NodeDesc{ .tag = "Text", .attrs = &li3_attrs };
    const list_items = [3]NodeDesc{ li1, li2, li3 };
    const list_col = NodeDesc{ .tag = "Column", .classes = "gap-1", .children = &list_items };

    const count_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "3 items" } }};
    const count_lbl = NodeDesc{ .tag = "Text", .classes = "text-sm text-muted", .attrs = &count_attrs };

    const list_sect_children = [4]NodeDesc{ list_h, count_lbl, list_note, list_col };
    const list_sect = NodeDesc{ .tag = "Card", .classes = "p-4 gap-3", .children = &list_sect_children };

    // -----------------------------------------------------------------------
    // Assemble
    // -----------------------------------------------------------------------
    const body_children = [5]NodeDesc{
        ctr_sect,
        NodeDesc{ .tag = "Separator" },
        cond_sect,
        NodeDesc{ .tag = "Separator" },
        list_sect,
    };
    const body = NodeDesc{ .tag = "Column", .classes = "gap-4", .children = &body_children };
    const scroll = NodeDesc{ .tag = "ScrollView", .classes = "flex-1", .children = &[1]NodeDesc{
        NodeDesc{ .tag = "Column", .classes = "p-2", .children = &[1]NodeDesc{body} },
    } };

    const content_children = [3]NodeDesc{ heading, sep, scroll };
    const content = NodeDesc{ .tag = "Column", .classes = "flex-1 gap-3 p-6", .children = &content_children };

    const root_children = [2]NodeDesc{ sidebar.buildSidebar(), content };
    const root = NodeDesc{ .tag = "Row", .classes = "w-full h-full", .children = &root_children };

    _ = try scene.instantiate(root, tokens);
    try shared.wireSidebarCallbacks(scene, c.global, tokens, 9); // 9 = State button

    // DFS: 0=root, 1=sidebar, 2-9=sidebar btns, 10=content, 11=heading, 12=sep, 13=scroll,
    //   14=inner-col, 15=body, 16=ctr_sect, 17=ctr_h, 18=ctr_row,
    //   19=btn_dec, 20=ctr_val, 21=btn_inc, 22=parity_lbl,
    //   23=Separator, 24=cond_sect, 25=cond_h, 26=cond_cb, 27=detail_card, 28=detail_text
    const value_idx: u32 = 20;
    const parity_idx: u32 = 22;
    const dec_idx: u32 = 19;
    const inc_idx: u32 = 21;
    const cond_cb_idx: u32 = 26;
    const detail_card_idx: u32 = 27;

    _cb_inc = CounterCb{ .scene = scene, .delta = 1,  .value_idx = value_idx, .label_idx = parity_idx };
    _cb_dec = CounterCb{ .scene = scene, .delta = -1, .value_idx = value_idx, .label_idx = parity_idx };

    try scene.setButtonCallback(inc_idx, CallbackFn{ .ptr = &_cb_inc, .call = CounterCb.onClick });
    try scene.setButtonCallback(dec_idx, CallbackFn{ .ptr = &_cb_dec, .call = CounterCb.onClick });

    // Detail card starts hidden; checkbox reveals it.
    scene.setHidden(detail_card_idx, true);
    _cb_cond = CondCb{ .scene = scene, .checkbox_idx = cond_cb_idx, .detail_idx = detail_card_idx };
    try scene.setCheckboxCallback(cond_cb_idx, CallbackFn{ .ptr = &_cb_cond, .call = CondCb.onChange });
}
