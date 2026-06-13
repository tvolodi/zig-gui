//! RF0 — M16-01: System tray icon + popup menu.
//!
//! Win32: backed by Shell_NotifyIconW (NOTIFYICONDATA) + a message-only window.
//! Linux: no-op stub — libnotify not yet approved (INV-5.6).

const std = @import("std");
const builtin = @import("builtin");
const mod07 = @import("../07/types.zig");

pub const CallbackFn = mod07.CallbackFn;

// ---------------------------------------------------------------------------
// MenuItem — internal item list entry (INV-3.1: stored in ArrayListUnmanaged).
// ---------------------------------------------------------------------------

const MenuItem = struct {
    label: []const u8,
    callback: CallbackFn,
    disabled: bool,
    is_separator: bool,
};

// ---------------------------------------------------------------------------
// Win32 C imports — conditional on platform
// ---------------------------------------------------------------------------

const c = if (builtin.os.tag == .windows) @cImport({
    @cInclude("windows.h");
    @cInclude("shellapi.h");
}) else void;

// ---------------------------------------------------------------------------
// WM_APP+1 used as the tray callback message.
// ---------------------------------------------------------------------------

const WM_TRAYICON: c_uint = if (builtin.os.tag == .windows) (0x8000 + 1) else 0;

// ---------------------------------------------------------------------------
// Tray struct
// ---------------------------------------------------------------------------

/// System tray icon with popup menu.
/// Win32: backed by Shell_NotifyIcon (NOTIFYICONDATA).
/// Linux: no-op stub — no visible tray icon until libnotify is approved (INV-5.6).
pub const Tray = struct {
    allocator: std.mem.Allocator,
    items: std.ArrayListUnmanaged(MenuItem),

    // Win32-specific fields (zero/null on Linux).
    _hwnd: if (builtin.os.tag == .windows) c.HWND else void,
    _hicon: if (builtin.os.tag == .windows) c.HICON else void,
    _hmenu: if (builtin.os.tag == .windows) c.HMENU else void,
    _visible: bool,

    /// Initialise the tray. On Win32, creates a message-only window and converts
    /// `icon_rgba` (raw RGBA pixels, 16×16 or 32×32) to an HICON.
    /// On Linux: no-op stub; all args accepted, nothing displayed.
    pub fn init(
        icon_rgba: []const u8,
        icon_w: u32,
        icon_h: u32,
        tooltip: []const u8,
        allocator: std.mem.Allocator,
    ) !Tray {
        if (comptime builtin.os.tag == .windows) {
            return initWin32(icon_rgba, icon_w, icon_h, tooltip, allocator);
        } else {
            @compileLog("Tray: no-op on Linux — libnotify not approved (INV-5.6)");
            _ = .{ icon_rgba, icon_w, icon_h, tooltip };
            return Tray{
                .allocator = allocator,
                .items = .empty,
                ._hwnd = {},
                ._hicon = {},
                ._hmenu = {},
                ._visible = false,
            };
        }
    }

    pub fn deinit(self: *Tray) void {
        if (builtin.os.tag == .windows) {
            deinitWin32(self);
        }
        self.items.deinit(self.allocator);
    }

    /// Add a menu item. `callback` is invoked when the item is clicked (unless disabled).
    pub fn addMenuItem(
        self: *Tray,
        label: []const u8,
        callback: CallbackFn,
        disabled: bool,
    ) !void {
        try self.items.append(self.allocator, .{
            .label = label,
            .callback = callback,
            .disabled = disabled,
            .is_separator = false,
        });
    }

    /// Add a visual separator line between menu items.
    pub fn addSeparator(self: *Tray) !void {
        try self.items.append(self.allocator, .{
            .label = "",
            .callback = .{ .ptr = undefined, .call = undefined },
            .disabled = true,
            .is_separator = true,
        });
    }

    /// Show or hide the tray icon. Must be called after init to make the icon appear.
    pub fn setVisible(self: *Tray, visible: bool) void {
        if (builtin.os.tag == .windows) {
            setVisibleWin32(self, visible);
        } else {
            self._visible = visible;
        }
    }

    /// Rebuild the popup menu from the current item list.
    /// Must be called after addMenuItem/addSeparator to see changes.
    pub fn update(self: *Tray) void {
        if (builtin.os.tag == .windows) {
            updateMenuWin32(self);
        }
    }

    /// Drain the message-only window's queue and dispatch tray events.
    /// Called once per frame by AppInner.
    pub fn pumpMessages(self: *Tray) void {
        if (builtin.os.tag == .windows) {
            pumpMessagesWin32(self);
        }
    }
};

