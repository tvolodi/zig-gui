# RI3 — M19-03: Staged update

> Roadmap item: M19-03  
> Depends on: M19-02 (Delta download — binary patching)  
> Read `00_constitution.md` before this file.

## Purpose

Atomically install a new application binary downloaded by RI2. The pattern follows
`PersistentSettings.flush()`: write the new binary to a temporary file in the same
directory as the current executable, verify its checksum, then rename it to replace
the running executable on the next app launch.

This prevents partial updates or binary corruption if the process crashes mid-write.

After this item ships:
1. RI2 produces a patched binary in `AppInner.update_manager.new_binary_data`.
2. **RI3: Write to temp, verify, mark for rename** ← this step.
3. On next app launch, the binary is renamed into place before anything else runs.
4. The old binary is moved to a backup path (optional; for rollback).

---

## What to build

### 1. `StagedUpdate` type — `src/app/update_manager.zig`

```zig
pub const StagedUpdate = struct {
    /// Path to the currently running executable.
    current_exe_path: []const u8,
    
    /// Path where the new binary is staged (temp location).
    staged_path: []const u8,  // e.g., "{exe_dir}/app.new"
    
    /// Path for the backup of the old binary (optional, for rollback).
    backup_path: ?[]const u8, // e.g., "{exe_dir}/app.bak"
    
    /// SHA256 hash of the new binary (for verification).
    new_binary_sha256: [32]u8,
    
    /// Size of the new binary (for verification).
    new_binary_size: usize,
    
    /// Timestamp when the update was staged (for logging/diagnostics).
    staged_at_ms: i64,
};
```

### 2. `UpdateManager` additions

```zig
pub const UpdateManager = struct {
    // ... existing fields ...
    
    /// A staged update waiting to be applied on next launch.
    staged_update: ?StagedUpdate = null,
    
    /// Human-readable message about staging status.
    staging_error: ?[]const u8 = null,

    /// Stage the patched binary from `self.new_binary_data` for atomic installation.
    /// Steps:
    ///   1. Allocate a staging directory (same dir as the running executable).
    ///   2. Write `new_binary_data` to a temp file (e.g., "app.new").
    ///   3. Verify the written file's SHA256 matches `latest_manifest.checksum_sha256`.
    ///   4. Create a marker file indicating the staged update (e.g., "app.update").
    ///   5. Return success; the binary will be renamed on next launch.
    /// On failure: populate `staging_error` and return an error.
    pub fn stageUpdate(self: *UpdateManager) !void;

    /// Check: is a staged update pending?
    /// Returns true if `staged_update` is populated and the marker file exists on disk.
    pub fn isStagedUpdatePending(self: *const UpdateManager) bool;

    /// Clear the staged update state (after successful installation on next launch).
    /// Call this early in `AppInner.init`, before any app logic runs.
    pub fn clearStagedUpdate(self: *UpdateManager) !void;
};
```

### 3. Boot-time binary swap

In `AppInner.init()`, **before instantiating any modules** (before Platform.init):
- Check if a staged update marker exists (e.g., `app.update` file).
- If present:
  - Verify the staged binary's SHA256 one more time.
  - Move the current executable to a backup path (e.g., `app.bak`).
  - Move the staged binary to replace the current executable.
  - Delete the marker file.
  - Log success: `std.log.info("Update installed: {s} → {s}", .{old_version, new_version})`.
- If verification fails, move the backup back and return an error (rollback).

### 4. File layout example

Before update:
```
/opt/app/
  app                 (running executable, v1.0.0)
  app.so              (GPU library, if needed)
  fonts/
```

During staged download + patch:
```
/opt/app/
  app                 (running executable, v1.0.0)
  app.new             (patched binary, v1.0.1)
  app.update          (marker file, empty)
```

On next app launch (before anything runs):
```
/opt/app/
  app                 (renamed from app.new, v1.0.1)
  app.bak             (old executable, v1.0.0, kept for rollback)
  app.so
  fonts/
```

After user confirms no rollback needed (or after 7 days), `app.bak` can be deleted.

### 5. Write and verify

```zig
/// Write `new_binary_data` to a temp file at `staged_path`.
/// Flush and close the file.
/// Read the written file back and compute its SHA256.
/// Compare against `expected_sha256`.
/// Return success only if checksums match exactly.
fn writeStagedBinary(
    gpa: std.mem.Allocator,
    staged_path: []const u8,
    new_binary_data: []const u8,
    expected_sha256: [32]u8,
) !void;

/// Create a marker file indicating a staged update is pending.
/// The marker exists to survive a crash: on next launch, we check for it.
fn createUpdateMarker(exe_dir_path: []const u8, marker_path: []const u8) !void;

/// Atomically rename: staged binary → current executable; old → backup.
/// If the rename fails partway through, rollback.
fn applyBinaryRename(
    exe_path: []const u8,
    staged_path: []const u8,
    backup_path: []const u8,
) !void;
```

