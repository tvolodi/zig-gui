# R82 — M8-03: Persistent settings

> Roadmap item: M8-03  
> Depends on: M1-01 (App main loop)  
> Read `00_constitution.md` before this file.

## Purpose

Read and write a small, typed key-value store to disk so that the application can remember
user preferences (window size, theme preference, last-used values) across restarts.

An application author writes:

```zig
var prefs = try PersistentSettings.load(gpa, "my-app");
defer prefs.deinit();

// Read (returns null if not set):
const w = prefs.getU32("window_width") orelse 1280;
const theme = prefs.getString("theme") orelse "light";

// Write (flushed lazily or explicitly):
try prefs.setU32("window_width", 1400);
try prefs.setString("theme", "dark");
try prefs.flush();   // write to disk
```

---

## Motivation

Without persistent settings the user's window size resets to the default on every launch and
there is no way to remember a theme preference. This is the minimum required to feel like a
real application. The store intentionally covers only a handful of value types and never
stores arbitrary data — large data belongs in a proper database.

---

## What to build

### 1. Storage format

A line-oriented UTF-8 text file. Each line is one key-value pair in the form:

```
<key>=<encoded-value>\n
```

Rules:
- `<key>` is a non-empty ASCII identifier string (letters, digits, underscores, hyphens).
  No spaces. Maximum length 128 bytes.
- `<encoded-value>` is the value encoded as a string (see encoding below).
- Lines beginning with `#` are ignored (comments). Preserved on flush.
- Blank lines are ignored. Preserved on flush.
- Unknown value prefixes are silently ignored on load and NOT re-emitted on flush
  (forward compatibility: newer versions of the app may have written values this version
  does not understand; dropping them on next flush is acceptable).

Value encoding:
- `u32` → decimal digits, e.g. `1280`
- `i32` → decimal digits with optional leading `-`, e.g. `-42`
- `f32` → decimal representation, e.g. `1.5`
- `bool` → `true` or `false`
- `string` → URL-percent-encoded UTF-8 so that newlines and `=` signs in values are safe.
  Encode only the characters that would break the format: `%`, `\r`, `\n`, `=`.
  Decoding is the reverse. Maximum decoded length 4096 bytes.

### 2. File location

The settings file is stored in a platform-appropriate user-data directory:

- **Windows**: `%APPDATA%\<app_name>\settings.txt`
- **Linux**: `$XDG_CONFIG_HOME/<app_name>/settings.txt` if `XDG_CONFIG_HOME` is set, else
  `$HOME/.config/<app_name>/settings.txt`.

`PersistentSettings.load` creates the directory if it does not exist (using
`std.fs.makeDirAbsolute` with `std.fs.path.join`). If creation fails the error is returned
to the caller.

The `<app_name>` argument to `load` is an ASCII identifier string (same rules as a key).
Maximum 64 bytes.

### 3. `PersistentSettings` struct

```zig
pub const PersistentSettings = struct {
    gpa: std.mem.Allocator,
    path: []const u8,            // owned absolute path to the settings file
    entries: EntryMap,           // HashMap(key → Entry)
    dirty: bool,                 // true when in-memory state diverges from disk

    const EntryMap = std.StringHashMapUnmanaged(Entry);

    const Entry = union(enum) {
        u32: u32,
        i32: i32,
        f32: f32,
        bool: bool,
        string: []const u8,    // owned slice
    };

    /// Load from disk. Creates the file (and parent dir) if it does not exist.
    /// Returns a fully initialised PersistentSettings on success.
    pub fn load(gpa: std.mem.Allocator, app_name: []const u8) !PersistentSettings;

    /// Free all memory. Does NOT flush to disk automatically (call flush() first if needed).
    pub fn deinit(self: *PersistentSettings) void;

    // ---- Getters (return null if key absent or type mismatch) ----

    pub fn getU32(self: *const PersistentSettings, key: []const u8) ?u32;
    pub fn getI32(self: *const PersistentSettings, key: []const u8) ?i32;
    pub fn getF32(self: *const PersistentSettings, key: []const u8) ?f32;
    pub fn getBool(self: *const PersistentSettings, key: []const u8) ?bool;
    /// Returned slice is valid until the next set/flush/deinit call.
    pub fn getString(self: *const PersistentSettings, key: []const u8) ?[]const u8;

    // ---- Setters (mark dirty; do NOT write to disk immediately) ----

    pub fn setU32(self: *PersistentSettings, key: []const u8, value: u32) !void;
    pub fn setI32(self: *PersistentSettings, key: []const u8, value: i32) !void;
    pub fn setF32(self: *PersistentSettings, key: []const u8, value: f32) !void;
    pub fn setBool(self: *PersistentSettings, key: []const u8, value: bool) !void;
    pub fn setString(self: *PersistentSettings, key: []const u8, value: []const u8) !void;

    /// Remove a key. Does nothing if absent. Marks dirty.
    pub fn remove(self: *PersistentSettings, key: []const u8) void;

    /// Write current state to disk. A no-op when !dirty.
    /// Writes to a temp file then renames (atomic on both platforms).
    pub fn flush(self: *PersistentSettings) !void;

    /// Returns true if in-memory state has been modified since the last flush/load.
    pub fn isDirty(self: *const PersistentSettings) bool;
};
```

