# RF3 — M16-04: OS native color-scheme detection

> Roadmap item: M16-04
> Depends on: M9-04 (theme live-swap — `AppInner.setTheme`, `AppInner.toggleTheme`)
> Read `00_constitution.md` before this file.

## Purpose

At startup, read the OS preference for light or dark UI and apply it as the initial theme
mode. This means the app launches in the correct mode automatically — dark mode for users who
have enabled it in system settings, light mode otherwise — without the user needing to toggle
anything. The detection is read-once at startup (not a live system-preference listener).

The API lives in `Platform` in `src/01/types.zig` (module 01). The app layer reads it during
`AppInner.init` and calls `setTheme` accordingly.

## What to build

### `ColorScheme` enum — `src/01/types.zig`

```zig
/// The OS-reported user preference for light or dark UI.
pub const ColorScheme = enum {
    light,
    dark,
    /// The OS preference could not be determined; use the app default.
    unknown,
};
```

### `Platform.getColorScheme` — `src/01/types.zig`

```zig
pub const Platform = struct {
    // ...existing fields...

    /// Read the OS current color-scheme preference.
    /// Call this once at startup before the first frame.
    /// Returns .light, .dark, or .unknown.
    /// Does NOT register a system listener — call again to refresh if needed.
    pub fn getColorScheme(self: *const Platform) ColorScheme
};
```

### Win32 implementation

```zig
// Registry path:
//   HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize
//   Value name: AppsUseLightTheme  (REG_DWORD)
//   0 = dark mode, 1 = light mode, absent = unknown

pub fn getColorScheme(self: *const Platform) ColorScheme {
    _ = self;
    // Use RegOpenKeyExW / RegQueryValueExW (Win32 registry API),
    // available via the existing @cImport in module 01 (winreg.h is included
    // transitively through windows.h).
    //
    // Steps:
    // 1. RegOpenKeyExW(HKEY_CURRENT_USER,
    //      L"SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize",
    //      0, KEY_READ, &hkey)
    //    On failure → return .unknown.
    // 2. RegQueryValueExW(hkey, L"AppsUseLightTheme", null, &type, &data, &size)
    //    On failure → RegCloseKey; return .unknown.
    // 3. RegCloseKey(hkey).
    // 4. If data == 0 → return .dark;
    //    If data == 1 → return .light;
    //    else → return .unknown.
}
```

No new Win32 header is required: `winreg.h` is already included via `windows.h` in the
existing module 01 `@cImport`.

### Linux implementation

On Linux, `gsettings` (a subprocess) is NOT used — subprocess spawning adds complexity and
may not be available in all environments. Instead, inspect environment variables:

```zig
pub fn getColorScheme(self: *const Platform) ColorScheme {
    _ = self;
    // Check GTK_THEME environment variable:
    //   If set and ends with ":dark" (case-insensitive) → return .dark.
    //   If set and ends with ":light" (case-insensitive) → return .light.
    //
    // Check XDG_CURRENT_DESKTOP + GNOME_DESKTOP_SESSION_ID for context.
    // Fallback: check COLORTERM or TERM environment variables for dark hints.
    //
    // Specifically:
    //   const gtk_theme = std.posix.getenv("GTK_THEME") orelse "";
    //   if (std.mem.endsWith(u8, gtk_theme, ":dark")) return .dark;
    //   if (std.mem.endsWith(u8, gtk_theme, ":light")) return .light;
    //
    //   // KDE / KColorScheme hint:
    //   const kde_scheme = std.posix.getenv("KDE_SESSION_VERSION") orelse "";
    //   // KDE sets COLORFGBG: dark bg is "15;default;0"
    //   const colorfgbg = std.posix.getenv("COLORFGBG") orelse "";
    //   if (std.mem.endsWith(u8, colorfgbg, ";0")) return .dark;
    //
    //   return .unknown;
    //
    // No subprocess. No file I/O beyond getenv (Zig std — approved).
}
```

### App layer integration

In `src/app/app.zig`, `AppInner.init` gains:

```zig
// After Platform.init, before the first frame:
const scheme = platform.getColorScheme();
const initial_mode: ThemeMode = switch (scheme) {
    .dark    => .dark,
    .light   => .light,
    .unknown => app_options.default_theme_mode, // fall back to app default
};
self.setTheme(Theme.build(self._current_palette, initial_mode));
```

`AppOptions` gains:

```zig
pub const AppOptions = struct {
    // ...existing fields...
    /// Theme mode used when the OS preference cannot be determined.
    /// Defaults to .light.
    default_theme_mode: ThemeMode = .light,
};
```

`ThemeMode` is the existing type from `src/05/types.zig` (module 05). The app layer imports
it; module 01 does NOT import module 05 (that would violate INV-3.4).
`getColorScheme` returns a `ColorScheme` (module 01 enum). The app layer maps it to a
`ThemeMode`. The mapping lives in the app layer, not in module 01.

### Module location

```
src/01/types.zig       — ColorScheme enum, Platform.getColorScheme signature
src/01/platform.zig    — Win32 registry read + Linux env-var check
src/app/types.zig      — AppOptions.default_theme_mode field
src/app/app.zig        — getColorScheme call in AppInner.init, mapping to ThemeMode
```

## Non-goals (DO NOT implement — INV-5.4)

- **No live system-preference listener** — read-once at startup only. No RegisterForNotify,
  no WM_SETTINGCHANGE handling, no ongoing polling.
- **No gsettings subprocess** — env-var approach only on Linux.
- **No portal API (XDG desktop portal)** — post-v1 enhancement.
- **No per-app theme override** — this reads the OS preference, not an in-app setting.
  `AppInner.toggleTheme` already handles user-driven overrides.
- **No macOS support** — Windows and Linux only (INV-1.2).
- **No color-scheme preference for non-app surfaces** — `AppsUseLightTheme` is used, not
  `SystemUsesLightTheme` (which controls the taskbar and title bars on Windows).

## Acceptance criteria

1. `ColorScheme` enum has variants `.light`, `.dark`, and `.unknown` in `src/01/types.zig`.
2. `Platform.getColorScheme()` returns `.dark` on a Windows system configured to dark mode
   (`AppsUseLightTheme = 0`).
3. `Platform.getColorScheme()` returns `.light` on a Windows system configured to light mode
   (`AppsUseLightTheme = 1`).
4. `Platform.getColorScheme()` returns `.unknown` when the registry key is absent.
5. On Linux, `Platform.getColorScheme()` returns `.dark` when `GTK_THEME` ends with `:dark`.
6. On Linux, `Platform.getColorScheme()` returns `.light` when `GTK_THEME` ends with `:light`.
7. On Linux, `Platform.getColorScheme()` returns `.unknown` when no env-var hint is present.
8. `AppInner.init` calls `getColorScheme()` and invokes `setTheme` before the first frame.
9. When `getColorScheme()` returns `.unknown`, `AppOptions.default_theme_mode` is used.
10. `getColorScheme()` does not spawn subprocesses; it uses only Win32 registry APIs (Win32)
    and `std.posix.getenv` (Linux) — both within the approved dependency set.
11. Unit tests cover: Win32 registry value parsing (mock registry data), Linux env-var cases,
    and .unknown fallback.
