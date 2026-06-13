# RG2 — M17-02: AT-SPI bridge (Linux)

> Roadmap item: M17-02
> Depends on: M17-01 (AccessNode tree)
> Read `00_constitution.md` before this file.

## HUMAN DECISION REQUIRED — D-Bus dependency

The ROADMAP lists `AT-SPI2 (Linux)` as the Linux implementation path for accessibility. AT-SPI2 is a D-Bus service specification that exposes the accessibility tree to screen readers like Orca. D-Bus is NOT yet on the approved list (INV-5.6). **The implementation path in this R-file requires a new external dependency to be useful.** Windows (COM) is pre-approved as part of `windows.h`. Linux (D-Bus) is NOT.

**Decision required:** Approve or reject D-Bus library bindings for the Linux AT-SPI2 implementation. Options:
1. Approve a Zig binding to `libdbus` (e.g. `dbus` crate equivalent).
2. Approve using GIO/GObject D-Bus bindings (higher-level, already used by GTK apps).
3. Reject D-Bus entirely and implement AT-SPI2 via a vendored minimal D-Bus marshaller (complex; low priority).

Until that decision is recorded, the Linux bridge will compile and be callable but will produce no D-Bus service. The Windows path (UIA COM, RG3) requires no new dependency and can proceed independently.

---

## Purpose

Expose the `AccessNode` tree built in M17-01 over the D-Bus AT-SPI2 interface so Linux screen readers (Orca, NVDA) can navigate and narrate the UI. On Windows, use COM/UIA instead (see RG3). On macOS, no-op stub (post-v1, INV-1.2).

## What to build

### `AtSpiService` struct — `src/app/atspi_bridge.zig`

The bridge manages the lifecycle of the D-Bus AT-SPI2 service. It registers the application with the AT-SPI registry, publishes accessibility events, and serves queries from screen readers.

```zig
pub const AtSpiService = struct {
    // Internal fields (Linux only):
    // - DBus connection handle (if compiling for Linux)
    // - AT-SPI object path ("/org/a11y/atspi/accessible/...")
    // - Event queue for accessibility changes (focus, state, text changes)
    // - Scene reference (does NOT own it; read-only access)

    /// Initialize the AT-SPI2 service for a given Scene.
    /// On Linux: register with D-Bus, publish the service path.
    /// On Windows: no-op stub (UIA is handled separately in RG3).
    /// `app_name` is the human-readable application name (e.g. "MyApp").
    /// Returns error if D-Bus registration fails.
    pub fn init(
        scene: *Scene,
        app_name: []const u8,
        allocator: std.mem.Allocator,
    ) !AtSpiService

    /// Shut down the AT-SPI2 service and close the D-Bus connection.
    pub fn deinit(self: *AtSpiService) void

    /// Call once per frame to process pending accessibility events and serve D-Bus queries.
    /// On Linux: may block briefly waiting for D-Bus messages.
    /// On Windows: no-op.
    pub fn tick(self: *AtSpiService) void

    /// Signal that an element's state or properties have changed (e.g. focus, checked, text).
    /// Enqueues an accessibility event that will be delivered to screen readers on the next tick.
    pub fn markElementChanged(self: *AtSpiService, idx: u32) void

    /// Signal that the entire tree has been rebuilt (e.g. screen change).
    /// Sends a tree-update event to screen readers.
    pub fn markTreeChanged(self: *AtSpiService) void
};
```

### Linux D-Bus message handling

The AT-SPI2 interface exposes these D-Bus methods on the application's accessibility object:

```xml
<!-- Pseudo-IDL for AT-SPI2-compatible interface -->

interface org.a11y.atspi.Accessible {
    <!-- Read properties -->
    string GetName()                        # AccessNode.name
    string GetDescription()                 # AccessNode.description
    uint32 GetRole()                        # AccessNode.role as u32
    
    <!-- Navigation -->
    DBusPath GetParent()                    # Parent element's D-Bus path
    DBusPath[] GetChildren()                # Array of children's D-Bus paths
    DBusPath GetChildAtIndex(int index)     # Nth child
    int GetIndexInParent()                  # Element's index among siblings
    
    <!-- State -->
    uint32 GetState()                       # AccessNode.state as u32 bitfield
    bool IsSelected()                       # AccessNode.state.selected
    bool IsVisible()                        # !AccessNode.state.hidden
    bool IsEnabled()                        # !AccessNode.state.disabled
    
    <!-- Value (for sliders, spinbuttons) -->
    double GetCurrentValue()                # AccessNode.value (as f64)
    double GetMinimumValue()                # AccessNode.value_min
    double GetMaximumValue()                # AccessNode.value_max
    SetCurrentValue(double val)             # (Optional; may not be implemented v1)
    
    <!-- Text (for text inputs, labels) -->
    string GetText()                        # AccessNode.name (same as GetName)
}
```

