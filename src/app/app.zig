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

const mod01 = @import("../01/types.zig");
const mod02 = @import("../02/types.zig");
const mod04 = @import("../04/types.zig");
const mod05 = @import("../05/types.zig");
const mod07 = @import("../07/types.zig");
const mod09 = @import("../09/types.zig");

pub const Event = mod01.InputEvent;
pub const EventQueue = events_mod.EventQueue;

/// Application startup options (R10).
pub const AppOptions = struct {
    window: mod01.WindowOptions = .{},
    /// Path to a .ttf file; read with std.fs.cwd().readFileAlloc.
    font_path: []const u8,
    font_size_px: f32 = 16,
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

// Scratch buffer size for layout engine (1 MiB).
const SCRATCH_SIZE: usize = 1024 * 1024;

/// Framebuffer resize callback (R12).  Writes new_size into pending_resize via AppInner pointer.
/// callconv(.c) not required here since this is called through our own function pointer, not
/// directly from C. But we store it as a *const fn(*anyopaque, Extent2D) void.
fn framebufferSizeCallback(user_data: *anyopaque, size: Extent2D) void {
    const pending: *?Extent2D = @ptrCast(@alignCast(user_data));
    pending.* = size;
}

/// Public implementation struct.  Exposed as `App._inner` through types.zig.
pub const AppInner = struct {
    gpa: std.mem.Allocator,

    // Subsystems — init order matches R10 exactly.
    platform: Platform,
    backend: VulkanBackend,
    font: Font,
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

    // R41 — Overlay layer (second draw pass).
    overlay: OverlayLayer,

    // R43 — Image atlas (CPU + GPU).
    image_atlas: ImageAtlas,
    image_atlas_generation_seen: u32,
    gpu_image_atlas: GpuImageAtlas,

    // Theme tokens — needed for pseudo-state resolution in buildDrawList (R40).
    tokens: Tokens,

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
        const font_bytes = std.fs.cwd().readFileAlloc(gpa, opts.font_path, 16 * 1024 * 1024) catch |err| {
            std.log.err("Failed to read font file '{s}': {}", .{ opts.font_path, err });
            return err;
        };
        defer gpa.free(font_bytes);

        // Step 5: Font.init.
        var font = try Font.init(gpa, font_bytes, opts.font_size_px);
        errdefer font.deinit();

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
        const draw_list = std.ArrayList(DrawCommand).init(gpa);

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
            .font = font,
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

        return self;
    }

    // -----------------------------------------------------------------------
    // Run (frame loop)
    // -----------------------------------------------------------------------

    pub fn run(self: *AppInner) void {
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

            // M2-02: Skip GPU work when nothing has changed.
            if (!self.scene.elements.hasDirty()) {
                self.platform.waitEvents(); // yield until the OS wakes us
                continue;
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

            // Measure text (module 07).
            self.scene.measurePass(&self.font, &self.atlas_cpu) catch {};

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

            // Build draw list (module 09).
            // Fire queued callbacks after layout, before render (INV-3.3).
            self.scene.fireQueuedCallbacks();

            // R40: Sync PseudoState from widget state before building draw list.
            self.syncPseudoStates();

            // buildDrawList returns a caller-owned slice; we use it and free it.
            const main_cmds = mod09.buildDrawList(
                self.gpa,
                &self.scene,
                &self.atlas_cpu,
                &self.image_atlas,
                &self.font,
                self.tokens,
            ) catch blk: {
                break :blk @as([]DrawCommand, &[_]DrawCommand{});
            };
            defer if (main_cmds.len > 0) self.gpa.free(main_cmds);

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

            // R43: Track image atlas generation (stub upload for v1).
            if (self.image_atlas.generation != self.image_atlas_generation_seen) {
                // For v1: upload is a stub; in a real GPU build this would call GpuImageAtlas.upload.
                self.image_atlas_generation_seen = self.image_atlas.generation;
            }

            // Render.
            self.backend.clear(Color{ .r = 0, .g = 0, .b = 0, .a = 1 });
            self.backend.drawFrame(all_cmds, &self.atlas_gpu, &self.gpu_image_atlas);
            self.backend.endFrame();

            // M2-02: Clear dirty bits — every dirty element was just painted.
            self.scene.elements.dirty.unsetAll();
        }
    }

    // -----------------------------------------------------------------------
    // Deinit (reverse init order, R10)
    // -----------------------------------------------------------------------

    pub fn deinit(self: *AppInner) void {
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
        // 4. font
        self.font.deinit();
        // 5. scratch
        self.gpa.free(self.scratch);
        // 6. draw_list
        self.draw_list.deinit();
        // 7. event_queue
        self.event_queue.deinit();
        // 8. backend (quad pipeline first, then backend)
        self.backend.deinitQuadPipeline();
        self.backend.deinit();
        // 9. platform
        self.platform.deinit();
    }

    // -----------------------------------------------------------------------
    // Binding refresh (M2-04)
    // -----------------------------------------------------------------------

    fn refreshBindings(self: *AppInner) void {
        self.bindings.refresh(&self.scene);
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
                },
                .mouse_button => |mb| {
                    if (mb.button == .left) {
                        if (mb.action == .press) {
                            self.left_mouse_down = true;
                            self.handleMousePress(mb.x, mb.y);
                        } else {
                            self.handleMouseRelease(mb.x, mb.y);
                            self.left_mouse_down = false;
                        }
                    }
                },
                .scroll => |sc| {
                    self.handleScroll(sc.dx, sc.dy);
                },
                .key => |k| {
                    if (k.action == .press) {
                        self.handleKey(k.key, k.mods);
                    }
                },
                .char => |ch| {
                    self.handleChar(ch.codepoint);
                },
            }
        }
    }

    /// Hit-test: find the topmost focusable element at (x, y). Returns idx or maxInt(u32).
    fn hitTestFocusable(self: *AppInner, x: f32, y: f32) u32 {
        const NONE = std.math.maxInt(u32);
        for (self.scene.focusable_indices.items) |idx| {
            if (idx >= self.scene.elements.layout.items.len) continue;
            const rect = self.scene.elements.layout.items[idx].computed;
            if (x >= rect.x and x < rect.x + rect.w and
                y >= rect.y and y < rect.y + rect.h)
            {
                return idx;
            }
        }
        return NONE;
    }

    fn updateHoverStates(self: *AppInner, x: f32, y: f32) void {
        for (self.scene.focusable_indices.items) |idx| {
            if (idx >= self.scene.elements.layout.items.len) continue;
            const rect = self.scene.elements.layout.items[idx].computed;
            const hit = x >= rect.x and x < rect.x + rect.w and
                y >= rect.y and y < rect.y + rect.h;
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
        const hit = self.hitTestFocusable(x, y);
        // Focus the hit element (or clear focus if none).
        self.scene.setFocus(hit);
        if (hit == NONE) return;
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
            else => {},
        }
    }

    fn handleMouseRelease(self: *AppInner, x: f32, y: f32) void {
        const NONE = std.math.maxInt(u32);
        _ = x;
        _ = y;
        // Activate any pressed button/checkbox under the cursor.
        for (self.scene.focusable_indices.items) |idx| {
            const kind = self.scene.kindOfIdx(idx);
            switch (kind) {
                .button => {
                    const st = self.scene.buttonStateOf(idx);
                    if (st.pressed) {
                        st.pressed = false;
                        if (st.hovered and !st.disabled) {
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
                        if (st.hovered and !st.disabled) {
                            st.checked = !st.checked;
                        }
                        if (idx < self.scene.elements.dirty.bit_length)
                            self.scene.elements.dirty.set(idx);
                    }
                },
                else => {},
            }
        }
        _ = NONE;
    }

    fn handleScroll(self: *AppInner, dx: f32, dy: f32) void {
        // Scroll whichever scrollview is under the cursor.
        for (0..self.scene._kind.items.len) |i| {
            const idx = @as(u32, @intCast(i));
            if (self.scene.kindOfIdx(idx) != .scrollview) continue;
            if (idx >= self.scene.elements.layout.items.len) continue;
            const rect = self.scene.elements.layout.items[idx].computed;
            if (self.last_cursor_x >= rect.x and self.last_cursor_x < rect.x + rect.w and
                self.last_cursor_y >= rect.y and self.last_cursor_y < rect.y + rect.h)
            {
                const ss = self.scene.scrollStateOf(idx);
                self.scene.setScrollOffset(idx, ss.scroll_y - dy * 16.0, ss.scroll_x - dx * 16.0);
                break;
            }
        }
    }

    fn handleKey(self: *AppInner, key: mod01.Key, mods: mod01.Modifiers) void {
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
            .dropdown => self.handleDropdownKey(focused, key, mods),
            .checkbox => self.handleCheckboxKey(focused, key),
            else => {},
        }
    }

    fn handleChar(self: *AppInner, codepoint: u21) void {
        const focused = self.scene.focused_idx;
        const NONE = std.math.maxInt(u32);
        if (focused == NONE) return;
        if (self.scene.kindOfIdx(focused) != .input) return;
        const inp = self.scene.inputStateOf(focused);
        if (!inp.active) return;
        // Encode codepoint to UTF-8.
        var buf: [4]u8 = undefined;
        const len = std.unicode.utf8Encode(codepoint, &buf) catch return;
        // Delete selection if any.
        if (inp.selection_start != inp.cursor) {
            const lo = @min(inp.selection_start, inp.cursor);
            const hi = @max(inp.selection_start, inp.cursor);
            inp.text.replaceRange(self.gpa, lo, hi - lo, &[_]u8{}) catch return;
            inp.cursor = lo;
            inp.selection_start = lo;
        }
        inp.text.insertSlice(self.gpa, inp.cursor, buf[0..len]) catch return;
        inp.cursor += @as(u32, @intCast(len));
        inp.selection_start = inp.cursor;
        if (focused < self.scene.elements.dirty.bit_length)
            self.scene.elements.dirty.set(focused);
    }

    fn handleInputKey(self: *AppInner, idx: u32, key: mod01.Key, mods: mod01.Modifiers) void {
        const inp = self.scene.inputStateOf(idx);
        const text_len = @as(u32, @intCast(inp.text.items.len));
        switch (key) {
            .backspace => {
                if (inp.selection_start != inp.cursor) {
                    // Delete selection.
                    const lo = @min(inp.selection_start, inp.cursor);
                    const hi = @max(inp.selection_start, inp.cursor);
                    inp.text.replaceRange(self.gpa, lo, hi - lo, &[_]u8{}) catch return;
                    inp.cursor = lo;
                    inp.selection_start = lo;
                } else if (inp.cursor > 0) {
                    inp.cursor -= 1;
                    inp.text.replaceRange(self.gpa, inp.cursor, 1, &[_]u8{}) catch return;
                    inp.selection_start = inp.cursor;
                }
            },
            .delete => {
                if (inp.selection_start != inp.cursor) {
                    const lo = @min(inp.selection_start, inp.cursor);
                    const hi = @max(inp.selection_start, inp.cursor);
                    inp.text.replaceRange(self.gpa, lo, hi - lo, &[_]u8{}) catch return;
                    inp.cursor = lo;
                    inp.selection_start = lo;
                } else if (inp.cursor < text_len) {
                    inp.text.replaceRange(self.gpa, inp.cursor, 1, &[_]u8{}) catch return;
                }
            },
            .left => {
                if (!mods.shift and inp.selection_start != inp.cursor) {
                    // Collapse selection to left end (C4).
                    inp.cursor = @min(inp.selection_start, inp.cursor);
                } else if (inp.cursor > 0) {
                    inp.cursor -= 1;
                }
                if (!mods.shift) inp.selection_start = inp.cursor;
            },
            .right => {
                if (!mods.shift and inp.selection_start != inp.cursor) {
                    // Collapse selection to right end (C4).
                    inp.cursor = @max(inp.selection_start, inp.cursor);
                } else if (inp.cursor < text_len) {
                    inp.cursor += 1;
                }
                if (!mods.shift) inp.selection_start = inp.cursor;
            },
            .home => {
                inp.cursor = 0;
                if (!mods.shift) inp.selection_start = 0;
            },
            .end => {
                inp.cursor = text_len;
                if (!mods.shift) inp.selection_start = text_len;
            },
            .c => {
                if (mods.ctrl) {
                    // Copy selection to clipboard.
                    const lo = @min(inp.selection_start, inp.cursor);
                    const hi = @max(inp.selection_start, inp.cursor);
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
                    if (inp.selection_start != inp.cursor) {
                        const lo = @min(inp.selection_start, inp.cursor);
                        const hi = @max(inp.selection_start, inp.cursor);
                        inp.text.replaceRange(self.gpa, lo, hi - lo, &[_]u8{}) catch return;
                        inp.cursor = lo;
                        inp.selection_start = lo;
                    }
                    inp.text.insertSlice(self.gpa, inp.cursor, clip) catch return;
                    inp.cursor += @as(u32, @intCast(clip.len));
                    inp.selection_start = inp.cursor;
                }
            },
            .x => {
                if (mods.ctrl) {
                    // Cut: copy then delete selection.
                    const lo = @min(inp.selection_start, inp.cursor);
                    const hi = @max(inp.selection_start, inp.cursor);
                    if (hi > lo) {
                        self.platform.setClipboard(inp.text.items[lo..hi]);
                        inp.text.replaceRange(self.gpa, lo, hi - lo, &[_]u8{}) catch return;
                        inp.cursor = lo;
                        inp.selection_start = lo;
                    }
                }
            },
            .a => {
                if (mods.ctrl) {
                    // Select all.
                    inp.selection_start = 0;
                    inp.cursor = text_len;
                }
            },
            else => return, // No dirty mark for unhandled keys.
        }
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
};
