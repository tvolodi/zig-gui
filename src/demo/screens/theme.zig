//! theme.zig — Theme live-swap showcase screen (Screen 5).

const std = @import("std");
const mod07 = @import("../07/types.zig");
const mod05 = @import("../05/types.zig");
const mod06 = @import("../06/types.zig");
const app_impl = @import("app").app_impl;

const Scene = mod07.Scene;
const Tokens = mod05.Tokens;
const NodeDesc = mod06.NodeDesc;
const Attr = mod06.Attr;
const CallbackFn = mod07.CallbackFn;

const shared = @import("../shared/types.zig");
const sidebar = @import("../shared/sidebar.zig");

pub const ThemeCtx = struct {
    global: *shared.GlobalState,
};

// ---------------------------------------------------------------------------
// Bug 8 fix — Font scale slider per-frame tick
// ---------------------------------------------------------------------------

// Module-level storage for slider/readout indices and readout buffer.
var _fs_slider_idx: u32 = 0;
var _fs_val_idx: u32 = 0;
var _fs_buf: [8]u8 = undefined;
var _fs_app_inner: ?*app_impl.AppInner = null;

// Track last applied font scale to avoid calling setFontScale every frame.
var _fs_last_val: f32 = 1.0;

/// Called each frame via AppInner.per_frame_fn.
/// Reads slider value, calls setFontScale only when changed, updates the readout text.
pub fn tick(scene: *Scene) void {
    if (_fs_slider_idx == 0) return;
    if (_fs_slider_idx >= scene.elements.layout.items.len) return;
    if (scene.kindOfIdx(_fs_slider_idx) != .slider) return;
    const val = scene.getSliderValue(_fs_slider_idx);
    // Call setFontScale only when the value changes to avoid rebuilding every frame.
    if (val != _fs_last_val) {
        _fs_last_val = val;
        if (_fs_app_inner) |ai| {
            ai.setFontScale(val);
        }
        // Format the readout (one decimal place + "×").
        const int_part: i32 = @intFromFloat(@trunc(val));
        const frac_part: u32 = @intFromFloat(@round(@rem(val, 1.0) * 10.0));
        const str = std.fmt.bufPrint(&_fs_buf, "{d}.{d}\xc3\x97", .{ int_part, frac_part }) catch return;
        scene.setText(_fs_val_idx, str);
        if (_fs_val_idx < scene.elements.dirty.bit_length)
            scene.elements.dirty.set(_fs_val_idx);
    }
}

// ---------------------------------------------------------------------------
// Theme-switch callbacks
// ---------------------------------------------------------------------------

const ThemeCb = struct {
    app_ptr: *app_impl.AppInner,
    mode: enum { light, dark, hc },

    pub fn onClick(ptr: *anyopaque) void {
        const self: *ThemeCb = @ptrCast(@alignCast(ptr));
        const new_theme = switch (self.mode) {
            .light => mod05.Theme.build(mod05.Palette.default(), .light),
            .dark  => mod05.Theme.build(mod05.Palette.default(), .dark),
            .hc    => mod05.Theme.hc_light,
        };
        self.app_ptr.setTheme(new_theme);
    }
};

var _cb_light: ThemeCb = undefined;
var _cb_dark:  ThemeCb = undefined;
var _cb_hc:    ThemeCb = undefined;

// ---------------------------------------------------------------------------
// build
// ---------------------------------------------------------------------------