### Platform check — `src/app/atspi_bridge.zig`

Compile-time guard (similar to RF0 pattern):

```zig
const builtin = @import("builtin");
const is_linux = builtin.os.tag == .linux;

pub const AtSpiService = if (is_linux) AtSpiServiceLinux else AtSpiServiceStub;

// Linux implementation behind comptime guard
// If D-Bus is not approved/available, this compiles as the stub and logs a warning.
```

### Linux implementation path (blocked until D-Bus approved)

When D-Bus is approved:

1. **D-Bus connection setup:** Create a connection to the session D-Bus bus. Register the application's main object path (e.g. `/org/a11y/atspi/accessible/MyApp`).
2. **Element → D-Bus path mapping:** Each element index maps to a D-Bus path like `/org/a11y/atspi/accessible/MyApp/0`, `/org/a11y/atspi/accessible/MyApp/1`, etc.
3. **Method handlers:** Implement handlers for the standard AT-SPI2 methods (GetName, GetRole, GetState, GetChildren, etc.) that query the `Scene._access_nodes` array.
4. **Event emission:** When `markElementChanged` is called, enqueue a D-Bus signal (e.g. `PropertyChanged` or `StateChanged`) that screen readers can listen for.
5. **Tree synchronization:** When an element is hidden, removed, or the Scene is reset, emit a `TreeChanged` event so screen readers re-query the tree.

### Windows stub (no D-Bus required)

On Windows, all `AtSpiService` methods are no-ops:

```zig
pub fn init(...) !AtSpiService { return .{}; }
pub fn deinit(self: *AtSpiService) void {}
pub fn tick(self: *AtSpiService) void {}
pub fn markElementChanged(self: *AtSpiService, idx: u32) void {}
pub fn markTreeChanged(self: *AtSpiService) void {}
```

The Windows implementation is handled separately via UIA (RG3).

### App layer integration — `src/app/app.zig`

In `AppOptions`:

```zig
pub const AppOptions = struct {
    // ... existing fields ...
    
    /// Optional application name for the accessibility service.
    /// If non-null, accessibility tree is exposed (Linux/Windows).
    /// Caller retains ownership; copied into AppInner if needed.
    app_name: ?[]const u8 = null,
};
```

In `AppInner`:

```zig
pub const AppInner = struct {
    // ... existing fields ...
    
    /// Linux AT-SPI2 bridge. Non-null if app_name was provided.
    atspi_service: ?AtSpiService = null,
    
    /// Windows UIA bridge (RG3). Non-null if app_name was provided.
    uia_bridge: ?UiaBridge = null,
};
```

In `AppInner.init()`:

```zig
if (options.app_name) |app_name| {
    self.atspi_service = try AtSpiService.init(&self.scene, app_name, gpa);
    self.uia_bridge = try UiaBridge.init(&self.scene, app_name, gpa);
}
```

In `AppInner.deinit()`:

```zig
if (self.atspi_service) |*svc| svc.deinit();
if (self.uia_bridge) |*br| br.deinit();
```

In the frame loop (after `Scene.fireQueuedCallbacks()` and before `buildDrawList`):

```zig
if (self.atspi_service) |*svc| svc.tick();
if (self.uia_bridge) |*br| br.tick();
```

Whenever an element's state changes (via `Scene.setFocus()`, toggle button pressed, etc.):

```zig
if (self.atspi_service) |*svc| svc.markElementChanged(idx);
if (self.uia_bridge) |*br| br.markElementChanged(idx);
```

Whenever the tree is rebuilt (on `Scene.instantiate()` or screen change):

