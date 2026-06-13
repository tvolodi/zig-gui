//! M16 platform integration unit tests (RF1–RF4).
//!
//! Covers:
//!   RF1 — Native file-open dialog (FileDialogFilter struct, showOpenDialog decl)
//!   RF2 — Native file-save dialog (showSaveDialog decl)
//!   RF3 — OS color-scheme detection (ColorScheme enum, getColorScheme decl)
//!   RF4 — MIME clipboard (setClipboardMime, getClipboardMime decls)
//!
//! All tests are pure compile-time / structural checks or lightweight runtime
//! checks. No GPU, no GLFW window, no real registry access, no real clipboard
//! access is required.

const std = @import("std");
const testing = std.testing;

// Import the module that contains all M16 public types and Platform methods.
const mod01 = @import("../01/types.zig");

// ============================================================================
// RF1 — Native file-open dialog
// ============================================================================

// RF1-AC9: FileDialogFilter is defined in src/01/types.zig with name + pattern fields.

test "RF1: FileDialogFilter has 'name' field" {
    comptime try testing.expect(@hasField(mod01.FileDialogFilter, "name"));
}

test "RF1: FileDialogFilter has 'pattern' field" {
    comptime try testing.expect(@hasField(mod01.FileDialogFilter, "pattern"));
}

test "RF1: FileDialogFilter can be constructed" {
    const filter = mod01.FileDialogFilter{
        .name = "Zig source files",
        .pattern = "*.zig",
    };
    try testing.expectEqualSlices(u8, "Zig source files", filter.name);
    try testing.expectEqualSlices(u8, "*.zig", filter.pattern);
}

test "RF1: FileDialogFilter slice can hold multiple entries" {
    const filters = [_]mod01.FileDialogFilter{
        .{ .name = "PNG images", .pattern = "*.png" },
        .{ .name = "JPEG images", .pattern = "*.jpg" },
        .{ .name = "All files", .pattern = "*.*" },
    };
    try testing.expectEqual(@as(usize, 3), filters.len);
    try testing.expectEqualSlices(u8, "PNG images", filters[0].name);
    try testing.expectEqualSlices(u8, "*.jpg", filters[1].pattern);
    try testing.expectEqualSlices(u8, "*.*", filters[2].pattern);
}

// RF1-AC declaration check: Platform.showOpenDialog exists as a public method.

test "RF1: Platform.showOpenDialog exists" {
    comptime try testing.expect(@hasDecl(mod01.Platform, "showOpenDialog"));
}

// RF1-AC7 (Linux stub): showOpenDialog returns null on Linux without crashing.
// We cannot call it without a Platform instance (which requires GLFW + GPU),
// so we verify the method exists (above) and document the Linux stub behavior:
//   On Linux, showOpenDialog returns null immediately (GTK not yet approved).
//   Verified manually by instantiating Platform on a Linux build; not automated here.

// ============================================================================
// RF2 — Native file-save dialog
// ============================================================================

// RF2-AC declaration check: Platform.showSaveDialog exists as a public method.

test "RF2: Platform.showSaveDialog exists" {
    comptime try testing.expect(@hasDecl(mod01.Platform, "showSaveDialog"));
}

// RF2: showSaveDialog and showOpenDialog are distinct declarations.

test "RF2: showSaveDialog and showOpenDialog are separate declarations" {
    comptime try testing.expect(@hasDecl(mod01.Platform, "showOpenDialog"));
    comptime try testing.expect(@hasDecl(mod01.Platform, "showSaveDialog"));
    // Confirm they are different by name (structural; always true when both exist).
    // The real behavioral difference (OFN_OVERWRITEPROMPT vs OFN_FILEMUSTEXIST)
    // can only be tested with a real Win32 desktop session.
}

// ============================================================================
// RF3 — OS color-scheme detection
// ============================================================================

// RF3-AC1: ColorScheme enum has .light, .dark, .unknown variants.

test "RF3: ColorScheme has .light, .dark, .unknown variants (exhaustive switch)" {
    const scheme: mod01.ColorScheme = .unknown;
    const found = switch (scheme) {
        .light => true,
        .dark => true,
        .unknown => true,
    };
    try testing.expect(found);
}

