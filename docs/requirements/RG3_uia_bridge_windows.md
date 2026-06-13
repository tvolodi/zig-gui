# RG3 — M17-03: UIA bridge (Windows)

> Roadmap item: M17-03
> Depends on: M17-01 (AccessNode tree)
> Read `00_constitution.md` before this file.

## Purpose

Expose the `AccessNode` tree built in M17-01 over the Windows UI Automation (UIA) COM interface so Windows screen readers (Narrator, NVDA) can navigate and narrate the UI. UIA is part of `windows.h` (already `@cImport`d in module 01) so NO new external dependency is required. On Linux, use AT-SPI2 instead (see RG2). On macOS, no-op stub (post-v1, INV-1.2).

## What to build

### `UiaBridge` struct — `src/app/uia_bridge.zig`

The bridge manages the lifecycle of the UIA provider for the application window. It registers element providers, handles COM queries from Windows, and synchronizes accessibility events.

```zig
pub const UiaBridge = struct {
    // Internal fields (Windows only):
    // - IRawElementProvider (COM interface) for the root application window
    // - Hash map: element index → IRawElementProvider COM object
    // - Event queue for accessibility changes (focus, state, text changes)
    // - Scene reference (does NOT own it; read-only access)

    /// Initialize the UIA bridge for a given Scene.
    /// On Windows: register element providers with UIA, set up COM object lifetime management.
    /// On Linux: no-op stub.
    /// `hwnd` is the application window handle from GLFW / Platform.
    /// `app_name` is the human-readable application name (e.g. "MyApp").
    pub fn init(
        scene: *Scene,
        hwnd: *anyopaque,        // HWND pointer (opaque to module 07, understood in app layer)
        app_name: []const u8,
        allocator: std.mem.Allocator,
    ) !UiaBridge

    /// Shut down the UIA bridge and release COM objects.
    pub fn deinit(self: *UiaBridge) void

    /// Call once per frame to process pending UIA events and serve COM queries.
    /// On Windows: may briefly pump message queue for UIA notifications.
    /// On Linux: no-op.
    pub fn tick(self: *UiaBridge) void

    /// Signal that an element's state or properties have changed (e.g. focus, checked, text).
    /// Enqueues a UIA event that will be delivered to screen readers on the next tick.
    pub fn markElementChanged(self: *UiaBridge, idx: u32) void

    /// Signal that the entire tree has been rebuilt (e.g. screen change).
    /// Sends a tree-update notification to screen readers.
    pub fn markTreeChanged(self: *UiaBridge) void
};
```

### Windows UIA implementation

The bridge implements the `IRawElementProvider` COM interface (required by UIA v3+):

```c
// Pseudo-C for the interface shape
interface IRawElementProvider {
    HRESULT GetPatternProvider(PATTERNID patternId, IUnknown **pRetVal);
    HRESULT GetPropertyValue(PROPERTYID propertyId, VARIANT *pRetVal);
    HRESULT GetHostRawElementProvider(IRawElementProvider **pRetVal);
    HRESULT BoundingRectangle(UiaRect *pRetVal);
    HRESULT BuildChildrenProvider(IRawElementProvider ***pRetVal, int *pChildCount);
    HRESULT get_FragmentRoot(IRawElementProvider **pRetVal);
    HRESULT NavigateFragment(NavigateDirection direction, IRawElementProvider **pRetVal);
    HRESULT SetFocus();
};
```

For v1, implement a minimal subset:

1. **GetPropertyValue:** Return UIA properties (UIA_NamePropertyId, UIA_ControlTypePropertyId, UIA_IsEnabledPropertyId, etc.) by reading from `Scene._access_nodes[idx]`.
2. **BoundingRectangle:** Return the element's computed layout rect from `Scene`.
3. **BuildChildrenProvider:** Return an array of `IRawElementProvider` for the element's children.
4. **NavigateFragment:** Navigate to parent, first child, next sibling via the element tree.
5. **SetFocus:** Route focus changes back to the application via `Scene.setFocus()`.

### AccessRole → UIA ControlType mapping

