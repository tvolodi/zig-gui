# R36 — M3-07: Clipboard

> Roadmap item: M3-07  
> Depends on: M1-02 (event delivery), GLFW  
> Read `00_constitution.md` before this file.

## Purpose

Provide read/write access to the system clipboard via GLFW's `glfwGetClipboardString` and
`glfwSetClipboardString` functions. This is a thin wrapper that integrates clipboard support
into the platform layer, enabling text input (R32) and other widgets to copy/paste content.
The API is simple: one function to get clipboard text, one to set it.

## What to build

### Clipboard API in `Platform`

Extend [01.types.zig](../specs/01.types.zig) `Platform` struct:

```zig
pub const Platform = struct {
    // ...existing fields...
    
    /// Set the system clipboard to the given text.
    /// Text is copied; ownership remains with the caller.
    /// `text` must be valid UTF-8.
    pub fn setClipboard(self: *Platform, text: []const u8) void
    
    /// Get the current system clipboard content as a UTF-8 string.
    /// Returns an allocated string (owned by the caller), or null if the clipboard is empty
    /// or contains non-UTF-8 data.
    /// The returned string must be freed by the caller with `allocator.free()`.
    pub fn getClipboard(self: *Platform, allocator: std.mem.Allocator) ?[]u8
};
```

### Implementation details

In `src/01/platform.zig`:

```zig
pub fn setClipboard(self: *Platform, text: []const u8) void {
    // Convert Zig slice to null-terminated C string
    var temp_buf: [4096]u8 = undefined
    if (text.len >= temp_buf.len) {
        std.debug.print("Clipboard text too large; truncating\n", .{})
        // Truncate and proceed
    }
    @memcpy(temp_buf[0..text.len], text)
    temp_buf[text.len] = 0
    
    // Call GLFW
    glfw.glfwSetClipboardString(self.window, &temp_buf[0])
}

pub fn getClipboard(self: *Platform, allocator: std.mem.Allocator) ?[]u8 {
    // Call GLFW
    const c_str = glfw.glfwGetClipboardString(self.window)
    if (c_str == null) return null
    
    // Convert C string to Zig slice
    const len = std.mem.len(c_str.?)
    if (len == 0) return null
    
    // Allocate and copy
    const result = allocator.alloc(u8, len) catch return null
    @memcpy(result, c_str.?[0..len])
    
    return result
}
```

### Integration with text input (R32)

No changes needed to R32 implementation; it already calls `platform.setClipboard()` and
`platform.getClipboard()` for Ctrl+C/V. This R36 requirement provides the underlying
implementation.

### Platform location

```
src/01/platform.zig               — setClipboard, getClipboard implementation
src/01/types.zig                  — Platform struct API extension
docs/requirements/R36_clipboard.md
```

## Public API

New `Platform` methods:

```zig
pub fn setClipboard(self: *Platform, text: []const u8) void
pub fn getClipboard(self: *Platform, allocator: std.mem.Allocator) ?[]u8
```

## Behavioral contract

| Operation | Behavior |
|---|---|
| `setClipboard(text)` | System clipboard set to `text` (UTF-8). Other applications see the new content. |
| `getClipboard(allocator)` | Returns a newly allocated UTF-8 string copied from the system clipboard. Caller owns the result and must free it. Returns null if clipboard is empty or non-UTF-8. |
| Maximum clipboard size | No hard limit imposed by this wrapper (OS/GLFW limits apply). If text exceeds platform limits, behavior is undefined (truncation, error, or silent failure). |

## Non-goals (DO NOT implement — INV-5.4)

- **No clipboard history** — only the current clipboard content is accessible.
- **No multiple clipboard formats** — text only (no HTML, images, rich text).
- **No clipboard event notifications** — no callback when clipboard changes externally.
- **No clipboard monitors** — the app does not know if clipboard content changed between calls.
- **No custom clipboard providers** — GLFW is the only mechanism (INV-2.2).
- **No encryption or security** — clipboard content is readable by any application (OS limitation).

## Acceptance criteria

1. Unit tests in `src/01/platform_test.zig` (or added to existing platform test file) cover:
   - `setClipboard(text)` stores the text in the system clipboard.
   - `getClipboard(allocator)` retrieves the stored text as an allocated string.
   - Allocation works: returned string is properly null-terminated (handled by Zig slice).
   - UTF-8 validation: non-UTF-8 clipboard content returns null.
   - Empty clipboard: `getClipboard()` returns null.
   - Large text: clipboard handles reasonably large strings (e.g., 10KB).
   - Memory: returned string must be freed without double-free or leaks.

2. Integration test with text input:
   - Run the app, focus an input field, type text.
   - Ctrl+C copies the text (clipboard verified by external tool or manual inspection).
   - Ctrl+V pastes the text from clipboard into the input.
   - Repeat with different text: copy, paste, verify.

3. Cross-platform verification:
   - Windows: Text copied to clipboard is visible in Notepad or clipboard manager.
   - Linux: Text copied to clipboard is visible in `xclip`, `xsel`, or clipboard manager.

4. No memory leaks:
   - `getClipboard()` allocations are freed by callers.
   - Platform deinit does not leak any clipboard-related resources.

5. Checklist fully ticked.

## Open questions

None. Clipboard is scoped: text only, system clipboard via GLFW, no history, no event
notifications.
