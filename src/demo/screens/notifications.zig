//! notifications.zig — Toast, dialog, and tooltip showcase screen (Screen 6).

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

pub const NotifCtx = struct {
    global: *shared.GlobalState,
};

// ---------------------------------------------------------------------------
// Toast trigger callbacks
// ---------------------------------------------------------------------------

const ToastCb = struct {
    global: *shared.GlobalState,
    msg: []const u8,
    kind: shared.ToastKind,
    duration_ms: u32,

    pub fn onClick(ptr: *anyopaque) void {
        const self: *ToastCb = @ptrCast(@alignCast(ptr));
        if (self.global.toasts) |tm| {
            const now = if (self.global.app_inner) |ai| ai.frame_time_ms else 0;
            tm.show(self.msg, self.kind, self.duration_ms, now);
        }
    }
};

var _cb_info:    ToastCb = undefined;
var _cb_success: ToastCb = undefined;
var _cb_warning: ToastCb = undefined;
var _cb_error:   ToastCb = undefined;
var _cb_flood:   ToastCb = undefined;  // reuses info kind; calls show 4×

const FloodCb = struct {
    global: *shared.GlobalState,

    pub fn onClick(ptr: *anyopaque) void {
        const self: *FloodCb = @ptrCast(@alignCast(ptr));
        const tm = self.global.toasts orelse return;
        const now = if (self.global.app_inner) |ai| ai.frame_time_ms else 0;
        tm.show("This is an info message",   .info,     3000, now);
        tm.show("Operation completed",        .success,  3000, now);
        tm.show("Low disk space",             .warning,  5000, now);
        tm.show("Connection failed",          .@"error", 5000, now);
    }
};
var _cb_flood_all: FloodCb = undefined;

// ---------------------------------------------------------------------------
// Inline feedback widget callbacks
// ---------------------------------------------------------------------------

// Progress steps: 0.0 → 0.25 → 0.50 → 0.75 → 1.0 → indeterminate → 0.0
var _pb_step: u32 = 0;
var _pb_lbl_buf: [32]u8 = undefined;

const ProgressCb = struct {
    scene:   *Scene,
    pb_idx:  u32,
    lbl_idx: u32,

    pub fn onClick(ptr: *anyopaque) void {
        const self: *ProgressCb = @ptrCast(@alignCast(ptr));
        _pb_step = (_pb_step + 1) % 6;
        const ps = self.scene.progressStateOf(self.pb_idx);
        if (_pb_step == 5) {
            ps.indeterminate = true;
            self.scene.setText(self.lbl_idx, "ProgressBar (indeterminate):");
        } else {
            ps.indeterminate = false;
            const v: f32 = @as(f32, @floatFromInt(_pb_step)) * 0.25;
            self.scene.setProgress(self.pb_idx, v);
            const pct: u32 = @intFromFloat(v * 100.0);
            const s = std.fmt.bufPrint(&_pb_lbl_buf, "ProgressBar ({d}%):", .{pct}) catch return;
            self.scene.setText(self.lbl_idx, s);
        }
        if (self.lbl_idx < self.scene.elements.dirty.bit_length)
            self.scene.elements.dirty.set(self.lbl_idx);
    }
};
var _cb_progress: ProgressCb = undefined;

var _badge_count: u32 = 42;
var _badge_buf: [8]u8 = undefined;

