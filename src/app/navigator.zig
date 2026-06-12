//! Navigator — stack-based screen navigation model (R80 / M8-01).
//!
//! Tracks a registry of named screens and a history stack.
//! Navigation from inside a frame must use request* methods (deferred);
//! drainPending() is called at the top of each frame by runWithNav.
//!
//! NOTE: AppInner is defined in app.zig which imports this file, so we cannot
//! import app.zig here (would create a circular build dependency). Instead,
//! app.zig re-exports the properly typed ScreenFn alias with *AppInner.
//! The raw function pointer type here uses *anyopaque for the app parameter.

const std = @import("std");

const mod07 = @import("../07/types.zig");
pub const Scene = mod07.Scene;

const mod05 = @import("../05/types.zig");
pub const Tokens = mod05.Tokens;

// ---------------------------------------------------------------------------
// Public types
// ---------------------------------------------------------------------------

/// A function that (re-)builds a scene for one named screen.
/// Called by Navigator.push / Navigator.pop / Navigator.replace after scene.reset().
/// `app` is the AppInner pointer (typed as anyopaque to avoid circular imports;
///   app.zig re-exports a typed ScreenFn alias as *AppInner).
/// `ctx` is an opaque pointer to the per-screen argument struct.
pub const ScreenFn = *const fn (
    scene: *Scene,
    tokens: Tokens,
    app: *anyopaque,
    ctx: ?*anyopaque,
) anyerror!void;

/// Registered screen descriptor.
pub const ScreenEntry = struct {
    name: []const u8, // owned slice (duped from the string literal at register time)
    build: ScreenFn,
};

/// One entry in the history stack.
pub const NavEntry = struct {
    screen_idx: u32, // index into Navigator.screens
    ctx: ?*anyopaque, // caller-owned argument pointer; may be null
};

/// Pending deferred navigation — set by request* methods, drained each frame.
pub const PendingNav = union(enum) {
    none,
    push: struct { name: []const u8, ctx: ?*anyopaque },
    pop,
    replace: struct { name: []const u8, ctx: ?*anyopaque },
};

// ---------------------------------------------------------------------------
// Navigator
// ---------------------------------------------------------------------------

