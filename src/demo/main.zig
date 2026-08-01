//! main.zig — Entry point for the zig-gui Showcase Demo Application.

const std = @import("std");
const app_types = @import("app");

const App = app_types.App;
const AppOptions = app_types.AppOptions;
const Navigator = app_types.Navigator;
const ToastManager = app_types.ToastManager;

const shared = @import("shared/types.zig");
const GlobalState = shared.GlobalState;
const SidebarCb = shared.SidebarCb;
const SidebarCbs = shared.SidebarCbs;

const home_screen = @import("screens/home.zig");
const text_screen = @import("screens/text.zig");
const forms_screen = @import("screens/forms.zig");
const data_screen = @import("screens/data.zig");
const theme_screen = @import("screens/theme.zig");
const notif_screen = @import("screens/notifications.zig");
const layout_screen = @import("screens/layout.zig");
const state_screen = @import("screens/state.zig");
const m12_screen = @import("screens/m12.zig");
const m13_screen = @import("screens/m13.zig");
const dashboard_screen = @import("screens/dashboard.zig");
const ecommerce_screen = @import("screens/ecommerce.zig");
const components_screen = @import("screens/components.zig");
const aiqadam_screen = @import("screens/aiqadam.zig");

/// Combined per-frame tick: runs all screen ticks. Each guards against wrong-screen.
fn combinedTick(scene: *@import("../07/types.zig").Scene) void {
    forms_screen.tick(scene);
    theme_screen.tick(scene);
}

// Module-level toast manager pointer — set in main() so the per-frame tick can reach it.
var _g_toasts: ?*ToastManager = null;

// --click-idx / --click-count support: fire N synthetic button clicks on a given element
// index on the second rendered frame (after nav drains). Used for automated screenshot testing.
var _click_idx: u32 = 0;
var _click_count: u32 = 0;
var _click_fired: bool = false;

// RN16 — --hover-idx support: hold a synthetic hover (ButtonState.hovered = true) on a given
// button element index from frame 2 onward, so a multi-frame screenshot comparison
// (--screenshot-frames 1 vs --screenshot-frames 10) can observe a hover color TRANSITION
// mid-flight rather than only ever seeing the fully-settled start/end state. Reuses the exact
// same "set state once, let the normal per-frame sync/tick loop do the rest" pattern as
// --click-idx above — no new interaction-injection mechanism.
var _hover_idx: u32 = std.math.maxInt(u32);

/// Per-frame app-level tick: update toast expiry, tooltip visibility, and rebuild overlay slots.
fn toastAppTick(ai: *app_types.app_impl.AppInner) void {
    // Synthetic click injection: fire _click_count clicks on _click_idx once, on frame 2+
    // (frame 1 = nav drain; frame 2 = scene stable).
    if (!_click_fired and _click_count > 0 and ai.frame_count >= 2) {
        _click_fired = true;
        const scene = &ai.scene;
        if (_click_idx < scene._button_state.items.len) {
            var n: u32 = 0;
            while (n < _click_count) : (n += 1) {
                if (scene._button_state.items[_click_idx].on_click) |cb| {
                    cb.call(cb.ptr);
                }
            }
            scene.elements.markAllDirty();
        }
    }
    // RN16 — Synthetic hover hold: set once at frame 2, held every frame after (the button's
    // .hovered field is read fresh each frame by AppInner.syncPseudoStates, so re-asserting it
    // isn't even required, but doing so is harmless and keeps this robust to future changes).
    if (_hover_idx != std.math.maxInt(u32) and ai.frame_count >= 2) {
        const scene = &ai.scene;
        if (_hover_idx < scene._button_state.items.len) {
            scene._button_state.items[_hover_idx].hovered = true;
            scene.elements.markAllDirty();
        }
    }
    const fb = ai.platform.framebufferSize();
    const w = @as(f32, @floatFromInt(fb.width));
    const h = @as(f32, @floatFromInt(fb.height));

    if (_g_toasts) |tm| {
        tm.tick(
            ai.frame_time_ms,
            w,
            h,
            ai.tokens,
            ai.font_family.face(false, false),
            &ai.atlas_cpu,
            &ai.overlay,
            ai.gpa,
        ) catch {};
    }

    ai.tooltip_manager.tick(
        ai.frame_time_ms,
        ai.last_cursor_x,
        ai.last_cursor_y,
        w,
        ai.tokens,
        ai.font_family.face(false, false),
        &ai.atlas_cpu,
        &ai.overlay,
        ai.gpa,
    ) catch {};

    // RN11 — Render ecommerce charts into ai.chart_cmds (no-op when screen not active).
    ecommerce_screen.renderCharts(ai) catch {};
}

