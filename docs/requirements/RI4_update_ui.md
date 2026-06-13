# RI4 — M19-04: Update UI

> Roadmap item: M19-04  
> Depends on: M19-02 (Delta download — progress tracking) and M7-05 (Toast manager)  
> Read `00_constitution.md` before this file.

## Purpose

Display user-facing notifications and progress indicators for the update pipeline:
1. **Update available toast:** When RI1 detects a newer version, show a toast with
   "Update available — restart to apply" or "Downloading update…".
2. **Download progress bar:** While RI2 is downloading the delta, show a progress bar
   (optionally in a modal or status overlay).
3. **Update staged toast:** When RI3 successfully stages the update, show "Update ready —
   restart the app to apply".
4. **Error toasts:** If any step fails, show the error message.

After this item ships, users see real-time feedback about the update status.

---

## What to build

### 1. `UpdateUiManager` — `src/app/update_ui_manager.zig`

```zig
pub const UpdateUiManager = struct {
    gpa: std.mem.Allocator,
    
    /// Is a progress UI (progress bar) currently visible?
    is_progress_visible: bool = false,
    
    /// Is a modal dialog for updates currently open?
    is_dialog_open: bool = false,

    /// Initialize the UI manager.
    pub fn init(gpa: std.mem.Allocator) !UpdateUiManager;

    /// Deinitialize. Frees any allocated state.
    pub fn deinit(self: *UpdateUiManager) void;

    /// Show an update-available toast (non-blocking).
    /// Message: "Update available: v{new_version} — tap to download" or similar.
    /// Kind: info or accent.
    pub fn showUpdateAvailableToast(
        self: *UpdateUiManager,
        toast_mgr: *ToastManager,
        new_version: []const u8,
        now_ms: i64,
    ) void;

    /// Show a download-progress UI (progress bar + cancel button).
    /// Displays the percentage and bytes downloaded / total.
    pub fn showDownloadProgress(
        self: *UpdateUiManager,
        scene: *Scene,
        toast_mgr: *ToastManager,
        now_ms: i64,
    ) void;

    /// Update the progress bar with current download stats.
    /// Call this every frame while downloading.
    pub fn updateDownloadProgress(
        self: *UpdateUiManager,
        bytes_downloaded: usize,
        total_bytes: usize,
    ) void;

    /// Hide the download progress UI (called when download completes or is cancelled).
    pub fn hideDownloadProgress(self: *UpdateUiManager) void;

    /// Show a "update staged" toast.
    /// Message: "Update staged — restart the app to apply" or similar.
    pub fn showUpdateStagedToast(
        self: *UpdateUiManager,
        toast_mgr: *ToastManager,
        now_ms: i64,
    ) void;

    /// Show an error toast.
    /// Message: "Update failed: {error_message}".
    pub fn showUpdateErrorToast(
        self: *UpdateUiManager,
        toast_mgr: *ToastManager,
        error_message: []const u8,
        now_ms: i64,
    ) void;
};
```

### 2. Integration with `AppInner`

`AppInner` gains:

```zig
update_ui: ?UpdateUiManager = null,
```

In `AppInner.init`:
- If `update_manager` is initialized, also initialize `update_ui`.

In the frame loop (after `update_manager.tick()` from RI1):
- If `update_manager.isUpdateAvailable()` and no toast yet shown, call
  `update_ui.showUpdateAvailableToast()`.

In the frame loop (after `update_manager` download progress):
- If `update_manager.is_downloading`, call `update_ui.updateDownloadProgress()` with
  current progress stats.
- If download just started, call `update_ui.showDownloadProgress()` to display the UI.

After `update_manager.stageUpdate()` succeeds:
- Call `update_ui.showUpdateStagedToast()` with a success message.

On any error in RI1/RI2/RI3:
- Call `update_ui.showUpdateErrorToast()` with the error message.

### 3. Toast notifications (use existing M7-05 ToastManager)

Each toast should:
- Auto-dismiss after 5–10 seconds (configurable).
- Display the message clearly.
- Use semantic colors:
  - **Info toast** for "Update available" (accent color).
  - **Success toast** for "Update staged" (success color, e.g., green).
  - **Error toast** for failures (error color, e.g., red).

Examples:
```
"Update available: v1.0.1 — download now"
"Downloading update: 45%"
"Update staged — restart the app to apply"
"Update failed: network error"
```

### 4. Download progress UI (modal or overlay)

While RI2 is downloading, display a modal or overlay with:
- A **progress bar** showing percentage (0–100%).
- **Bytes downloaded / total** (e.g., "12 MB / 25 MB").
- An optional **cancel button** to abort the download.
- A **status message** (e.g., "Downloading…", "Verifying…", "Staging…").

Layout (suggested):
```
┌─────────────────────────────────┐
│  Update Installation            │
├─────────────────────────────────┤
│  Downloading update for v1.0.1  │
│                                 │
│  [████████░░░░] 45%             │
│  12 MB / 25 MB downloaded       │
│                                 │
│          [ Cancel ]             │
└─────────────────────────────────┘
```

The progress modal should:
- Be non-blocking (user can still interact with the app, but not navigate away).
- Update every frame with the latest download bytes / total.
- Automatically close when download completes or fails.
- Show an error message if download fails.

### 5. Frame loop additions