pub const Navigator = struct {
    gpa: std.mem.Allocator,
    screens: std.ArrayListUnmanaged(ScreenEntry),
    stack: std.ArrayListUnmanaged(NavEntry),
    pending: PendingNav = .none,

    pub fn init(gpa: std.mem.Allocator) Navigator {
        return Navigator{
            .gpa = gpa,
            .screens = .empty,
            .stack = .empty,
            .pending = .none,
        };
    }

    pub fn deinit(self: *Navigator) void {
        // Free duped name slices.
        for (self.screens.items) |entry| {
            self.gpa.free(entry.name);
        }
        self.screens.deinit(self.gpa);
        self.stack.deinit(self.gpa);
    }

    /// Register a named screen. Names must be unique — duplicate is a
    /// programming error (asserts/panics in debug, returns error.DuplicateName in release).
    pub fn register(self: *Navigator, name: []const u8, build: ScreenFn) !void {
        // Check for duplicate.
        for (self.screens.items) |entry| {
            if (std.mem.eql(u8, entry.name, name)) {
                if (@import("builtin").mode == .Debug) {
                    std.debug.panic("Navigator.register: duplicate screen name '{s}'", .{name});
                }
                return error.DuplicateName;
            }
        }
        const owned_name = try self.gpa.dupe(u8, name);
        errdefer self.gpa.free(owned_name);
        try self.screens.append(self.gpa, .{ .name = owned_name, .build = build });
    }

    /// Find screen index by name. Returns null if not found.
    fn findScreen(self: *const Navigator, name: []const u8) ?u32 {
        for (self.screens.items, 0..) |entry, i| {
            if (std.mem.eql(u8, entry.name, name)) {
                return @intCast(i);
            }
        }
        return null;
    }

    /// Push a new screen onto the history stack.
    /// Resets the scene, calls the screen's ScreenFn, and pushes onto the stack.
    /// Returns error.ScreenNotFound if the name is not registered.
    pub fn push(
        self: *Navigator,
        name: []const u8,
        ctx: ?*anyopaque,
        scene: *Scene,
        tokens: Tokens,
        app: *anyopaque,
    ) !void {
        const idx = self.findScreen(name) orelse return error.ScreenNotFound;
        scene.reset();
        try self.screens.items[idx].build(scene, tokens, app, ctx);
        try self.stack.append(self.gpa, .{ .screen_idx = idx, .ctx = ctx });
    }

    /// Pop the current screen. Restores the previous screen (calls its ScreenFn again).
    /// Returns error.EmptyStack if the stack has only one entry.
    pub fn pop(
        self: *Navigator,
        scene: *Scene,
        tokens: Tokens,
        app: *anyopaque,
    ) !void {
        if (self.stack.items.len <= 1) return error.EmptyStack;
        _ = self.stack.pop();
        const top = self.stack.items[self.stack.items.len - 1];
        const entry = &self.screens.items[top.screen_idx];
        scene.reset();
        try entry.build(scene, tokens, app, top.ctx);
    }

    /// Replace the current top of stack without adding a history entry.
    /// Equivalent to pop() + push() but does not error on a single-entry stack.
    pub fn replace(
        self: *Navigator,
        name: []const u8,
        ctx: ?*anyopaque,
        scene: *Scene,
        tokens: Tokens,
        app: *anyopaque,
    ) !void {
        const idx = self.findScreen(name) orelse return error.ScreenNotFound;
        scene.reset();
        try self.screens.items[idx].build(scene, tokens, app, ctx);
        if (self.stack.items.len > 0) {
            // Replace the top entry in place.
            self.stack.items[self.stack.items.len - 1] = .{ .screen_idx = idx, .ctx = ctx };
        } else {
            // Empty stack — push first entry.
            try self.stack.append(self.gpa, .{ .screen_idx = idx, .ctx = ctx });
        }
    }

    /// Return the name of the current screen, or null if the stack is empty.
    pub fn currentName(self: *const Navigator) ?[]const u8 {
        if (self.stack.items.len == 0) return null;
        const top = self.stack.items[self.stack.items.len - 1];
        return self.screens.items[top.screen_idx].name;
    }

    /// Return the stack depth (number of entries).
    pub fn depth(self: *const Navigator) usize {
        return self.stack.items.len;
    }

    // -----------------------------------------------------------------------
    // Deferred navigation (called from within frame callbacks)
    // -----------------------------------------------------------------------

    /// Queue a push to be applied at the start of the next frame.
    /// Last-write-wins: overwrites any previous pending request.
    pub fn requestPush(self: *Navigator, name: []const u8, ctx: ?*anyopaque) void {
        self.pending = .{ .push = .{ .name = name, .ctx = ctx } };
    }

    /// Queue a pop to be applied at the start of the next frame.
    pub fn requestPop(self: *Navigator) void {
        self.pending = .pop;
    }

    /// Queue a replace to be applied at the start of the next frame.
    pub fn requestReplace(self: *Navigator, name: []const u8, ctx: ?*anyopaque) void {
        self.pending = .{ .replace = .{ .name = name, .ctx = ctx } };
    }

    // -----------------------------------------------------------------------
    // RA0 — Error boundary integration
    // -----------------------------------------------------------------------

    /// Push a new screen with error boundary protection.
    /// When `boundary.call(...)` returns false:
    ///   1. scene.reset() is called.
    ///   2. buildFallbackScreen is called.
    ///   3. The failed screen does NOT appear on the stack.
    ///   4. Returns normally (original error captured in `boundary`).
    /// Returns error.ScreenNotFound if the name is not registered.
    pub fn pushWithBoundary(
        self: *Navigator,
        name: []const u8,
        ctx: ?*anyopaque,
        scene: *Scene,
        tokens: Tokens,
        app: *anyopaque,
        boundary: *@import("error_boundary.zig").ErrorBoundary,
    ) !void {
        const idx = self.findScreen(name) orelse return error.ScreenNotFound;
        scene.reset();
        const ok = boundary.call(self.screens.items[idx].build, scene, tokens, app, ctx);
        if (!ok) {
            // Call failed: build fallback scene. Do NOT push onto stack.
            scene.reset();
            @import("error_boundary.zig").buildFallbackScreen(boundary, scene, tokens);
            return;
        }
        try self.stack.append(self.gpa, .{ .screen_idx = idx, .ctx = ctx });
    }

    /// Drain any pending navigation request. Called by runWithNav at the top of each frame.
    pub fn drainPending(self: *Navigator, scene: *Scene, tokens: Tokens, app: *anyopaque) !void {
        const p = self.pending;
        if (p == .none) return;
        self.pending = .none;
        switch (p) {
            .none => {},
            .push => |info| try self.push(info.name, info.ctx, scene, tokens, app),
            .pop => try self.pop(scene, tokens, app),
            .replace => |info| try self.replace(info.name, info.ctx, scene, tokens, app),
        }
    }

    /// Drain pending navigation with error boundary protection (RA0).
    /// Push/replace operations use pushWithBoundary; pop is unchanged.
    pub fn drainPendingWithBoundary(
        self: *Navigator,
        scene: *Scene,
        tokens: Tokens,
        app: *anyopaque,
        boundary: *@import("error_boundary.zig").ErrorBoundary,
    ) !void {
        const p = self.pending;
        if (p == .none) return;
        self.pending = .none;
        switch (p) {
            .none => {},
            .push => |info| try self.pushWithBoundary(info.name, info.ctx, scene, tokens, app, boundary),
            .pop => try self.pop(scene, tokens, app),
            .replace => |info| try self.pushWithBoundary(info.name, info.ctx, scene, tokens, app, boundary),
        }
    }
};