pub fn main(init: std.process.Init) !void {
    var gpa_impl = std.heap.DebugAllocator(.{}).init;
    defer _ = gpa_impl.deinit();
    const gpa = gpa_impl.allocator();

    // Parse optional screenshot flags: --screenshot-frames N --screenshot-out path --initial-screen name
    const proc_args = try init.minimal.args.toSlice(init.arena.allocator());
    var screenshot_frames: u32 = 0;
    var screenshot_out: []const u8 = "testdata/screenshot_actual.png";
    var initial_screen: []const u8 = "home";
    var dark_mode = false;
    _click_idx = 0;
    _click_count = 0;
    _click_fired = false;
    _hover_idx = std.math.maxInt(u32);
    {
        var i: usize = 1;
        while (i < proc_args.len) : (i += 1) {
            if (std.mem.eql(u8, proc_args[i], "--screenshot-frames") and i + 1 < proc_args.len) {
                i += 1;
                screenshot_frames = std.fmt.parseInt(u32, proc_args[i], 10) catch 3;
            } else if (std.mem.eql(u8, proc_args[i], "--screenshot-out") and i + 1 < proc_args.len) {
                i += 1;
                screenshot_out = proc_args[i];
            } else if (std.mem.eql(u8, proc_args[i], "--initial-screen") and i + 1 < proc_args.len) {
                i += 1;
                initial_screen = proc_args[i];
            } else if (std.mem.eql(u8, proc_args[i], "--click-idx") and i + 1 < proc_args.len) {
                i += 1;
                _click_idx = std.fmt.parseInt(u32, proc_args[i], 10) catch 0;
            } else if (std.mem.eql(u8, proc_args[i], "--click-count") and i + 1 < proc_args.len) {
                i += 1;
                _click_count = std.fmt.parseInt(u32, proc_args[i], 10) catch 0;
            } else if (std.mem.eql(u8, proc_args[i], "--hover-idx") and i + 1 < proc_args.len) {
                i += 1;
                _hover_idx = std.fmt.parseInt(u32, proc_args[i], 10) catch std.math.maxInt(u32);
            } else if (std.mem.eql(u8, proc_args[i], "--dark")) {
                dark_mode = true;
            }
        }
    }

    var app = try App.init(gpa, AppOptions{
        .font_path = "testdata/DejaVuSans.ttf",
        .font_size_px = 14,
        .screenshot_frames = screenshot_frames,
        .screenshot_out = screenshot_out,
        .default_theme_mode = if (dark_mode) .dark else .light,
        .window = .{
            .title = "zig-gui Showcase",
            .width = 1180,
            .height = 1100,
        },
    });
    defer app.deinit();

    // ToastManager needs the overlay layer from AppInner.
    var toasts = ToastManager.init(&app._inner.overlay);
    defer toasts.deinit(gpa);

    // Per-frame tick: update slider readouts on forms and theme screens.
    // Each tick function guards against wrong-screen via kindOfIdx checks.
    app._inner.per_frame_fn = combinedTick;

    // Wire toast expiry/render tick. Runs every frame before overlay flatten.
    _g_toasts = &toasts;
    app._inner.per_frame_app_fn = toastAppTick;
    defer {
        _g_toasts = null;
        app._inner.per_frame_app_fn = null;
    }

    var nav = Navigator.init(gpa);
    defer nav.deinit();

    // -----------------------------------------------------------------------
    // Per-screen context structs — stack-allocated (program lifetime).
    // -----------------------------------------------------------------------
    var home_ctx = home_screen.HomeCtx{ .global = undefined };
    var text_ctx = text_screen.TextCtx{ .global = undefined };
    var forms_ctx = forms_screen.FormsCtx{ .global = undefined };
    var data_ctx = data_screen.DataCtx{ .global = undefined };
    var theme_ctx = theme_screen.ThemeCtx{ .global = undefined };
    var notif_ctx = notif_screen.NotifCtx{ .global = undefined };
    var layout_ctx = layout_screen.LayoutCtx{ .global = undefined };
    var state_ctx = state_screen.StateCtx{ .global = undefined };
    var m12_ctx = m12_screen.M12Ctx{ .global = undefined };
    var m13_ctx = m13_screen.M13Ctx{ .global = undefined };
    var dashboard_ctx = dashboard_screen.DashboardCtx{ .global = undefined };
    var ecommerce_ctx = ecommerce_screen.EcommerceCtx{ .global = undefined };
    var components_ctx = components_screen.ComponentsCtx{ .global = undefined };
    var aiqadam_ctx = aiqadam_screen.AiQadamCtx{ .global = undefined };

    // -----------------------------------------------------------------------
    // GlobalState — wire everything together.
    // -----------------------------------------------------------------------
    var global = GlobalState{
        .nav = &nav,
        .toasts = &toasts,
        .app_inner = &app._inner,
    };
    global.home_ctx = &home_ctx;
    global.text_ctx = &text_ctx;
    global.forms_ctx = &forms_ctx;
    global.data_ctx = &data_ctx;
    global.theme_ctx = &theme_ctx;
    global.notif_ctx = &notif_ctx;
    global.layout_ctx = &layout_ctx;
    global.state_ctx = &state_ctx;
    global.m12_ctx = &m12_ctx;
    global.m13_ctx = &m13_ctx;
    global.dashboard_ctx = &dashboard_ctx;
    global.ecommerce_ctx = &ecommerce_ctx;
    global.components_ctx = &components_ctx;
    global.aiqadam_ctx = &aiqadam_ctx;

    home_ctx.global = &global;
    text_ctx.global = &global;
    forms_ctx.global = &global;
    data_ctx.global = &global;
    theme_ctx.global = &global;
    notif_ctx.global = &global;
    layout_ctx.global = &global;
    state_ctx.global = &global;
    m12_ctx.global = &global;
    m13_ctx.global = &global;
    dashboard_ctx.global = &global;
    ecommerce_ctx.global = &global;
    components_ctx.global = &global;
    aiqadam_ctx.global = &global;

    global.sidebar_cbs = SidebarCbs{
        .home = SidebarCb{ .global = &global, .screen_name = "home" },
        .text = SidebarCb{ .global = &global, .screen_name = "text" },
        .forms = SidebarCb{ .global = &global, .screen_name = "forms" },
        .data = SidebarCb{ .global = &global, .screen_name = "data" },
        .theme = SidebarCb{ .global = &global, .screen_name = "theme" },
        .notifications = SidebarCb{ .global = &global, .screen_name = "notifications" },
        .layout = SidebarCb{ .global = &global, .screen_name = "layout" },
        .state = SidebarCb{ .global = &global, .screen_name = "state" },
        .m12 = SidebarCb{ .global = &global, .screen_name = "m12" },
        .m13 = SidebarCb{ .global = &global, .screen_name = "m13" },
        .dashboard = SidebarCb{ .global = &global, .screen_name = "dashboard" },
        .ecommerce = SidebarCb{ .global = &global, .screen_name = "ecommerce" },
        .components = SidebarCb{ .global = &global, .screen_name = "components" },
        .aiqadam = SidebarCb{ .global = &global, .screen_name = "aiqadam" },
    };

    // -----------------------------------------------------------------------
    // Register screens.
    // -----------------------------------------------------------------------
    try nav.register("home", home_screen.build);
    try nav.register("text", text_screen.build);
    try nav.register("forms", forms_screen.build);
    try nav.register("data", data_screen.build);
    try nav.register("theme", theme_screen.build);
    try nav.register("notifications", notif_screen.build);
    try nav.register("layout", layout_screen.build);
    try nav.register("state", state_screen.build);
    try nav.register("m12", m12_screen.build);
    try nav.register("m13", m13_screen.build);
    try nav.register("dashboard", dashboard_screen.build);
    try nav.register("ecommerce", ecommerce_screen.build);
    try nav.register("components", components_screen.build);
    try nav.register("aiqadam", aiqadam_screen.build);

    // Request initial screen — drainPending fires on the first frame.
    // --initial-screen <name> selects which screen to start on (default: home).
    if (std.mem.eql(u8, initial_screen, "forms")) {
        nav.requestPush("forms", &forms_ctx);
    } else if (std.mem.eql(u8, initial_screen, "text")) {
        nav.requestPush("text", &text_ctx);
    } else if (std.mem.eql(u8, initial_screen, "data")) {
        nav.requestPush("data", &data_ctx);
    } else if (std.mem.eql(u8, initial_screen, "theme")) {
        nav.requestPush("theme", &theme_ctx);
    } else if (std.mem.eql(u8, initial_screen, "notifications")) {
        nav.requestPush("notifications", &notif_ctx);
    } else if (std.mem.eql(u8, initial_screen, "layout")) {
        nav.requestPush("layout", &layout_ctx);
    } else if (std.mem.eql(u8, initial_screen, "state")) {
        nav.requestPush("state", &state_ctx);
    } else if (std.mem.eql(u8, initial_screen, "m12")) {
        nav.requestPush("m12", &m12_ctx);
    } else if (std.mem.eql(u8, initial_screen, "m13")) {
        nav.requestPush("m13", &m13_ctx);
    } else if (std.mem.eql(u8, initial_screen, "dashboard")) {
        nav.requestPush("dashboard", &dashboard_ctx);
    } else if (std.mem.eql(u8, initial_screen, "ecommerce")) {
        nav.requestPush("ecommerce", &ecommerce_ctx);
    } else if (std.mem.eql(u8, initial_screen, "components")) {
        nav.requestPush("components", &components_ctx);
    } else if (std.mem.eql(u8, initial_screen, "aiqadam")) {
        nav.requestPush("aiqadam", &aiqadam_ctx);
    } else {
        nav.requestPush("home", &home_ctx);
    }

    app.runWithNav(&nav);
}
