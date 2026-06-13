# RF4 — M16-05: MIME clipboard

> Roadmap item: M16-05
> Depends on: M3-07 (clipboard — `Platform.setClipboard` / `getClipboard` in `src/01/types.zig`)
> Read `00_constitution.md` before this file.

## Purpose

Extend the platform clipboard API (R36) to carry a MIME type alongside the data payload.
This allows the application to write rich clipboard content — such as HTML, images, or
application-specific formats — and to read the specific format back when pasting. Plain-text
copying and pasting (existing R36) is preserved as the `"text/plain"` MIME type.

The MIME clipboard API lives in `Platform` in `src/01/types.zig`, alongside the existing
`setClipboard` / `getClipboard` functions. It does NOT replace them — the existing plain-text
functions remain for backward compatibility (INV-5.1).

## What to build

### `Platform.setClipboardMime` and `Platform.getClipboardMime` — `src/01/types.zig`

```zig
pub const Platform = struct {
    // ...existing fields including setClipboard / getClipboard from R36...

    /// Write data of a specific MIME type to the system clipboard.
    ///
    /// `mime_type` — MIME type string, e.g. "text/plain", "text/html", "image/png".
    /// `data`      — raw bytes to place on the clipboard.
    ///
    /// On Windows, MIME types are mapped to Win32 clipboard formats:
    ///   "text/plain"       → CF_UNICODETEXT (data is interpreted as UTF-8, converted to UTF-16)
    ///   "text/html"        → CF_HTML (registered custom format "HTML Format")
    ///   any other MIME     → RegisterClipboardFormatW(mime_type) → custom format
    ///
    /// On Linux (GLFW): GLFW 3 only supports CF_TEXT / plain strings.
    ///   "text/plain" → glfwSetClipboardString (existing R36 behavior).
    ///   Any other MIME type on Linux is a no-op returning void without error.
    ///   This matches the approved dependency set (INV-5.6): no X11/Wayland clipboard APIs.
    ///
    /// Ownership: `data` is copied into OS clipboard storage; caller retains ownership.
    pub fn setClipboardMime(
        self: *Platform,
        mime_type: []const u8,
        data: []const u8,
    ) void

    /// Read data of a specific MIME type from the system clipboard.
    ///
    /// `mime_type`  — MIME type string to request, e.g. "text/html".
    /// `buf`        — caller-supplied buffer to receive the data.
    ///
    /// Returns a slice of `buf` containing the clipboard data, or null if:
    ///   - the clipboard does not contain data of the requested MIME type,
    ///   - the data is larger than `buf`,
    ///   - or (Linux) the requested MIME type is not "text/plain".
    ///
    /// On Windows: maps mime_type to a clipboard format; calls GetClipboardData.
    /// On Linux:   only "text/plain" returns data (via glfwGetClipboardString);
    ///             all other MIME types return null.
    ///
    /// No allocation: result is a slice of the caller-provided `buf`.
    pub fn getClipboardMime(
        self: *Platform,
        mime_type: []const u8,
        buf: []u8,
    ) ?[]const u8
};
```

### Win32 implementation

```zig
// In src/01/platform.zig

const CF_HTML_FORMAT_NAME = "HTML Format"; // Win32 registered name

fn mimeToClipboardFormat(mime_type: []const u8) u32 {
    if (std.mem.eql(u8, mime_type, "text/plain")) return windows.CF_UNICODETEXT;
    if (std.mem.eql(u8, mime_type, "text/html")) {
        // RegisterClipboardFormatA returns a UINT; cached after first call.
        return windows.RegisterClipboardFormatA(CF_HTML_FORMAT_NAME);
    }
    // For all other MIME types: register a custom Win32 format by the MIME string itself.
    // RegisterClipboardFormatA is idempotent — returns the same UINT for the same string.
    var buf: [256]u8 = undefined;
    const len = @min(mime_type.len, buf.len - 1);
    @memcpy(buf[0..len], mime_type[0..len]);
    buf[len] = 0;
    return windows.RegisterClipboardFormatA(&buf[0]);
}

pub fn setClipboardMime(
    self: *Platform,
    mime_type: []const u8,
    data: []const u8,
) void {
    // Special case: "text/plain" delegates to the existing R36 setClipboard.
    if (std.mem.eql(u8, mime_type, "text/plain")) {
        self.setClipboard(data);
        return;
    }
    const fmt = mimeToClipboardFormat(mime_type);
    // OpenClipboard → EmptyClipboard → GlobalAlloc(GMEM_MOVEABLE) →
    // GlobalLock → memcpy → GlobalUnlock → SetClipboardData → CloseClipboard.
    _ = fmt; // implementation body omitted here for brevity
}

pub fn getClipboardMime(
    self: *Platform,
    mime_type: []const u8,
    buf: []u8,
) ?[]const u8 {
    if (std.mem.eql(u8, mime_type, "text/plain")) {
        // Delegate to R36 getClipboard with a stack allocator over buf.
        // Convert UNICODETEXT → UTF-8 into buf; return slice on success.
        _ = self;
        return null; // placeholder — real impl converts CF_UNICODETEXT to UTF-8
    }
    const fmt = mimeToClipboardFormat(mime_type);
    // OpenClipboard → GetClipboardData(fmt) → GlobalLock →
    // if data_len <= buf.len: memcpy to buf → GlobalUnlock → CloseClipboard → return slice.
    // else: GlobalUnlock → CloseClipboard → return null.
    _ = fmt;
    return null;
}
```

