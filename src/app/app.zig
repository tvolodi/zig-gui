//! App implementation (R10 / R11 / R12 / R13).
//!
//! AppInner owns all subsystems and drives the main frame loop.

const std = @import("std");

// NOTE: app.zig does NOT import types.zig (types.zig imports us; circular import is forbidden).
// AppOptions is defined here directly; types.zig re-exports it.
const events_mod = @import("events.zig");
const binding_mod = @import("binding.zig");
const overlay_mod = @import("overlay.zig");
const image_atlas_mod = @import("image_atlas.zig");
const font_family_mod = @import("font_family.zig");
const navigator_mod = @import("navigator.zig");
const debug_overlay_mod = @import("debug_overlay.zig");
const perf_hud_mod = @import("perf_hud.zig");
const markup_mod = @import("../06/types.zig");
// M10 modules — imported via named module imports (build.zig registers each file
// as exactly one named module to avoid the "file exists in multiple modules" error).
pub const persistent_settings_mod = @import("persistent_settings.zig");
pub const file_logger_mod = @import("file_logger.zig");
pub const logger_mod = @import("logger.zig");
pub const budgeted_arena_mod = @import("budgeted_arena.zig");
pub const window_state_mod = @import("window_state.zig");
pub const error_boundary_mod = @import("error_boundary.zig");
pub const startup_error_mod = @import("startup_error.zig");
pub const Navigator = navigator_mod.Navigator;

// R56: hot-reload build option (comptime gate).
// When build_options is not available (not a hot-reload build), default to false.
const hot_reload: bool = if (@hasDecl(@import("root"), "build_options"))
    @import("build_options").hot_reload
else
    false;

// R56: FileWatcher is only imported when hot_reload is true.
const file_watcher_mod = if (hot_reload) @import("file_watcher.zig") else void;
const FileWatcher = if (hot_reload) file_watcher_mod.FileWatcher else void;
const WatchEntry = if (hot_reload) file_watcher_mod.WatchEntry else void;
const ParseDiagnostic = if (hot_reload) @import("../06/types.zig").ParseDiagnostic else void;

const mod01 = @import("../01/types.zig");
const mod02 = @import("../02/types.zig");
const mod03 = @import("../03/types.zig");
const mod04 = @import("../04/types.zig");
const mod05 = @import("../05/types.zig");
const mod07 = @import("../07/types.zig");
const mod09 = @import("../09/types.zig");
const store_mod = mod03;

pub const Event = mod01.InputEvent;
pub const EventQueue = events_mod.EventQueue;

// ---------------------------------------------------------------------------
// M11 — RB1: Drag-and-drop types
// ---------------------------------------------------------------------------

/// Transient drag-and-drop state stored on AppInner (not in Scene — one drag at a time).
pub const DragState = struct {
    /// Index of the element that is the drag source. NONE = no drag in progress.
    source_idx: u32 = mod07.NONE,
    /// True once the deadzone (4 px) has been exceeded.
    active: bool = false,
    origin_x: f32 = 0,
    origin_y: f32 = 0,
    current_x: f32 = 0,
    current_y: f32 = 0,
    /// App-defined opaque payload set by on_drag_start; passed to subsequent callbacks.
    payload: u64 = 0,
};

const DRAG_DEADZONE_PX: f32 = 4;

// ---------------------------------------------------------------------------
// M11 — RB3: Double-click detection types
// ---------------------------------------------------------------------------

/// Transient double-click detection state stored on AppInner.
pub const DoubleClickState = struct {
    last_press_ms: u64 = 0,
    last_x: f32 = 0,
    last_y: f32 = 0,
    last_hit: u32 = mod07.NONE,
};

const DOUBLE_CLICK_DEADZONE_PX: f32 = 4;

// ---------------------------------------------------------------------------
// M11 — RB4: Keyboard shortcut table
// ---------------------------------------------------------------------------

pub const ShortcutError = error{TooManyShortcuts};
pub const MAX_SHORTCUTS: usize = 64;

pub const Shortcut = struct {
    key: mod01.Key = .other,
    mods: mod01.Modifiers = .{},
    cb: mod07.CallbackFn = undefined,
    active: bool = false,
};

pub const ShortcutTable = struct {
    entries: [MAX_SHORTCUTS]Shortcut = [_]Shortcut{.{}} ** MAX_SHORTCUTS,
    count: usize = 0,

    pub fn register(self: *ShortcutTable, key: mod01.Key, mods: mod01.Modifiers, cb: mod07.CallbackFn) ShortcutError!void {
        // Replace existing entry for the same key+mods if present.
        for (self.entries[0..self.count]) |*e| {
            if (e.key == key and std.meta.eql(e.mods, mods)) {
                e.cb = cb;
                return;
            }
        }
        if (self.count >= MAX_SHORTCUTS) return ShortcutError.TooManyShortcuts;
        self.entries[self.count] = .{ .key = key, .mods = mods, .cb = cb, .active = true };
        self.count += 1;
    }

    pub fn unregister(self: *ShortcutTable, key: mod01.Key, mods: mod01.Modifiers) void {
        var i: usize = 0;
        while (i < self.count) : (i += 1) {
            if (self.entries[i].key == key and std.meta.eql(self.entries[i].mods, mods)) {
                // Compact: move last entry into this slot.
                self.count -= 1;
                if (i < self.count) self.entries[i] = self.entries[self.count];
                self.entries[self.count] = .{};
                return;
            }
        }
    }

    pub fn lookup(self: *const ShortcutTable, key: mod01.Key, mods: mod01.Modifiers) ?mod07.CallbackFn {
        for (self.entries[0..self.count]) |e| {
            if (e.key == key and std.meta.eql(e.mods, mods)) return e.cb;
        }
        return null;
    }
};

// ---------------------------------------------------------------------------
// M11 — RB0: Cursor shape helper
// ---------------------------------------------------------------------------

fn defaultCursorFor(kind: mod07.WidgetKind, disabled: bool) mod01.CursorShape {
    if (disabled) return .not_allowed;
    return switch (kind) {
        .button, .checkbox, .radio, .dropdown,
        .slider, .tabs, .accordion, .date_picker => .hand,
        .input, .textarea                         => .text_beam,
        else                                      => .arrow,
    };
}

// ---------------------------------------------------------------------------
// M11 — RB1/RB3/RB5: General hit-test (all live elements, reverse order)
// ---------------------------------------------------------------------------

/// Hit-test ALL non-hidden elements in reverse index order (highest index = topmost).
/// Returns the index of the topmost element whose computed rect contains (x, y), or NONE.
fn hitTest(scene: *const mod07.Scene, x: f32, y: f32) u32 {
    const count = scene.elements.layout.items.len;
    if (count == 0) return mod07.NONE;
    // M12 RC4 — z-index hit-test: when we find a hit, check if any same-parent sibling
    // has a higher z_index. If so, that sibling wins (if it also contains the point).
    var i: u32 = @intCast(count);
    while (i > 0) {
        i -= 1;
        if (i < scene._hidden.items.len and scene._hidden.items[i]) continue;
        const node = &scene.elements.layout.items[i];
        const raw_rect = node.computed;
        if (raw_rect.w == 0 or raw_rect.h == 0) continue;
        // M12 RC1 — adjust hit rect y for sticky elements.
        const sticky_dy: f32 = if (i < scene._sticky_offset_y.items.len) scene._sticky_offset_y.items[i] else 0;
        const rect = store_mod.Rect{
            .x = raw_rect.x,
            .y = raw_rect.y + sticky_dy,
            .w = raw_rect.w,
            .h = raw_rect.h,
        };
        if (x >= rect.x and x < rect.x + rect.w and y >= rect.y and y < rect.y + rect.h) {
            // M12 RC4 — check siblings with higher z_index.
            const parent_idx = scene.elements.parent.items[i];
            if (parent_idx != store_mod.NONE) {
                const my_z = node.z_index;
                var sib_cursor = scene.elements.first_child.items[parent_idx];
                while (sib_cursor != store_mod.NONE) {
                    if (sib_cursor != i) {
                        const sib_node = &scene.elements.layout.items[sib_cursor];
                        if (sib_node.z_index > my_z) {
                            const sib_sticky_dy: f32 = if (sib_cursor < scene._sticky_offset_y.items.len) scene._sticky_offset_y.items[sib_cursor] else 0;
                            const sib_rect = store_mod.Rect{
                                .x = sib_node.computed.x,
                                .y = sib_node.computed.y + sib_sticky_dy,
                                .w = sib_node.computed.w,
                                .h = sib_node.computed.h,
                            };
                            if (x >= sib_rect.x and x < sib_rect.x + sib_rect.w and
                                y >= sib_rect.y and y < sib_rect.y + sib_rect.h)
                            {
                                return sib_cursor;
                            }
                        }
                    }
                    sib_cursor = scene.elements.next_sibling.items[sib_cursor];
                }
            }
            return i;
        }
    }
    return mod07.NONE;
}

/// Application startup options (R10).
pub const AppOptions = struct {
    window: mod01.WindowOptions = .{},
    /// Path to a .ttf file; read with std.fs.cwd().readFileAlloc.
    font_path: []const u8,
    font_size_px: f32 = 16,
    /// R60: optional bold and italic font face paths.
    bold_font_path: ?[]const u8 = null,
    italic_font_path: ?[]const u8 = null,

    // RA2 — Release logging.
    /// Optional path for the file log. When null, no file log is written (stderr only).
    /// Parent directories are created on first write if they do not exist.
    log_path: ?[]const u8 = null,
    /// Maximum file size before rolling (truncating). Default 1 MiB.
    log_max_bytes: usize = 1024 * 1024,

    // RA1 — Memory budget enforcement.
    /// Memory budget for the per-screen arena allocator, in bytes.
    /// 0 means unlimited (default). When set, Scene.reset() calls BudgetedArena.reset().
    arena_budget_bytes: usize = 0,

    // RA0 — Error boundary.
    /// Enable error boundary. When true, ScreenFn errors display a fallback screen.
    enable_error_boundary: bool = false,

    // M11 — RB3: Double-click timing threshold.
    /// Maximum interval (ms) between two clicks to be considered a double-click. Default 250 ms.
    double_click_threshold_ms: u64 = 250,

    // Visual testing — headless screenshot mode.
    /// When > 0, render this many frames, write a PNG screenshot, then exit.
    /// Used by `zig build visual-check`. Default 0 = normal interactive mode.
    screenshot_frames: u32 = 0,
    /// Output path for the screenshot PNG (only used when screenshot_frames > 0).
    screenshot_out: []const u8 = "testdata/screenshot_actual.png",

    // RA4 — Window state persistence.
    /// Enable automatic window state persistence.
    /// When true, AppInner.init restores the saved window state (if any) from
    /// persistent_settings (which must also be provided). AppInner.deinit saves and flushes.
    persist_window_state: bool = false,
    /// Prefix for window state keys in PersistentSettings. Default "win_".
    /// Must be <= 28 bytes (prefix + 3-char key suffix <= 31-byte PersistentSettings key limit).
    window_state_key_prefix: []const u8 = "win_",
    /// Optional reference to a PersistentSettings for window-state persistence.
    /// The caller owns the PersistentSettings and must keep it alive for the duration of App.run.
    persistent_settings: ?*persistent_settings_mod.PersistentSettings = null, // RA4
};

// Convenience aliases for the module types we need.
const Platform = mod01.Platform;
const VulkanBackend = mod01.VulkanBackend;
const Extent2D = mod01.Extent2D;
const Color = mod01.Color;
const Font = mod02.Font;
const GlyphAtlas = mod02.GlyphAtlas;
const Scene = mod07.Scene;
const GpuAtlas = mod09.GpuAtlas;
const GpuImageAtlas = mod09.GpuImageAtlas;
const DrawCommand = mod01.DrawCommand;
const Constraints = mod04.Constraints;
const BindingSet = binding_mod.BindingSet;
const OverlayLayer = overlay_mod.OverlayLayer;
const ImageAtlas = image_atlas_mod.ImageAtlas;
const Tokens = mod05.Tokens;
const PseudoState = mod07.PseudoState;
const FontFamily = font_family_mod.FontFamily;
const DebugOverlay = debug_overlay_mod.DebugOverlay;
const PerfHud = perf_hud_mod.PerfHud;
const FrameCounters = perf_hud_mod.FrameCounters;

// Scratch buffer size for layout engine (1 MiB).
const SCRATCH_SIZE: usize = 1024 * 1024;

/// Framebuffer resize callback (R12).  Writes new_size into pending_resize via AppInner pointer.
/// callconv(.c) not required here since this is called through our own function pointer, not
/// directly from C. But we store it as a *const fn(*anyopaque, Extent2D) void.
fn framebufferSizeCallback(user_data: *anyopaque, size: Extent2D) void {
    const pending: *?Extent2D = @ptrCast(@alignCast(user_data));
    pending.* = size;
}

