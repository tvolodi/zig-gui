# RI1 — M19-01: Update manifest check

> Roadmap item: M19-01  
> Depends on: M10-03 (Release logging — structured app-layer error handling)  
> Read `00_constitution.md` before this file.

## Purpose

On application startup, fetch a JSON manifest from a configured URL and compare the bundled
version string. Notify the user (via release log and toast) if a newer version is available.
This is the first step of the auto-update pipeline: it detects an available update without
downloading or installing anything.

After this item ships, an application author configures:

```zig
var app = try App.init(gpa, opts.{
    .update_manifest_url = "https://example.com/app-manifest.json",
    .current_version = "1.0.0",
});
```

On `App.init`, the manifest is fetched in a background task. If newer, a log entry is written
and an internal signal flags the availability. The app may then check this signal to display
a toast or badge.

---

## What to build

### 1. `UpdateManifest` type — `src/app/update_manager.zig`

```zig
pub const UpdateManifest = struct {
    version: []const u8,    // semantic version string (e.g., "1.0.1")
    download_url: []const u8, // URL to download the new binary / delta
    checksum_sha256: [32]u8, // SHA256 hash of the binary (32 bytes)
    release_notes: ?[]const u8, // optional; displayed in the UI
};
```

### 2. `UpdateManager` — `src/app/update_manager.zig`

```zig
pub const UpdateManager = struct {
    gpa: std.mem.Allocator,
    current_version: []const u8,  // owned copy of the version string
    manifest_url: ?[]const u8,    // owned copy; null = no manifest URL configured
    latest_manifest: ?UpdateManifest, // lazily populated on fetch
    fetch_error: ?[]const u8,     // if fetch failed, error message (owned)
    is_checking: bool,            // true while fetch is in-flight
    check_time_ms: i64,           // timestamp of last successful fetch

    /// Initialize. Does NOT fetch yet.
    pub fn init(
        gpa: std.mem.Allocator,
        current_version: []const u8,
        manifest_url: ?[]const u8,
    ) !UpdateManager;

    /// Deinitialize. Frees owned memory.
    pub fn deinit(self: *UpdateManager) void;

    /// Start a non-blocking manifest fetch from `self.manifest_url`.
    /// Returns immediately; the actual fetch happens asynchronously.
    /// Sets `is_checking = true` and `fetch_error = null`.
    /// Call `tick()` each frame to check if the fetch completed.
    pub fn startFetch(self: *UpdateManager) void;

    /// Poll the fetch status. Returns true if a fetch completed this tick.
    /// On completion: if successful, populates `latest_manifest` and clears `is_checking`.
    /// If failed, populates `fetch_error` and clears `is_checking`.
    pub fn tick(self: *UpdateManager) bool;

    /// Check: is a newer version available?
    /// Returns true if `latest_manifest` was successfully fetched AND
    /// `latest_manifest.version > current_version` (semantic version compare).
    pub fn isUpdateAvailable(self: *const UpdateManager) bool;
};
```

### 3. `AppOptions` addition

```zig
/// Optional URL to fetch the update manifest. If set, the app will check for updates
/// on startup via `UpdateManager.startFetch()`.
update_manifest_url: ?[]const u8 = null,

/// Current app version (e.g., "1.0.0"). Required if `update_manifest_url` is set.
/// Compared against `manifest.version` to detect newer builds.
current_version: ?[]const u8 = null,
```

### 4. `AppInner` integration

`AppInner` gains:

```zig
update_manager: ?UpdateManager = null,
```

In `AppInner.init`:
- If `opts.update_manifest_url != null`, initialize `update_manager` with
  `UpdateManager.init(gpa, opts.current_version, opts.update_manifest_url)`.
- Immediately call `update_manager.startFetch()` to begin the background fetch.

In the frame loop (after `dispatchEvents`, before `beginFrame`):
- If `update_manager` exists, call `update_manager.tick()`.
- If it returns true (fetch completed), log the result via `std.log.info` or `.err`.
- If `update_manager.isUpdateAvailable()`, optionally signal a toast (future: M19-04).

### 5. Manifest fetch implementation

**HTTP Client Requirement:** Fetching the manifest requires an HTTP GET. This is a HUMAN
DECISION REQUIRED issue (see §6 below).

The fetch implementation must:
- Read the manifest URL from `self.manifest_url`.
- Issue a GET request.
- Parse the response as JSON with this schema:

```json
{
  "version": "1.0.1",
  "download_url": "https://example.com/app-1.0.1.zip",
  "checksum_sha256": "abcd1234...",
  "release_notes": "Bug fixes and performance improvements"
}
```

- Validate that all required fields are present and correctly typed.
- Store the result in `self.latest_manifest`.
- Record the fetch timestamp in `self.check_time_ms` (use `std.time.milliTimestamp()`).

### 6. Version comparison