```zig
// In AppInner.runWithNav() frame loop:

// After update_manager.tick():
if (self.update_ui) {
    if (self.update_manager.is_downloading) {
        if (!self.update_ui.is_progress_visible) {
            try self.update_ui.showDownloadProgress(&self.scene, &self.toasts, now_ms);
        }
        self.update_ui.updateDownloadProgress(
            self.update_manager.download_progress_bytes,
            self.update_manager.download_total_bytes,
        );
    } else if (self.update_ui.is_progress_visible) {
        self.update_ui.hideDownloadProgress();
    }
}

// After update_manager.isUpdateAvailable():
if (self.update_manager.isUpdateAvailable() && !already_notified) {
    try self.update_ui.showUpdateAvailableToast(
        &self.toasts,
        self.update_manager.latest_manifest.?.version,
        now_ms,
    );
    already_notified = true;
}

// After update_manager.applyDelta():
if (self.update_manager.isPatchedBinaryReady()) {
    try self.update_manager.stageUpdate();
    if (self.update_manager.isStagedUpdatePending()) {
        try self.update_ui.showUpdateStagedToast(&self.toasts, now_ms);
    }
}
```

---

## Acceptance criteria

1. Toasts are displayed using the existing M7-05 `ToastManager`.
2. Update-available toast shows when `update_manager.isUpdateAvailable()` is true.
3. Update-available toast auto-dismisses after 5–10 seconds.
4. Download-progress UI is displayed while `update_manager.is_downloading` is true.
5. Progress bar updates every frame with current download percentage.
6. Progress bar shows bytes downloaded / total (e.g., "12 MB / 25 MB").
7. Download-progress UI auto-closes when download completes.
8. Download-progress UI auto-closes on error.
9. Error toast is displayed with the error message when `update_manager.download_error` is set.
10. Error toast shows when `update_manager.staging_error` is set (from RI3).
11. Update-staged toast is displayed after `stageUpdate()` succeeds.
12. Update-staged toast auto-dismisses after 5–10 seconds.
13. Cancel button on progress UI is functional (aborts the download when clicked).
14. Modal / overlay is non-blocking (app remains responsive).
15. No more than one progress UI is displayed at a time.

---

## Non-goals

- No persistent notification history (toasts are transient).
- No "download later" option (the download is automatically triggered on update availability).
- No settings UI for update preferences (e.g., "check for updates on launch", "auto-download",
  "notify before installing"). Those are post-v1.
- No custom branding or theme for the update UI beyond the existing semantic tokens.
- No voice or sound notification for updates.
- No email or push notification (updates are local to the running app).

---

## Visual appearance

### Update-available toast
- **Text:** "Update available: v{version}" or "New version {version} available"
- **Color:** Accent color (from `tokens.accent`)
- **Duration:** 8 seconds (auto-dismiss)
- **Icon:** Optional checkmark or download icon

### Download-progress modal
- **Background:** Semi-transparent overlay (from M7-06 modal styling)
- **Panel:** Centered card with rounded corners and shadow
- **Progress bar:** Animated fill (use `transition-width` from M14-02 if available)
- **Text:** Small, left-aligned below the bar: "12 MB / 25 MB — 45%"
- **Cancel button:** Secondary style (outline + text)

### Update-staged toast
- **Text:** "Update staged — restart to apply" or "Ready to install"
- **Color:** Success color (green, from `tokens.ok` or similar)
- **Duration:** 10 seconds (auto-dismiss)
- **Icon:** Optional checkmark

### Error toast
- **Text:** "Update failed: {error_message}" (truncate message if too long)
- **Color:** Error color (red, from `tokens.err`)
- **Duration:** 10 seconds (auto-dismiss)
- **Icon:** Optional X or exclamation mark

---

## INV-3.3 compliance note

Update UI rendering uses the existing `ToastManager` and overlay system, which do NOT
violate INV-3.3 (the dirty-bitset reactivity model). Toast and modal rendering is
driven by app-layer state (`update_manager` fields), which marks elements dirty when
those fields change. No parallel event-emission or callback mechanism is introduced.

---

## Dependencies

**Existing dependencies used:**
- M7-05: `ToastManager` (from `src/app/toast.zig`)
- M7-06: `DialogManager` (from `src/app/dialog.zig`) for the progress modal
- Module 07: `Scene` and widgets (for rendering the progress bar + buttons)
- Module 05: Theme tokens (for colors)

**No new dependencies introduced.**

---

## Implementation notes

### Toast message localization

If M15-03 (string table / i18n) is implemented by the time this is coded:
- Use `t("update.available")`, `t("update.staged")`, `t("update.error")` keys.
- Interpolate the version and error message: `formatString("{msg}", .{error_message})`.

### Progress bar styling

The progress bar can be a simple `<div class="h-1 bg-accent">` inside a `<card>` for the
progress display. The fill width is computed as `(bytes_downloaded / total_bytes) * 100%`.

### Cancel button behavior

When the user clicks the cancel button:
- Set a flag: `update_manager.cancel_download_requested = true`.
- The background download task checks this flag and aborts gracefully.
- Clean up any partial downloads and close the progress UI.
- Show a toast: "Update cancelled".

### Progress update frequency

Update the progress bar every frame (60 Hz typical). No throttling needed since the
progress fields are trivial to read.

### Toast overlap

If multiple toasts are queued (e.g., "Update available" + "Download failed"), the
`ToastManager` handles the stacking automatically. No special logic needed in
`UpdateUiManager`.
