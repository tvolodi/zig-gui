# RF2 — M16-03: Native file-save dialog

> Roadmap item: M16-03
> Depends on: M16-02 (native file-open dialog — `FileDialogFilter` defined there, Win32 COMDLG infrastructure)
> Read `00_constitution.md` before this file.

## HUMAN DECISION REQUIRED — Linux dependency

Same constraint as RF1: GTK is a NEW external dependency (INV-5.6) and is not yet approved.
**The Linux path is a no-op stub returning `null`.** The Windows path uses `GetSaveFileNameW`,
a Win32 API in the same `COMDLG32` family as `GetOpenFileNameW` — no new dependency.

---

## Purpose

Present the OS-native file-save dialog so the user can choose a destination path and
filename. Like the open dialog, the result is a UTF-8 string (the selected path including
the filename) or `null` on cancel. The call is synchronous. The save dialog differs from the
open dialog in one key respect: the selected file does not need to exist yet; the dialog
prompts the user for an overwrite confirmation if the file already exists.

The API lives in `Platform` in `src/01/types.zig` — same rationale as RF1 (INV-3.4).

## What to build

### `Platform.showSaveDialog` — `src/01/types.zig`

```zig
pub const Platform = struct {
    // ...existing fields (including showOpenDialog from RF1)...

    /// Display the native file-save dialog.
    ///
    /// `default_name` — initial filename pre-filled in the filename field (may be empty).
    /// `filters`      — slice of FileDialogFilter entries (may be empty for "all files").
    ///                  `FileDialogFilter` is defined by RF1 in this same file.
    /// `allocator`    — used to allocate the returned path string.
    ///
    /// Returns an allocator-owned UTF-8 path string, or null if:
    ///   - the user cancelled,
    ///   - or (Linux stub) the platform does not support native dialogs yet.
    ///
    /// Caller must free the returned slice with `allocator.free(path)`.
    /// Blocking: does not return until the dialog is dismissed.
    /// If the selected path already exists, the OS dialog handles the overwrite prompt.
    pub fn showSaveDialog(
        self: *Platform,
        default_name: []const u8,
        filters: []const FileDialogFilter,
        allocator: std.mem.Allocator,
    ) ?[]u8
};
```

`FileDialogFilter` is defined in `src/01/types.zig` by RF1. RF2 does not redefine it.

### Win32 implementation

```zig
pub fn showSaveDialog(
    self: *Platform,
    default_name: []const u8,
    filters: []const FileDialogFilter,
    allocator: std.mem.Allocator,
) ?[]u8 {
    // 1. Build a wide-char filter string — same as showOpenDialog.
    // 2. Convert `default_name` from UTF-8 to wide-char (szFile pre-fill).
    // 3. Zero-initialise an OPENFILENAMEW struct.
    //    Set hwndOwner = glfwGetWin32Window(self.window).
    //    Set Flags: OFN_OVERWRITEPROMPT (prompt before overwriting).
    //    Do NOT set OFN_FILEMUSTEXIST (save target may not exist yet).
    // 4. Call GetSaveFileNameW(&ofn).
    //    If it returns FALSE → return null.
    // 5. Convert the wide-char result to UTF-8 via WideCharToMultiByte.
    // 6. Allocate and return the UTF-8 slice.
}
```

`GetSaveFileNameW` is in the same `commdlg.h` header as `GetOpenFileNameW` and is already
accessible via the existing `@cImport` in module 01. No new header or library linkage is
needed beyond what RF1 established.

### Linux stub

```zig
pub fn showSaveDialog(
    self: *Platform,
    default_name: []const u8,
    filters: []const FileDialogFilter,
    allocator: std.mem.Allocator,
) ?[]u8 {
    _ = self; _ = default_name; _ = filters; _ = allocator;
    return null;
}
```

### Module location

```
src/01/types.zig       — Platform.showSaveDialog signature
src/01/platform.zig    — Win32 implementation + Linux stub
```

## Non-goals (DO NOT implement — INV-5.4)

- **No GTK on Linux** — not approved (INV-5.6); stub only until human approves.
- **No async/callback variant** — synchronous and blocking only.
- **No file-exists check in Zig code** — the OS dialog shows the overwrite prompt via
  `OFN_OVERWRITEPROMPT`; we do not do it ourselves.
- **No default-directory parameter** — the dialog opens at the OS default location.
- **No file extension auto-append** — if the user types a name without an extension, no
  extension is added automatically. `OFN_EXTENSIONDIFFERENT` detection is not implemented.
- **No macOS support** — Windows and Linux only (INV-1.2).
- **No memory of previously used paths** — stateless per call.

## Acceptance criteria

1. `Platform.showSaveDialog(default_name, filters, allocator)` returns a non-null UTF-8 path
   when the user confirms the dialog on Windows.
2. `default_name` is pre-filled in the filename text box when the dialog opens.
3. The returned path is allocator-owned; freeing it produces no errors or leaks.
4. `showSaveDialog` returns `null` when the user presses Cancel on Windows.
5. If the user types a path to an existing file, the OS-native overwrite-confirmation prompt
   appears (`OFN_OVERWRITEPROMPT`); accepting it returns the path; cancelling returns `null`.
6. `filters` restricts the visible file types in the dropdown on Windows.
7. The dialog is parented to the application window on Windows.
8. On Linux (stub), `showSaveDialog` returns `null` and does not crash.
9. No new external dependency is linked on either platform.
10. Unit tests cover: default_name pre-fill (Win32 wide-char round-trip), stub behavior on
    Linux, and cancel returning null.
