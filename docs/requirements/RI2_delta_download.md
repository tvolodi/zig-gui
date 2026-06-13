# RI2 — M19-02: Delta download

> Roadmap item: M19-02  
> Depends on: M19-01 (Update manifest check)  
> Read `00_constitution.md` before this file.

## Purpose

Download only a binary diff (in bsdiff format) between the current running binary and the
newer version specified in the update manifest. Apply the diff in-process to reconstruct
the new binary, then hand off to M19-03 (staged update) for atomicity.

This dramatically reduces download size for typical updates (often 10–20% of the full binary).

After this item ships, the update flow is:
1. RI1: Detect newer version available.
2. **RI2: Download delta + apply to produce new binary** ← this step.
3. RI3: Write new binary to temp, verify, rename on next launch.
4. RI4: Show progress UI during download.

---

## What to build

### 1. `BinaryDelta` type — `src/app/update_manager.zig`

```zig
pub const BinaryDelta = struct {
    /// Pointer to the bsdiff-encoded diff data (owned).
    patch_data: []u8,
    patch_len: usize,
    
    /// Expected SHA256 of the new binary after patching.
    new_binary_sha256: [32]u8,
    
    /// Size of the original binary.
    original_size: usize,
    
    /// Size of the new binary after patching.
    new_size: usize,
};
```

### 2. `UpdateManager` additions

```zig
pub const UpdateManager = struct {
    // ... existing fields ...
    
    /// Downloaded binary diff (populated after download completes).
    current_delta: ?BinaryDelta = null,
    
    /// Downloaded new binary bytes (produced by applying the delta).
    new_binary_data: ?[]u8 = null,
    
    /// Progress: bytes downloaded so far (0–total).
    download_progress_bytes: usize = 0,
    download_total_bytes: usize = 0,
    
    /// Download state.
    is_downloading: bool = false,
    download_error: ?[]const u8 = null,

    /// Start downloading the binary delta from the URL specified in `latest_manifest.download_url`.
    /// The delta file must be in bsdiff format.
    /// Sets `is_downloading = true` and `download_error = null`.
    /// Call `tick()` to monitor progress.
    pub fn startDeltaDownload(self: *UpdateManager) void;

    /// Apply the downloaded delta patch to the current running binary to produce the
    /// new binary. The new binary is stored in `self.new_binary_data`.
    /// Returns true on success; on failure, returns false and populates `download_error`.
    /// Assumes `self.current_delta` is populated (call after download completes).
    pub fn applyDelta(self: *UpdateManager) bool;

    /// Check: is a complete patched binary ready for staging (RI3)?
    /// Returns true if the delta was downloaded, applied successfully, and the SHA256
    /// matches `latest_manifest.checksum_sha256`.
    pub fn isPatchedBinaryReady(self: *const UpdateManager) bool;
};
```

### 3. Binary delta fetch

```zig
/// Download a binary delta (bsdiff patch) from the given URL.
/// On success: populate `self.current_delta` with the patch data and metadata.
/// On failure: populate `download_error` with a message.
/// Progress is tracked in `download_progress_bytes` and `download_total_bytes`.
/// Must handle streaming downloads to avoid loading the entire patch into memory at once.
fn downloadBinaryDelta(self: *UpdateManager) !void;
```

### 4. Binary delta application

```zig
/// Apply a bsdiff patch to the current running binary.
/// Inputs:
///   - self.current_binary_path: path to the running executable
///   - self.current_delta.patch_data: the bsdiff patch
/// Output:
///   - self.new_binary_data: allocated buffer containing the new binary
/// Returns: !void (error if patching fails)
/// On failure: populate download_error with details and return an error.
fn applyBsdiffPatch(self: *UpdateManager) !void;
```

### 5. Frame loop integration

In `AppInner` frame loop:
- If `update_manager.is_downloading`, call `update_manager.tick()` to update progress.
- When download completes (tick returns true and !is_downloading), call
  `update_manager.applyDelta()`.
- If patching succeeds and `isPatchedBinaryReady()`, notify RI3 (staged update).

---

## Acceptance criteria