### 6. Frame loop integration (from RI2)

After `update_manager.applyDelta()` succeeds in RI2:
- Call `update_manager.stageUpdate()`.
- If successful, log and optionally show a toast (RI4): "Update staged. Will install on next launch."
- If failed, log the error and show an error toast.

---

## Acceptance criteria

1. `stageUpdate()` writes `new_binary_data` to a temp file.
2. The written temp file is verified via SHA256 before marking as staged.
3. If SHA256 mismatch: return error, do NOT create marker file.
4. A marker file (e.g., `app.update`) is created to persist staging across crashes.
5. `isStagedUpdatePending()` checks for the marker file on disk.
6. Boot-time swap (in `AppInner.init`) detects the marker and performs the rename.
7. Rename is atomic: either fully succeeds or fully rolls back to the original binary.
8. On successful rename: log the new version and clear the marker.
9. On rename failure: rollback and return an error.
10. Backup of the old binary is created (for user manual rollback if needed).
11. Path resolution handles Windows and Linux executable conventions (`.exe` suffix, etc.).
12. Memory is freed on `UpdateManager.deinit()`.
13. A crashed update (staged but not yet renamed) recovers gracefully on next launch.

---

## Non-goals

- No automatic cleanup of old backups (user or a separate tool decides when to delete `.bak`).
- No rollback UI (users can manually restore `app.bak` if the new version is broken).
- No scheduled updates (users must restart the app to apply the staged update).
- No background patching while the app is running (RI2 patch happens at download time; boot-time
  swap is fast and atomic).

---

## Non-visual

No rendered output. Staging success/failure is logged and exposed to RI4 (progress UI).

---

## Dependencies

**No new external dependencies.** Staged updates use only:
- Zig std (file I/O, SHA256 verification)
- `std.fs.copyFile` / `std.fs.renameAbsolute` (atomic on both Windows and Linux)
- Existing `UpdateManager` (from RI1–RI2)

---

## Implementation notes

### Executable path resolution

Use `std.fs.selfExePath(alloc)` to get the current executable's path. This works on both
Windows and Linux.

### Temp file naming

The staged binary and marker file should live in the same directory as the running executable
for atomicity:
- Staged binary: `{exe_name}.new` or `{exe_name}.staged`
- Marker file: `{exe_name}.update` or `{exe_name}.pending-update`
- Backup: `{exe_name}.bak`

### Atomic rename

Use `std.fs.renameAbsolute(old_path, new_path)` which is atomic on both Windows
(via `ReplaceFileW`) and Linux (via `rename(2)`). On Windows, if the target exists, pass
`REPLACE_EXISTING` flag.

### Windows `.exe` extension handling

On Windows, the executable may be `app.exe`. The staged binary should be `app.exe.new` and
the backup `app.exe.bak`. The marker should be `app.exe.update` or a separate file.

### Crash recovery

If the app crashes between writing the staged binary and renaming it:
- On next launch, `AppInner.init` checks for the marker file.
- If the marker exists but the new binary is missing: log an error and return.
- If both exist: re-verify the new binary's SHA256 before attempting the rename.
- If re-verification fails: delete the staged files and log an error (no update applied).

### Rollback safety

The backup file is **not** automatically deleted. If the new version is broken, users can:
1. Manually rename `app` to `app.broken` and `app.bak` to `app`.
2. Restart the app to run the old version.

A future feature (post-v1) could offer a "rollback to previous version" button in settings.

### Logging

Log all major steps:
- `"Update staged: {s} bytes written to {s}"` (after write)
- `"Update staged: SHA256 verified"` (after verification)
- `"Update pending install: will apply on next launch"` (after marker created)
- `"Update applied: {s} → {s}"` (on boot-time swap)
- `"Update rollback: checksum mismatch, restoring old binary"` (on recovery failure)

---

## INV-3.3 compliance note

Staged updates do NOT violate INV-3.3 (the dirty-bitset reactivity mechanism). The update
system runs outside the per-frame loop: it stages a binary during RI2 (between frames), and
applies it on next app launch (before any widgets are instantiated). No signals are involved.