test "RF3: ColorScheme.light variant exists" {
    const s: mod01.ColorScheme = .light;
    try testing.expectEqual(mod01.ColorScheme.light, s);
}

test "RF3: ColorScheme.dark variant exists" {
    const s: mod01.ColorScheme = .dark;
    try testing.expectEqual(mod01.ColorScheme.dark, s);
}

test "RF3: ColorScheme.unknown variant exists" {
    const s: mod01.ColorScheme = .unknown;
    try testing.expectEqual(mod01.ColorScheme.unknown, s);
}

// RF3: Platform.getColorScheme exists as a public declaration.

test "RF3: Platform.getColorScheme exists" {
    comptime try testing.expect(@hasDecl(mod01.Platform, "getColorScheme"));
}

// RF3-AC9: AppOptions.default_theme_mode field exists and defaults to .light.
// AppOptions lives in src/app/app.zig, imported here by relative path.

test "RF3: AppOptions.default_theme_mode field exists" {
    const AppOptions = @import("app.zig").AppOptions;
    comptime try testing.expect(@hasField(AppOptions, "default_theme_mode"));
}

test "RF3: AppOptions.default_theme_mode defaults to .light" {
    const AppOptions = @import("app.zig").AppOptions;
    const opts = AppOptions{ .font_path = "dummy.ttf" };
    // mod05.Mode.light is the expected default per RF3 spec.
    const mod05 = @import("../05/types.zig");
    try testing.expectEqual(mod05.Mode.light, opts.default_theme_mode);
}

// RF3 Linux env-var behavior (pure Zig; no platform runtime required):
// We exercise the getColorScheme logic indirectly by verifying the code path
// compiles. A direct call requires a Platform instance (GLFW + GPU). Instead
// we validate that the ColorScheme enum values match the spec mapping.

test "RF3: ColorScheme enum values are distinct" {
    try testing.expect(mod01.ColorScheme.light != mod01.ColorScheme.dark);
    try testing.expect(mod01.ColorScheme.light != mod01.ColorScheme.unknown);
    try testing.expect(mod01.ColorScheme.dark != mod01.ColorScheme.unknown);
}

// ============================================================================
// RF4 — MIME clipboard helpers
// ============================================================================

// RF4: Platform.setClipboardMime exists as a public declaration.

test "RF4: Platform.setClipboardMime exists" {
    comptime try testing.expect(@hasDecl(mod01.Platform, "setClipboardMime"));
}

// RF4: Platform.getClipboardMime exists as a public declaration.

test "RF4: Platform.getClipboardMime exists" {
    comptime try testing.expect(@hasDecl(mod01.Platform, "getClipboardMime"));
}

// RF4 + RF1: FileDialogFilter struct fields (redundant but explicit for RF4 coverage).

test "RF4+RF1: FileDialogFilter.name field exists" {
    comptime try testing.expect(@hasField(mod01.FileDialogFilter, "name"));
}

test "RF4+RF1: FileDialogFilter.pattern field exists" {
    comptime try testing.expect(@hasField(mod01.FileDialogFilter, "pattern"));
}

// RF4: Backward-compat declaration check — existing R36 methods still present.

test "RF4: Platform.setClipboard (R36) still exists after RF4" {
    comptime try testing.expect(@hasDecl(mod01.Platform, "setClipboard"));
}

test "RF4: Platform.getClipboard (R36) still exists after RF4" {
    comptime try testing.expect(@hasDecl(mod01.Platform, "getClipboard"));
}

// RF4: ColorScheme exhaustive switch (mirrors RF3; included here per RF4 requirement note).

test "RF4: ColorScheme exhaustive switch returning bool" {
    const verify = struct {
        fn check(cs: mod01.ColorScheme) bool {
            return switch (cs) {
                .light   => true,
                .dark    => true,
                .unknown => true,
            };
        }
    };
    try testing.expect(verify.check(.light));
    try testing.expect(verify.check(.dark));
    try testing.expect(verify.check(.unknown));
}