/// Color equality helper for R93 theme live-swap style merging.
fn colorEq(a: mod05.Color, b: mod05.Color) bool {
    return a.r == b.r and a.g == b.g and a.b == b.b and a.a == b.a;
}

/// Returns true when the scene contains any widget that requires continuous redraws
/// (spinners, indeterminate progress bars). Used to decide between waitEvents/pollEvents.
fn hasAnimatedElements(scene: *const Scene, tooltip: *const @import("tooltip.zig").TooltipManager) bool {
    if (tooltip.isPending()) return true;
    var i: u32 = 0;
    while (i < scene._kind.items.len) : (i += 1) {
        if (i < scene._hidden.items.len and scene._hidden.items[i]) continue;
        switch (scene._kind.items[i]) {
            .spinner => return true,
            .progress_bar => {
                if (i < scene._progress_state.items.len and
                    scene._progress_state.items[i].indeterminate) return true;
            },
            else => {},
        }
    }
    return false;
}

/// Public implementation struct.  Exposed as `App._inner` through types.zig.
pub const AppInner = struct {
    gpa: std.mem.Allocator,

    // Subsystems — init order matches R10 exactly.
    platform: Platform,
    backend: VulkanBackend,
    /// R60: replaced font: Font with font_family: FontFamily.
    font_family: FontFamily,
    atlas_cpu: GlyphAtlas,
    atlas_gpu: GpuAtlas,
    scene: Scene,

    // Pre-allocated draw-list (no per-frame heap alloc for the buffer itself).
    draw_list: std.ArrayList(DrawCommand),

    // Layout viewport constraints (updated on resize).
    viewport_constraints: Constraints,

    // Atlas generation tracking (R10).
    atlas_generation_seen: u32,

    // Pending resize from GLFW framebuffer callback (R12).
    pending_resize: ?Extent2D,

    // Event queue (R11).
    event_queue: EventQueue,

    // Scratch buffer for layout solve.
    scratch: []u8,

    // Data bindings — static screen signal→element connections (M2-04).
    bindings: BindingSet,

    // Mouse tracking for press/release hit-testing (R31, R34).
    left_mouse_down: bool = false,
    last_cursor_x: f32 = 0,
    last_cursor_y: f32 = 0,

    // R62 — Text selection drag state.
    dragging_text_idx: ?u32 = null,

    // Bug 3 fix — Slider drag state.
    dragging_slider_idx: ?u32 = null,

    // Scrollbar thumb drag state.
    dragging_scrollbar_idx: ?u32 = null,

    // R41 — Overlay layer (second draw pass).
    overlay: OverlayLayer,

    // R43 — Image atlas (CPU + GPU).
    image_atlas: ImageAtlas,
    image_atlas_generation_seen: u32,
    gpu_image_atlas: GpuImageAtlas,

    // Theme tokens — needed for pseudo-state resolution in buildDrawList (R40).
    tokens: Tokens,

    // R56 — Optional hook called after every successful hot-reload.
    // The application sets this to re-register bindings after scene.reset().
    rebind_fn: ?*const fn (*AppInner) anyerror!void = null,

    // Per-frame tick hook: called each dirty frame in refreshBindings, after BindingSet.refresh.
    // Used by screens that need to derive display text from live widget state (e.g. slider readout).
    per_frame_fn: ?*const fn (*Scene) void = null,

    // Per-frame app-level tick hook: called every rendered frame just before the overlay is
    // flattened. Has access to all AppInner fields. Used for overlay producers (e.g. ToastManager).
    per_frame_app_fn: ?*const fn (*AppInner) void = null,

    // R73 — Frame counter and timestamp for animation.
    frame_count: u64 = 0,
    frame_time_ms: u64 = 0,

    // R56 — File watcher (only present when hot_reload = true).
    watcher: if (hot_reload) FileWatcher else void = if (hot_reload) undefined else {},

    // R7C — Tooltip manager.
    tooltip_manager: @import("tooltip.zig").TooltipManager = .{},

    // R7D — Context-menu manager.
    context_menu_manager: @import("context_menu.zig").ContextMenuManager = .{},

    // R90 — Debug overlay (F1 toggle).
    debug_overlay: DebugOverlay = DebugOverlay.init(),

    // R92 — Performance HUD (shown when debug overlay is enabled).
    perf_hud: PerfHud = PerfHud.init(),

    // R92 — Frame start timestamp in nanoseconds (set before beginFrame).
    _frame_start_ns: i128 = 0,

    // R93 / R94 — Current palette and mode for live-swap and font-scale rebuilds.
    _current_palette: mod05.Palette,
    _current_mode: mod05.Mode,

    // Demo F2 theme cycling index (0=light, 1=dark, 2=hc-light).
    _theme_idx: u2 = 0,

    // R94 — Current font scale factor (1.0 = default).
    _font_scale: f32 = 1.0,

    // RA2 — File logger (null when opts.log_path == null).
    file_logger: ?file_logger_mod.FileLogger = null,

    // RA1 — Budgeted arena (null when opts.arena_budget_bytes == 0).
    budget_arena: ?budgeted_arena_mod.BudgetedArena = null,

    // RA0 — Error boundary (null when opts.enable_error_boundary == false).
    error_boundary: ?error_boundary_mod.ErrorBoundary = null,

    // RA4 — Window state manager (null when opts.persist_window_state == false).
    window_state_mgr: ?window_state_mod.WindowStateManager = null,

    // Visual testing — screenshot mode (0 = disabled).
    _screenshot_frames: u32 = 0,
    _screenshot_out: []const u8 = "testdata/screenshot_actual.png",

    // M11 — RB1: Intra-window drag-and-drop state.
    drag: DragState = .{},

    // M11 — RB3: Double-click detection state and configurable threshold.
    double_click: DoubleClickState = .{},
    double_click_threshold_ms: u64 = 250,

    // M11 — RB4: Global keyboard shortcut table.
    shortcuts: ShortcutTable = .{},

    // -----------------------------------------------------------------------
    // Init
    // -----------------------------------------------------------------------

    pub fn init(gpa: std.mem.Allocator, opts: AppOptions) !AppInner {
        // Step 1: Platform.
        var platform = try Platform.init(gpa, opts.window);
        errdefer platform.deinit();

        // Step 2: VulkanBackend.
        var backend = try VulkanBackend.init(gpa, &platform);
        errdefer backend.deinit();

        // Step 3: initQuadPipeline.
        try backend.initQuadPipeline(gpa);
        errdefer backend.deinitQuadPipeline();

        // Step 4: Load font bytes.
        const _init_io = std.Io.Threaded.global_single_threaded.io();
        const font_bytes = std.Io.Dir.readFileAlloc(std.Io.Dir.cwd(), _init_io, opts.font_path, gpa, .limited(16 * 1024 * 1024)) catch |err| {
            std.log.err("Failed to read font file '{s}': {}", .{ opts.font_path, err });
            return err;
        };
        defer gpa.free(font_bytes);

        // Step 5: FontFamily.init — load regular face; bold/italic are optional (R60).
        const bold_bytes: ?[]const u8 = if (opts.bold_font_path) |bp|
            std.Io.Dir.readFileAlloc(std.Io.Dir.cwd(), _init_io, bp, gpa, .limited(16 * 1024 * 1024)) catch null
        else
            null;
        defer if (bold_bytes) |b| gpa.free(b);
        const italic_bytes: ?[]const u8 = if (opts.italic_font_path) |ip|
            std.Io.Dir.readFileAlloc(std.Io.Dir.cwd(), _init_io, ip, gpa, .limited(16 * 1024 * 1024)) catch null
        else
            null;
        defer if (italic_bytes) |it| gpa.free(it);
        var font_family = try FontFamily.init(gpa, font_bytes, bold_bytes, italic_bytes);
        errdefer font_family.deinit();

        // Step 6: GlyphAtlas.init.
        var atlas_cpu = try GlyphAtlas.init(gpa, 1024, 1024);
        errdefer atlas_cpu.deinit();

        // Step 7: GpuAtlas.upload (initially empty atlas).
        const vk = try backend._impl_vulkan();
        var atlas_gpu = try GpuAtlas.upload(
            gpa,
            vk.device,
            vk.phys_device,
            vk.cmd_pool,
            vk.graphics_queue,
            &atlas_cpu,
        );
        errdefer atlas_gpu.deinit(vk.device);

        // Step 8: Scene.init.
        var scene = Scene.init(gpa);
        errdefer scene.deinit();

        // Allocate scratch buffer.
        const scratch = try gpa.alloc(u8, SCRATCH_SIZE);
        errdefer gpa.free(scratch);

        // Pre-allocate draw list.
        const draw_list = std.ArrayList(DrawCommand).empty;

        // Initial viewport constraints from the framebuffer size.
        const fb = platform.framebufferSize();
        const viewport_constraints = Constraints{
            .min_w = 0,
            .max_w = @floatFromInt(fb.width),
            .min_h = 0,
            .max_h = @floatFromInt(fb.height),
        };

        // Build default tokens (light theme from default palette).
        const default_tokens = mod05.Tokens.light(mod05.Palette.default());

        // Initialize ImageAtlas (CPU side).
        var image_atlas = try ImageAtlas.init(gpa);
        errdefer image_atlas.deinit();

        var self = AppInner{
            .gpa = gpa,
            .platform = platform,
            .backend = backend,
            .font_family = font_family,
            .atlas_cpu = atlas_cpu,
            .atlas_gpu = atlas_gpu,
            .scene = scene,
            .draw_list = draw_list,
            .viewport_constraints = viewport_constraints,
            .atlas_generation_seen = atlas_cpu.generation,
            .pending_resize = null,
            .event_queue = EventQueue.init(gpa),
            .scratch = scratch,
            .bindings = BindingSet.init(),
            .left_mouse_down = false,
            .last_cursor_x = 0,
            .last_cursor_y = 0,
            .overlay = OverlayLayer.init(gpa),
            .image_atlas = image_atlas,
            .image_atlas_generation_seen = 0,
            .gpu_image_atlas = GpuImageAtlas{},
            .tokens = default_tokens,
            .watcher = if (hot_reload) FileWatcher.init(gpa) else {},
            ._current_palette = mod05.Palette.default(),
            ._current_mode = .light,
        };

        // Register GLFW event queue (R11).
        // setEventQueue stores the push function pointer so module 01 callbacks can call it
        // without an upward import.
        self.platform.setEventQueue(
            @ptrCast(&self.event_queue),
            EventQueue.pushThunk,
        );

        // Register framebuffer resize callback (R12).
        // user_data points directly to self.pending_resize so the callback can write to it.
        self.platform.setFramebufferSizeCallback(
            @ptrCast(&self.pending_resize),
            framebufferSizeCallback,
        );

        // RA2: Initialise file logger when log_path is provided.
        if (opts.log_path) |log_path| {
            if (file_logger_mod.FileLogger.init(gpa, log_path, opts.log_max_bytes)) |logger| {
                self.file_logger = logger;
                logger_mod.g_logger = &self.file_logger.?;
            } else |log_err| {
                std.log.warn("Failed to open log file '{s}': {}", .{ log_path, log_err });
            }
        }

        // RA1: Initialise budgeted arena when arena_budget_bytes > 0.
        // Note: Scene is already initialised above with gpa; budget_arena is stored for
        // future use (e.g., by new scenes or reset calls). Full wiring requires post-init
        // scene replacement which is not done here to avoid disrupting the init sequence.
        if (opts.arena_budget_bytes > 0) {
            self.budget_arena = budgeted_arena_mod.BudgetedArena.init(gpa, opts.arena_budget_bytes);
        }

        // RA0: Initialise error boundary when enable_error_boundary is true.
        if (opts.enable_error_boundary) {
            self.error_boundary = error_boundary_mod.ErrorBoundary{};
        }

        // RA4: Initialise window state manager when persist_window_state is true.
        if (opts.persist_window_state) {
            if (opts.persistent_settings) |ps| {
                var wsm = window_state_mod.WindowStateManager.init(ps, opts.window_state_key_prefix);
                if (wsm.load()) |saved_state| {
                    window_state_mod.applyToPlatform(saved_state, &self.platform);
                }
                self.window_state_mgr = wsm;
            } else {
                // persistent_settings is null but persist_window_state is true.
                std.log.err("persist_window_state=true requires persistent_settings to be set", .{});
                return error.MissingPersistentSettings;
            }
        }

        self._screenshot_frames = opts.screenshot_frames;
        self._screenshot_out = opts.screenshot_out;
        self.double_click_threshold_ms = opts.double_click_threshold_ms;

        return self;
    }

    // -----------------------------------------------------------------------
    // Run (frame loop)
    // -----------------------------------------------------------------------

    pub fn run(self: *AppInner) void {
        // Re-register event queue and resize callback with the stable self pointer.
        // (AppInner may have been value-copied after init; self is the final location.)
        self.platform.setEventQueue(@ptrCast(&self.event_queue), EventQueue.pushThunk);
        self.platform.setFramebufferSizeCallback(@ptrCast(&self.pending_resize), framebufferSizeCallback);
        while (!self.platform.shouldClose()) {
            // R12: zero-size guard (minimised window).
            const fb = self.platform.framebufferSize();
            if (fb.width == 0 or fb.height == 0) {
                self.platform.pollEvents();
                continue;
            }

            // M2-02 / R21: Collect OS events.
            self.platform.pollEvents();
            {
                const evs = self.event_queue.drain();
                defer self.event_queue.clear();
                self.dispatchEvents(evs);
            }

            // R12: a pending resize must force a redraw even when no scene element is dirty.
            if (self.pending_resize != null) self.scene.elements.markAllDirty();

            // M2-02: Skip GPU work when nothing has changed.
            if (!self.scene.elements.hasDirty()) {
                if (hasAnimatedElements(&self.scene, &self.tooltip_manager)) {
                    // Tooltip pending or animated widget: keep rendering so tick() fires.
                    // Force a dirty bit so the render path runs this iteration.
                    self.scene.elements.markAllDirty();
                } else {
                    self.platform.waitEvents(); // yield until the OS wakes us
                    continue;
                }
            }

            // R56: Poll watched .ui files for changes (hot-reload only).
            if (comptime hot_reload) {
                self.watcher.poll();
                for (self.watcher.drainChanged()) |entry_idx| {
                    const entry = &self.watcher.entries.items[entry_idx];
                    self.reloadFile(entry.path) catch |err| {
                        std.log.err("hot-reload: {}", .{err});
                    };
                }
            }

            // M2-04: Copy current signal values into Scene arrays before layout.
            self.refreshBindings();

            // R12: apply pending resize before beginFrame.
            if (self.pending_resize) |new_size| {
                self.backend.onResize(new_size);
                // Update stored viewport constraints so layout uses the new size.
                self.viewport_constraints = Constraints{
                    .min_w = 0,
                    .max_w = @floatFromInt(new_size.width),
                    .min_h = 0,
                    .max_h = @floatFromInt(new_size.height),
                };
                self.pending_resize = null;
            }

            // Begin frame — returns false when swapchain out-of-date (skip frame).
            if (!self.backend.beginFrame()) continue;

            // R92: record frame start time.
            const _t_io1 = std.Io.Threaded.global_single_threaded.io();
            self._frame_start_ns = @as(i128, std.Io.Clock.real.now(_t_io1).nanoseconds);

            // R73: Advance animation frame counter.
            self.frame_count +%= 1;
            self.frame_time_ms = @bitCast(@as(i64, @truncate(@divFloor(std.Io.Clock.real.now(_t_io1).nanoseconds, 1_000_000))));
            self.scene.frame_count = self.frame_count;
            self.scene.frame_time_ms = self.frame_time_ms;

            // Measure text (module 07).
            self.scene.font_family = &self.font_family;
            self.scene.measurePass(self.font_family.face(false, false), &self.atlas_cpu) catch {};

            // Re-upload GPU atlas if the CPU atlas changed (R10).
            if (self.atlas_cpu.generation != self.atlas_generation_seen) {
                const vk = self.backend._impl_vulkan() catch {
                    _ = self.backend.endFrame;
                    self.backend.endFrame();
                    continue;
                };
                self.atlas_gpu.deinit(vk.device);
                self.atlas_gpu = GpuAtlas.upload(
                    self.gpa,
                    vk.device,
                    vk.phys_device,
                    vk.cmd_pool,
                    vk.graphics_queue,
                    &self.atlas_cpu,
                ) catch {
                    self.backend.endFrame();
                    continue;
                };
                self.atlas_generation_seen = self.atlas_cpu.generation;
            }

            // Layout solve (module 04).
            const s = self.scene.store();
            if (s.live > 0) {
                // Find root element (first valid element with no parent).
                var idx: u32 = 0;
                while (idx < s.gen.items.len) : (idx += 1) {
                    const id = mod04.ElementId{ .index = idx, .gen = s.gen.items[idx] };
                    if (!s.isValid(id)) continue;
                    if (s.parentOf(id) == null) {
                        mod04.solve(s, id, self.viewport_constraints, self.scratch);
                        break;
                    }
                }
            }

            // Update scroll container dimensions from post-layout computed sizes.
            self.updateScrollDimensions();

            // Build draw list (module 09).
            // Fire queued callbacks after layout, before render (INV-3.3).
            self.scene.fireQueuedCallbacks();
            self.scene.font_family = &self.font_family;
            self.scene.measurePass(self.font_family.face(false, false), &self.atlas_cpu) catch {};

            // R40: Sync PseudoState from widget state before building draw list.
            self.syncPseudoStates();

            // buildDrawList returns a caller-owned slice; we use it and free it.
            const main_cmds = mod09.buildDrawList(
                self.gpa,
                &self.scene,
                &self.atlas_cpu,
                &self.image_atlas,
                self.font_family.face(false, false),
                self.tokens,
            ) catch blk: {
                break :blk @as([]DrawCommand, &[_]DrawCommand{});
            };
            defer if (main_cmds.len > 0) self.gpa.free(main_cmds);

            // Fire per-frame app-level tick (e.g. toast expiry + overlay rebuild).
            if (self.per_frame_app_fn) |f| f(self);

            // R41: Flatten overlay slots and concatenate with main commands.
            const overlay_cmds = self.overlay.flatten(self.gpa) catch &[_]DrawCommand{};
            defer if (overlay_cmds.len > 0) self.gpa.free(overlay_cmds);

            const all_cmds = blk: {
                if (overlay_cmds.len == 0) break :blk main_cmds;
                const combined = self.gpa.alloc(DrawCommand, main_cmds.len + overlay_cmds.len) catch main_cmds;
                if (combined.len == main_cmds.len + overlay_cmds.len) {
                    @memcpy(combined[0..main_cmds.len], main_cmds);
                    @memcpy(combined[main_cmds.len..], overlay_cmds);
                }
                break :blk combined;
            };
            defer if (all_cmds.ptr != main_cmds.ptr and all_cmds.len > 0) self.gpa.free(all_cmds);

            // R90 / R92: Debug overlay and perf HUD draw lists.
            self.debug_overlay.updateHover(&self.scene, self.last_cursor_x, self.last_cursor_y);
            const debug_cmds = self.debug_overlay.buildDebugDrawList(
                self.gpa,
                &self.scene,
                self.tokens,
                self.font_family.face(false, false),
                &self.atlas_cpu,
            ) catch &[_]DrawCommand{};
            defer if (debug_cmds.len > 0) self.gpa.free(debug_cmds);

            const fb2 = self.platform.framebufferSize();
            const hud_cmds = self.perf_hud.buildHudDrawList(
                self.gpa,
                @as(f32, @floatFromInt(fb2.width)),
                self.tokens,
                self.font_family.face(false, false),
                &self.atlas_cpu,
            ) catch &[_]DrawCommand{};
            defer if (hud_cmds.len > 0) self.gpa.free(hud_cmds);

            const all_cmds2: []DrawCommand = blk: {
                const extra = debug_cmds.len + hud_cmds.len;
                if (extra == 0) break :blk all_cmds;
                const combined2 = self.gpa.alloc(DrawCommand, all_cmds.len + extra) catch break :blk all_cmds;
                @memcpy(combined2[0..all_cmds.len], all_cmds);
                @memcpy(combined2[all_cmds.len..][0..debug_cmds.len], debug_cmds);
                @memcpy(combined2[all_cmds.len + debug_cmds.len ..], hud_cmds);
                break :blk combined2;
            };
            defer if (all_cmds2.ptr != all_cmds.ptr and all_cmds2.len > 0) self.gpa.free(all_cmds2);

            // R43: Track image atlas generation (stub upload for v1).
            if (self.image_atlas.generation != self.image_atlas_generation_seen) {
                // For v1: upload is a stub; in a real GPU build this would call GpuImageAtlas.upload.
                self.image_atlas_generation_seen = self.image_atlas.generation;
            }

            // Render — clear to theme canvas color so empty space matches the theme.
            const c1 = self.tokens.bg_canvas;
            self.backend.clear(Color{
                .r = @as(f32, @floatFromInt(c1.r)) / 255.0,
                .g = @as(f32, @floatFromInt(c1.g)) / 255.0,
                .b = @as(f32, @floatFromInt(c1.b)) / 255.0,
                .a = 1.0,
            });
            self.backend.drawFrame(all_cmds2, &self.atlas_gpu);
            self.backend.endFrame();

            // R92: Record frame counters.
            const elapsed_ns = @as(i128, std.Io.Clock.real.now(_t_io1).nanoseconds) - self._frame_start_ns;
            const elapsed_ms: f32 = @as(f32, @floatFromInt(elapsed_ns)) / 1_000_000.0;
            const dirty_count2 = self.scene.elements.dirty.count();
            var live_count: u32 = 0;
            for (self.scene.elements.gen.items) |g| if (g != 0) {
                live_count += 1;
            };
            self.perf_hud.record(.{
                .frame_ms = elapsed_ms,
                .cmd_count = @intCast(all_cmds2.len),
                .dirty_count = dirty_count2,
                .element_count = live_count,
            });

            // M2-02: Clear dirty bits — every dirty element was just painted.
            self.scene.elements.dirty.unsetAll();
        }
    }

    /// R80: runWithNav is identical to run but drains any pending navigation
    /// request from the Navigator at the top of each frame, before layout.
    pub fn runWithNav(self: *AppInner, nav: *Navigator) void {
        // Re-register event queue and resize callback with the stable self pointer.
        // (AppInner may have been value-copied after init; self is the final location.)
        self.platform.setEventQueue(@ptrCast(&self.event_queue), EventQueue.pushThunk);
        self.platform.setFramebufferSizeCallback(@ptrCast(&self.pending_resize), framebufferSizeCallback);
        while (!self.platform.shouldClose()) {
            // R12: zero-size guard (minimised window).
            const fb = self.platform.framebufferSize();
            if (fb.width == 0 or fb.height == 0) {
                self.platform.pollEvents();
                continue;
            }

            // M2-02 / R21: Collect OS events.
            self.platform.pollEvents();
            {
                const evs = self.event_queue.drain();
                defer self.event_queue.clear();
                self.dispatchEvents(evs);
            }

            // R80: Drain pending navigation before the layout pass.
            // RA0: Use pushWithBoundary when error_boundary is set.
            if (self.error_boundary) |*eb| {
                nav.drainPendingWithBoundary(&self.scene, self.tokens, @ptrCast(self), eb) catch |err| {
                    std.log.err("runWithNav: drainPendingWithBoundary failed: {}", .{err});
                };
            } else {
                nav.drainPending(&self.scene, self.tokens, @ptrCast(self)) catch |err| {
                    std.log.err("runWithNav: drainPending failed: {}", .{err});
                };
            }

            // R12: a pending resize must force a redraw even when no scene element is dirty.
            if (self.pending_resize != null) self.scene.elements.markAllDirty();

            // M2-02: Skip GPU work when nothing has changed (bypass in screenshot mode).
            if (self._screenshot_frames == 0 and !self.scene.elements.hasDirty()) {
                if (hasAnimatedElements(&self.scene, &self.tooltip_manager)) {
                    // Tooltip pending or animated widget: keep rendering so tick() fires.
                    self.scene.elements.markAllDirty();
                } else {
                    self.platform.waitEvents();
                    continue;
                }
            }
            // Screenshot mode: force dirty so every frame renders.
            if (self._screenshot_frames > 0) self.scene.elements.markAllDirty();

            // R56: Poll watched .ui files for changes (hot-reload only).
            if (comptime hot_reload) {
                self.watcher.poll();
                for (self.watcher.drainChanged()) |entry_idx| {
                    const entry = &self.watcher.entries.items[entry_idx];
                    self.reloadFile(entry.path) catch |err| {
                        std.log.err("hot-reload: {}", .{err});
                    };
                }
            }

            // M2-04: Copy current signal values into Scene arrays before layout.
            self.refreshBindings();

            // R12: apply pending resize before beginFrame.
            if (self.pending_resize) |new_size| {
                self.backend.onResize(new_size);
                self.viewport_constraints = Constraints{
                    .min_w = 0,
                    .max_w = @floatFromInt(new_size.width),
                    .min_h = 0,
                    .max_h = @floatFromInt(new_size.height),
                };
                self.pending_resize = null;
            }

            if (!self.backend.beginFrame()) continue;

            // R92: record frame start time.
            const _t_io2 = std.Io.Threaded.global_single_threaded.io();
            self._frame_start_ns = @as(i128, std.Io.Clock.real.now(_t_io2).nanoseconds);

            // R73: Advance animation frame counter.
            self.frame_count +%= 1;
            self.frame_time_ms = @bitCast(@as(i64, @truncate(@divFloor(std.Io.Clock.real.now(_t_io2).nanoseconds, 1_000_000))));
            self.scene.frame_count = self.frame_count;
            self.scene.frame_time_ms = self.frame_time_ms;

            self.scene.font_family = &self.font_family;
            self.scene.measurePass(self.font_family.face(false, false), &self.atlas_cpu) catch {};

            if (self.atlas_cpu.generation != self.atlas_generation_seen) {
                const vk = self.backend._impl_vulkan() catch {
                    self.backend.endFrame();
                    continue;
                };
                self.atlas_gpu.deinit(vk.device);
                self.atlas_gpu = GpuAtlas.upload(
                    self.gpa,
                    vk.device,
                    vk.phys_device,
                    vk.cmd_pool,
                    vk.graphics_queue,
                    &self.atlas_cpu,
                ) catch {
                    self.backend.endFrame();
                    continue;
                };
                self.atlas_generation_seen = self.atlas_cpu.generation;
            }

            const s = self.scene.store();
            if (s.live > 0) {
                var idx: u32 = 0;
                while (idx < s.gen.items.len) : (idx += 1) {
                    const id = mod04.ElementId{ .index = idx, .gen = s.gen.items[idx] };
                    if (!s.isValid(id)) continue;
                    if (s.parentOf(id) == null) {
                        mod04.solve(s, id, self.viewport_constraints, self.scratch);
                        break;
                    }
                }
            }

            // Update scroll container dimensions from post-layout computed sizes.
            self.updateScrollDimensions();

            // Fire queued callbacks after layout, before render (INV-3.3).
            self.scene.fireQueuedCallbacks();
            self.scene.font_family = &self.font_family;
            self.scene.measurePass(self.font_family.face(false, false), &self.atlas_cpu) catch {};

            self.syncPseudoStates();

            const main_cmds = mod09.buildDrawList(
                self.gpa,
                &self.scene,
                &self.atlas_cpu,
                &self.image_atlas,
                self.font_family.face(false, false),
                self.tokens,
            ) catch blk: {
                break :blk @as([]DrawCommand, &[_]DrawCommand{});
            };
            defer if (main_cmds.len > 0) self.gpa.free(main_cmds);

            // Fire per-frame app-level tick (e.g. toast expiry + overlay rebuild).
            if (self.per_frame_app_fn) |f| f(self);

            const overlay_cmds = self.overlay.flatten(self.gpa) catch &[_]DrawCommand{};
            defer if (overlay_cmds.len > 0) self.gpa.free(overlay_cmds);

            const all_cmds = blk: {
                if (overlay_cmds.len == 0) break :blk main_cmds;
                const combined = self.gpa.alloc(DrawCommand, main_cmds.len + overlay_cmds.len) catch main_cmds;
                if (combined.len == main_cmds.len + overlay_cmds.len) {
                    @memcpy(combined[0..main_cmds.len], main_cmds);
                    @memcpy(combined[main_cmds.len..], overlay_cmds);
                }
                break :blk combined;
            };
            defer if (all_cmds.ptr != main_cmds.ptr and all_cmds.len > 0) self.gpa.free(all_cmds);

            // R90 / R92: Debug overlay and perf HUD draw lists.
            self.debug_overlay.updateHover(&self.scene, self.last_cursor_x, self.last_cursor_y);
            const debug_cmds = self.debug_overlay.buildDebugDrawList(
                self.gpa,
                &self.scene,
                self.tokens,
                self.font_family.face(false, false),
                &self.atlas_cpu,
            ) catch &[_]DrawCommand{};
            defer if (debug_cmds.len > 0) self.gpa.free(debug_cmds);

            const fb2 = self.platform.framebufferSize();
            const hud_cmds = self.perf_hud.buildHudDrawList(
                self.gpa,
                @as(f32, @floatFromInt(fb2.width)),
                self.tokens,
                self.font_family.face(false, false),
                &self.atlas_cpu,
            ) catch &[_]DrawCommand{};
            defer if (hud_cmds.len > 0) self.gpa.free(hud_cmds);

            const all_cmds2: []DrawCommand = blk: {
                const extra = debug_cmds.len + hud_cmds.len;
                if (extra == 0) break :blk all_cmds;
                const combined2 = self.gpa.alloc(DrawCommand, all_cmds.len + extra) catch break :blk all_cmds;
                @memcpy(combined2[0..all_cmds.len], all_cmds);
                @memcpy(combined2[all_cmds.len..][0..debug_cmds.len], debug_cmds);
                @memcpy(combined2[all_cmds.len + debug_cmds.len ..], hud_cmds);
                break :blk combined2;
            };
            defer if (all_cmds2.ptr != all_cmds.ptr and all_cmds2.len > 0) self.gpa.free(all_cmds2);

            if (self.image_atlas.generation != self.image_atlas_generation_seen) {
                self.image_atlas_generation_seen = self.image_atlas.generation;
            }

            const c2 = self.tokens.bg_canvas;
            self.backend.clear(Color{
                .r = @as(f32, @floatFromInt(c2.r)) / 255.0,
                .g = @as(f32, @floatFromInt(c2.g)) / 255.0,
                .b = @as(f32, @floatFromInt(c2.b)) / 255.0,
                .a = 1.0,
            });
            self.backend.drawFrame(all_cmds2, &self.atlas_gpu);
            self.backend.endFrame();

            // R92: Record frame counters.
            const elapsed_ns = @as(i128, std.Io.Clock.real.now(_t_io2).nanoseconds) - self._frame_start_ns;
            const elapsed_ms: f32 = @as(f32, @floatFromInt(elapsed_ns)) / 1_000_000.0;
            const dirty_count2 = self.scene.elements.dirty.count();
            var live_count: u32 = 0;
            for (self.scene.elements.gen.items) |g| if (g != 0) {
                live_count += 1;
            };
            self.perf_hud.record(.{
                .frame_ms = elapsed_ms,
                .cmd_count = @intCast(all_cmds2.len),
                .dirty_count = @intCast(dirty_count2),
                .element_count = live_count,
            });

            self.scene.elements.dirty.unsetAll();

            // Screenshot mode: after the Nth frame, read back pixels, write PNG, exit.
            if (self._screenshot_frames > 0 and self.frame_count >= self._screenshot_frames) {
                const rgba = self.backend.readbackFrameRgba(self.gpa) catch |err| {
                    std.log.err("screenshot readback failed: {}", .{err});
                    return;
                };
                defer self.gpa.free(rgba);
                const fb3 = self.platform.framebufferSize();
                const png_mod = @import("png_writer.zig");
                png_mod.writePng(self.gpa, self._screenshot_out, rgba, fb3.width, fb3.height) catch |err| {
                    std.log.err("screenshot write failed: {}", .{err});
                };
                std.log.info("screenshot written to '{s}'", .{self._screenshot_out});
                return;
            }
        }
    }

    // -----------------------------------------------------------------------
    // Deinit (reverse init order, R10)
    // -----------------------------------------------------------------------

    pub fn deinit(self: *AppInner) void {
        // RA4: Save window state before tearing down the window.
        if (self.window_state_mgr) |*wsm| {
            const state = window_state_mod.readFromPlatform(&self.platform);
            wsm.save(state) catch {};
            wsm.settings.flush() catch {};
        }

        // R56: deinit file watcher
        if (comptime hot_reload) {
            self.watcher.deinit();
        }
        // R7C/R7D: deinit tooltip and context menu managers
        self.tooltip_manager.deinit(self.gpa);
        self.context_menu_manager.deinit(self.gpa);
        // 1. bindings (no GPU resources)
        self.bindings.deinit(self.gpa);
        // 1b. overlay (no GPU resources)
        self.overlay.deinit();
        // 1c. image_atlas CPU
        self.image_atlas.deinit();
        // 2. scene
        self.scene.deinit();
        // 2. atlas_gpu — need device handle
        if (self.backend._impl_vulkan()) |vk| {
            self.atlas_gpu.deinit(vk.device);
        } else |_| {
            // backend already torn down; atlas handles were already invalid
        }
        // 3. atlas_cpu
        self.atlas_cpu.deinit();
        // 4. font_family (R60)
        self.font_family.deinit();
        // 5. scratch
        self.gpa.free(self.scratch);
        // 6. draw_list
        self.draw_list.deinit(self.gpa);
        // 7. event_queue
        self.event_queue.deinit();
        // 8. backend (quad pipeline first, then backend)
        self.backend.deinitQuadPipeline();
        self.backend.deinit();
        // 9. platform
        self.platform.deinit();

        // RA1: Deinit budget arena.
        if (self.budget_arena) |*ba| {
            ba.deinit();
        }

        // RA2: Deinit file logger (flush + close).
        if (self.file_logger) |*logger| {
            logger_mod.g_logger = null;
            logger.deinit();
        }
    }

    // -----------------------------------------------------------------------
    // Binding refresh (M2-04)
    // -----------------------------------------------------------------------

    fn refreshBindings(self: *AppInner) void {
        self.bindings.refresh(&self.scene, self.tokens);
        if (self.per_frame_fn) |f| f(&self.scene);
    }

    // -----------------------------------------------------------------------
    // R93 — Theme live-swap
    // -----------------------------------------------------------------------

    /// Apply `theme` to all live elements, re-resolving CSS classes against new tokens.
    /// Also applies the current font scale factor (R94 interaction).
    pub fn setTheme(self: *AppInner, new_theme: mod05.Theme) void {
        self._current_palette = new_theme.palette;
        self._current_mode = new_theme.mode;
        self.tokens = new_theme.tokens.scaled(self._font_scale);
        self.scene.elements.markAllDirty();
        self.rebuildStyles();
    }

    /// Toggle between light and dark modes using the current palette (R93).
    pub fn toggleTheme(self: *AppInner) void {
        self._current_mode = switch (self._current_mode) {
            .light => .dark,
            .dark => .light,
        };
        self.setTheme(mod05.Theme.build(self._current_palette, self._current_mode));
    }

    /// Re-resolve class-based styles for every live element against the current tokens.
    fn rebuildStyles(self: *AppInner) void {
        const s = self.scene.store();
        for (0..s.gen.items.len) |i| {
            const idx = @as(u32, @intCast(i));
            const id = mod04.ElementId{ .index = idx, .gen = s.gen.items[idx] };
            if (!s.isValid(id)) continue;
            const kind = self.scene.kindOfIdx(idx);
            const base = mod07.defaultStyleFor(kind, self.tokens);
            self.scene._style.items[idx] = self.resolveStyleForIdx(idx, base);
        }
    }

    /// Merge class-defined overrides on top of `base` for element `idx`.
    fn resolveStyleForIdx(self: *AppInner, idx: u32, base: mod05.ComputedStyle) mod05.ComputedStyle {
        if (idx >= self.scene._classes.items.len) return base;
        const classes = self.scene._classes.items[idx];
        const resolved = markup_mod.resolveClasses(classes, self.tokens);
        const empty = markup_mod.resolveClasses("", self.tokens);
        var out = base;
        if (!colorEq(resolved.style.background, empty.style.background)) out.background = resolved.style.background;
        if (!colorEq(resolved.style.text_color, empty.style.text_color)) out.text_color = resolved.style.text_color;
        if (!colorEq(resolved.style.border_color, empty.style.border_color)) out.border_color = resolved.style.border_color;
        if (resolved.style.border_width != empty.style.border_width) out.border_width = resolved.style.border_width;
        if (resolved.style.radius != empty.style.radius) out.radius = resolved.style.radius;
        if (resolved.style.gap != empty.style.gap) out.gap = resolved.style.gap;
        if (resolved.style.font_size != empty.style.font_size) out.font_size = resolved.style.font_size;
        if (resolved.style.truncate != empty.style.truncate) out.truncate = resolved.style.truncate;
        if (resolved.style.opacity != empty.style.opacity) out.opacity = resolved.style.opacity;
        if (resolved.style.shadow_blur != empty.style.shadow_blur) out.shadow_blur = resolved.style.shadow_blur;
        if (resolved.style.shadow_offset_x != empty.style.shadow_offset_x) out.shadow_offset_x = resolved.style.shadow_offset_x;
        if (resolved.style.shadow_offset_y != empty.style.shadow_offset_y) out.shadow_offset_y = resolved.style.shadow_offset_y;
        if (!colorEq(resolved.style.shadow_color, empty.style.shadow_color)) out.shadow_color = resolved.style.shadow_color;
        if (resolved.style.padding.top != empty.style.padding.top) out.padding.top = resolved.style.padding.top;
        if (resolved.style.padding.right != empty.style.padding.right) out.padding.right = resolved.style.padding.right;
        if (resolved.style.padding.bottom != empty.style.padding.bottom) out.padding.bottom = resolved.style.padding.bottom;
        if (resolved.style.padding.left != empty.style.padding.left) out.padding.left = resolved.style.padding.left;
        // Bug 7 fix: preserve font_bold and font_italic so rebuildStyles does not erase them.
        if (resolved.style.font_bold != empty.style.font_bold) out.font_bold = resolved.style.font_bold;
        if (resolved.style.font_italic != empty.style.font_italic) out.font_italic = resolved.style.font_italic;
        return out;
    }

    // -----------------------------------------------------------------------
    // R94 — Font scaling
    // -----------------------------------------------------------------------

    /// Set the global font scale factor (0.5–4.0). Rebuilds tokens and marks all dirty.
    pub fn setFontScale(self: *AppInner, factor: f32) void {
        self._font_scale = std.math.clamp(factor, 0.5, 4.0);
        self.tokens = mod05.Theme.build(self._current_palette, self._current_mode).tokens.scaled(self._font_scale);
        self.rebuildStyles();
        self.scene.elements.markAllDirty();
    }

    /// Return the current font scale factor.
    pub fn getFontScale(self: *const AppInner) f32 {
        return self._font_scale;
    }

    // -----------------------------------------------------------------------
    // M11 — RB4: Keyboard shortcut registration
    // -----------------------------------------------------------------------

    pub fn registerShortcut(self: *AppInner, key: mod01.Key, mods: mod01.Modifiers, cb: mod07.CallbackFn) ShortcutError!void {
        return self.shortcuts.register(key, mods, cb);
    }

    pub fn unregisterShortcut(self: *AppInner, key: mod01.Key, mods: mod01.Modifiers) void {
        self.shortcuts.unregister(key, mods);
    }

    // -----------------------------------------------------------------------
    // R56 — Hot-reload (comptime-gated; compiled out in production)
    // -----------------------------------------------------------------------

    fn reloadFile(self: *AppInner, path: [:0]const u8) !void {
        if (comptime !hot_reload) return;

        // 1. Read the changed .ui file.
        const _reload_io = std.Io.Threaded.global_single_threaded.io();
        const source = try std.Io.Dir.readFileAllocOptions(std.Io.Dir.cwd(), _reload_io, path, self.gpa, .limited(1024 * 1024), std.mem.Alignment.of(u8), null);
        defer self.gpa.free(source);

        // 2. Parse with diagnostics.
        var arena = std.heap.ArenaAllocator.init(self.gpa);
        var diag: markup_mod.ParseDiagnostic = undefined;
        const root = markup_mod.parseWithDiag(arena.allocator(), source, &diag) catch |err| {
            if (err != error.OutOfMemory) {
                std.log.err("[hot-reload] {s}:{}:{}: {s}", .{ path, diag.loc.line, diag.loc.column, diag.message });
            }
            arena.deinit();
            return; // Keep the old scene; do not reset on parse failure.
        };

        // 3. Reset scene and bindings.
        self.scene.reset();
        self.bindings.deinit(self.gpa);
        self.bindings = BindingSet.init();

        // 4. Re-instantiate.
        const new_root_id = self.scene.instantiate(root, self.tokens) catch |err| {
            std.log.err("[hot-reload] instantiate failed: {}", .{err});
            arena.deinit();
            return;
        };
        _ = new_root_id;

        // 5. Re-run measure pass.
        self.scene.font_family = &self.font_family;
        self.scene.measurePass(self.font_family.face(false, false), &self.atlas_cpu) catch {};

        // 6. Mark all elements dirty so the next frame paints the new tree.
        self.scene.elements.markAllDirty();

        // 7. Free the parse arena.
        arena.deinit();

        // 8. Call rebind hook if set.
        if (self.rebind_fn) |rebind| {
            rebind(self) catch |err| {
                std.log.err("[hot-reload] rebind failed: {}", .{err});
            };
        }

        std.log.info("[hot-reload] reloaded {s}", .{path});
    }

    // -----------------------------------------------------------------------
    // Scroll dimension update — run after layout solve each frame.
    // Sets content_height/width and container_height/width on every ScrollView
    // by measuring the bounding box of its first child after layout.
    // -----------------------------------------------------------------------

    fn updateScrollDimensions(self: *AppInner) void {
        const NONE32 = std.math.maxInt(u32);
        for (0..self.scene._kind.items.len) |i| {
            const idx = @as(u32, @intCast(i));
            if (self.scene.kindOfIdx(idx) != .scrollview) continue;
            if (idx >= self.scene.elements.layout.items.len) continue;
            const sv_computed = self.scene.elements.layout.items[idx].computed;
            const ss = self.scene.scrollStateOf(idx);
            ss.container_height = sv_computed.h;
            ss.container_width  = sv_computed.w;
            // Measure children's total extent.
            var child_max_y: f32 = 0;
            var child_max_x: f32 = 0;
            var child_i = self.scene.elements.first_child.items[idx];
            while (child_i != NONE32) {
                if (child_i >= self.scene.elements.layout.items.len) break;
                const cr = self.scene.elements.layout.items[child_i].computed;
                // cr.y is relative to the document (not the scroll container), so
                // the child extent within the container = (cr.y - sv_computed.y) + cr.h.
                const local_y = (cr.y - sv_computed.y) + cr.h;
                const local_x = (cr.x - sv_computed.x) + cr.w;
                if (local_y > child_max_y) child_max_y = local_y;
                if (local_x > child_max_x) child_max_x = local_x;
                child_i = self.scene.elements.next_sibling.items[child_i];
            }
            ss.content_height = child_max_y;
            ss.content_width  = child_max_x;
        }
    }

    // -----------------------------------------------------------------------
    // R40 — Pseudo-state sync (after event dispatch, before buildDrawList)
    // -----------------------------------------------------------------------

    fn syncPseudoStates(self: *AppInner) void {
        for (self.scene.focusable_indices.items) |idx| {
            const kind = self.scene.kindOfIdx(idx);
            const is_focused = self.scene.getFocus() == idx;
            switch (kind) {
                .button => {
                    const bs = self.scene.buttonStateOf(idx);
                    self.scene.setPseudo(idx, .{
                        .hover = bs.hovered and !bs.disabled,
                        .active = bs.pressed,
                        .disabled = bs.disabled,
                        .focus = is_focused,
                    });
                },
                .input => {
                    const inp = self.scene.inputStateOf(idx);
                    self.scene.setPseudo(idx, .{
                        .hover = false,
                        .active = inp.active,
                        .disabled = false,
                        .focus = is_focused,
                    });
                },
                .dropdown => {
                    self.scene.setPseudo(idx, .{
                        .hover = false,
                        .active = false,
                        .disabled = false,
                        .focus = is_focused,
                    });
                },
                .checkbox => {
                    const cs = self.scene.checkboxStateOf(idx);
                    self.scene.setPseudo(idx, .{
                        .hover = cs.hovered and !cs.disabled,
                        .active = cs.pressed,
                        .disabled = cs.disabled,
                        .focus = is_focused,
                    });
                },
                .textarea => {
                    const inp = self.scene.inputStateOf(idx);
                    self.scene.setPseudo(idx, .{
                        .hover = false,
                        .active = inp.active,
                        .disabled = false,
                        .focus = is_focused,
                    });
                },
                else => {},
            }
        }
    }

    // -----------------------------------------------------------------------
    // Event dispatch (R11, R30–R36)
    // -----------------------------------------------------------------------

    fn dispatchEvents(self: *AppInner, evs: []const Event) void {
        for (evs) |ev| {
            switch (ev) {
                .mouse_move => |mm| {
                    self.last_cursor_x = mm.x;
                    self.last_cursor_y = mm.y;
                    self.updateHoverStates(mm.x, mm.y);
                    // R7C: tooltip hover tracking — find topmost element with a tooltip attr.
                    var found_tooltip = false;
                    for (0..self.scene._kind.items.len) |i| {
                        const idx = @as(u32, @intCast(i));
                        if (idx >= self.scene.elements.layout.items.len) continue;
                        const rect = self.scene.elements.layout.items[idx].computed;
                        if (mm.x >= rect.x and mm.x < rect.x + rect.w and
                            mm.y >= rect.y and mm.y < rect.y + rect.h)
                        {
                            if (self.scene.tooltipOf(idx)) |tip_text| {
                                self.tooltip_manager.onHover(idx, tip_text, self.frame_time_ms);
                                found_tooltip = true;
                                break;
                            }
                        }
                    }
                    if (!found_tooltip) {
                        self.tooltip_manager.onLeave(self.tooltip_manager.hover_idx);
                    }
                    // M11 RB1: update drag position and fire on_drag_move if active.
                    if (self.drag.source_idx != mod07.NONE) {
                        self.drag.current_x = mm.x;
                        self.drag.current_y = mm.y;
                        if (!self.drag.active) {
                            const ddx = mm.x - self.drag.origin_x;
                            const ddy = mm.y - self.drag.origin_y;
                            if (ddx * ddx + ddy * ddy > DRAG_DEADZONE_PX * DRAG_DEADZONE_PX) {
                                self.drag.active = true;
                                if (self.scene._drag.items[self.drag.source_idx]) |cbs| {
                                    if (cbs.on_drag_start) |f| {
                                        self.drag.payload = f(self.drag.source_idx, mm.x, mm.y);
                                    }
                                }
                            }
                        } else {
                            if (self.scene._drag.items[self.drag.source_idx]) |cbs| {
                                if (cbs.on_drag_move) |f| {
                                    f(self.drag.source_idx, mm.x, mm.y, self.drag.payload);
                                }
                            }
                        }
                    }
                    // M11 RB0: update OS cursor shape based on hovered element.
                    {
                        const cursor_shape: mod01.CursorShape = blk: {
                            if (self.drag.active) break :blk .resize_all;
                            const hovered = hitTest(&self.scene, mm.x, mm.y);
                            if (hovered == mod07.NONE) break :blk .arrow;
                            if (self.scene.cursorOf(hovered)) |override| break :blk override;
                            const disabled = hovered < self.scene._pseudo.items.len and
                                self.scene._pseudo.items[hovered].disabled;
                            break :blk defaultCursorFor(self.scene.kindOfIdx(hovered), disabled);
                        };
                        self.platform.setCursor(cursor_shape);
                    }
                    // R62: update text selection drag.
                    if (self.left_mouse_down) {
                        if (self.dragging_text_idx) |didx| {
                            const byte_offset = self.hitTestText(didx, mm.x);
                            self.scene.selectionOf(didx).active = byte_offset;
                            if (didx < self.scene.elements.dirty.bit_length)
                                self.scene.elements.dirty.set(didx);
                        }
                        // Bug 3 fix: update slider value while dragging.
                        if (self.dragging_slider_idx) |sidx| {
                            if (sidx < self.scene.elements.layout.items.len) {
                                const rect = self.scene.elements.layout.items[sidx].computed;
                                if (rect.w > 0) {
                                    const ss = self.scene.sliderStateOf(sidx);
                                    const t = std.math.clamp((mm.x - rect.x) / rect.w, 0.0, 1.0);
                                    const value = ss.min + t * (ss.max - ss.min);
                                    self.scene.setSliderValue(sidx, value);
                                }
                            }
                        }
                        // Scrollbar thumb drag: translate thumb movement into scroll offset.
                        if (self.dragging_scrollbar_idx) |svidx| {
                            if (svidx < self.scene.elements.layout.items.len) {
                                const rect = self.scene.elements.layout.items[svidx].computed;
                                const ss = self.scene.scrollStateOf(svidx);
                                const container_h = if (ss.container_height > 0) ss.container_height else rect.h;
                                const content_h = ss.content_height;
                                if (content_h > container_h and container_h > 0) {
                                    const track_h = rect.h;
                                    const thumb_h = @max(20.0, track_h * (container_h / content_h));
                                    const scrollable_track = track_h - thumb_h;
                                    if (scrollable_track > 0) {
                                        const delta_y = mm.y - ss.drag_start_y;
                                        const max_scroll = content_h - container_h;
                                        const new_scroll = ss.drag_start_scroll_y + delta_y * max_scroll / scrollable_track;
                                        self.scene.setScrollOffset(svidx, std.math.clamp(new_scroll, 0, max_scroll), ss.scroll_x);
                                    }
                                }
                            }
                        }
                    }
                },
                .mouse_button => |mb| {
                    if (mb.button == .left) {
                        if (mb.action == .press) {
                            // M11 RB3: double-click detection (BEFORE drag candidate recording).
                            const now_ms = self.frame_time_ms;
                            const hit_dc = hitTest(&self.scene, mb.x, mb.y);
                            const dt = now_ms -| self.double_click.last_press_ms;
                            const ddx = mb.x - self.double_click.last_x;
                            const ddy = mb.y - self.double_click.last_y;
                            const close = ddx * ddx + ddy * ddy <= DOUBLE_CLICK_DEADZONE_PX * DOUBLE_CLICK_DEADZONE_PX;
                            const same_el = hit_dc == self.double_click.last_hit and hit_dc != mod07.NONE;
                            if (dt <= self.double_click_threshold_ms and close and same_el) {
                                // Synthesize double-click and dispatch it.
                                if (self.scene.doubleClickOf(hit_dc)) |cb| {
                                    self.scene._queued_callbacks.append(self.gpa, cb) catch {};
                                }
                                // Reset so triple-click doesn't produce a second double.
                                self.double_click = .{};
                            } else {
                                self.double_click = .{
                                    .last_press_ms = now_ms,
                                    .last_x = mb.x,
                                    .last_y = mb.y,
                                    .last_hit = hit_dc,
                                };
                            }
                            // M11 RB1: record drag candidate (AFTER double-click check).
                            if (self.drag.source_idx == mod07.NONE) {
                                const hit_drag = hitTest(&self.scene, mb.x, mb.y);
                                if (hit_drag != mod07.NONE and
                                    hit_drag < self.scene._drag.items.len and
                                    self.scene._drag.items[hit_drag] != null)
                                {
                                    self.drag = .{
                                        .source_idx = hit_drag,
                                        .origin_x = mb.x,
                                        .origin_y = mb.y,
                                        .current_x = mb.x,
                                        .current_y = mb.y,
                                    };
                                }
                            }
                            self.left_mouse_down = true;
                            self.handleMousePress(mb.x, mb.y);
                        } else {
                            // M11 RB1: complete drag on left release.
                            if (self.drag.source_idx != mod07.NONE) {
                                if (self.drag.active) {
                                    if (self.scene._drag.items[self.drag.source_idx]) |cbs| {
                                        if (cbs.on_drag_end) |f| {
                                            f(self.drag.source_idx, self.drag.payload);
                                        }
                                    }
                                    const hit_drop = hitTest(&self.scene, mb.x, mb.y);
                                    if (hit_drop != mod07.NONE and
                                        hit_drop < self.scene._drop.items.len and
                                        self.scene._drop.items[hit_drop] != null)
                                    {
                                        if (self.scene._drop.items[hit_drop]) |dcbs| {
                                            if (dcbs.on_drop) |f| {
                                                f(hit_drop, self.drag.source_idx, self.drag.payload);
                                            }
                                        }
                                    }
                                }
                                self.drag = .{};
                            }
                            self.handleMouseRelease(mb.x, mb.y);
                            self.left_mouse_down = false;
                        }
                    } else if (mb.button == .right and mb.action == .press) {
                        const hit_rc = hitTest(&self.scene, mb.x, mb.y);
                        // M11 RB2: fire on_right_click callback (independent of context menu).
                        if (hit_rc != mod07.NONE) {
                            if (self.scene.rightClickOf(hit_rc)) |cb| {
                                self.scene._queued_callbacks.append(self.gpa, cb) catch {};
                            }
                        }
                        // R7D: right-click opens context menu if widget has one registered.
                        if (hit_rc != mod07.NONE) {
                            const menu_idx = self.scene.contextMenuIdxOf(hit_rc);
                            if (menu_idx != 0xFF) {
                                self.context_menu_manager.openAt(
                                    menu_idx,
                                    mb.x,
                                    mb.y,
                                    &self.overlay,
                                    self.tokens,
                                    &self.font_family.regular,
                                    &self.atlas_cpu,
                                    self.gpa,
                                ) catch {};
                            }
                        }
                    }
                },
                .mouse_button_double => {
                    // Synthesized by dispatchEvents above — already handled inline.
                },
                .scroll => |sc| {
                    self.handleScroll(sc.dx, sc.dy);
                },
                // M11 RB5: trackpad swipe — route to scroll containers like a normal scroll.
                .gesture_swipe => |gs| {
                    self.handleScroll(gs.dx, gs.dy);
                },
                // M11 RB5: pinch gesture — deliver to topmost element with on_pinch.
                .gesture_pinch => |gp| {
                    const hit_p = hitTest(&self.scene, self.last_cursor_x, self.last_cursor_y);
                    if (hit_p != mod07.NONE) {
                        if (self.scene.pinchOf(hit_p)) |cb| {
                            cb(hit_p, gp.scale_delta);
                        }
                    }
                },
                .key => |k| {
                    if (k.action == .press) {
                        // M11 RB4: check global shortcuts before focused-element handling.
                        if (self.shortcuts.lookup(k.key, k.mods)) |cb| {
                            self.scene._queued_callbacks.append(self.gpa, cb) catch {};
                            // Shortcut consumed — do NOT fall through to handleKey.
                        } else {
                            // M11 RB1: Escape cancels an active drag.
                            if (k.key == .escape and self.drag.active) {
                                if (self.scene._drag.items[self.drag.source_idx]) |cbs| {
                                    if (cbs.on_drag_end) |f| {
                                        f(self.drag.source_idx, self.drag.payload);
                                    }
                                }
                                self.drag = .{};
                            }
                            self.handleKey(k.key, k.mods);
                        }
                    }
                },
                .char => |ch| {
                    self.handleChar(ch.codepoint);
                },
            }
        }
    }

    /// Walk up the ancestor chain for `idx` and accumulate the total scroll offset.
    /// Elements inside a ScrollView have computed positions set at layout time (scroll=0);
    /// the visual position is computed - scroll_offset. We invert to get visual → layout.
    fn scrollOffsetFor(self: *AppInner, idx: u32) struct { x: f32, y: f32 } {
        var acc_x: f32 = 0;
        var acc_y: f32 = 0;
        const NONE32 = std.math.maxInt(u32);
        var cur = idx;
        while (cur < self.scene.elements.parent.items.len) {
            const p = self.scene.elements.parent.items[cur];
            if (p == NONE32 or p >= self.scene.elements.layout.items.len) break;
            if (self.scene.kindOfIdx(p) == .scrollview) {
                const ss = self.scene.scrollStateOf(p);
                acc_x += ss.scroll_x;
                acc_y += ss.scroll_y;
            }
            cur = p;
        }
        return .{ .x = acc_x, .y = acc_y };
    }

    /// Hit-test: find the topmost focusable element at (x, y). Returns idx or maxInt(u32).
    fn hitTestFocusable(self: *AppInner, x: f32, y: f32) u32 {
        const NONE = std.math.maxInt(u32);
        for (self.scene.focusable_indices.items) |idx| {
            if (idx >= self.scene.elements.layout.items.len) continue;
            const scroll = self.scrollOffsetFor(idx);
            const rect = self.scene.elements.layout.items[idx].computed;
            // M12 RC1 — adjust hit y for sticky elements.
            const sticky_dy: f32 = if (idx < self.scene._sticky_offset_y.items.len)
                self.scene._sticky_offset_y.items[idx]
            else
                0;
            const vx = rect.x - scroll.x;
            const vy = rect.y - scroll.y + sticky_dy;
            if (x >= vx and x < vx + rect.w and
                y >= vy and y < vy + rect.h)
            {
                return idx;
            }
        }
        return NONE;
    }

    fn updateHoverStates(self: *AppInner, x: f32, y: f32) void {
        for (self.scene.focusable_indices.items) |idx| {
            if (idx >= self.scene.elements.layout.items.len) continue;
            const scroll = self.scrollOffsetFor(idx);
            const rect = self.scene.elements.layout.items[idx].computed;
            const vx = rect.x - scroll.x;
            const vy = rect.y - scroll.y;
            const hit = x >= vx and x < vx + rect.w and
                y >= vy and y < vy + rect.h;
            const kind = self.scene.kindOfIdx(idx);
            var dirty = false;
            switch (kind) {
                .button => {
                    const was = self.scene.buttonStateOf(idx).hovered;
                    self.scene.buttonStateOf(idx).hovered = hit;
                    if (was != hit) dirty = true;
                },
                .checkbox => {
                    const was = self.scene.checkboxStateOf(idx).hovered;
                    self.scene.checkboxStateOf(idx).hovered = hit;
                    if (was != hit) dirty = true;
                },
                else => {},
            }
            if (dirty and idx < self.scene.elements.dirty.bit_length)
                self.scene.elements.dirty.set(idx);
        }
    }

    fn handleMousePress(self: *AppInner, x: f32, y: f32) void {
        const NONE = std.math.maxInt(u32);

        // Scrollbar thumb drag: check all scrollviews for a hit on the vertical thumb.
        const bar_w: f32 = 14.0;
        for (0..self.scene._kind.items.len) |i| {
            const idx = @as(u32, @intCast(i));
            if (self.scene.kindOfIdx(idx) != .scrollview) continue;
            if (idx >= self.scene.elements.layout.items.len) continue;
            const rect = self.scene.elements.layout.items[idx].computed;
            const ss = self.scene.scrollStateOf(idx);
            const content_h = ss.content_height;
            const container_h = if (ss.container_height > 0) ss.container_height else rect.h;
            if (content_h <= container_h or container_h <= 0) continue;
            const track_x = rect.x + rect.w - bar_w;
            const track_y = rect.y;
            const track_h = rect.h;
            const ratio = container_h / content_h;
            const thumb_h = @max(20.0, track_h * ratio);
            const max_scroll = content_h - container_h;
            const scroll_frac = if (max_scroll > 0) ss.scroll_y / max_scroll else 0;
            const thumb_y = track_y + scroll_frac * (track_h - thumb_h);
            if (x >= track_x and x < track_x + bar_w and
                y >= thumb_y and y < thumb_y + thumb_h)
            {
                ss.dragging_v_scrollbar = true;
                ss.drag_start_y = y;
                ss.drag_start_scroll_y = ss.scroll_y;
                self.dragging_scrollbar_idx = idx;
                return;
            }
        }

        // Bug 3 fix: when a dropdown is open, check if click is in its option panel first.
        // Option panels are rendered as overlays outside the element's computed rect, so
        // hitTestFocusable would never return them.
        for (0..self.scene._kind.items.len) |i| {
            const idx = @as(u32, @intCast(i));
            if (self.scene.kindOfIdx(idx) != .dropdown) continue;
            const dd = self.scene.dropdownStateOf(idx);
            if (!dd.open or dd.options.items.len == 0) continue;
            if (idx >= self.scene.elements.layout.items.len) continue;
            const rect = self.scene.elements.layout.items[idx].computed;
            const item_h = rect.h;
            const panel_y = rect.y + rect.h;
            const panel_h = item_h * @as(f32, @floatFromInt(dd.options.items.len));
            if (x >= rect.x and x < rect.x + rect.w and y >= panel_y and y < panel_y + panel_h) {
                const oi: u32 = @intFromFloat((y - panel_y) / item_h);
                self.scene.selectDropdownOption(idx, oi) catch {};
                return;
            }
        }

        const hit = self.hitTestFocusable(x, y);
        // Focus the hit element (or clear focus if none).
        self.scene.setFocus(hit);
        if (hit != NONE) {
            const kind = self.scene.kindOfIdx(hit);
            switch (kind) {
                .button => {
                    self.scene.buttonStateOf(hit).pressed = true;
                    if (hit < self.scene.elements.dirty.bit_length)
                        self.scene.elements.dirty.set(hit);
                },
                .checkbox => {
                    self.scene.checkboxStateOf(hit).pressed = true;
                    if (hit < self.scene.elements.dirty.bit_length)
                        self.scene.elements.dirty.set(hit);
                },
                .dropdown => {
                    self.scene.toggleDropdown(hit);
                },
                .radio => {
                    // Bug 2 fix: select the clicked radio and deselect others in the same group.
                    self.scene.selectRadio(hit);
                    if (hit < self.scene.elements.dirty.bit_length)
                        self.scene.elements.dirty.set(hit);
                },
                .accordion => {
                    // R77 — Toggle accordion open/closed on click.
                    self.scene.toggleAccordion(hit);
                },
                .slider => {
                    // Bug 3 fix: start slider drag and set initial value from click position.
                    self.dragging_slider_idx = hit;
                    const ss = self.scene.sliderStateOf(hit);
                    ss.dragging = true;
                    if (hit < self.scene.elements.layout.items.len) {
                        const rect = self.scene.elements.layout.items[hit].computed;
                        if (rect.w > 0) {
                            const t = std.math.clamp((x - rect.x) / rect.w, 0.0, 1.0);
                            const value = ss.min + t * (ss.max - ss.min);
                            self.scene.setSliderValue(hit, value);
                        }
                    }
                },
                else => {},
            }
        }

        // R76 — Tab bar click: hit-test each tabs widget independently
        // (tabs are not in focusable_indices; we scan them directly).
        for (0..self.scene._kind.items.len) |i| {
            const idx = @as(u32, @intCast(i));
            if (self.scene.kindOfIdx(idx) != .tabs) continue;
            if (idx >= self.scene.elements.layout.items.len) continue;
            const rect = self.scene.elements.layout.items[idx].computed;
            const tab_bar_h: f32 = 36.0;
            if (x >= rect.x and x < rect.x + rect.w and
                y >= rect.y and y < rect.y + tab_bar_h)
            {
                const ts = self.scene.tabsStateOf(idx);
                if (ts.tab_count > 0) {
                    const tab_w = rect.w / @as(f32, @floatFromInt(ts.tab_count));
                    const tab_i: u32 = @intFromFloat((x - rect.x) / tab_w);
                    if (tab_i < ts.tab_count) {
                        self.scene.selectTab(idx, tab_i);
                    }
                }
            }
        }
        // Data table header click → sort column.
        for (0..self.scene._kind.items.len) |i| {
            const idx = @as(u32, @intCast(i));
            if (self.scene.kindOfIdx(idx) != .data_table) continue;
            if (idx >= self.scene.elements.layout.items.len) continue;
            const rect = self.scene.elements.layout.items[idx].computed;
            // Adjust the table's raw Y for any ancestor ScrollView offset so that
            // the hit-test uses the actual screen position rather than the layout rect.
            var screen_y = rect.y;
            for (0..self.scene._kind.items.len) |si| {
                if (self.scene.kindOfIdx(@intCast(si)) != .scrollview) continue;
                if (si >= self.scene.elements.layout.items.len) continue;
                const sv_rect = self.scene.elements.layout.items[si].computed;
                if (sv_rect.x <= rect.x and sv_rect.y <= rect.y and
                    sv_rect.x + sv_rect.w >= rect.x + rect.w)
                {
                    screen_y -= self.scene._scroll_state.items[si].scroll_y;
                    break;
                }
            }
            const header_h: f32 = 36.0;
            if (x < rect.x or x >= rect.x + rect.w) continue;
            if (y < screen_y or y >= screen_y + header_h) continue;
            const ts = self.scene.tableStateOf(idx);
            var col_x = rect.x;
            var col_found: ?u8 = null;
            for (ts.columns[0..ts.col_count], 0..) |*col, ci| {
                if (x >= col_x and x < col_x + col.width_px) {
                    col_found = @intCast(ci);
                    break;
                }
                col_x += col.width_px;
            }
            if (col_found) |col_idx| {
                self.scene.sortTable(idx, col_idx);
            }
        }

        // R62: hit-test read-only .text elements for selection.
        for (0..self.scene._kind.items.len) |i| {
            const idx = @as(u32, @intCast(i));
            if (self.scene.kindOfIdx(idx) != .text) continue;
            if (idx >= self.scene.elements.layout.items.len) continue;
            const rect = self.scene.elements.layout.items[idx].computed;
            if (x >= rect.x and x < rect.x + rect.w and y >= rect.y and y < rect.y + rect.h) {
                const byte_offset = self.hitTestText(idx, x);
                self.scene.setSelection(idx, byte_offset, byte_offset);
                self.dragging_text_idx = idx;
                break;
            }
        }
    }

    fn handleMouseRelease(self: *AppInner, x: f32, y: f32) void {
        // R62: clear text drag state.
        self.dragging_text_idx = null;
        // Bug 3 fix: clear slider drag state.
        if (self.dragging_slider_idx) |sidx| {
            self.scene.sliderStateOf(sidx).dragging = false;
            self.dragging_slider_idx = null;
        }
        // Clear scrollbar drag state.
        if (self.dragging_scrollbar_idx) |svidx| {
            self.scene.scrollStateOf(svidx).dragging_v_scrollbar = false;
            self.dragging_scrollbar_idx = null;
        }
        // Activate any pressed button/checkbox under the cursor.
        for (self.scene.focusable_indices.items) |idx| {
            // Fresh geometric hit test at the release position — do NOT rely on the
            // stale st.hovered flag, which is only updated by mouse_move events and
            // will be false after a scene rebuild (e.g. navigation) with no cursor move.
            const hit_at_release = if (idx < self.scene.elements.layout.items.len) blk: {
                const rect = self.scene.elements.layout.items[idx].computed;
                break :blk x >= rect.x and x < rect.x + rect.w and
                    y >= rect.y and y < rect.y + rect.h;
            } else false;
            const kind = self.scene.kindOfIdx(idx);
            switch (kind) {
                .button => {
                    const st = self.scene.buttonStateOf(idx);
                    if (st.pressed) {
                        st.pressed = false;
                        if (hit_at_release and !st.disabled) {
                            if (st.on_click) |cb| {
                                self.scene._queued_callbacks.append(self.scene.gpa, cb) catch {};
                            }
                        }
                        if (idx < self.scene.elements.dirty.bit_length)
                            self.scene.elements.dirty.set(idx);
                    }
                },
                .checkbox => {
                    const st = self.scene.checkboxStateOf(idx);
                    if (st.pressed) {
                        st.pressed = false;
                        if (hit_at_release and !st.disabled) {
                            st.checked = !st.checked;
                            if (st.on_change) |cb| {
                                self.scene._queued_callbacks.append(self.scene.gpa, cb) catch {};
                            }
                        }
                        if (idx < self.scene.elements.dirty.bit_length)
                            self.scene.elements.dirty.set(idx);
                    }
                },
                else => {},
            }
        }
    }

    fn handleScroll(self: *AppInner, dx: f32, dy: f32) void {
        const n = self.scene._kind.items.len;

        // First: check if cursor is over a data_table — if so, scroll it and return.
        // This must run before the scrollview block so an ancestor ScrollView does not
        // consume the event first.
        var j = n;
        while (j > 0) {
            j -= 1;
            const idx = @as(u32, @intCast(j));
            if (self.scene.kindOfIdx(idx) != .data_table) continue;
            if (idx >= self.scene.elements.layout.items.len) continue;
            const rect = self.scene.elements.layout.items[idx].computed;
            if (self.last_cursor_x >= rect.x and self.last_cursor_x < rect.x + rect.w and
                self.last_cursor_y >= rect.y and self.last_cursor_y < rect.y + rect.h)
            {
                const ts = self.scene.tableStateOf(idx);
                const header_h: f32 = 36.0;
                const view_h = rect.h - header_h;
                const n_rows: u32 = if (ts.rows) |r| r.row_count else 0;
                const max_scroll = @max(0.0, ts.row_height * @as(f32, @floatFromInt(n_rows)) - view_h);
                ts.scroll_y = std.math.clamp(ts.scroll_y - dy * 32.0, 0.0, max_scroll);
                if (idx < self.scene.elements.dirty.bit_length) self.scene.elements.dirty.set(idx);
                return;
            }
        }

        // Then: scroll the innermost (highest-index) scrollview under the cursor.
        // Iterating in reverse DFS order ensures descendants match before ancestors.
        var i = n;
        while (i > 0) {
            i -= 1;
            const idx = @as(u32, @intCast(i));
            if (self.scene.kindOfIdx(idx) != .scrollview) continue;
            if (idx >= self.scene.elements.layout.items.len) continue;
            const rect = self.scene.elements.layout.items[idx].computed;
            if (self.last_cursor_x >= rect.x and self.last_cursor_x < rect.x + rect.w and
                self.last_cursor_y >= rect.y and self.last_cursor_y < rect.y + rect.h)
            {
                const ss = self.scene.scrollStateOf(idx);
                const max_y = @max(0.0, ss.content_height - ss.container_height);
                if (max_y <= 0 and dy != 0) continue; // can't scroll vertically, try parent
                self.scene.setScrollOffset(idx, ss.scroll_y - dy * 16.0, ss.scroll_x - dx * 16.0);
                break;
            }
        }
    }

    fn handleKey(self: *AppInner, key: mod01.Key, mods: mod01.Modifiers) void {
        // F1: toggle performance HUD (frame time, FPS, draw commands).
        if (key == .f1) {
            self.perf_hud.toggleHud();
            self.scene.elements.markAllDirty();
            return;
        }

        // F3: toggle debug bounds overlay (element rects + hover info).
        if (key == .f3) {
            self.debug_overlay.toggle();
            self.scene.elements.markAllDirty();
            return;
        }

        // F2: cycle theme light → dark → high-contrast-light.
        if (key == .f2) {
            self._theme_idx = (self._theme_idx + 1) % 3;
            const new_theme = switch (self._theme_idx) {
                0 => mod05.Theme.build(mod05.Palette.default(), .light),
                1 => mod05.Theme.build(mod05.Palette.default(), .dark),
                else => mod05.Theme.hc_light,
            };
            self.setTheme(new_theme);
            return;
        }

        const focused = self.scene.focused_idx;
        const NONE = std.math.maxInt(u32);

        // Global: Tab / Shift+Tab always changes focus.
        if (key == .tab) {
            if (mods.shift) self.scene.focusPrev() else self.scene.focusNext();
            return;
        }
        // Escape clears dropdown/focus.
        if (key == .escape) {
            if (focused != NONE and self.scene.kindOfIdx(focused) == .dropdown) {
                self.scene.closeDropdown(focused);
            } else {
                self.scene.setFocus(NONE);
            }
            return;
        }

        if (focused == NONE) return;
        const kind = self.scene.kindOfIdx(focused);
        switch (kind) {
            .input => self.handleInputKey(focused, key, mods),
            .textarea => self.handleTextareaKey(focused, key, mods),
            .dropdown => self.handleDropdownKey(focused, key, mods),
            .checkbox => self.handleCheckboxKey(focused, key),
            .button => self.handleButtonKey(focused, key),
            .text => self.handleTextKey(focused, key, mods),
            else => {},
        }
    }

    fn handleChar(self: *AppInner, codepoint: u21) void {
        // Bug 6 fix: guard against non-printable codepoints (control characters).
        // GLFW char callback should only fire for printable characters, but guard here
        // to be safe: codepoints < 32 (control chars) or 127 (DEL) are not text.
        if (codepoint < 32 or codepoint == 127) return;
        const focused = self.scene.focused_idx;
        const NONE = std.math.maxInt(u32);
        if (focused == NONE) return;
        const kind = self.scene.kindOfIdx(focused);
        if (kind != .input and kind != .textarea) return;
        const inp = self.scene.inputStateOf(focused);
        if (!inp.active) return;
        const sel = self.scene.selectionOf(focused);
        // Encode codepoint to UTF-8.
        var buf: [4]u8 = undefined;
        const len = std.unicode.utf8Encode(codepoint, &buf) catch return;
        // Delete selection if any.
        if (sel.anchor != inp.cursor) {
            const lo = @min(sel.anchor, inp.cursor);
            const hi = @max(sel.anchor, inp.cursor);
            inp.text.replaceRange(self.gpa, lo, hi - lo, &[_]u8{}) catch return;
            inp.cursor = lo;
            sel.anchor = lo;
            sel.active = lo;
        }
        inp.text.insertSlice(self.gpa, inp.cursor, buf[0..len]) catch return;
        inp.cursor += @as(u32, @intCast(len));
        sel.anchor = inp.cursor;
        sel.active = inp.cursor;
        if (focused < self.scene.elements.dirty.bit_length)
            self.scene.elements.dirty.set(focused);
        // R63: rebuild line starts after char insert in textarea.
        if (self.scene.kindOfIdx(focused) == .textarea) {
            const ts = self.scene.textareaStateOf(focused);
            rebuildLineStarts(ts, inp.text.items, self.gpa);
        }
    }

    fn handleInputKey(self: *AppInner, idx: u32, key: mod01.Key, mods: mod01.Modifiers) void {
        const inp = self.scene.inputStateOf(idx);
        const text_len = @as(u32, @intCast(inp.text.items.len));
        const sel = self.scene.selectionOf(idx);
        switch (key) {
            .backspace => {
                if (sel.anchor != inp.cursor) {
                    // Delete selection.
                    const lo = @min(sel.anchor, inp.cursor);
                    const hi = @max(sel.anchor, inp.cursor);
                    inp.text.replaceRange(self.gpa, lo, hi - lo, &[_]u8{}) catch return;
                    inp.cursor = lo;
                    sel.anchor = lo;
                    sel.active = lo;
                } else if (inp.cursor > 0) {
                    inp.cursor -= 1;
                    inp.text.replaceRange(self.gpa, inp.cursor, 1, &[_]u8{}) catch return;
                    sel.anchor = inp.cursor;
                    sel.active = inp.cursor;
                }
            },
            .delete => {
                if (sel.anchor != inp.cursor) {
                    const lo = @min(sel.anchor, inp.cursor);
                    const hi = @max(sel.anchor, inp.cursor);
                    inp.text.replaceRange(self.gpa, lo, hi - lo, &[_]u8{}) catch return;
                    inp.cursor = lo;
                    sel.anchor = lo;
                    sel.active = lo;
                } else if (inp.cursor < text_len) {
                    inp.text.replaceRange(self.gpa, inp.cursor, 1, &[_]u8{}) catch return;
                    sel.anchor = inp.cursor;
                    sel.active = inp.cursor;
                }
            },
            .left => {
                if (!mods.shift and sel.anchor != inp.cursor) {
                    // Collapse selection to left end (C4).
                    inp.cursor = @min(sel.anchor, inp.cursor);
                } else if (inp.cursor > 0) {
                    inp.cursor -= 1;
                }
                sel.active = inp.cursor;
                if (!mods.shift) sel.anchor = inp.cursor;
            },
            .right => {
                if (!mods.shift and sel.anchor != inp.cursor) {
                    // Collapse selection to right end (C4).
                    inp.cursor = @max(sel.anchor, inp.cursor);
                } else if (inp.cursor < text_len) {
                    inp.cursor += 1;
                }
                sel.active = inp.cursor;
                if (!mods.shift) sel.anchor = inp.cursor;
            },
            .home => {
                inp.cursor = 0;
                sel.active = 0;
                if (!mods.shift) sel.anchor = 0;
            },
            .end => {
                inp.cursor = text_len;
                sel.active = text_len;
                if (!mods.shift) sel.anchor = text_len;
            },
            .c => {
                if (mods.ctrl) {
                    // Copy selection to clipboard.
                    const lo = @min(sel.anchor, inp.cursor);
                    const hi = @max(sel.anchor, inp.cursor);
                    if (hi > lo) {
                        self.platform.setClipboard(inp.text.items[lo..hi]);
                    }
                    return; // don't mark dirty
                }
            },
            .v => {
                if (mods.ctrl) {
                    // Paste from clipboard.
                    const clip = self.platform.getClipboard(self.gpa) orelse return;
                    defer self.gpa.free(clip);
                    // Delete selection first.
                    if (sel.anchor != inp.cursor) {
                        const lo = @min(sel.anchor, inp.cursor);
                        const hi = @max(sel.anchor, inp.cursor);
                        inp.text.replaceRange(self.gpa, lo, hi - lo, &[_]u8{}) catch return;
                        inp.cursor = lo;
                        sel.anchor = lo;
                        sel.active = lo;
                    }
                    inp.text.insertSlice(self.gpa, inp.cursor, clip) catch return;
                    inp.cursor += @as(u32, @intCast(clip.len));
                    sel.anchor = inp.cursor;
                    sel.active = inp.cursor;
                }
            },
            .x => {
                if (mods.ctrl) {
                    // Cut: copy then delete selection.
                    const lo = @min(sel.anchor, inp.cursor);
                    const hi = @max(sel.anchor, inp.cursor);
                    if (hi > lo) {
                        self.platform.setClipboard(inp.text.items[lo..hi]);
                        inp.text.replaceRange(self.gpa, lo, hi - lo, &[_]u8{}) catch return;
                        inp.cursor = lo;
                        sel.anchor = lo;
                        sel.active = lo;
                    }
                }
            },
            .a => {
                if (mods.ctrl) {
                    // Select all.
                    sel.anchor = 0;
                    inp.cursor = text_len;
                    sel.active = text_len;
                }
            },
            else => return, // No dirty mark for unhandled keys.
        }
        if (idx < self.scene.elements.dirty.bit_length)
            self.scene.elements.dirty.set(idx);
    }

    // -----------------------------------------------------------------------
    // R63 — Textarea helpers
    // -----------------------------------------------------------------------

    fn handleTextareaKey(self: *AppInner, idx: u32, key: mod01.Key, mods: mod01.Modifiers) void {
        const inp = self.scene.inputStateOf(idx);
        const ts = self.scene.textareaStateOf(idx);
        const text_len = @as(u32, @intCast(inp.text.items.len));
        const sel = self.scene.selectionOf(idx);
        switch (key) {
            .enter => {
                // Delete selection if any.
                if (sel.anchor != inp.cursor) {
                    const lo = @min(sel.anchor, inp.cursor);
                    const hi = @max(sel.anchor, inp.cursor);
                    inp.text.replaceRange(self.gpa, lo, hi - lo, &[_]u8{}) catch return;
                    inp.cursor = lo;
                    sel.anchor = lo;
                    sel.active = lo;
                }
                inp.text.insert(self.gpa, inp.cursor, '\n') catch return;
                inp.cursor += 1;
                sel.anchor = inp.cursor;
                sel.active = inp.cursor;
                rebuildLineStarts(ts, inp.text.items, self.gpa);
            },
            .up => {
                const line = taLineOfByte(ts, inp.cursor);
                if (line == 0) {
                    inp.cursor = 0;
                } else {
                    const col = inp.cursor - ts.line_starts.items[line];
                    const prev_line_start = ts.line_starts.items[line - 1];
                    const prev_line_end: u32 = ts.line_starts.items[line] -| 1;
                    const prev_line_len = prev_line_end - prev_line_start;
                    inp.cursor = prev_line_start + @min(col, prev_line_len);
                }
                if (!mods.shift) {
                    sel.anchor = inp.cursor;
                    sel.active = inp.cursor;
                } else {
                    sel.active = inp.cursor;
                }
            },
            .down => {
                const line = taLineOfByte(ts, inp.cursor);
                if (line + 1 >= ts.line_starts.items.len) {
                    inp.cursor = text_len;
                } else {
                    const col = inp.cursor - ts.line_starts.items[line];
                    const next_line_start = ts.line_starts.items[line + 1];
                    const next_line_end: u32 = if (line + 2 < ts.line_starts.items.len)
                        ts.line_starts.items[line + 2] -| 1
                    else
                        text_len;
                    const next_line_len = next_line_end - next_line_start;
                    inp.cursor = next_line_start + @min(col, next_line_len);
                }
                if (!mods.shift) {
                    sel.anchor = inp.cursor;
                    sel.active = inp.cursor;
                } else {
                    sel.active = inp.cursor;
                }
            },
            else => {
                self.handleInputKey(idx, key, mods);
                rebuildLineStarts(ts, inp.text.items, self.gpa);
                scrollToCursor(ts, inp.cursor, taLineHeight(self, idx));
                return; // handleInputKey already marks dirty
            },
        }
        scrollToCursor(ts, inp.cursor, taLineHeight(self, idx));
        if (idx < self.scene.elements.dirty.bit_length)
            self.scene.elements.dirty.set(idx);
    }

    fn handleDropdownKey(self: *AppInner, idx: u32, key: mod01.Key, mods: mod01.Modifiers) void {
        _ = mods;
        const dd = self.scene.dropdownStateOf(idx);
        switch (key) {
            .space, .enter => {
                if (!dd.open) {
                    dd.open = true;
                    dd.highlight_idx = dd.selected_idx;
                } else {
                    // Confirm selection.
                    dd.selected_idx = dd.highlight_idx;
                    dd.open = false;
                }
            },
            .up => {
                if (dd.open and dd.highlight_idx > 0)
                    dd.highlight_idx -= 1;
            },
            .down => {
                if (dd.open and dd.options.items.len > 0 and
                    dd.highlight_idx < @as(u32, @intCast(dd.options.items.len)) - 1)
                    dd.highlight_idx += 1;
            },
            .escape => {
                dd.open = false;
            },
            else => return,
        }
        if (idx < self.scene.elements.dirty.bit_length)
            self.scene.elements.dirty.set(idx);
    }

    fn handleCheckboxKey(self: *AppInner, idx: u32, key: mod01.Key) void {
        if (key == .space or key == .enter) {
            const st = self.scene.checkboxStateOf(idx);
            st.checked = !st.checked;
            if (idx < self.scene.elements.dirty.bit_length)
                self.scene.elements.dirty.set(idx);
        }
    }

    fn handleButtonKey(self: *AppInner, idx: u32, key: mod01.Key) void {
        if (key == .space or key == .enter) {
            const st = self.scene.buttonStateOf(idx);
            if (!st.disabled) {
                if (st.on_click) |cb| {
                    self.scene._queued_callbacks.append(self.scene.gpa, cb) catch {};
                }
                if (idx < self.scene.elements.dirty.bit_length)
                    self.scene.elements.dirty.set(idx);
            }
        }
    }

    /// R62: keyboard selection for read-only .text elements.
    fn handleTextKey(self: *AppInner, idx: u32, key: mod01.Key, mods: mod01.Modifiers) void {
        const id = mod07.ElementId{ .index = idx, .gen = self.scene.elements.gen.items[idx] };
        const text_str = self.scene.textOf(id) orelse return;
        const text_len = @as(u32, @intCast(text_str.len));
        const sel = self.scene.selectionOf(idx);
        switch (key) {
            .left => {
                if (mods.shift) {
                    if (sel.active > 0) sel.active -= 1;
                } else {
                    const new_pos: u32 = if (sel.active > 0) sel.active - 1 else 0;
                    sel.* = .{ .anchor = new_pos, .active = new_pos };
                }
            },
            .right => {
                if (mods.shift) {
                    if (sel.active < text_len) sel.active += 1;
                } else {
                    const new_pos: u32 = if (sel.active < text_len) sel.active + 1 else text_len;
                    sel.* = .{ .anchor = new_pos, .active = new_pos };
                }
            },
            .home => {
                if (mods.shift) {
                    sel.active = 0;
                } else {
                    sel.* = .{ .anchor = 0, .active = 0 };
                }
            },
            .end => {
                if (mods.shift) {
                    sel.active = text_len;
                } else {
                    sel.* = .{ .anchor = text_len, .active = text_len };
                }
            },
            .a => {
                if (!mods.ctrl) return;
                sel.* = .{ .anchor = 0, .active = text_len };
            },
            .c => {
                if (!mods.ctrl) return;
                if (!sel.isEmpty()) {
                    const r = sel.range();
                    self.platform.setClipboard(text_str[r.lo..r.hi]);
                }
                return; // don't mark dirty
            },
            else => return,
        }
        if (idx < self.scene.elements.dirty.bit_length)
            self.scene.elements.dirty.set(idx);
    }

    /// R62: hit-test a .text element at mouse_x and return its byte offset.
    fn hitTestText(self: *AppInner, idx: u32, mouse_x: f32) u32 {
        if (idx >= self.scene.elements.layout.items.len) return 0;
        const id = mod07.ElementId{ .index = idx, .gen = self.scene.elements.gen.items[idx] };
        const layout_rect = self.scene.elements.layout.items[idx].computed;
        const text_str = self.scene.textOf(id) orelse return 0;
        if (text_str.len == 0) return 0;
        const style = self.scene.styleOf(id).*;
        const font = self.font_family.face(style.font_bold, style.font_italic);
        const para = mod02.layoutParagraph(self.gpa, font, &self.atlas_cpu, text_str, style.font_size, 1e6) catch return 0;
        defer self.gpa.free(para.glyphs);
        if (para.glyphs.len == 0) return 0;
        // If mouse is past the last glyph's right edge, return text_str.len.
        const last = para.glyphs[para.glyphs.len - 1];
        if (mouse_x > layout_rect.x + last.dest_x + last.dest_w) {
            return @intCast(text_str.len);
        }
        var best_offset: u32 = 0;
        var best_dist: f32 = std.math.inf(f32);
        for (para.glyphs) |g| {
            const mid_x = layout_rect.x + g.dest_x + g.dest_w / 2;
            const dist = @abs(mouse_x - mid_x);
            if (dist < best_dist) {
                best_dist = dist;
                best_offset = g.byte_offset;
            }
        }
        return best_offset;
    }

    // -----------------------------------------------------------------------
    // R63 — Textarea standalone helpers (methods for access to self.gpa / font_family)
    // -----------------------------------------------------------------------

    fn taLineHeight(self: *AppInner, idx: u32) f32 {
        if (idx >= self.scene._style.items.len) return 16.0;
        const style = self.scene._style.items[idx];
        const font = self.font_family.face(style.font_bold, style.font_italic);
        const fm = font.metrics(style.font_size);
        return fm.ascent + fm.descent + fm.line_gap;
    }
};