Map `AccessRole` enums to UIA control types:

```zig
pub fn uiaControlTypeFor(role: AccessRole) u32 {
    return switch (role) {
        .button => UIA_ButtonControlTypeId,
        .text => UIA_TextControlTypeId,
        .textbox => UIA_EditControlTypeId,
        .checkbox => UIA_CheckBoxControlTypeId,
        .radio => UIA_RadioButtonControlTypeId,
        .combobox => UIA_ComboBoxControlTypeId,
        .listbox => UIA_ListControlTypeId,
        .option => UIA_ListItemControlTypeId,
        .listitem => UIA_ListItemControlTypeId,
        .slider => UIA_SliderControlTypeId,
        .spinbutton => UIA_SpinnerControlTypeId,
        .textarea => UIA_EditControlTypeId,
        .tab => UIA_TabItemControlTypeId,
        .tablist => UIA_TabControlTypeId,
        .tabpanel => UIA_PaneControlTypeId,
        .progressbar => UIA_ProgressBarControlTypeId,
        .dialog => UIA_WindowControlTypeId,
        .menu => UIA_MenuControlTypeId,
        .menuitem => UIA_MenuItemControlTypeId,
        .tooltip => UIA_ToolTipControlTypeId,
        .img => UIA_ImageControlTypeId,
        .link => UIA_HyperlinkControlTypeId,
        .list => UIA_GroupControlTypeId,
        .region => UIA_GroupControlTypeId,
        .none => UIA_CustomControlTypeId,
        else => UIA_CustomControlTypeId,
    };
}
```

### AccessState → UIA properties

Map `AccessState` flags to UIA properties:

```zig
pub fn uiaPropertiesFor(state: AccessState) struct {
    is_enabled: bool,
    is_selected: bool,
    is_hidden: bool,
} {
    return .{
        .is_enabled = !state.disabled,
        .is_selected = state.selected,
        .is_hidden = state.hidden,
    };
}
```

### Platform check — `src/app/uia_bridge.zig`

Compile-time guard:

```zig
const builtin = @import("builtin");
const is_windows = builtin.os.tag == .windows;

pub const UiaBridge = if (is_windows) UiaBridgeWindows else UiaBridgeStub;
```

### Windows implementation path

When implementing on Windows:

1. **COM object factory:** Create a COM class factory that hands out `IRawElementProvider` instances for each element.
2. **Provider registration:** Register the root provider with UIA via `UiaRegisterProvider()`.
3. **Property lookups:** When UIA calls `GetPropertyValue(UIA_NamePropertyId, …)`, read from `AccessNode.name` and return a BSTR (COM string).
4. **Control type mapping:** Return the result of `uiaControlTypeFor(node.role)` for UIA_ControlTypePropertyId.
5. **Child enumeration:** When UIA calls `BuildChildrenProvider()`, walk `Scene.childrenOf()` and return an array of providers.
6. **Focus and navigation:** Route SetFocus() back to `Scene.setFocus()`; implement NavigateFragment() for tree navigation.
7. **Event raising:** When `markElementChanged()` is called, raise a UIA event via `UiaRaiseAutomationEvent()` (e.g. `UIA_AutomationPropertyChangedEventId`).

### Linux stub

On Linux, all `UiaBridge` methods are no-ops:

```zig
pub fn init(...) !UiaBridge { return .{}; }
pub fn deinit(self: *UiaBridge) void {}
pub fn tick(self: *UiaBridge) void {}
pub fn markElementChanged(self: *UiaBridge, idx: u32) void {}
pub fn markTreeChanged(self: *UiaBridge) void {}
```