// ---------------------------------------------------------------------------
// Win32 implementation
// ---------------------------------------------------------------------------

// HWND_MESSAGE = (HWND)(LONG_PTR)-3.
// c.HWND_MESSAGE cannot be used directly in Zig 0.16: the C translation helper
// emits a comptime cast from -3 to an aligned pointer type, which fails.
// Workaround: declare CreateWindowExW with hWndParent as usize (same ABI on
// x86-64 Windows; pointer and usize are both 8 bytes).  The linker resolves
// "CreateWindowExW" from user32 regardless of our parameter spelling.
const CreateWindowExW_AnyParent = *const fn (
    c.DWORD, [*:0]const c.WCHAR, [*:0]const c.WCHAR, c.DWORD,
    c_int, c_int, c_int, c_int,
    usize,          // hWndParent — accept as usize to pass HWND_MESSAGE (-3)
    c.HMENU, c.HINSTANCE, ?*anyopaque,
) callconv(.c) c.HWND;

const createWindowExW: CreateWindowExW_AnyParent = @ptrCast(&c.CreateWindowExW);
const HWND_MESSAGE_USIZE: usize = @bitCast(@as(isize, -3));

fn initWin32(
    icon_rgba: []const u8,
    icon_w: u32,
    icon_h: u32,
    tooltip: []const u8,
    allocator: std.mem.Allocator,
) !Tray {
    // Create message-only window.
    const hinstance = c.GetModuleHandleW(null);
    const hwnd = createWindowExW(
        0,
        std.unicode.utf8ToUtf16LeStringLiteral("STATIC"),
        std.unicode.utf8ToUtf16LeStringLiteral(""),
        0,
        0, 0, 0, 0,
        HWND_MESSAGE_USIZE,
        null,
        hinstance,
        null,
    );
    if (hwnd == null) return error.OutOfMemory;

    // Build HICON from raw RGBA pixels.
    const hicon = rgbaToHicon(icon_rgba, icon_w, icon_h);

    var self = Tray{
        .allocator = allocator,
        .items = .empty,
        ._hwnd = hwnd.?,
        ._hicon = hicon,
        ._hmenu = null,
        ._visible = false,
    };

    // Register tray icon (hidden until setVisible is called).
    var nid = std.mem.zeroes(c.NOTIFYICONDATAW);
    nid.cbSize = @sizeOf(c.NOTIFYICONDATAW);
    nid.hWnd = hwnd.?;
    nid.uID = 1;
    nid.uFlags = c.NIF_ICON | c.NIF_TIP | c.NIF_MESSAGE;
    nid.uCallbackMessage = WM_TRAYICON;
    nid.hIcon = hicon;

    // Copy tooltip (truncate to 128 wchars if needed).
    var tip_wide: [128]c.WCHAR = undefined;
    @memset(&tip_wide, 0);
    const tip_wide_len = std.unicode.utf8ToUtf16Le(&tip_wide, tooltip) catch 0;
    _ = tip_wide_len;
    @memcpy(&nid.szTip, &tip_wide);

    _ = c.Shell_NotifyIconW(c.NIM_ADD, &nid);
    // Hide immediately — only shown via setVisible(true).
    _ = c.Shell_NotifyIconW(c.NIM_DELETE, &nid);
    self._visible = false;

    return self;
}

fn deinitWin32(self: *Tray) void {
    if (self._visible) {
        var nid = std.mem.zeroes(c.NOTIFYICONDATAW);
        nid.cbSize = @sizeOf(c.NOTIFYICONDATAW);
        nid.hWnd = self._hwnd;
        nid.uID = 1;
        _ = c.Shell_NotifyIconW(c.NIM_DELETE, &nid);
    }
    if (self._hmenu) |hm| _ = c.DestroyMenu(hm);
    if (self._hicon) |hi| _ = c.DestroyIcon(hi);
    _ = c.DestroyWindow(self._hwnd);
}

fn setVisibleWin32(self: *Tray, visible: bool) void {
    var nid = std.mem.zeroes(c.NOTIFYICONDATAW);
    nid.cbSize = @sizeOf(c.NOTIFYICONDATAW);
    nid.hWnd = self._hwnd;
    nid.uID = 1;
    nid.uFlags = c.NIF_ICON | c.NIF_TIP | c.NIF_MESSAGE;
    nid.uCallbackMessage = WM_TRAYICON;
    nid.hIcon = self._hicon;

    if (visible and !self._visible) {
        _ = c.Shell_NotifyIconW(c.NIM_ADD, &nid);
    } else if (!visible and self._visible) {
        _ = c.Shell_NotifyIconW(c.NIM_DELETE, &nid);
    }
    self._visible = visible;
}

