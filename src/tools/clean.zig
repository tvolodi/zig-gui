//! Project-wide cleanup tool — deletes temporary artifacts scattered across
//! the project tree. Wired into `zig build clean` from build.zig.
//!
//! Removes, in order:
//!   1. Root-level directories matching `^[\w-]{13,}$`
//!      (std.testing.TmpDir artifacts created by Zig 0.16 at CWD)
//!   2. docs/.agent-context/ (orchestrator handoff files)
//!   3. dist/ (package output)
//!   4. test-results/ (visual validation PNGs)
//!   5. .zig-cache/, zig-cache/, zig-pkg/, zig-out/, build/ (build artifacts)
//!
//! Cross-platform (Windows / Linux / macOS).
//!
//! Idempotent: missing directories are reported as warnings, not errors.

const std = @import("std");
const Io = std.Io;

/// Matches Zig std.testing.TmpDir directory names: 13+ chars of
/// [A-Za-z0-9_-] (alphanumeric + underscore + hyphen), anchored at root.
/// Named dirs in the project (e.g. `src`, `docs`, `vendor`, `deps`) are
/// far shorter and never match.
const TmpDirNameMinLen: usize = 13;

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    // Resolve the current working directory to an absolute path, then re-open it
    // with iterate capability. Io.Dir.cwd() on Windows has no iterate handle.
    var path_buf: [Io.Dir.max_path_bytes]u8 = undefined;
    const cwd_path_len = Io.Dir.realPath(Io.Dir.cwd(), io, &path_buf) catch |err| {
        std.debug.print("clean: cannot resolve CWD: {s}\n", .{@errorName(err)});
        std.process.exit(1);
    };
    const cwd_path = path_buf[0..cwd_path_len];
    const root = Io.Dir.openDirAbsolute(io, cwd_path, .{ .iterate = true }) catch |err| {
        std.debug.print("clean: cannot open CWD '{s}': {s}\n", .{ cwd_path, @errorName(err) });
        std.process.exit(1);
    };
    defer Io.Dir.close(root, io);

    // -----------------------------------------------------------------
    // 1. Sweep std.testing.TmpDir artifacts at the project root.
    // -----------------------------------------------------------------
    var tmp_dirs_removed: usize = 0;
    var root_iter = Io.Dir.iterate(root);
    while (try root_iter.next(io)) |entry| {
        if (entry.kind != .directory) continue;
        if (!isTmpDirName(entry.name)) continue;

        // Best-effort: open to confirm it's a real directory, then delete the tree.
        const sub = Io.Dir.openDir(root, io, entry.name, .{ .iterate = true }) catch continue;
        Io.Dir.close(sub, io);
        Io.Dir.deleteTree(root, io, entry.name) catch |err| {
            std.debug.print("clean: cannot remove tmp dir '{s}': {s}\n", .{ entry.name, @errorName(err) });
            continue;
        };
        tmp_dirs_removed += 1;
    }

    // -----------------------------------------------------------------
    // 2-5. Remove well-known project paths.
    // -----------------------------------------------------------------
    const named_paths = [_][]const u8{
        "docs/.agent-context",
        "dist",
        "test-results",
        ".zig-cache",
        "zig-cache",
        "zig-pkg",
        "zig-out",
        "build",
    };

    var named_removed: usize = 0;
    for (named_paths) |path| {
        if (removeIfExists(root, io, path)) |removed| {
            if (removed) named_removed += 1;
        } else |err| {
            std.debug.print("clean: cannot remove '{s}': {s}\n", .{ path, @errorName(err) });
        }
    }

    // -----------------------------------------------------------------
    // Summary.
    // -----------------------------------------------------------------
    std.debug.print("clean: ok - removed {d} std.testing.TmpDir dirs and {d} named paths\n", .{
        tmp_dirs_removed,
        named_removed,
    });
    std.debug.print("clean: swept docs/.agent-context, dist, test-results, .zig-cache, zig-cache, zig-pkg, zig-out, build\n", .{});
}

/// Returns true if `name` consists entirely of [A-Za-z0-9_-] and has length
/// >= TmpDirNameMinLen. Anchored implicitly - names with path separators
/// cannot reach here because DirIterator yields single path components.
fn isTmpDirName(name: []const u8) bool {
    if (name.len < TmpDirNameMinLen) return false;
    for (name) |c| {
        const ok = switch (c) {
            'A'...'Z', 'a'...'z', '0'...'9' => true,
            '_', '-' => true,
            else => false,
        };
        if (!ok) return false;
    }
    return true;
}

/// Returns true if a directory was removed, false if it didn't exist.
fn removeIfExists(cwd: Io.Dir, io: Io, path: []const u8) !bool {
    const sub = Io.Dir.openDir(cwd, io, path, .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound => return false,
        error.NotDir => return false,
        else => return err,
    };
    Io.Dir.close(sub, io);
    try Io.Dir.deleteTree(cwd, io, path);
    return true;
}
