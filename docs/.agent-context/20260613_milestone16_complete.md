# Milestone 16 — Platform integrations — COMPLETE

Date: 2026-06-13
Branch: main

## Features implemented

| ID    | Feature                    | File(s)                                          | Status |
|-------|----------------------------|--------------------------------------------------|--------|
| RF0   | System tray icon (Win32)   | src/app/tray.zig                                 | done   |
| RF1   | Native file-open dialog    | src/01/types.zig (showOpenDialog)                | done   |
| RF2   | Native file-save dialog    | src/01/types.zig (showSaveDialog)                | done   |
| RF3   | OS color-scheme detection  | src/01/types.zig (getColorScheme, ColorScheme)   | done   |
| RF4   | MIME clipboard              | src/01/types.zig (setClipboardMime, getClipboard)| done   |

## Tests

- `test-tray` — headless Tray struct tests (12 tests, pass)
- `test-m16` — structural/compile-time tests for RF1–RF4 (22 tests, pass)
- Pre-existing full test suite: 240/241 pass (1 pre-existing failure in test-07-unit unrelated to M16)

## Known limitations

- Tray, showOpenDialog, showSaveDialog: Win32 only. Linux stubs compile but do nothing. Pending libnotify / GTK approval (INV-5.6).
- Behavioral unit tests for Win32 dialog + clipboard round-trips require a running Win32 session (cannot run in headless CI). Structural/compile-time tests added instead.

## Dependencies added

None. All Win32 APIs used (Shell_NotifyIconW, GetOpenFileNameW, GetSaveFileNameW, RegOpenKeyExW, RegisterClipboardFormatA, OpenClipboard, SetClipboardData, GetClipboardData) are accessed via the existing @cImport in module 01.
