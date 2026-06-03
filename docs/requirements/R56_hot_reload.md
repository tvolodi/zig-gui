# R56 — M5-07: Hot-reload

> Roadmap item: M5-07  
> Depends on: module 06 (`parse`), R54 (error reporting), M1-01 (`App.run`), module 07 (`Scene.reset`)  
> Read `00_constitution.md` before this file.

## Purpose

When the app is built with `-Dhot-reload=true`, a background file-watcher thread monitors
the `.ui` files listed in `build.zig`. When a file changes, it re-parses the markup, calls
`scene.reset()`, and re-instantiates the new tree — all without recompiling or restarting
the binary. This feature is for development only; it is compiled out entirely in production
builds.

## What to build

### Build flag

In `build.zig`, add:

```zig
const hot_reload = b.option(bool, "hot-reload", "Enable .ui file watcher for live editing") orelse false;
const options = b.addOptions();
options.addOption(bool, "hot_reload", hot_reload);
// Add the options module to the app module:
app_module.addImport("build_options", options.createModule());
```

All hot-reload code is gated on `build_options.hot_reload` at comptime:

```zig
const hot_reload = @import("build_options").hot_reload;

// In App.run() or wherever the watcher is invoked:
if (comptime hot_reload) {
    // watcher code
}
```

In release builds (`-Dhot-reload` not set), the watcher code is dead code and the parser
is not linked into the binary.

### File watcher — `src/app/file_watcher.zig`

A minimal file watcher that polls file modification times in a background thread.

```zig
/// A watched file entry. Stores the last-seen mtime so changes can be detected.
pub const WatchEntry = struct {
    path:       [:0]const u8,  // null-terminated for OS stat calls
    last_mtime: i128 = 0,      // nanosecond-precision mtime from std.fs.File.stat()
};

pub const FileWatcher = struct {
    entries:  std.ArrayListUnmanaged(WatchEntry),
    changed:  std.ArrayListUnmanaged(u32),  // indices of entries that changed since last poll
    gpa:      std.mem.Allocator,

    pub fn init(gpa: std.mem.Allocator) FileWatcher

    pub fn deinit(self: *FileWatcher) void

    /// Add a file to watch. Path is copied; caller need not keep it alive.
    pub fn addFile(self: *FileWatcher, path: []const u8) !void

    /// Poll all watched files for mtime changes.
    /// Appends the indices of changed files to `self.changed`.
    /// Call once per frame (or on a background thread — see threading model).
    pub fn poll(self: *FileWatcher) void

    /// Drain the changed-file list. Returns a slice of entry indices; valid until next poll.
    pub fn drainChanged(self: *FileWatcher) []const u32
};
```

### Threading model — main-thread poll (v1)

v1 uses **main-thread polling** rather than a background thread. `FileWatcher.poll()` is
called once per frame in `App.run()`, inside the existing hot-reload guard. On Windows and
Linux, `stat()`-based mtime polling is fast enough (~microseconds per file) for the small
number of `.ui` files in a typical project.

A background thread with OS-specific inotify/ReadDirectoryChangesW would be faster but
adds synchronization complexity. That is post-v1. The v1 polling approach is safe and
correct.

```zig
// In App.run(), inside the comptime hot_reload gate:
if (comptime hot_reload) {
    watcher.poll();
    for (watcher.drainChanged()) |entry_idx| {
        const entry = &watcher.entries.items[entry_idx];
        reloadFile(app, entry.path, &diag) catch |err| {
            std.log.err("hot-reload: {}", .{err});
        };
    }
}
```

### `reloadFile` — the reload procedure

```zig
fn reloadFile(app: *App, path: [:0]const u8, diag: ?*ParseDiagnostic) !void {
    // 1. Read the changed .ui file.
    const source = try std.fs.cwd().readFileAlloc(app.gpa, path, 1024 * 1024);
    defer app.gpa.free(source);

    // 2. Parse with diagnostics.
    var arena = std.heap.ArenaAllocator.init(app.gpa);
    // Arena owns the NodeDesc tree for instantiate.

    var diag_val: ParseDiagnostic = undefined;
    const root = parse(arena.allocator(), source, &diag_val) catch |err| {
        if (err == error.ParseFailed) {
            std.log.err("[hot-reload] {s}:{}:{}: {} — {s}",
                .{ path, diag_val.loc.line, diag_val.loc.column, diag_val.err, diag_val.message });
        }
        arena.deinit();
        return;  // Keep the old scene; do not reset on parse failure.
    };
    _ = root;

    // 3. Reset scene and bindings.
    app.scene.reset();
    app.bindings.deinit(app.gpa);
    app.bindings = BindingSet.init();

    // 4. Re-instantiate.
    const new_root_id = try app.scene.instantiate(root, app.tokens);
    _ = new_root_id;

    // 5. Re-run measure pass.
    try app.scene.measurePass(&app.font, &app.glyph_atlas);

    // 6. Mark all elements dirty so the next frame paints the new tree.
    app.scene.elements.markAllDirty();

    // 7. Free the parse arena.
    arena.deinit();

    std.log.info("[hot-reload] reloaded {s}", .{path});
}
```

