//! FileWatcher — mtime-based file watcher for hot-reload (R56).
//!
//! Uses main-thread polling (one stat() call per file per frame).
//! No background thread, no OS-native file events (those are post-v1).
//! All hot-reload code is behind the comptime `build_options.hot_reload` gate
//! in app.zig; this file only exists in the hot-reload build variant.

const std = @import("std");

/// A watched file entry. Stores the last-seen mtime so changes can be detected.
pub const WatchEntry = struct {
    path:       [:0]const u8,   // null-terminated for OS stat calls
    last_mtime: i96 = 0,        // nanoseconds from Io.Timestamp (Zig 0.16)
};

pub const FileWatcher = struct {
    entries:  std.ArrayListUnmanaged(WatchEntry),
    changed:  std.ArrayListUnmanaged(u32),  // indices of entries that changed since last poll
    gpa:      std.mem.Allocator,

    pub fn init(gpa: std.mem.Allocator) FileWatcher {
        return FileWatcher{
            .entries = .empty,
            .changed = .empty,
            .gpa     = gpa,
        };
    }

    pub fn deinit(self: *FileWatcher) void {
        for (self.entries.items) |e| self.gpa.free(e.path);
        self.entries.deinit(self.gpa);
        self.changed.deinit(self.gpa);
    }

    /// Add a file to watch. Path is copied (null-terminated); caller need not keep it alive.
    pub fn addFile(self: *FileWatcher, path: []const u8) !void {
        // Allocate a null-terminated copy.
        const owned: [:0]u8 = try self.gpa.allocSentinel(u8, path.len, 0);
        @memcpy(owned[0..path.len], path);
        try self.entries.append(self.gpa, .{
            .path       = owned,
            .last_mtime = 0,
        });
    }

    /// Poll all watched files for mtime changes.
    /// Appends the indices of changed files to `self.changed`.
    /// Call once per frame on the main thread.
    pub fn poll(self: *FileWatcher) void {
        self.changed.clearRetainingCapacity();
        for (self.entries.items, 0..) |*entry, i| {
            const mtime = statMtime(entry.path) orelse continue;
            if (mtime != entry.last_mtime) {
                entry.last_mtime = mtime;
                self.changed.append(self.gpa, @intCast(i)) catch {};
            }
        }
    }

    /// Drain the changed-file list. Returns a slice of entry indices; valid until next poll.
    pub fn drainChanged(self: *FileWatcher) []const u32 {
        return self.changed.items;
    }
};

/// Read the modification time of a file. Returns null if the file cannot be stat'd.
/// Uses std.Io.Dir.statFile via a Threaded Io instance (Zig 0.16 API).
fn statMtime(path: [:0]const u8) ?i96 {
    var threaded = std.Io.Threaded.init(std.heap.page_allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();
    const cwd = std.Io.Dir.cwd();
    const st = std.Io.Dir.statFile(cwd, io, path, .{}) catch return null;
    return st.mtime.nanoseconds;
}