1. `startDeltaDownload()` sets `is_downloading = true` and `download_error = null`.
2. Progress tracking: `download_progress_bytes` increases as data is downloaded.
3. On successful download and patch: `new_binary_data` is populated with the reconstructed binary.
4. `applyDelta()` returns true on success; false on error (populate `download_error`).
5. Patch application validates the checksum: `SHA256(new_binary) == manifest.checksum_sha256`.
6. If checksum mismatch: return error and populate `download_error`.
7. `isPatchedBinaryReady()` returns false before download completes.
8. `isPatchedBinaryReady()` returns true after successful patch application.
9. `isPatchedBinaryReady()` returns false if checksum validation failed.
10. Streaming download: does NOT load the entire patch into memory at once (chunk-based).
11. Error cases (network failure, invalid patch format) populate `download_error`.
12. Patching memory is freed on `deinit()`.

---

## Non-goals

- No resume/retry on interrupted download (next app launch will re-check and re-download).
- No persistent cache of the patch (downloaded fresh, applied, then freed).
- No parallel downloads.
- No compression of the delta transmission (assume the HTTP transport handles gzip if needed).
- No signature validation of the patch (checksum of the output is the integrity check).

---

## Non-visual

No rendered output. Progress is exposed via `download_progress_bytes` and `download_total_bytes`
for RI4 (progress bar).

---

## HUMAN DECISION REQUIRED — bsdiff Library

**Blocker:** Applying a bsdiff patch requires either:
1. Binding to an existing bsdiff C library (e.g., `libbsdiff`), or
2. A pure-Zig implementation of the bsdiff/bspatch algorithm.

The Zig ecosystem does NOT have an approved bsdiff implementation. This is a HUMAN DECISION.

**Options:**

**Option A: Vendored pure-Zig bsdiff implementation**
- Implement bsdiff patch application in pure Zig (no C dependencies).
- Scope: parse the bsdiff format, compute linear combinations over the old binary,
  produce the new binary.
- Complexity: moderate (the algorithm is non-trivial but documented).
- Advantage: no external C dependency; fits the pure-Zig philosophy.
- Disadvantage: we own implementation and bugs; bsdiff is a specialized algorithm.

**Option B: Approve an external bsdiff library**
- Identify a Zig ecosystem bsdiff package or bind to `libbsdiff` / `brotli` (which includes bsdiff).
- Record in INV-5.6, requiring explicit human approval.
- Advantage: proven implementation; standardized binary format.
- Disadvantage: new external dependency; C bindings overhead.

**Option C: Use a simpler delta format**
- Instead of bsdiff, use a simpler delta encoding (e.g., VCDIFF / RFC 3284).
- Lower complexity; still achieves compression.
- Downside: less compression than bsdiff; slower patching.

**Option D: Defer delta download; ship full binary download only**
- Skip RI2 entirely; implement RI1, RI3, RI4 with full binary downloads.
- Users download the entire new binary (~50 MB typical).
- Simpler; no bsdiff dependency.
- Disadvantage: slower for users with slow connections.

**Recommendation for this task:**
- Proceed with RI2 spec authoring assuming **Option A** will be chosen.
- Flag bsdiff in the R-file as "HUMAN DECISION REQUIRED".
- Mark RI2 blocked pending this decision.
- RI1, RI3, RI4 can proceed in parallel (they do not depend on the bsdiff choice).

---

## HUMAN DECISION REQUIRED — HTTP Client Dependency (from RI1)

This R-file also depends on the HTTP client decision from RI1. See RI1 § for details.

---

## Dependencies

**New dependencies introduced (pending human decisions):**
- bsdiff library: TBD (see § above)
- HTTP client: TBD (inherited from RI1)

**Existing approved dependencies:**
- Zig std (SHA256 for checksum validation, memory management)

---

## Implementation notes

- The current running binary path can be retrieved via `std.fs.selfExePath(alloc)`.
- SHA256 validation must happen **before** handing the binary to RI3 (staged update).
- If patching fails, retain the error message for user-facing diagnostics (RI4 toast).
- The new binary is ephemeral (freed after RI3 writes it to disk); do not cache it.
- Consider a size limit: if the patch is > 80% of the full binary size, warn (likely better
  to download the full binary instead).

---

## bsdiff format reference (informational)

If a pure-Zig implementation is chosen, reference the bsdiff paper:
- Percival, Colin. "Naive Differences of Executable Code" (2003)
- Format: control block size (varint), diff block size (varint), new file size (varint),
  followed by control, diff, and extra blocks.
- See `bsdiff.org` for format details and reference implementation.