**Parse failure behavior:** on a parse error, the old scene is kept intact. The error is
logged with line and column. The next poll will try again if the file changes again.

**Binding invalidation:** after `scene.reset()`, all element indices are stale. Bindings
are cleared (`bindings.deinit` + re-init). The application must re-register its bindings.
For simple apps (static screen only, no dynamic bindings), this is a no-op. For apps with
signals, the developer must provide a `rebind()` function that re-calls `bindText` /
`bindCond` after each reload. **How to wire `rebind` is the application's responsibility;
the framework does not automate it.** Document this in `HOW_TO_USE.md`.

### `App` changes

Add to `App` (behind the hot_reload comptime gate):

```zig
// Only present when hot_reload is true:
watcher: if (comptime hot_reload) FileWatcher else void,

// In App.init (hot_reload path):
if (comptime hot_reload) {
    app.watcher = FileWatcher.init(gpa);
    for (ui_file_paths) |path| {
        try app.watcher.addFile(path);
    }
}

// In App.deinit (hot_reload path):
if (comptime hot_reload) {
    app.watcher.deinit();
}
```

`ui_file_paths` is a comptime-known list of `.ui` file paths (same list used by the codegen
step in M5-06). The application passes it when constructing `App`.

### `zig build run-dev` convenience target

Add a convenience build step that builds the app with `-Dhot-reload=true` and runs it:

```zig
const run_dev = b.step("run-dev", "Run the app with hot-reload enabled");
const exe_dev = b.addExecutable(.{
    .name = "zig-gui-dev",
    // ... same as normal exe but with hot_reload option set ...
});
// exe_dev inherits the same modules; add build_options with hot_reload = true.
const run = b.addRunArtifact(exe_dev);
run_dev.dependOn(&run.step);
```

### Behavioral contract

| Situation | Behavior |
|---|---|
| File unchanged between frames | No action; `drainChanged()` returns empty slice |
| File changed, parse succeeds | Scene reset + re-instantiate; all elements repainted next frame |
| File changed, parse fails | Error logged with line/column; old scene kept; retry on next change |
| Multiple files changed in same frame | Each changed file triggers one reload in order |
| `-Dhot-reload` not set | All watcher code compiled out; `parse` not linked into binary |

### Module location

```
src/app/file_watcher.zig  — FileWatcher, WatchEntry
src/app/app.zig           — reloadFile, watcher field, poll call in run loop
build.zig                  — hot_reload option, run-dev step
docs/requirements/R56_hot_reload.md
```

## Public API

New (hot-reload only):

```zig
pub const WatchEntry = struct { path, last_mtime }
pub const FileWatcher = struct {
    pub fn init(gpa) FileWatcher
    pub fn deinit(self) void
    pub fn addFile(self, path) !void
    pub fn poll(self) void
    pub fn drainChanged(self) []const u32
}
```

## Non-goals (DO NOT implement — INV-5.4)

- **No OS-native file events** (inotify / ReadDirectoryChangesW) — mtime polling only in
  v1. OS-native watchers are post-v1.
- **No background thread** — polling runs on the main thread once per frame. A background
  watcher thread with cross-thread notification is post-v1.
- **No automatic signal rebinding** — after a reload, application-level signals are not
  automatically reconnected to new element indices. The developer provides a `rebind()`
  hook. Automatic wiring is blocked on a reflection system that does not exist in v1.
- **No partial tree update** — reload always resets the entire scene; incremental patching
  is blocked on structural diffing, which is post-v1.
- **No hot-reload for Zig code** — only `.ui` markup files are watched; Zig source changes
  require recompile and restart.
- **No rollback on crash** — if re-instantiation panics, the process aborts. Crash-safe
  reload with a previous-scene fallback is post-v1.
- **No reload of binary assets** (fonts, images) — only `.ui` markup files.

## Acceptance criteria

1. `zig build run-dev` starts the app. Editing a `.ui` file and saving causes the screen to
   visually update within one frame (< 16 ms poll latency at 60 fps).

2. A malformed `.ui` file (e.g. unclosed tag) logs an error with line and column and
   keeps the previous scene visible (no crash, no blank screen).

3. The production binary (`zig build run`) does not contain a reference to `parse` or
   `FileWatcher` (verify with `zig objdump --syms` or equivalent).

4. `FileWatcher.poll()` on a directory with 10 files completes in < 1 ms on the test
   machine (mtime stat cost).

5. After reload, the new element tree behaves correctly: buttons are clickable, text is
   readable, layout matches the new markup.

6. Checklist fully ticked.

## Open questions

One: **binding rebind hook.** The cleanest v1 approach is a user-provided function pointer
on `App` (something like `rebind_fn: ?*const fn(*App) anyerror!void = null`) that is called
after every successful reload. The application sets it up once. Confirm this design with the
human before implementing — the alternative (no hook, documented as a known limitation) is
simpler but less ergonomic.