### 4. Atomic write

`flush` writes to `<path>.tmp`, then renames the temp file to `<path>`. This avoids a
half-written settings file if the process is killed mid-write. On Windows, rename uses
`std.fs.rename`; on Linux, `std.posix.rename`. Both are available in the Zig standard
library with no additional dependencies (INV-5.6).

### 5. Key validation

`load`, `getX`, and `setX` do NOT validate key strings beyond a debug-mode assert that the
key is non-empty and contains only printable ASCII. Invalid keys in production are silently
ignored on load and cause undefined behavior in set if the assert is disabled — the caller
is expected to use only literal string constants as keys.

---

## Module location

```
src/app/persistent_settings.zig       — PersistentSettings implementation
src/app/persistent_settings_test.zig  — acceptance tests (file I/O using a temp dir)
docs/requirements/R82_persistent_settings.md
```

`src/app/types.zig` must re-export `PersistentSettings`.

---

## Invariant interactions

- **INV-5.6**: No new dependencies. All I/O uses `std.fs` and `std.fmt` from the Zig
  standard library.
- **INV-1.1**: No extension points. The type set (u32/i32/f32/bool/string) is hardcoded;
  new types are added only when a spec requires them.
- **INV-1.2**: Platform detection for the storage path uses `builtin.os.tag` at comptime —
  no runtime OS probing.

---

## Glossary addition

Add to `docs/specs/glossary.md`:

```
## PersistentSettings

A line-oriented key-value store written to the platform user-data directory
(`%APPDATA%\<app>\settings.txt` on Windows, `~/.config/<app>/settings.txt` on Linux).
Supports u32, i32, f32, bool, and string values. Writes are deferred until `flush()` is
called. Flush is atomic (write-to-tmp then rename). Defined in
`src/app/persistent_settings.zig`.

See: R82 (M8-03).
```

---

## Non-goals (DO NOT implement — INV-5.4)

- NO automatic flush on deinit — the caller decides when to flush.
- NO encryption or authentication of stored values.
- NO file locking — single process, single thread (INV-2.2 / GLFW single-thread).
- NO section / namespace support within one file — a flat key space is sufficient.
- NO binary format — text-only; readability and debuggability outweigh compactness here.
- NO large values (> 4096 bytes for strings) — use a proper file/database for large data.
- NO migration / versioning system for the file format.

---

## Acceptance criteria

The module is done when:

1. `zig build test-settings` runs `src/app/persistent_settings_test.zig` and all tests pass.
2. `load` on a non-existent file creates the file and parent directories without error.
3. `setU32` + `flush` + fresh `load` round-trips the value correctly.
4. `setString` with a value containing `=`, `\n`, and `%` round-trips correctly.
5. `getBool` returns `null` for a key that holds a `u32` (type mismatch → null).
6. `flush` is a no-op when `isDirty()` is false.
7. Killing the process between the temp-write and rename leaves the original file intact
   (verified by manually inspecting the temp file lifecycle in the test).
8. `deinit` produces no memory leaks (tested with `std.testing.allocator`).
9. The checklist for this item is fully ticked.

---

## Edge cases (each has a test)

- File with comment lines and blank lines → loaded correctly; comments and blank lines
  preserved on flush.
- Key with an unknown value prefix (from a future version) → silently ignored on load;
  NOT emitted on flush.
- `remove` a key that does not exist → no error, `isDirty()` unchanged.
- `setString` called twice with the same key → second value replaces first; old slice freed.
- `app_name` containing a path separator → `load` returns `error.InvalidAppName` (asserts
  in debug mode).
- `flush` fails mid-write (e.g. disk full) → original file is unchanged (temp file rename
  never happened).
