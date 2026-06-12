# RA2 — M10-03: Release logging

> Roadmap item: M10-03  
> Depends on: M1-01 (App main loop — AppOptions, AppInner)  
> Read `00_constitution.md` before this file.

## Purpose

Provide a structured `std.log` wrapper that writes to a rolling file on disk. `App.init`
accepts an optional log-file path; when set, all `std.log` output is tee'd to that file
with a timestamp prefix and log level. The file rolls (truncates) when it exceeds 1 MiB.

---

## Motivation

Production binaries currently write logs only to stderr. When the application is launched
without a terminal (double-click on Windows, `.desktop` on Linux), log output is silently
lost. A file log makes post-crash debugging possible.

---

## What to build

### 1. `FileLogger` — `src/app/file_logger.zig`

```zig
const std = @import("std");

pub const FileLogger = struct {
    file: ?std.fs.File,
    path: []const u8,        // owned slice
    gpa: std.mem.Allocator,
    max_bytes: usize,        // roll threshold (default 1 MiB)
    bytes_written: usize,

    /// Open (or create) the log file at `path`. Creates parent directories.
    /// Returns a fully initialised FileLogger on success.
    pub fn init(gpa: std.mem.Allocator, path: []const u8, max_bytes: usize) !FileLogger;

    /// Flush and close the file. Frees owned memory.
    pub fn deinit(self: *FileLogger) void;

    /// Write one log line. Format:
    ///   YYYY-MM-DDTHH:MM:SS [LEVEL] message\n
    /// If `bytes_written` would exceed `max_bytes` after this write, truncate the file
    /// first (roll) and reset `bytes_written` to 0.
    pub fn log(
        self: *FileLogger,
        level: std.log.Level,
        scope: @TypeOf(.enum_literal),
        comptime format: []const u8,
        args: anytype,
    ) void;

    /// Flush buffered writes to disk.
    pub fn flush(self: *FileLogger) void;
};
```

### 2. `AppOptions` addition

```zig
/// Optional path for the file log. When null, no file log is written (stderr only).
/// Parent directories are created on first write if they do not exist.
log_path: ?[]const u8 = null,

/// Maximum file size before rolling (truncating). Default 1 MiB.
log_max_bytes: usize = 1024 * 1024,
```

### 3. `AppInner` integration

`AppInner` gains:

```zig
file_logger: ?FileLogger = null,
```

`AppInner.init`:
- When `opts.log_path != null`, initialises `file_logger` with `FileLogger.init(gpa, path, max_bytes)`.
- Installs a global `std.log.defaultLog` override (via the `root` module's `pub fn log` hook)
  that writes to both stderr and `file_logger` when the logger is present.

Because Zig's `std.log` override is application-global (set via `pub const log_level` and
`pub fn log` in `root`), the app layer provides a thin `pub fn log` in `src/app/logger.zig`
that callers include in their `root` module:

```zig
// src/app/logger.zig
pub fn log(
    comptime level: std.log.Level,
    comptime scope: @TypeOf(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void;
```

This function writes to stderr (always) and, if a global `*FileLogger` is set, to the file.
The global pointer is a module-level `var g_logger: ?*FileLogger = null` set by `AppInner.init`.

### 4. Log line format

```
2026-06-03T14:22:11 [info ] message text
2026-06-03T14:22:11 [err  ] error message
```

- Timestamp is UTC, ISO 8601 date + time, space-separated.
- Level is left-padded to 5 characters.
- Message is the formatted string from the `std.log` call.
- Each line ends with `\n`.

### 5. Rolling behavior

When a `log()` call would cause `bytes_written` to exceed `max_bytes`:
1. Seek to the start of the file.
2. Truncate the file to zero (`file.setEndPos(0)`).
3. Reset `bytes_written` to 0.
4. Write the new log line.

No rotation into a numbered file (e.g. `.1`, `.2`) — truncation is the only strategy.

---

## Module location

```
src/app/file_logger.zig       — FileLogger implementation
src/app/logger.zig            — Global log hook (pub fn log)
src/app/file_logger_test.zig  — unit tests (uses a temp file)
docs/requirements/RA2_release_logging.md
```

`src/app/types.zig` must re-export `FileLogger`.

---

## Invariant interactions

- **INV-5.6**: No new dependencies. File I/O uses `std.fs`; timestamps use `std.time`.
- **INV-1.2**: File path construction uses `std.fs.path.join` and `builtin.os.tag` —
  works on both Windows and Linux.
- **INV-1.1**: `log_path = null` (default) produces zero overhead — no file is opened
  and the global pointer remains null.

---

## Glossary addition

Add to `docs/specs/glossary.md`:

```
## FileLogger

A `std.log`-compatible sink that writes timestamped log lines to a file on disk. The file
rolls (truncates to zero) when it exceeds `max_bytes`. Installed globally by `AppInner.init`
when `AppOptions.log_path` is set. Defined in `src/app/file_logger.zig`. See: RA2 (M10-03).
```

---

## Non-goals (DO NOT implement — INV-5.4)

- NO log rotation into numbered backup files (`.1`, `.2`, etc.) — truncation only.
- NO compression of rolled logs.
- NO log levels configurable at runtime — `std.log.Level` from the call site is passed through.
- NO structured JSON output — plain-text lines only.
- NO network log shipping.
- NO buffering beyond what `std.fs.File.write` provides — each `log()` call writes immediately.
- NO per-module or per-scope filtering.

---

## Acceptance criteria

The module is done when:

1. `zig build test-file-logger` runs `src/app/file_logger_test.zig` and all tests pass.
2. `FileLogger.init` creates the file (and parent directories) if they do not exist.
3. `log()` writes a correctly formatted line including timestamp, level, and message.
4. After `bytes_written` exceeds `max_bytes`, the next `log()` truncates the file and
   resets `bytes_written` before writing the new line.
5. `deinit` closes the file without memory leaks.
6. `log_path = null` (default) leaves `file_logger` null; no file is opened.
7. The global `pub fn log` hook in `logger.zig` writes to both stderr and the file logger.

---

## Edge cases (each has a test)

- `log()` called before any prior writes → line appears at the start of the file.
- `log()` with a format string containing `%` characters → correctly formatted, no panic.
- `max_bytes` set to a very small value (e.g. 128) → rolls after the first long message.
- Log file parent directory does not exist → `init` creates it and succeeds.
- `flush()` on a null file (logger not initialised) → no-op, no crash.