```zig
/// Parse a semantic version string (e.g., "1.0.1") into (major, minor, patch).
/// Returns (0, 0, 0) if parsing fails.
fn parseVersion(version_str: []const u8) struct { major: u32, minor: u32, patch: u32 };

/// Return true if `new > current` using semantic version rules.
/// "1.1.0" > "1.0.9", "2.0.0" > "1.9.9", etc.
fn isNewerVersion(current: []const u8, new: []const u8) bool;
```

---

## Acceptance criteria

1. `UpdateManager.init()` succeeds with a null manifest URL (no-op update check).
2. `UpdateManager.init()` succeeds with a non-null manifest URL.
3. `UpdateManager.deinit()` frees all owned memory without errors.
4. `isUpdateAvailable()` returns false when no manifest has been fetched.
5. `isUpdateAvailable()` returns false when the fetched version is older or equal to current.
6. `isUpdateAvailable()` returns true when the fetched version is newer.
7. Semantic version comparison: "1.0.1" > "1.0.0" ✓; "2.0.0" > "1.9.9" ✓; "1.0.0" == "1.0.0" ✗.
8. `startFetch()` sets `is_checking = true` and clears `fetch_error`.
9. `tick()` returns true exactly once when a fetch completes.
10. `tick()` returns false when no fetch is in-flight or still in-flight.
11. On fetch error (network, malformed JSON), `fetch_error` is populated with a message.
12. On fetch success, `latest_manifest` is populated and `fetch_error` is null.
13. `AppInner` initializes `UpdateManager` when `opts.update_manifest_url != null`.
14. Frame loop calls `tick()` every frame when `update_manager` exists.
15. Non-test environments tolerate null manifest URL (update checking disabled).

---

## Non-goals

- No automatic periodic re-checks (this is M19-02 territory — delta download triggers re-check).
- No UI for "check now" or "skip this version" (deferred).
- No local cache of the manifest (fetched fresh each app launch).
- No timeout on the fetch (use a sensible HTTP timeout; exact value TBD).
- No integration with the actual download (M19-02 handles download; this is detection only).
- No HTTPS certificate validation (use system-default CA bundles; defer custom certs).

---

## Non-visual

This feature produces no rendered output. The update detection is logged and exposed via an
internal signal; the UI (M19-04) handles notification rendering.

---

## HUMAN DECISION REQUIRED — HTTP Client Dependency

**Blocker:** Fetching a JSON manifest from a URL requires an HTTP client library. The Zig
standard library does NOT provide HTTP out of the box. Current approved dependencies (GLFW,
Vulkan, stb_truetype, libdbus) do not include an HTTP client.

**Options:**

**Option A: Vendored minimal HTTP client (pure Zig)**
- Implement a minimal synchronous HTTP/1.1 GET client in pure Zig (no C dependencies).
- Scope: parse URL, establish socket/TLS connection, send GET headers, read response body.
- Complexity: moderate; TLS support is non-trivial.
- Advantage: no new external dependency; pure Zig; small binary footprint.
- Disadvantage: we own the implementation and all future bugs.

**Option B: Approve an external Zig HTTP library**
- Identify a Zig ecosystem HTTP client (e.g., `zig-http`, `zurl`, if they exist and are
  maintained).
- Record it in INV-5.6 (`00_constitution.md`), triggering a formal human decision.
- Advantage: battle-tested implementation; maintainers own bugs.
- Disadvantage: adds an external dependency; requires human approval in writing.

**Option C: Defer auto-update to post-v1; implement packaging only (M19-05 without download)**
- Skip RI1, RI2, RI3, RI4 entirely.
- Implement only M19-05 (app installer) — bundle the binary + manifest into a zip, no
  automatic checks.
- Users download updates manually from a website.
- Advantage: ships the core framework without introducing HTTP.
- Disadvantage: users do not get automatic notifications; less convenient.

**Recommendation for this task:**
- Proceed with M19-01–M19-04 spec authoring assuming **Option A** or **Option B** will be
  chosen by the human.
- Flag HTTP client in the R-file as "HUMAN DECISION REQUIRED" and mark RI1–RI4 blocked
  pending this decision.
- M19-05 (packaging) does NOT require HTTP and can proceed independently.

---

## Dependencies

**New dependencies introduced (pending human decision):**
- HTTP client: TBD (see § above)

**Existing approved dependencies:**
- Zig std (JSON parsing, version string handling, logging)
- App layer (signals, toast integration, M19-04)

---

## Implementation notes

- The fetch should be non-blocking; use platform threads (via `std.Thread`) or a simple
  async task queue.
- If the manifest fetch takes > 30 seconds, timeout and populate `fetch_error`.
- Log successful fetches: `std.log.info("Update available: {s}", .{new_version})`.
- Log fetch errors: `std.log.err("Manifest fetch failed: {s}", .{error_message})`.
- The `latest_manifest` is not persisted; it is re-fetched on every app launch.