fn updateMenuWin32(self: *Tray) void {
    if (self._hmenu) |hm| {
        _ = c.DestroyMenu(hm);
        self._hmenu = null;
    }
    const hmenu = c.CreatePopupMenu();
    if (hmenu == null) return;
    self._hmenu = hmenu.?;

    for (self.items.items, 0..) |item, idx| {
        if (item.is_separator) {
            _ = c.AppendMenuW(hmenu.?, c.MF_SEPARATOR, 0, null);
        } else {
            // MF_STRING and MF_GRAYED are c_long in the Windows SDK; keep arithmetic in c_long.
            const grayed: c_long = if (item.disabled) @as(c_long, c.MF_GRAYED) else 0;
            const flags: c.UINT = @bitCast(@as(c_long, c.MF_STRING) | grayed);
            var wide_label: [256]c.WCHAR = undefined;
            @memset(&wide_label, 0);
            _ = std.unicode.utf8ToUtf16Le(&wide_label, item.label) catch 0;
            _ = c.AppendMenuW(hmenu.?, flags, idx + 1, &wide_label[0]);
        }
    }
}

fn pumpMessagesWin32(self: *Tray) void {
    var msg: c.MSG = undefined;
    while (c.PeekMessageW(&msg, self._hwnd, 0, 0, c.PM_REMOVE) != 0) {
        if (msg.message == WM_TRAYICON) {
            const lparam = @as(c_uint, @intCast(msg.lParam & 0xFFFF));
            if (lparam == c.WM_RBUTTONUP or lparam == c.WM_LBUTTONUP) {
                if (self._hmenu) |hm| {
                    var pt: c.POINT = undefined;
                    _ = c.GetCursorPos(&pt);
                    _ = c.SetForegroundWindow(self._hwnd);
                    _ = c.TrackPopupMenu(hm, c.TPM_RIGHTBUTTON | c.TPM_BOTTOMALIGN,
                        pt.x, pt.y, 0, self._hwnd, null);
                    _ = c.PostMessageW(self._hwnd, c.WM_NULL, 0, 0);
                }
            }
        } else if (msg.message == c.WM_COMMAND) {
            const item_id = msg.wParam & 0xFFFF;
            if (item_id >= 1 and item_id - 1 < self.items.items.len) {
                const item = self.items.items[item_id - 1];
                if (!item.disabled and !item.is_separator) {
                    item.callback.call(item.callback.ptr);
                }
            }
        } else {
            _ = c.TranslateMessage(&msg);
            _ = c.DispatchMessageW(&msg);
        }
    }
}

fn rgbaToHicon(rgba: []const u8, w: u32, h: u32) c.HICON {
    if (rgba.len < w * h * 4) return null;

    // Build a 32-bit DIB section in BGRA order (Win32 expects BGRA in CreateBitmap).
    const n_pixels = w * h;
    var bgra_buf: [32 * 32 * 4]u8 = undefined;
    if (n_pixels * 4 > bgra_buf.len) return null;

    var i: usize = 0;
    while (i < n_pixels) : (i += 1) {
        bgra_buf[i * 4 + 0] = rgba[i * 4 + 2]; // B
        bgra_buf[i * 4 + 1] = rgba[i * 4 + 1]; // G
        bgra_buf[i * 4 + 2] = rgba[i * 4 + 0]; // R
        bgra_buf[i * 4 + 3] = rgba[i * 4 + 3]; // A
    }

    const hbm_color = c.CreateBitmap(@intCast(w), @intCast(h), 1, 32, &bgra_buf[0]);
    if (hbm_color == null) return null;
    defer _ = c.DeleteObject(hbm_color);

    // Mask bitmap (all zeros = fully opaque when alpha in color bitmap is used).
    const mask_size = (w * h + 7) / 8;
    var mask_buf: [32 * 32 / 8]u8 = undefined;
    @memset(mask_buf[0..mask_size], 0);
    const hbm_mask = c.CreateBitmap(@intCast(w), @intCast(h), 1, 1, &mask_buf[0]);
    if (hbm_mask == null) return null;
    defer _ = c.DeleteObject(hbm_mask);

    var ii = std.mem.zeroes(c.ICONINFO);
    ii.fIcon = c.TRUE;
    ii.hbmColor = hbm_color;
    ii.hbmMask = hbm_mask;
    return c.CreateIconIndirect(&ii);
}