The Linux implementation is handled separately via AT-SPI2 (RG2).

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
    
    /// Linux AT-SPI2 bridge (RG2). Non-null if app_name was provided.
    atspi_service: ?AtSpiService = null,
    
    /// Windows UIA bridge. Non-null if app_name was provided.
    uia_bridge: ?UiaBridge = null,
};
```

In `AppInner.init()`:

```zig
if (options.app_name) |app_name| {
    self.atspi_service = try AtSpiService.init(&self.scene, app_name, gpa);
    self.uia_bridge = try UiaBridge.init(&self.scene, self.platform.window, app_name, gpa);
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
src/app/uia_bridge.zig            — UiaBridge struct (Windows + Linux stub)
src/app/app.zig                   — Integration: AppOptions.app_name, AppInner.uia_bridge, tick/markChanged calls
```

## Non-goals (DO NOT implement — INV-5.4)

- **No accessibility patterns (Value, Toggle, Invoke, etc.).** v1 exposes properties only; screen readers can navigate and read but not programmatically invoke actions. Action patterns are post-v1.
- **No rich text support (TextPattern).** Single-line text properties only; rich formatting is post-v1.
- **No custom properties.** Standard UIA properties only.
- **No annotation/error underlining.** Text input validation errors are post-v1.
- **No macOS or other platform support.** Windows and Linux only (INV-1.2).

## Acceptance criteria

1. `UiaBridge` struct is defined with `init`, `deinit`, `tick`, `markElementChanged`, `markTreeChanged` methods.
2. On Linux, all methods are no-ops and do NOT attempt to use COM or any Windows-specific API.
3. On Windows:
   - COM objects implementing `IRawElementProvider` are created for each live element.
   - `GetPropertyValue()` reads from `Scene._access_nodes` and returns:
     - UIA_NamePropertyId → `AccessNode.name` (as BSTR)
     - UIA_ControlTypePropertyId → mapped control type from `uiaControlTypeFor()`
     - UIA_IsEnabledPropertyId → `!AccessState.disabled`
     - UIA_IsSelectedPropertyId → `AccessState.selected`
     - UIA_IsHiddenPropertyId → `AccessState.hidden`
   - `BoundingRectangle()` returns the element's layout rect from `Scene`.
   - `BuildChildrenProvider()` returns an array of child providers via `Scene.childrenOf()`.
   - `NavigateFragment()` navigates to parent, next, previous, first child via the element tree.
   - `SetFocus()` calls `Scene.setFocus()` to route focus changes.
   - `tick()` raises UIA events (via `UiaRaiseAutomationEvent()`) when elements change.
   - `markElementChanged(idx)` enqueues an event notification.
   - `markTreeChanged()` enqueues a tree-update notification.
4. App layer integration:
   - `AppOptions.app_name` field exists and is optional.
   - `AppInner` initializes the bridge if `app_name` is provided.
   - `tick()` is called once per frame.
   - `markElementChanged()` is called when element state changes.
   - `markTreeChanged()` is called when the scene is rebuilt.
5. Unit tests cover:
   - Bridge initialization and shutdown on both platforms (no crashes).
   - `markElementChanged()` and `markTreeChanged()` enqueue events without panicking.
   - Linux stub returns immediately (no-op).
   - Windows: COM reference counting is correct (no leaks, no double-free).
   - Property lookups return correct UIA property values.
   - Navigation methods return correct parent/child/sibling providers.
6. Manual testing (Windows only):
   - Run the app and open Windows Narrator (Windows + Ctrl + Enter).
   - Narrator should read element names, control types, and state (enabled, checked, etc.).
   - Tab navigation should be tracked by Narrator.
   - Focus changes should be announced.
7. No Zig compiler errors or warnings.
8. Build system does NOT link COM/UIA libraries on non-Windows platforms.

## Open questions

1. **COM reference counting:** Should we use Zig's error union for COM HRESULT handling, or wrap HRESULTs in a custom error type?
   - **Recommendation:** Wrap HRESULTs and provide readable error messages (e.g. "E_OUTOFMEMORY" → "out of memory").
2. **Event batching:** When multiple elements change in one frame, should we emit one tree-changed event or individual property-changed events per element?
   - **Recommendation:** Individual property-changed events for specific property changes, tree-changed only on full rebuild.
3. **Caching:** Should we cache COM provider objects (one per element) or create them on demand?
   - **Recommendation:** Cache them in a hashmap (element index → provider). This avoids re-allocation and matches UIA's expectations of object identity.
