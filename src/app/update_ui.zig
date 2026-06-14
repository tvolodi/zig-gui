// Update UI — M19-04
// State machine and toast integration for the auto-update pipeline.
//
// UpdateManager drives the lifecycle:
//   idle → checking → available → downloading → ready_to_restart
//                                             ↘ error_state
//
// Typical usage from app startup:
//   1. Call `manager.checkAsync(io, manifest_url, current_version)` on a background thread
//      or deferred to after first frame.
//   2. Each frame, call `manager.toastMessage()` — if non-null, show it as a toast.
//   3. When the user clicks the toast action (if state == .available), call
//      `manager.downloadAndStage(io, binary_path)`.
//   4. When state == .ready_to_restart, inform the user and optionally call
//      `staged_update.applyPendingUpdate(binary_path)` on next launch.

const std = @import("std");
const update_check = @import("../tools/update_check.zig");
const delta_download = @import("../tools/delta_download.zig");
const staged_update = @import("../tools/staged_update.zig");

pub const UpdateState = enum {
    idle,
    checking,
    available,
    downloading,
    ready_to_restart,
    error_state,
};

pub const UpdateManager = struct {
    state: UpdateState = .idle,
    /// Owned slice; valid when state == .available or later. Free via deinit().
    latest_version: []const u8 = &[_]u8{},
    /// Owned slice; valid when state == .available or later. Free via deinit().
    download_url: []const u8 = &[_]u8{},
    /// 0.0–1.0 progress fraction; updated during .downloading state.
    download_progress: f32 = 0.0,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) UpdateManager {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *UpdateManager) void {
        if (self.latest_version.len > 0) self.allocator.free(self.latest_version);
        if (self.download_url.len > 0) self.allocator.free(self.download_url);
        self.* = undefined;
    }

    /// Check for updates. Designed to be called from a background thread or a
    /// deferred async context — it performs a blocking HTTP request.
    ///
    /// io:              std.Io handle (required by std.http.Client in Zig 0.16)
    /// manifest_url:    URL of the JSON update manifest
    /// current_version: the running app's version string (e.g. "1.0.0")
    pub fn checkAsync(
        self: *UpdateManager,
        io: std.Io,
        manifest_url: []const u8,
        current_version: []const u8,
    ) void {
        self.state = .checking;
        const result = update_check.checkForUpdate(
            self.allocator,
            io,
            manifest_url,
            current_version,
        ) catch {
            self.state = .error_state;
            return;
        };

        if (result) |r| {
            self.latest_version = r.latest_version;
            self.download_url = r.download_url;
            self.state = .available;
        } else {
            self.state = .idle;
        }
    }

    /// Download the patch and stage the update. Designed to be called after the user
    /// confirms via the toast action (when state == .available). Blocking — run on a
    /// background thread in a real app.
    ///
    /// io:          std.Io handle (required by std.http.Client in Zig 0.16)
    /// binary_path: path to the current binary (used to locate it and stage next to it)
    pub fn downloadAndStage(
        self: *UpdateManager,
        io: std.Io,
        binary_path: []const u8,
    ) void {
        self.state = .downloading;
        self.download_progress = 0.0;

        const patch = delta_download.downloadAndApplyPatch(
            self.allocator,
            io,
            self.download_url,
            binary_path,
            null,
        ) catch {
            self.state = .error_state;
            return;
        };
        defer patch.deinit();

        self.download_progress = 1.0;

        staged_update.stageUpdate(binary_path, patch.new_binary) catch {
            self.state = .error_state;
            return;
        };

        self.state = .ready_to_restart;
    }

    /// Returns the toast message string appropriate for the current update state,
    /// or null if no toast should be shown. Wire this into the app's per-frame
    /// toast check.
    ///
    /// The returned slice is a string literal — it is never freed.
    pub fn toastMessage(self: *const UpdateManager) ?[]const u8 {
        return switch (self.state) {
            .available => "Update available — click to download",
            .downloading => "Downloading update...",
            .ready_to_restart => "Update ready — restart to apply",
            .error_state => "Update check failed",
            else => null,
        };
    }
};
