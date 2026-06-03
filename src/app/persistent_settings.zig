//! R82 -- M8-03: Persistent settings.
//!
//! A line-oriented key-value store written to the platform user-data directory.
//! Windows: %APPDATA%\<app_name>\settings.txt
//! Linux:   $XDG_CONFIG_HOME/<app_name>/settings.txt  (or $HOME/.config/...)
//!
//! INV-5.6: All I/O via std.Io from the Zig standard library. No new deps.
//! INV-1.2: Platform selection uses builtin.os.tag at comptime.

const std = @import("std");
const builtin = @import("builtin");

pub const PersistentSettings = struct {
    gpa: std.mem.Allocator,
    /// Owned absolute path to the settings file.
    path: []const u8,
    entries: EntryMap,
    /// true when in-memory state diverges from disk.
    dirty: bool,
    /// Comment and blank lines from the original file, preserved on flush.
    /// Each slice is owned (duped from the file content).
    raw_comments: std.ArrayListUnmanaged([]const u8),

    pub const EntryMap = std.StringHashMapUnmanaged(Entry);

    pub const Entry = union(enum) {
        u32: u32,
        i32: i32,
        f32: f32,
        bool: bool,
        string: []const u8, // owned slice
    };

    // -----------------------------------------------------------------------
    // Construction / destruction
    // -----------------------------------------------------------------------

    /// Load settings from disk, creating the file (and parent dir) if missing.
    /// Returns `error.InvalidAppName` when app_name contains a path separator
    /// or is empty.
    pub fn load(gpa: std.mem.Allocator, app_name: []const u8) !PersistentSettings {
        if (app_name.len == 0 or app_name.len > 64) return error.InvalidAppName;
        for (app_name) |c| {
            if (c == '/' or c == '\\' or c == ':') return error.InvalidAppName;
        }

        var threaded = std.Io.Threaded.init(std.heap.page_allocator, .{});
        defer threaded.deinit();
        const io = threaded.io();

        const path = try resolveSettingsPath(gpa, io, app_name);
        errdefer gpa.free(path);

        return loadFromPath(gpa, io, path);
    }

    /// Load settings from an explicit absolute path.
    /// Duplicates `abs_path` internally so the caller need not keep it alive.
    pub fn loadAbsolute(gpa: std.mem.Allocator, abs_path: []const u8) !PersistentSettings {
        var threaded = std.Io.Threaded.init(std.heap.page_allocator, .{});
        defer threaded.deinit();
        const io = threaded.io();

        const owned_path = try gpa.dupe(u8, abs_path);
        errdefer gpa.free(owned_path);

        return loadFromPath(gpa, io, owned_path);
    }

    /// Internal: load from an owned absolute path (path ownership is transferred).
    fn loadFromPath(gpa: std.mem.Allocator, io: std.Io, owned_path: []const u8) !PersistentSettings {
        var entries = EntryMap{};
        errdefer freeEntries(gpa, &entries);

        var raw_comments: std.ArrayListUnmanaged([]const u8) = .empty;
        errdefer {
            for (raw_comments.items) |line| gpa.free(line);
            raw_comments.deinit(gpa);
        }

        // Ensure parent directory exists.
        const dir_path = std.fs.path.dirname(owned_path) orelse owned_path;
        std.Io.Dir.createDirPath(.cwd(), io, dir_path) catch |e| switch (e) {
            error.PathAlreadyExists => {},
            else => return e,
        };

        // Try to read the file; create empty if missing.
        const content: []const u8 = blk: {
            const c = std.Io.Dir.readFileAlloc(.cwd(), io, owned_path, gpa, .unlimited) catch |e| switch (e) {
                error.FileNotFound => {
                    const f = try std.Io.Dir.createFileAbsolute(io, owned_path, .{});
                    f.close(io);
                    break :blk "";
                },
                else => return e,
            };
            break :blk c;
        };
        defer {
            if (content.len > 0) gpa.free(content);
        }

        // Parse line by line.
        var lines = std.mem.splitScalar(u8, content, '\n');
        while (lines.next()) |raw_line| {
            const line = if (raw_line.len > 0 and raw_line[raw_line.len - 1] == '\r')
                raw_line[0 .. raw_line.len - 1]
            else
                raw_line;

            if (line.len == 0) {
                const dup = try gpa.dupe(u8, raw_line);
                errdefer gpa.free(dup);
                try raw_comments.append(gpa, dup);
                continue;
            }
            if (line[0] == '#') {
                const dup = try gpa.dupe(u8, raw_line);
                errdefer gpa.free(dup);
                try raw_comments.append(gpa, dup);
                continue;
            }

            const eq_idx = std.mem.indexOfScalar(u8, line, '=') orelse continue;
            const key = line[0..eq_idx];
            const raw_value = line[eq_idx + 1 ..];

            if (key.len == 0) continue;

            if (std.mem.startsWith(u8, raw_value, "u32:")) {
                const v = std.fmt.parseInt(u32, raw_value[4..], 10) catch continue;
                const key_dup = try gpa.dupe(u8, key);
                errdefer gpa.free(key_dup);
                try entries.put(gpa, key_dup, .{ .u32 = v });
            } else if (std.mem.startsWith(u8, raw_value, "i32:")) {
                const v = std.fmt.parseInt(i32, raw_value[4..], 10) catch continue;
                const key_dup = try gpa.dupe(u8, key);
                errdefer gpa.free(key_dup);
                try entries.put(gpa, key_dup, .{ .i32 = v });
            } else if (std.mem.startsWith(u8, raw_value, "f32:")) {
                const v = std.fmt.parseFloat(f32, raw_value[4..]) catch continue;
                const key_dup = try gpa.dupe(u8, key);
                errdefer gpa.free(key_dup);
                try entries.put(gpa, key_dup, .{ .f32 = v });
            } else if (std.mem.startsWith(u8, raw_value, "bool:")) {
                const word = raw_value[5..];
                const v: bool = if (std.mem.eql(u8, word, "true"))
                    true
                else if (std.mem.eql(u8, word, "false"))
                    false
                else
                    continue;
                const key_dup = try gpa.dupe(u8, key);
                errdefer gpa.free(key_dup);
                try entries.put(gpa, key_dup, .{ .bool = v });
            } else if (std.mem.startsWith(u8, raw_value, "str:")) {
                const decoded = try percentDecode(gpa, raw_value[4..]);
                errdefer gpa.free(decoded);
                const key_dup = try gpa.dupe(u8, key);
                errdefer gpa.free(key_dup);
                try entries.put(gpa, key_dup, .{ .string = decoded });
            }
            // Unknown prefix: silently ignore (forward-compat; not re-emitted on flush).
        }

        return PersistentSettings{
            .gpa = gpa,
            .path = owned_path,
            .entries = entries,
            .dirty = false,
            .raw_comments = raw_comments,
        };
    }

    /// Free all memory. Does NOT flush to disk; call flush() first if needed.
    pub fn deinit(self: *PersistentSettings) void {
        self.gpa.free(self.path);
        freeEntries(self.gpa, &self.entries);
        for (self.raw_comments.items) |line| self.gpa.free(line);
        self.raw_comments.deinit(self.gpa);
    }

    // -----------------------------------------------------------------------
    // Getters: return null on absent key or type mismatch.
    // -----------------------------------------------------------------------

    pub fn getU32(self: *const PersistentSettings, key: []const u8) ?u32 {
        return switch (self.entries.get(key) orelse return null) {
            .u32 => |v| v,
            else => null,
        };
    }

    pub fn getI32(self: *const PersistentSettings, key: []const u8) ?i32 {
        return switch (self.entries.get(key) orelse return null) {
            .i32 => |v| v,
            else => null,
        };
    }

    pub fn getF32(self: *const PersistentSettings, key: []const u8) ?f32 {
        return switch (self.entries.get(key) orelse return null) {
            .f32 => |v| v,
            else => null,
        };
    }

    pub fn getBool(self: *const PersistentSettings, key: []const u8) ?bool {
        return switch (self.entries.get(key) orelse return null) {
            .bool => |v| v,
            else => null,
        };
    }

    /// Returned slice is valid until the next set/flush/deinit call.
    pub fn getString(self: *const PersistentSettings, key: []const u8) ?[]const u8 {
        return switch (self.entries.get(key) orelse return null) {
            .string => |v| v,
            else => null,
        };
    }

    // -----------------------------------------------------------------------
    // Setters: mark dirty; do NOT write to disk immediately.
    // -----------------------------------------------------------------------

    pub fn setU32(self: *PersistentSettings, key: []const u8, value: u32) !void {
        std.debug.assert(key.len > 0);
        try putEntry(self.gpa, &self.entries, key, .{ .u32 = value });
        self.dirty = true;
    }

    pub fn setI32(self: *PersistentSettings, key: []const u8, value: i32) !void {
        std.debug.assert(key.len > 0);
        try putEntry(self.gpa, &self.entries, key, .{ .i32 = value });
        self.dirty = true;
    }

    pub fn setF32(self: *PersistentSettings, key: []const u8, value: f32) !void {
        std.debug.assert(key.len > 0);
        try putEntry(self.gpa, &self.entries, key, .{ .f32 = value });
        self.dirty = true;
    }

    pub fn setBool(self: *PersistentSettings, key: []const u8, value: bool) !void {
        std.debug.assert(key.len > 0);
        try putEntry(self.gpa, &self.entries, key, .{ .bool = value });
        self.dirty = true;
    }

    pub fn setString(self: *PersistentSettings, key: []const u8, value: []const u8) !void {
        std.debug.assert(key.len > 0);
        std.debug.assert(value.len <= 4096);
        const val_dup = try self.gpa.dupe(u8, value);
        errdefer self.gpa.free(val_dup);
        try putEntry(self.gpa, &self.entries, key, .{ .string = val_dup });
        self.dirty = true;
    }

    /// Remove a key. Does nothing if absent. Marks dirty only if key existed.
    pub fn remove(self: *PersistentSettings, key: []const u8) void {
        const kv = self.entries.fetchRemove(key) orelse return;
        self.gpa.free(kv.key);
        freeEntry(self.gpa, kv.value);
        self.dirty = true;
    }

    /// Write current state to disk atomically. A no-op when !dirty.
    /// Writes to a .tmp file then renames to avoid half-written files.
    pub fn flush(self: *PersistentSettings) !void {
        if (!self.dirty) return;

        var threaded = std.Io.Threaded.init(std.heap.page_allocator, .{});
        defer threaded.deinit();
        const io = threaded.io();

        const tmp_path = try std.fmt.allocPrint(self.gpa, "{s}.tmp", .{self.path});
        defer self.gpa.free(tmp_path);

        // Build content in memory first.
        var out_buf = std.Io.Writer.Allocating.init(self.gpa);
        defer out_buf.deinit();
        const w = &out_buf.writer;

        for (self.raw_comments.items) |line| {
            try w.writeAll(line);
            try w.writeByte('\n');
        }

        var iter = self.entries.iterator();
        while (iter.next()) |kv| {
            try w.writeAll(kv.key_ptr.*);
            try w.writeByte('=');
            switch (kv.value_ptr.*) {
                .u32 => |v| try w.print("u32:{d}", .{v}),
                .i32 => |v| try w.print("i32:{d}", .{v}),
                .f32 => |v| try w.print("f32:{d}", .{v}),
                .bool => |v| try w.print("bool:{s}", .{if (v) "true" else "false"}),
                .string => |v| {
                    try w.writeAll("str:");
                    try percentEncodeWriter(w, v);
                },
            }
            try w.writeByte('\n');
        }

        const content = try out_buf.toOwnedSlice();
        defer self.gpa.free(content);

        // Write atomically: tmp then rename.
        {
            const file = try std.Io.Dir.createFileAbsolute(io, tmp_path, .{ .truncate = true });
            defer file.close(io);
            try std.Io.File.writeStreamingAll(file, io, content);
        }

        try std.Io.Dir.renameAbsolute(tmp_path, self.path, io);
        self.dirty = false;
    }

    /// Returns true if in-memory state has been modified since the last flush/load.
    pub fn isDirty(self: *const PersistentSettings) bool {
        return self.dirty;
    }

    // -----------------------------------------------------------------------
    // Private helpers
    // -----------------------------------------------------------------------

    fn putEntry(gpa: std.mem.Allocator, map: *EntryMap, key: []const u8, value: Entry) !void {
        const gop = try map.getOrPut(gpa, key);
        if (gop.found_existing) {
            freeEntry(gpa, gop.value_ptr.*);
            gop.value_ptr.* = value;
        } else {
            gop.key_ptr.* = try gpa.dupe(u8, key);
            gop.value_ptr.* = value;
        }
    }

    fn freeEntry(gpa: std.mem.Allocator, entry: Entry) void {
        switch (entry) {
            .string => |s| gpa.free(s),
            else => {},
        }
    }

    fn freeEntries(gpa: std.mem.Allocator, map: *EntryMap) void {
        var iter = map.iterator();
        while (iter.next()) |kv| {
            gpa.free(kv.key_ptr.*);
            freeEntry(gpa, kv.value_ptr.*);
        }
        map.deinit(gpa);
    }

    fn resolveSettingsPath(gpa: std.mem.Allocator, io: std.Io, app_name: []const u8) ![]const u8 {
        _ = io;
        const env = std.process.Environ{ .block = .{ .use_global = true } };
        if (builtin.os.tag == .windows) {
            const appdata = try env.getAlloc(gpa, "APPDATA");
            defer gpa.free(appdata);
            return std.fs.path.join(gpa, &.{ appdata, app_name, "settings.txt" });
        } else {
            if (env.getAlloc(gpa, "XDG_CONFIG_HOME") catch null) |xdg| {
                defer gpa.free(xdg);
                return std.fs.path.join(gpa, &.{ xdg, app_name, "settings.txt" });
            }
            const home = try env.getAlloc(gpa, "HOME");
            defer gpa.free(home);
            return std.fs.path.join(gpa, &.{ home, ".config", app_name, "settings.txt" });
        }
    }
};

