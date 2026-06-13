# RF1 — M16-02: Native file-open dialog

> Roadmap item: M16-02
> Depends on: M1-01 (app main loop — `Platform` in `src/01/types.zig`)
> Read `00_constitution.md` before this file.

## HUMAN DECISION REQUIRED — Linux dependency

The ROADMAP lists `GTK GtkFileChooserDialog` as the Linux implementation path.
GTK is a NEW external dependency and requires an explicit human decision before it may be
used (INV-5.6). **The Linux path in this R-file is a no-op stub returning `null` with a
compile-time log warning.** The Windows path uses `GetOpenFileNameW` — a Win32 API with
no new dependency. The Linux path will be upgraded to the real GTK dialog once a human
records the approval in `00_constitution.md`.

---

## Purpose

Present the OS-native file-picker dialog so the user can select a file from the filesystem.
Native dialogs are familiar, respect the OS theme, and require no custom UI. The result is
the selected file path as a UTF-8 string, or `null` if the user cancelled. The call is
synchronous (blocking): it returns only when the dialog is dismissed.

The API lives in the `Platform` struct in `src/01/types.zig` (module 01, the platform
layer). The app layer calls it. This preserves the build order: higher-numbered modules may
call into module 01; module 01 does not import higher-numbered modules (INV-3.4).

## What to build

### `FileDialogFilter` — `src/01/types.zig`

```zig
/// A single file-type filter entry for the file dialog.
/// Example: .{ .name = "PNG images", .pattern = "*.png" }
pub const FileDialogFilter = struct {
    name: []const u8,    // human-readable label shown in the filter dropdown
    pattern: []const u8, // glob pattern, e.g. "*.png" or "*.zig"
};
```

### `Platform.showOpenDialog` — `src/01/types.zig`

```zig
pub const Platform = struct {
    // ...existing fields...

    /// Display the native file-open dialog.
    ///
    /// `filters`    — slice of FileDialogFilter entries (may be empty for "all files").
    /// `allocator`  — used to allocate the returned path string.
    ///
    /// Returns an allocator-owned UTF-8 path string, or null if:
    ///   - the user cancelled,
    ///   - no file was selected,
    ///   - or (Linux stub) the platform does not support native dialogs yet.
    ///
    /// Caller must free the returned slice with `allocator.free(path)`.
    /// Blocking: does not return until the dialog is dismissed.
    pub fn showOpenDialog(
        self: *Platform,
        filters: []const FileDialogFilter,
        allocator: std.mem.Allocator,
    ) ?[]u8
};
```

### Win32 implementation

In `src/01/platform.zig`, accessed via the existing `@cImport` block:

```zig
// Relevant Win32 types/functions (already available via @cImport in module 01):
// OPENFILENAMEW, GetOpenFileNameW, CommDlgExtendedError

pub fn showOpenDialog(
    self: *Platform,
    filters: []const FileDialogFilter,
    allocator: std.mem.Allocator,
) ?[]u8 {
    // 1. Build a wide-char filter string: "Name\0*.ext\0\0"
    //    Each FileDialogFilter becomes two null-terminated wide strings;
    //    the list is terminated by an extra null.
    // 2. Zero-initialise an OPENFILENAMEW struct.
    //    Set hwndOwner = self.hwnd (the GLFW window's Win32 handle,
    //    retrieved via glfwGetWin32Window).
    // 3. Set szFile to a [MAX_PATH]u16 buffer for the result.
    // 4. Call GetOpenFileNameW(&ofn).
    //    If it returns FALSE, the user cancelled (or CommDlgExtendedError != 0) → return null.
    // 5. Convert the wide-char result buffer to UTF-8 via WideCharToMultiByte.
    // 6. Allocate and return the UTF-8 slice.
}
```

`glfwGetWin32Window` is already available via the existing GLFW `@cImport` — no new include.

### Linux stub

```zig
// Linux path — no-op stub.
// Returns null immediately; emits a comptime log on Linux builds:
//   "showOpenDialog: GTK not yet approved (INV-5.6) — returns null on Linux"
pub fn showOpenDialog(
    self: *Platform,
    filters: []const FileDialogFilter,
    allocator: std.mem.Allocator,
) ?[]u8 {
    _ = self; _ = filters; _ = allocator;
    return null;
}
```

### Module location

```
src/01/types.zig       — FileDialogFilter struct, Platform.showOpenDialog signature
src/01/platform.zig    — Win32 implementation + Linux stub
```

## Non-goals (DO NOT implement — INV-5.4)

- **No GTK on Linux** — not approved (INV-5.6); stub only until human approves.
- **No multi-file selection** — single-file open only; `OPENFILENAME.OFN_ALLOWMULTISELECT` is NOT set.
- **No directory picker** — files only; directory selection is a separate feature (post-v1).
- **No async/callback variant** — the call is synchronous and blocking.
- **No file-system traversal in Zig** — the OS dialog handles navigation.
- **No initial-directory parameter** — dialog opens at the OS default location.
- **No macOS support** — Windows and Linux only (INV-1.2).
- **No memory of previously selected paths** — stateless per call.

## Acceptance criteria

1. `Platform.showOpenDialog(filters, allocator)` returns a non-null UTF-8 path string when
   the user selects a file and confirms the dialog on Windows.
2. The returned path string is allocator-owned; freeing it produces no errors or leaks.
3. `showOpenDialog` returns `null` when the user presses Cancel on Windows.
4. `filters` restricts the visible file types in the dialog dropdown on Windows.
5. Passing an empty `filters` slice shows all files ("All files `*.*`") on Windows.
6. The dialog is parented to the application window (not a free-floating dialog) on Windows.
7. On Linux (stub), `showOpenDialog` returns `null` and does not crash.
8. No new external dependency is linked on either platform.
9. `FileDialogFilter` is defined in `src/01/types.zig` with `name` and `pattern` fields.
10. Unit tests cover: filter construction, path conversion from wide-char to UTF-8 (Win32),
    and stub behavior on Linux.