```zig
if (self.atspi_service) |*svc| svc.markTreeChanged();
if (self.uia_bridge) |*br| br.markTreeChanged();
```

### Module location

```
src/app/atspi_bridge.zig          — AtSpiService struct (Linux + Windows stub)
src/app/app.zig                   — Integration: AppOptions.app_name, AppInner.atspi_service, tick/markChanged calls
```

### Compile-time warning (while D-Bus is not approved)

The Linux code path should emit a `@compileLog` warning when D-Bus is not available:

```zig
// In atspi_bridge.zig, Linux path:
if (!dbus_available) {
    @compileLog("AT-SPI2: D-Bus not approved (INV-5.6) — accessibility tree is not exposed on Linux");
}
```

## Non-goals (DO NOT implement — INV-5.4)

- **No libnotify integration.** System notifications are handled separately (RF0, M16).
- **No screen reader interaction hooks (speech, Braille).** The AT-SPI2 service exposes the tree; screen readers consume it and synthesize speech/Braille independently.
- **No live region announcements (aria-live).** Announced regions are post-v1.
- **No custom accessible actions.** AT-SPI2 supports custom actions; v1 exposes standard navigation and state only.
- **No macOS or other platform support.** Windows and Linux only (INV-1.2).
- **No D-Bus until explicitly approved.** Until a human records the approval, the Linux path is a no-op.

## Acceptance criteria

1. `AtSpiService` struct is defined with `init`, `deinit`, `tick`, `markElementChanged`, `markTreeChanged` methods.
2. On Windows, all methods are no-ops and do NOT attempt to use D-Bus or any unapproved library.
3. On Linux (when D-Bus is approved):
   - D-Bus connection is established and the service is registered.
   - `GetName()`, `GetRole()`, `GetState()` D-Bus methods read from `Scene._access_nodes`.
   - `GetChildren()` and `GetParent()` navigate the element tree via `Scene`.
   - `tick()` processes pending screen-reader queries and sends accessibility events.
   - `markElementChanged(idx)` enqueues a property-changed event.
   - `markTreeChanged()` enqueues a tree-update event.
4. App layer integration:
   - `AppOptions.app_name` field exists and is optional.
   - `AppInner` initializes the service if `app_name` is provided.
   - `tick()` is called once per frame.
   - `markElementChanged()` is called when element state changes.
   - `markTreeChanged()` is called when the scene is rebuilt.
5. Unit tests cover:
   - Service initialization and shutdown on both platforms (no crashes).
   - `markElementChanged()` and `markTreeChanged()` enqueue events without panicking.
   - Windows stub returns immediately (no-op).
   - Linux stub (when D-Bus not available) compiles without D-Bus symbols.
6. No Zig compiler errors or warnings (except the expected `@compileLog` message while D-Bus is pending).
7. Build system does NOT attempt to link D-Bus unless explicitly configured (post-approval).

## Dependency decision checklist

Before merging this R-file, the human must record a decision:

- [ ] D-Bus library choice (libdbus, GIO, vendored, or none) is approved and documented in `00_constitution.md`.
- [ ] OR — D-Bus is rejected and the Linux path is a permanent no-op stub.
- [ ] The decision is recorded in `00_constitution.md` INV-5.6 table.

Until one of these is done, the R-file serves as a template; implementation is blocked.

## Open questions

1. **D-Bus library choice:** Should we use `libdbus-1` (low-level), GIO D-Bus bindings (higher-level, GTK-friendly), or a Zig-native minimal D-Bus marshaller?
   - **Recommendation:** GIO D-Bus bindings are the most pragmatic for a GTK-native Linux app. Requires approving GLib as a dependency.
2. **Method implementation scope:** Should we implement all AT-SPI2 methods (Text, EditableText, Value, Component, Action) or a minimal subset (Accessible, State, Value)?
   - **v1 scope:** Minimal subset (Accessible + State + Value). Custom actions (Action interface) and rich text methods (Text, EditableText) are post-v1.
3. **Error handling:** Should D-Bus registration failures be fatal (crash the app) or non-fatal (log a warning and continue)?
   - **Recommendation:** Non-fatal. If screen readers are not available, the app should still run with accessibility disabled.