// ---------------------------------------------------------------------------
// Percent-encoding helpers (encode only % \r \n = characters).
// ---------------------------------------------------------------------------

fn percentEncodeWriter(w: anytype, s: []const u8) !void {
    for (s) |c| {
        switch (c) {
            '%' => try w.writeAll("%25"),
            '\r' => try w.writeAll("%0D"),
            '\n' => try w.writeAll("%0A"),
            '=' => try w.writeAll("%3D"),
            else => try w.writeByte(c),
        }
    }
}

fn percentDecode(gpa: std.mem.Allocator, s: []const u8) ![]u8 {
    var out: std.ArrayListUnmanaged(u8) = .empty;
    errdefer out.deinit(gpa);
    var i: usize = 0;
    while (i < s.len) {
        if (s[i] == '%' and i + 2 < s.len) {
            const hi = hexDigit(s[i + 1]) orelse {
                try out.append(gpa, s[i]);
                i += 1;
                continue;
            };
            const lo = hexDigit(s[i + 2]) orelse {
                try out.append(gpa, s[i]);
                i += 1;
                continue;
            };
            try out.append(gpa, (hi << 4) | lo);
            i += 3;
        } else {
            try out.append(gpa, s[i]);
            i += 1;
        }
    }
    return out.toOwnedSlice(gpa);
}

fn hexDigit(c: u8) ?u8 {
    return switch (c) {
        '0'...'9' => c - '0',
        'A'...'F' => c - 'A' + 10,
        'a'...'f' => c - 'a' + 10,
        else => null,
    };
}