/// Rebuild line_starts from a block of text (R63).
/// Clears existing entries, then inserts byte 0 as first line, then scans for '\n'.
fn rebuildLineStarts(ts: *mod07.TextareaState, text: []const u8, gpa: std.mem.Allocator) void {
    ts.line_starts.clearRetainingCapacity();
    ts.line_starts.append(gpa, 0) catch return;
    for (text, 0..) |c, i| {
        if (c == '\n') {
            const next: u32 = @as(u32, @intCast(i + 1));
            if (next <= text.len and ts.line_starts.items.len < 1024) {
                ts.line_starts.append(gpa, next) catch return;
            }
        }
    }
}

/// Binary search: return the line index whose start is <= `offset`.
fn taLineOfByte(ts: *const mod07.TextareaState, offset: u32) u32 {
    const items = ts.line_starts.items;
    if (items.len == 0) return 0;
    var lo: u32 = 0;
    var hi: u32 = @as(u32, @intCast(items.len));
    while (lo + 1 < hi) {
        const mid = (lo + hi) / 2;
        if (items[mid] <= offset) {
            lo = mid;
        } else {
            hi = mid;
        }
    }
    return lo;
}

/// Adjust scroll_y so the cursor's line is visible (R63).
fn scrollToCursor(ts: *mod07.TextareaState, cursor: u32, line_h: f32) void {
    if (line_h <= 0) return;
    const line = taLineOfByte(ts, cursor);
    const cursor_y = @as(f32, @floatFromInt(line)) * line_h;
    if (cursor_y < ts.scroll_y) {
        ts.scroll_y = cursor_y;
    } else if (ts.container_h > 0 and cursor_y + line_h > ts.scroll_y + ts.container_h) {
        ts.scroll_y = cursor_y + line_h - ts.container_h;
    }
}
