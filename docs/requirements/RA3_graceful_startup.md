# RA3 — M10-04: Graceful startup failure

> Roadmap item: M10-04  
> Depends on: M1-01 (App main loop — AppInner.init, Platform, VulkanBackend)  
> Read `00_constitution.md` before this file.

## Purpose

When Vulkan is unavailable (missing driver, insufficient hardware, no display), display a
native OS error dialog instead of crashing to stderr. The process exits cleanly with a
non-zero exit code after the user dismisses the dialog.

---

## Motivation

Today, `AppInner.init` propagates `error.VulkanInitFailed` (or similar) to `main`, which
typically prints a stack trace to stderr and exits. On production machines without a
terminal this is invisible to the user. A native dialog box gives actionable feedback.

---

## What to build

### 1. `showErrorDialog` — `src/app/startup_error.zig`

```zig
const std = @import("std");

/// Display a native OS error dialog and block until the user dismisses it.
/// On Windows: calls MessageBoxW via @cImport of <windows.h>.
/// On Linux:   writes to stderr (native dialog requires GTK, which is out of scope —
///             see Non-goals). A simple `std.debug.print` prefixed with "ERROR: " is
///             the Linux implementation.
pub fn showErrorDialog(title: []const u8, message: []const u8) void;
```

The function is comptime-dispatched on `builtin.os.tag`:
- **Windows**: `MessageBoxW(null, message_w, title_w, MB_OK | MB_ICONERROR)`.
  Converts `title` and `message` from UTF-8 to UTF-16LE using `std.unicode.utf8ToUtf16Le`
  into stack-allocated buffers (max 512 UTF-16 code units each).
- **Linux**: `std.io.getStdErr().writer().print("ERROR: {s}: {s}\n", .{title, message})`
  (stderr fallback; see Non-goals).

### 2. `AppInner.init` integration

`AppInner.init` currently returns `!AppInner`. The error set is unchanged.

Add a convenience wrapper in `src/app/startup_error.zig`:

```zig
/// Run `App.init` and, on failure, display a native error dialog before returning the error.
/// Intended to be called from `main`:
///
///   const app = try startup_error.initOrDialog(gpa, opts);
///
pub fn initOrDialog(
    gpa: std.mem.Allocator,
    opts: AppOptions,
) !app_impl.AppInner {
    return app_impl.AppInner.init(gpa, opts) catch |err| {
        const msg = std.fmt.allocPrint(gpa, "Failed to start: {s}", .{@errorName(err)})
            catch "Failed to start (out of memory formatting message)";
        defer if (@TypeOf(msg) == []u8) gpa.free(msg);
        showErrorDialog("Application Error", msg);
        return err;
    };
}
```

`AppOptions` is unchanged. No new fields are added.

### 3. Build target

No new build target is needed. `showErrorDialog` links `user32` on Windows (already linked
by GLFW — no new library dependency). On Linux it uses only `std.io`.

---

## Module location

```
src/app/startup_error.zig       — showErrorDialog + initOrDialog
src/app/startup_error_test.zig  — unit tests (platform detection, message truncation)
docs/requirements/RA3_graceful_startup.md
```

`src/app/types.zig` must re-export `showErrorDialog` and `initOrDialog`.

---

## Invariant interactions

- **INV-5.6**: No new dependencies. Windows `MessageBoxW` is part of `user32`, already
  transitively linked through GLFW. Linux implementation uses only `std.io`.
- **INV-1.2**: The comptime OS dispatch covers Windows and Linux only. No macOS path.
- **INV-1.1**: No new `AppOptions` fields — `initOrDialog` is a standalone helper, not
  wired into `App.init` automatically.

---

## Glossary addition

Add to `docs/specs/glossary.md`:

```
## showErrorDialog

A platform-specific function that displays a native error message to the user.
On Windows, uses `MessageBoxW`. On Linux, writes to stderr. Used by `initOrDialog`
to surface Vulkan or other startup failures gracefully. Defined in
`src/app/startup_error.zig`. See: RA3 (M10-04).
```

---

## Non-goals (DO NOT implement — INV-5.4)

- NO GTK dialog on Linux — GTK is not an approved dependency (INV-5.6). Stderr is sufficient.
- NO retry / recovery from within the dialog — the dialog is purely informational; the user
  must fix the system and relaunch.
- NO custom icon or branding in the dialog window.
- NO automatic Vulkan error message lookup (e.g., VkResult → human string). `@errorName`
  is the only error-to-string conversion.
- NO wrapping of non-startup errors in a dialog. Only `initOrDialog` is provided; callers
  decide whether to use `showErrorDialog` for other purposes.

---

## Acceptance criteria

The module is done when:

1. `zig build test-startup-error` runs `src/app/startup_error_test.zig` and all tests pass.
2. On Windows, `showErrorDialog` calls `MessageBoxW` without crashing (tested via
   a compile-check test — a full GUI test is out of scope for CI).
3. On Linux, `showErrorDialog` writes a line to stderr containing both title and message.
4. `initOrDialog` with a failing `AppInner.init` calls `showErrorDialog` and re-returns
   the original error.
5. `initOrDialog` with a succeeding `AppInner.init` returns the `AppInner` without showing
   any dialog.
6. UTF-8 title/message with non-ASCII characters (e.g., Cyrillic) converts correctly to
   UTF-16LE on Windows without stack overflow.

---

## Edge cases (each has a test)

- Message exactly 512 UTF-16 code units → fits in the stack buffer, no truncation.
- Message exceeding 512 UTF-16 code units → truncated to 511 + NUL; no crash.
- Title is empty string → `showErrorDialog` still completes without panic.
- `initOrDialog` called with `opts.font_path = ""` → font loading fails, dialog shown,
  original error returned.
