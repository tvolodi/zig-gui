# RF0 — M16-01: System tray icon + popup menu

> Roadmap item: M16-01
> Depends on: M8-04 (multi-window — `MultiWindowApp`, `Platform` win32 surface already accessed via `@cImport`)
> Read `00_constitution.md` before this file.

## HUMAN DECISION REQUIRED — Linux dependency

The ROADMAP lists `libnotify (Linux)` as the Linux implementation path for the system tray.
`libnotify` is a NEW external dependency and requires an explicit human decision before it
may be used (INV-5.6). **The implementation path in this R-file is libnotify-FREE.** The
Linux path is a no-op stub until a human records the approval of libnotify in
`00_constitution.md`.

**Decision required:** Approve or reject `libnotify` for the Linux tray implementation.
Until that decision is recorded, the Linux `Tray` struct will compile and be callable but
will produce no visible system tray icon.

---

## Purpose

Allow the application to place a small icon in the OS system notification area (the "tray").
The tray icon can carry a tooltip label and a popup context menu so the user can interact
with the application even when its main window is hidden or minimized. On Windows this uses
the Win32 `Shell_NotifyIcon` API, which requires no new dependency — Win32 is already
accessed via `@cImport` in module 01. On Linux the struct is a no-op stub.

## What to build

### `Tray` struct — `src/app/tray.zig`

```zig
/// System tray icon with popup menu.
/// Win32: backed by Shell_NotifyIcon (NOTIFYICONDATA).
/// Linux: no-op stub — no visible tray icon until libnotify is approved (INV-5.6).
pub const Tray = struct {
    // internal fields (Win32: hwnd, nid; Linux: nothing)

    pub fn init(
        icon_rgba: []const u8, // raw RGBA pixel data, 16×16 or 32×32
        icon_w: u32,
        icon_h: u32,
        tooltip: []const u8,   // tooltip text shown on hover (null-terminated at call site)
        allocator: std.mem.Allocator,
    ) !Tray

    pub fn deinit(self: *Tray) void

    /// Add a menu item to the popup menu.
    /// `label` — display text; `callback` — a `CallbackFn` fired when the item is clicked.
    /// `disabled` — renders the item greyed out; callback is not invoked when disabled.
    pub fn addMenuItem(
        self: *Tray,
        label: []const u8,
        callback: CallbackFn,
        disabled: bool,
    ) !void

    /// Add a visual separator line between menu items.
    pub fn addSeparator(self: *Tray) !void

    /// Show or hide the tray icon.
    /// Must be called after init to make the icon appear.
    pub fn setVisible(self: *Tray, visible: bool) void

    /// Rebuild the popup menu from the current item list.
    /// Must be called after `addMenuItem`/`addSeparator` to see changes.
    pub fn update(self: *Tray) void
};
```

`CallbackFn` is the existing type from `src/07/types.zig` (R31). Import it from that module —
do NOT redefine it (INV-5.5).

### Win32 implementation

```zig
// In src/app/tray.zig, behind a comptime platform check:
const windows = builtin.os.tag == .windows;

// Win32 path:
// 1. Create a hidden message-only window (CreateWindowExW with HWND_MESSAGE parent).
//    This window receives WM_TRAYICON messages from the shell.
// 2. Convert icon_rgba to an HICON via CreateBitmap + CreateIconIndirect.
// 3. Call Shell_NotifyIconW(NIM_ADD, &nid) to register the icon.
// 4. For the popup: build an HMENU from addMenuItem calls.
//    On WM_TRAYICON + NIN_BALLOONUSERCLICK or WM_RBUTTONUP: call
//    TrackPopupMenu(hmenu, ...) at cursor position.
// 5. Dispatch WM_COMMAND messages → invoke the registered CallbackFn.
// 6. On deinit: Shell_NotifyIconW(NIM_DELETE, &nid) + DestroyIcon + DestroyMenu.

// Message-only window pump: call pumpMessages() once per frame from App.run()
// to drain the hidden window's message queue.
pub fn pumpMessages(self: *Tray) void
```

`Shell_NotifyIcon`, `CreateIconIndirect`, `TrackPopupMenu`, `CreateWindowExW` are all Win32
APIs accessible via the existing `@cImport` in module 01 (`src/01/platform.zig`). No new
C library is needed.

### App layer integration

In `src/app/app.zig`, `AppOptions` gains an optional tray:

```zig
pub const AppOptions = struct {
    // ...existing fields...
    /// Optional system tray icon. Non-null enables tray support.
    /// Caller retains ownership; App calls pumpMessages() each frame.
    tray: ?*Tray = null,
};
```

In the frame loop, after `endFrame()` and before checking dirty bits, call:

```zig
if (options.tray) |t| t.pumpMessages();
```

### Linux stub

```zig
// Linux path — no-op stub.
// All methods compile and run without error; no icon appears.
// Produces a comptime @compileLog warning on Linux builds:
//   "Tray: libnotify not yet approved (INV-5.6) — tray is a no-op on Linux"
```

### Module location

```
src/app/tray.zig           — Tray struct (Win32 impl + Linux stub)
src/app/types.zig          — AppOptions.tray field
src/app/app.zig            — pumpMessages call in frame loop
```

## Non-goals (DO NOT implement — INV-5.4)

- **No libnotify on Linux** — not approved (INV-5.6); stub only until human approves.
- **No animated/blinking tray icons** — static icon only.
- **No balloon notifications** — tray tooltip + popup menu only.
- **No multi-icon tray** — one `Tray` instance per app.
- **No drag-and-drop from tray** — popup menu interaction only.
- **No tray icon from a file path** — caller supplies raw RGBA pixel data; file I/O is
  outside scope (INV-5.6: no stb_image).
- **No macOS or other platform support** — Windows and Linux only (INV-1.2).

## Acceptance criteria

1. On Windows, `Tray.init(...)` followed by `setVisible(true)` places an icon in the
   notification area within one frame.
2. Right-clicking the tray icon opens a popup menu with the items added via `addMenuItem`.
3. Clicking a menu item invokes the registered `CallbackFn` exactly once.
4. A disabled menu item does not invoke its `CallbackFn` when clicked.
5. `addSeparator` inserts a visual divider between items in the popup menu.
6. `setVisible(false)` removes the icon from the notification area.
7. `Tray.deinit()` removes the icon from the tray and frees all resources; no leaks.
8. On Linux, all `Tray` methods compile without errors and run without panics (stub behavior).
9. `AppOptions.tray` wires correctly: when non-null, `pumpMessages()` is called once per frame.
10. No new external dependency is linked on either platform (Win32 only; Linux is stub).
11. Unit tests cover: init, addMenuItem, addSeparator, setVisible, deinit, pumpMessages on
    both platform paths (Linux stub tested via cross-compiled unit test or flag guard).