const BadgeCb = struct {
    scene:     *Scene,
    badge_idx: u32,

    pub fn onClick(ptr: *anyopaque) void {
        const self: *BadgeCb = @ptrCast(@alignCast(ptr));
        _badge_count += 1;
        if (_badge_count > 99) _badge_count = 0;
        const s = std.fmt.bufPrint(&_badge_buf, "{d}", .{_badge_count}) catch return;
        self.scene.setText(self.badge_idx, s);
        if (self.badge_idx < self.scene.elements.dirty.bit_length)
            self.scene.elements.dirty.set(self.badge_idx);
    }
};
var _cb_badge: BadgeCb = undefined;

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
    const c: *NotifCtx = @ptrCast(@alignCast(ctx.?));

    _cb_info    = .{ .global = c.global, .msg = "This is an info message",   .kind = .info,     .duration_ms = 3000 };
    _cb_success = .{ .global = c.global, .msg = "Operation completed",        .kind = .success,  .duration_ms = 3000 };
    _cb_warning = .{ .global = c.global, .msg = "Low disk space",             .kind = .warning,  .duration_ms = 5000 };
    _cb_error   = .{ .global = c.global, .msg = "Connection failed",          .kind = .@"error", .duration_ms = 5000 };
    _cb_flood_all = .{ .global = c.global };

    const h_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Notifications & Feedback" } }};
    const heading = NodeDesc{ .tag = "Text", .classes = "text-xl", .attrs = &h_attrs };
    const sep = NodeDesc{ .tag = "Separator" };

    // -----------------------------------------------------------------------
    // 6a. Toast triggers
    // -----------------------------------------------------------------------
    const toast_h_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Toast notifications" } }};
    const toast_h = NodeDesc{ .tag = "Text", .classes = "font-bold", .attrs = &toast_h_attrs };

    const bi_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Info toast" } }};
    const bs_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Success toast" } }};
    const bw_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Warning toast" } }};
    const be_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Error toast" } }};
    const bf_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Flood (4\xc3\x97)" } }};

    const btn_info    = NodeDesc{ .tag = "Button", .attrs = &bi_attrs };
    const btn_success = NodeDesc{ .tag = "Button", .attrs = &bs_attrs };
    const btn_warning = NodeDesc{ .tag = "Button", .attrs = &bw_attrs };
    const btn_error   = NodeDesc{ .tag = "Button", .attrs = &be_attrs };
    const btn_flood   = NodeDesc{ .tag = "Button", .attrs = &bf_attrs };

    const toast_btns_children = [5]NodeDesc{ btn_info, btn_success, btn_warning, btn_error, btn_flood };
    const toast_btns = NodeDesc{ .tag = "Row", .classes = "gap-2", .children = &toast_btns_children };

    const toast_sect_children = [2]NodeDesc{ toast_h, toast_btns };
    const toast_sect = NodeDesc{ .tag = "Column", .classes = "gap-3", .children = &toast_sect_children };

    // -----------------------------------------------------------------------
    // 6c. Tooltips (simple hover targets)
    // -----------------------------------------------------------------------
    const tooltip_h_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Tooltips (hover for 500 ms)" } }};
    const tooltip_h = NodeDesc{ .tag = "Text", .classes = "font-bold", .attrs = &tooltip_h_attrs };

    const tip1_attrs = [2]Attr{
        .{ .name = "text",    .value = .{ .literal = "Copy" } },
        .{ .name = "tooltip", .value = .{ .literal = "Copy to clipboard" } },
    };
    const tip2_attrs = [2]Attr{
        .{ .name = "text",    .value = .{ .literal = "Cut" } },
        .{ .name = "tooltip", .value = .{ .literal = "Cut selection" } },
    };
    const tip3_attrs = [2]Attr{
        .{ .name = "text",    .value = .{ .literal = "Paste" } },
        .{ .name = "tooltip", .value = .{ .literal = "Paste from clipboard" } },
    };
    const tip4_attrs = [2]Attr{
        .{ .name = "text",    .value = .{ .literal = "Delete" } },
        .{ .name = "tooltip", .value = .{ .literal = "Delete selection" } },
    };
    const tip5_attrs = [2]Attr{
        .{ .name = "text",    .value = .{ .literal = "Settings" } },
        .{ .name = "tooltip", .value = .{ .literal = "Open settings" } },
    };
    const tip1 = NodeDesc{ .tag = "Button", .attrs = &tip1_attrs };
    const tip2 = NodeDesc{ .tag = "Button", .attrs = &tip2_attrs };
    const tip3 = NodeDesc{ .tag = "Button", .attrs = &tip3_attrs };
    const tip4 = NodeDesc{ .tag = "Button", .attrs = &tip4_attrs };
    const tip5 = NodeDesc{ .tag = "Button", .attrs = &tip5_attrs };

    const tip_row_children = [5]NodeDesc{ tip1, tip2, tip3, tip4, tip5 };
    const tip_row = NodeDesc{ .tag = "Row", .classes = "gap-2", .children = &tip_row_children };

    const tooltip_sect_children = [2]NodeDesc{ tooltip_h, tip_row };
    const tooltip_sect = NodeDesc{ .tag = "Column", .classes = "gap-3", .children = &tooltip_sect_children };

    // -----------------------------------------------------------------------
    // Progress / spinner / badge (still present from spec §6a context)
    // -----------------------------------------------------------------------
    const misc_h_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Inline feedback widgets" } }};
    const misc_h = NodeDesc{ .tag = "Text", .classes = "font-bold", .attrs = &misc_h_attrs };

    const pb_lbl_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "ProgressBar (0%):" } }};
    const pb_lbl = NodeDesc{ .tag = "Text", .classes = "text-sm", .attrs = &pb_lbl_attrs };
    const pb_attrs = [1]Attr{.{ .name = "value", .value = .{ .literal = "0.0" } }};
    const pb = NodeDesc{ .tag = "ProgressBar", .classes = "flex-1", .attrs = &pb_attrs };
    const pb_sim_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Step" } }};
    const btn_simulate = NodeDesc{ .tag = "Button", .classes = "text-sm", .attrs = &pb_sim_attrs };
    const pb_row_children = [2]NodeDesc{ pb, btn_simulate };
    const pb_row = NodeDesc{ .tag = "Row", .classes = "gap-2 items-center", .children = &pb_row_children };
    const pb_group_children = [2]NodeDesc{ pb_lbl, pb_row };
    const pb_group = NodeDesc{ .tag = "Column", .classes = "gap-1", .children = &pb_group_children };

    const sp_lbl_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Spinner:" } }};
    const sp_lbl = NodeDesc{ .tag = "Text", .classes = "text-sm", .attrs = &sp_lbl_attrs };
    const spinner = NodeDesc{ .tag = "Spinner" };
    const sp_group_children = [2]NodeDesc{ sp_lbl, spinner };
    const sp_group = NodeDesc{ .tag = "Row", .classes = "gap-3 items-center", .children = &sp_group_children };

    const badge_lbl_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Unread messages:" } }};
    const badge_lbl = NodeDesc{ .tag = "Text", .classes = "text-sm", .attrs = &badge_lbl_attrs };
    const badge_val_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "42" } }};
    const badge = NodeDesc{ .tag = "Badge", .attrs = &badge_val_attrs };
    const badge_inc_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "+" } }};
    const btn_badge_inc = NodeDesc{ .tag = "Button", .classes = "w-8 h-8", .attrs = &badge_inc_attrs };
    const badge_group_children = [3]NodeDesc{ badge_lbl, badge, btn_badge_inc };
    const badge_group = NodeDesc{ .tag = "Row", .classes = "gap-3 items-center", .children = &badge_group_children };

    const misc_children = [4]NodeDesc{ misc_h, pb_group, sp_group, badge_group };
    const misc_sect = NodeDesc{ .tag = "Column", .classes = "gap-3", .children = &misc_children };

    // -----------------------------------------------------------------------
    // Assemble with ScrollView
    // -----------------------------------------------------------------------
    const body_children = [5]NodeDesc{
        toast_sect,
        NodeDesc{ .tag = "Separator" },
        tooltip_sect,
        NodeDesc{ .tag = "Separator" },
        misc_sect,
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
    try shared.wireSidebarCallbacks(scene, c.global, tokens, 7); // 7 = Notifications button

    // DFS: 0=root,1=sidebar,2-9=btns,10=content,11=heading,12=sep,13=scroll,
    //   14=inner-col,15=body,16=toast_sect,17=toast_h,18=toast_btns,
    //   19=btn_info,20=btn_success,21=btn_warning,22=btn_error,23=btn_flood,
    //   24=Separator,25=tooltip_sect,26=tooltip_h,27=tip_row,28-32=tips,
    //   33=Separator,34=misc_sect,35=misc_h,
    //   36=pb_group,37=pb_lbl,38=pb_row,39=pb,40=btn_simulate,
    //   41=sp_group,42=sp_lbl,43=spinner,
    //   44=badge_group,45=badge_lbl,46=badge,47=btn_badge_inc
    try scene.setButtonCallback(19, CallbackFn{ .ptr = &_cb_info,    .call = ToastCb.onClick });
    try scene.setButtonCallback(20, CallbackFn{ .ptr = &_cb_success, .call = ToastCb.onClick });
    try scene.setButtonCallback(21, CallbackFn{ .ptr = &_cb_warning, .call = ToastCb.onClick });
    try scene.setButtonCallback(22, CallbackFn{ .ptr = &_cb_error,   .call = ToastCb.onClick });
    try scene.setButtonCallback(23, CallbackFn{ .ptr = &_cb_flood_all, .call = FloodCb.onClick });

    _pb_step = 0;
    scene.setProgress(39, 0.0);
    _cb_progress = ProgressCb{ .scene = scene, .pb_idx = 39, .lbl_idx = 37 };
    try scene.setButtonCallback(40, CallbackFn{ .ptr = &_cb_progress, .call = ProgressCb.onClick });

    _badge_count = 42;
    _cb_badge = BadgeCb{ .scene = scene, .badge_idx = 46 };
    try scene.setButtonCallback(47, CallbackFn{ .ptr = &_cb_badge, .call = BadgeCb.onClick });
}