All Win32 functions used (`OpenClipboard`, `GetClipboardData`, `SetClipboardData`,
`RegisterClipboardFormatA`, `GlobalAlloc`, `GlobalLock`, `GlobalUnlock`, `CloseClipboard`)
are in `windows.h` — already available via the `@cImport` in module 01. No new dependency.

### Linux implementation

GLFW 3 exposes only string clipboard access (`glfwGetClipboardString` / `glfwSetClipboardString`).
Raw X11 or Wayland clipboard protocol requires additional library bindings that are NOT
approved (INV-5.6). The Linux path is therefore limited to `"text/plain"` and is a no-op
for all other MIME types.

```zig
pub fn setClipboardMime(
    self: *Platform,
    mime_type: []const u8,
    data: []const u8,
) void {
    if (std.mem.eql(u8, mime_type, "text/plain")) {
        self.setClipboard(data); // existing R36 path
    }
    // All other MIME types: no-op.
}

pub fn getClipboardMime(
    self: *Platform,
    mime_type: []const u8,
    buf: []u8,
) ?[]const u8 {
    if (std.mem.eql(u8, mime_type, "text/plain")) {
        const raw = glfw.glfwGetClipboardString(self.window) orelse return null;
        const len = std.mem.len(raw);
        if (len > buf.len) return null;
        @memcpy(buf[0..len], raw[0..len]);
        return buf[0..len];
    }
    return null;
}
```

### Backward compatibility

The existing `setClipboard(text)` and `getClipboard(allocator)` from R36 remain unchanged.
`setClipboardMime("text/plain", data)` is equivalent to `setClipboard(data)`. Callers that
only need plain text continue using R36 functions; callers needing MIME-typed data use the
new functions.

### Module location

```
src/01/types.zig       — Platform.setClipboardMime, Platform.getClipboardMime signatures
src/01/platform.zig    — Win32 MIME clipboard + Linux GLFW-only stub
```

## Non-goals (DO NOT implement — INV-5.4)

- **No X11 clipboard protocol** — would require libxcb or libX11, which are NOT approved
  (INV-5.6). Only GLFW string clipboard on Linux.
- **No Wayland clipboard protocol** — same rationale; not approved.
- **No multi-format clipboard write** — `setClipboardMime` writes one format per call. Win32
  multi-format clipboard (writing several formats in one OpenClipboard session) is post-v1.
- **No clipboard change notifications** — no polling or callback when clipboard content
  changes externally.
- **No image decode/encode** — if `"image/png"` data is written, it is stored as raw bytes.
  Decoding is the caller's responsibility (INV-5.6: no stb_image).
- **No clipboard history** — current content only.
- **No allocating variant of `getClipboardMime`** — caller provides the buffer.
- **No macOS support** — Windows and Linux only (INV-1.2).

## Acceptance criteria

1. `Platform.setClipboardMime("text/plain", data)` and `Platform.setClipboard(data)` produce
   identical clipboard contents (both write plain text) on Windows.
2. `Platform.getClipboardMime("text/plain", buf)` returns a non-null slice containing the
   plain-text clipboard content on Windows.
3. `setClipboardMime("text/html", html_bytes)` registers the `CF_HTML` format and stores the
   bytes in the Windows clipboard without error.
4. `getClipboardMime("text/html", buf)` retrieves the previously stored HTML bytes from the
   Windows clipboard (round-trip: set then get returns the same bytes).
5. `getClipboardMime("text/html", buf)` returns null when the clipboard does not contain HTML.
6. `getClipboardMime` returns null when `buf` is smaller than the clipboard data.
7. On Linux, `setClipboardMime("text/plain", data)` sets the plain-text clipboard.
8. On Linux, `setClipboardMime("text/html", data)` is a no-op and does not panic.
9. On Linux, `getClipboardMime("text/html", buf)` returns null.
10. `setClipboard` and `getClipboard` (R36) continue to work unchanged after RF4 is applied.
11. No new external dependency is linked on either platform.
12. Unit tests cover: text/plain round-trip, text/html round-trip (Win32), unknown MIME type
    returning null, buffer-too-small returning null, and Linux stub behavior.