pub fn build(
    scene: *Scene,
    tokens: Tokens,
    app: *anyopaque,
    ctx: ?*anyopaque,
) anyerror!void {
    const app_inner: *app_impl.AppInner = @ptrCast(@alignCast(app));
    const c: *ThemeCtx = @ptrCast(@alignCast(ctx.?));

    _cb_light = ThemeCb{ .app_ptr = app_inner, .mode = .light };
    _cb_dark  = ThemeCb{ .app_ptr = app_inner, .mode = .dark };
    _cb_hc    = ThemeCb{ .app_ptr = app_inner, .mode = .hc };

    const h_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Theme" } }};
    const heading = NodeDesc{ .tag = "Text", .classes = "text-xl", .attrs = &h_attrs };
    const sep = NodeDesc{ .tag = "Separator" };

    // -----------------------------------------------------------------------
    // Left panel — controls
    // -----------------------------------------------------------------------
    const ctrl_h_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Color scheme" } }};
    const ctrl_h = NodeDesc{ .tag = "Text", .classes = "font-bold", .attrs = &ctrl_h_attrs };

    const btn_light_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Light" } }};
    const btn_dark_attrs  = [1]Attr{.{ .name = "text", .value = .{ .literal = "Dark" } }};
    const btn_hc_attrs    = [1]Attr{.{ .name = "text", .value = .{ .literal = "High contrast" } }};
    const btn_light = NodeDesc{ .tag = "Button", .classes = "w-full", .attrs = &btn_light_attrs };
    const btn_dark  = NodeDesc{ .tag = "Button", .classes = "w-full", .attrs = &btn_dark_attrs };
    const btn_hc    = NodeDesc{ .tag = "Button", .classes = "w-full", .attrs = &btn_hc_attrs };

    const scheme_children = [4]NodeDesc{ ctrl_h, btn_light, btn_dark, btn_hc };
    const scheme_col = NodeDesc{ .tag = "Column", .classes = "gap-2", .children = &scheme_children };

    const hint_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Tip: F2 cycles themes globally" } }};
    const hint = NodeDesc{ .tag = "Text", .classes = "text-sm text-muted", .attrs = &hint_attrs };

    // Bug 8 fix — Font scale section.
    const fs_h_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Font scale" } }};
    const fs_h = NodeDesc{ .tag = "Text", .classes = "font-bold", .attrs = &fs_h_attrs };
    const fs_lbl_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Font scale:" } }};
    const fs_lbl = NodeDesc{ .tag = "Text", .classes = "text-sm", .attrs = &fs_lbl_attrs };
    const fs_slider_attrs = [4]Attr{
        .{ .name = "min",   .value = .{ .literal = "0.5" } },
        .{ .name = "max",   .value = .{ .literal = "4.0" } },
        .{ .name = "step",  .value = .{ .literal = "0.25" } },
        .{ .name = "value", .value = .{ .literal = "1.0" } },
    };
    const fs_slider = NodeDesc{ .tag = "Slider", .classes = "flex-1", .attrs = &fs_slider_attrs };
    const fs_val_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "1.0\xc3\x97" } }};
    const fs_val = NodeDesc{ .tag = "Text", .classes = "w-8", .attrs = &fs_val_attrs };
    const fs_row_children = [3]NodeDesc{ fs_lbl, fs_slider, fs_val };
    const fs_row = NodeDesc{ .tag = "Row", .classes = "gap-3 items-center", .children = &fs_row_children };
    const fs_group_children = [2]NodeDesc{ fs_h, fs_row };
    const fs_group = NodeDesc{ .tag = "Column", .classes = "gap-2", .children = &fs_group_children };

    const left_children = [4]NodeDesc{ scheme_col, fs_group, NodeDesc{ .tag = "Separator" }, hint };
    const left_panel = NodeDesc{ .tag = "Card", .classes = "w-56 p-4 gap-4", .children = &left_children };

    // -----------------------------------------------------------------------
    // Right panel — live token preview
    // -----------------------------------------------------------------------
    const prev_h_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Live preview" } }};
    const prev_h = NodeDesc{ .tag = "Text", .classes = "font-bold", .attrs = &prev_h_attrs };

    // Background swatches
    const sw_canvas_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "bg-canvas" } }};
    const sw_surface_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "bg-surface" } }};
    const sw_raised_attrs  = [1]Attr{.{ .name = "text", .value = .{ .literal = "bg-raised" } }};
    const sw_canvas  = NodeDesc{ .tag = "Card", .classes = "p-2 bg-canvas",   .attrs = &sw_canvas_attrs };
    const sw_surface = NodeDesc{ .tag = "Card", .classes = "p-2 bg-surface",  .attrs = &sw_surface_attrs };
    const sw_raised  = NodeDesc{ .tag = "Card", .classes = "p-2 bg-raised",   .attrs = &sw_raised_attrs };
    const sw_children = [3]NodeDesc{ sw_canvas, sw_surface, sw_raised };
    const swatches = NodeDesc{ .tag = "Row", .classes = "gap-2", .children = &sw_children };

    // Text samples
    const t_body_attrs   = [1]Attr{.{ .name = "text", .value = .{ .literal = "text-body \xe2\x80\x94 primary text" } }};
    const t_muted_attrs  = [1]Attr{.{ .name = "text", .value = .{ .literal = "text-muted \xe2\x80\x94 secondary" } }};
    const t_accent_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "text-accent \xe2\x80\x94 accent" } }};
    const t_body   = NodeDesc{ .tag = "Text", .classes = "text-body",   .attrs = &t_body_attrs };
    const t_muted  = NodeDesc{ .tag = "Text", .classes = "text-muted",  .attrs = &t_muted_attrs };
    const t_accent = NodeDesc{ .tag = "Text", .classes = "text-accent", .attrs = &t_accent_attrs };
    const text_samples_children = [3]NodeDesc{ t_body, t_muted, t_accent };
    const text_samples = NodeDesc{ .tag = "Column", .classes = "gap-1", .children = &text_samples_children };

    // Widgets sample row
    const sample_btn_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Button" } }};
    const sample_btn = NodeDesc{ .tag = "Button", .attrs = &sample_btn_attrs };
    const sample_cb_attrs = [1]Attr{.{ .name = "label", .value = .{ .literal = "Checkbox" } }};
    const sample_cb = NodeDesc{ .tag = "Checkbox", .attrs = &sample_cb_attrs };
    const sample_input = NodeDesc{ .tag = "Input" };
    const widgets_children = [3]NodeDesc{ sample_btn, sample_cb, sample_input };
    const widgets_row = NodeDesc{ .tag = "Row", .classes = "gap-3 items-center", .children = &widgets_children };

    const right_inner = [5]NodeDesc{
        prev_h,
        NodeDesc{ .tag = "Text", .classes = "text-sm text-muted", .attrs = &[1]Attr{.{ .name = "text", .value = .{ .literal = "Background tokens:" } }} },
        swatches,
        text_samples,
        widgets_row,
    };
    const right_panel = NodeDesc{ .tag = "Card", .classes = "flex-1 p-4 gap-3", .children = &right_inner };

    // -----------------------------------------------------------------------
    // Two-column layout
    // -----------------------------------------------------------------------
    const cols_children = [2]NodeDesc{ left_panel, right_panel };
    const cols = NodeDesc{ .tag = "Row", .classes = "gap-4", .children = &cols_children };

    const content_children = [3]NodeDesc{ heading, sep, cols };
    const content = NodeDesc{ .tag = "Column", .classes = "flex-1 gap-4 p-6", .children = &content_children };

    const root_children = [2]NodeDesc{ sidebar.buildSidebar(), content };
    const root = NodeDesc{ .tag = "Row", .classes = "w-full h-full", .children = &root_children };

    _ = try scene.instantiate(root, tokens);
    try shared.wireSidebarCallbacks(scene, c.global, tokens, 6); // 6 = Theme button

    // DFS: 0=root,1=sidebar,2-9=btns,10=content,11=heading,12=sep,13=cols,
    //   14=left_panel,
    //   15=scheme_col, 16=ctrl_h, 17=btn_light, 18=btn_dark, 19=btn_hc,
    //   20=fs_group, 21=fs_h, 22=fs_row, 23=fs_lbl, 24=fs_slider, 25=fs_val,
    //   26=sep2, 27=hint,
    //   28=right_panel,...
    try scene.setButtonCallback(17, CallbackFn{ .ptr = &_cb_light, .call = ThemeCb.onClick });
    try scene.setButtonCallback(18, CallbackFn{ .ptr = &_cb_dark,  .call = ThemeCb.onClick });
    try scene.setButtonCallback(19, CallbackFn{ .ptr = &_cb_hc,    .call = ThemeCb.onClick });

    // Bug 8 fix: record slider/readout indices and app_inner for per-frame tick.
    _fs_slider_idx = 24;
    _fs_val_idx    = 25;
    _fs_app_inner  = app_inner;
}
