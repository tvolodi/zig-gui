// Staged update — M19-03
// Writes the new binary to a temp path and schedules atomic rename on next launch.
//
// Pattern mirrors PersistentSettings.flush(): write-to-temp then rename.
// On Windows, fs.rename over an existing file requires the old file to be deleted first
// (Windows does not support atomic over-rename). Both paths are handled.

const std = @import("std");

pub const StagedUpdateError = error{
    WriteError,
    OutOfMemory,
};

/// Write `new_binary` to `<binary_path>.update` and create a sentinel marker file
/// `<binary_path>.update.pending` so the launcher can detect and apply the update on
/// next startup (via `applyPendingUpdate`).
///
/// binary_path: absolute or relative path to the currently-running binary
/// new_binary:  the patched binary bytes to stage
pub fn stageUpdate(
    binary_path: []const u8,
    new_binary: []const u8,
) StagedUpdateError!void {
    var tmp_buf: [std.fs.max_path_bytes]u8 = undefined;
    var sentinel_buf: [std.fs.max_path_bytes]u8 = undefined;

    const tmp_path = std.fmt.bufPrint(&tmp_buf, "{s}.update", .{binary_path}) catch
        return StagedUpdateError.WriteError;
    const sentinel_path = std.fmt.bufPrint(&sentinel_buf, "{s}.update.pending", .{binary_path}) catch
        return StagedUpdateError.WriteError;

    // Write staged binary
    const tmp_file = std.fs.cwd().createFile(tmp_path, .{}) catch
        return StagedUpdateError.WriteError;
    defer tmp_file.close();
    tmp_file.writeAll(new_binary) catch return StagedUpdateError.WriteError;

    // Write sentinel so the launcher knows to apply on next startup
    const sentinel = std.fs.cwd().createFile(sentinel_path, .{}) catch
        return StagedUpdateError.WriteError;
    sentinel.close();
}

/// Called at app startup: if `<binary_path>.update` and `<binary_path>.update.pending`
/// both exist, atomically replace the binary (or copy+delete on Windows) and remove the
/// sentinel. Returns true if an update was applied; the caller should notify the user
/// (e.g. "App updated to v1.2.3 — please restart if you see issues").
///
/// Call this before any UI is shown, immediately after entering main().
pub fn applyPendingUpdate(binary_path: []const u8) bool {
    var tmp_buf: [std.fs.max_path_bytes]u8 = undefined;
    var sentinel_buf: [std.fs.max_path_bytes]u8 = undefined;

    const tmp_path = std.fmt.bufPrint(&tmp_buf, "{s}.update", .{binary_path}) catch return false;
    const sentinel_path = std.fmt.bufPrint(&sentinel_buf, "{s}.update.pending", .{binary_path}) catch return false;

    // Bail if the sentinel is absent — nothing to apply
    std.fs.cwd().access(sentinel_path, .{}) catch return false;

    // Attempt atomic rename (works on POSIX; may fail on Windows over an existing file)
    std.fs.cwd().rename(tmp_path, binary_path) catch {
        // Windows fallback: delete the current binary first, then rename the staged one
        std.fs.cwd().deleteFile(binary_path) catch {};
        std.fs.cwd().rename(tmp_path, binary_path) catch return false;
    };

    // Remove the sentinel so we don't try again next launch
    std.fs.cwd().deleteFile(sentinel_path) catch {};
    return true;
}
