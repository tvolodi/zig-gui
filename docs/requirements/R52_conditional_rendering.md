# R52 — M5-03: Conditional rendering

> Roadmap item: M5-03  
> Depends on: M2-04 (static binding, `BindingSet`), module 06 (markup parser), module 07 (`Scene.instantiate`)  
> Read `00_constitution.md` before this file.

## Purpose

An element subtree with `if="{bind condition}"` is hidden when the bound signal is `false`
and shown when it is `true`. Shown/hidden state is stored in a parallel array in `Scene`;
the renderer and layout engine skip elements (and their subtrees) whose hidden flag is set.
The element always exists in the element store — it is not added/removed — so indices remain
stable and no re-instantiation is needed on condition changes.

## What to build

### Attribute syntax

```html
<Column if="{bind show_details}">
    <Text text="Extra detail" />
</Column>

<Button if="{bind is_logged_in}" text="Log out" />
```

`if=` accepts only a `{bind ...}` value pointing to a `Signal(bool)`. A literal `if="true"`
or `if="false"` is also valid (parsed as `.literal`; "true" shows, anything else hides).
Unknown bind paths are treated as `false` (hidden) at startup until the signal refreshes.

### `hidden` flag in `Scene`

Extend [07.types.zig](../specs/07.types.zig):

```zig
pub const Scene = struct {
    // ...existing fields...

    /// Parallel bool array, indexed by ElementId.index.
    /// true = the element and its entire subtree are hidden (excluded from layout and paint).
    /// false (default) = visible.
    _hidden: std.ArrayListUnmanaged(bool) = .empty,

    /// Return whether element `idx` is currently hidden.
    pub fn isHidden(self: *const Scene, idx: u32) bool

    /// Set the hidden state for element `idx` and mark it dirty.
    /// Propagates to children: all descendants are also marked dirty so the renderer
    /// can skip them in the same frame.
    pub fn setHidden(self: *Scene, idx: u32, hidden: bool) void
};
```

`_hidden` is allocated in `instantiate()` and cleared in `reset()`.

### `NodeDesc` changes for `if=`

During `Scene.instantiate`, after storing the element, check `desc.attrs` for an attribute
named `"if"`:

```zig
// In Scene.instantiate, after creating the element and storing kind/style/text:
for (desc.attrs) |attr| {
    if (!std.mem.eql(u8, attr.name, "if")) continue;
    switch (attr.value) {
        .literal => |s| {
            if (!std.mem.eql(u8, s, "true")) {
                scene.setHidden(id.index, true);
            }
        },
        .bind => |path| {
            // Record the element index and bind path for the CondBinding system.
            // The actual hidden state is set by BindingSet.refresh() before first frame.
            _ = path;  // handled by CondBinding below
            scene.setHidden(id.index, true);  // start hidden until signal resolves
        },
    }
    break;  // only one `if` attribute per element
}
```

### `CondBinding` — conditional binding entry

Extend `src/app/binding.zig` with a new binding kind:

```zig
/// A registered connection between one Signal(bool) and one element index.
/// When the signal is true, the element is shown; when false, hidden.
pub const CondBinding = struct {
    element_idx: u32,
    signal_ptr:  *anyopaque,
    read_fn:     *const fn (*const anyopaque) bool,
};

pub const BindingSet = struct {
    text:  std.ArrayListUnmanaged(TextBinding) = .empty,
    cond:  std.ArrayListUnmanaged(CondBinding) = .empty,   // NEW

    // ...existing methods...

    /// Bind a Signal(bool) field to an element's hidden state.
    /// When the signal is true, element is shown; when false, hidden.
    pub fn bindCond(
        self: *BindingSet,
        comptime StateType: type,
        comptime field_name: []const u8,
        state: *StateType,
        element_idx: u32,
        gpa: std.mem.Allocator,
    ) !void

    /// Extend refresh() to also apply conditional bindings.
    pub fn refresh(self: *const BindingSet, scene: *Scene) void
};
```

`bindCond` follows the same comptime pattern as `bindText`:

```zig
pub fn bindCond(
    self: *BindingSet,
    comptime StateType: type,
    comptime field_name: []const u8,
    state: *StateType,
    element_idx: u32,
    gpa: std.mem.Allocator,
) !void {
    comptime {
        const FieldType = @TypeOf(@field(@as(*StateType, undefined).*, field_name));
        if (FieldType != Signal(bool)) {
            @compileError("bindCond: field '" ++ field_name ++
                "' must be Signal(bool)");
        }
    }
    const sig: *Signal(bool) = &@field(state, field_name);
    try sig.subscribe(element_idx);

    const ReadFns = struct {
        fn read(ptr: *const anyopaque) bool {
            return @as(*const Signal(bool), @ptrCast(@alignCast(ptr))).get();
        }
    };
    try self.cond.append(gpa, .{
        .element_idx = element_idx,
        .signal_ptr  = sig,
        .read_fn     = &ReadFns.read,
    });
}
```

`refresh` is extended to apply conditional bindings after text bindings:

```zig
pub fn refresh(self: *const BindingSet, scene: *Scene) void {
    for (self.text.items) |b| {
        scene.setText(b.element_idx, b.read_fn(b.signal_ptr));
    }
    for (self.cond.items) |b| {
        const visible = b.read_fn(b.signal_ptr);
        scene.setHidden(b.element_idx, !visible);
    }
}
```

### Layout engine — skipping hidden elements

In `src/04/types.zig` `solveNode`, before resolving dimensions:

```zig
fn solveNode(s: *ElementStore, id: ElementId, ...) Size {
    // NEW: skip hidden elements
    // The hidden flag lives in Scene, which is not accessible from the layout engine.
    // Instead: hidden elements have display = .none set by Scene.setHidden.
    // ...
}
```

**Design decision:** rather than passing `Scene` to the layout engine (which would violate
INV-3.4 since Scene is in the app layer above module 04), `Scene.setHidden` additionally
sets `LayoutNode.display = .none` on the element. When visibility is restored
(`setHidden(idx, false)`), `display` is restored to the element's original `display` value.

This requires `Scene` to cache the original display value per element:

```zig
pub const Scene = struct {
    // ...
    _saved_display: std.ArrayListUnmanaged(store.Display) = .empty,

    pub fn setHidden(self: *Scene, idx: u32, hidden: bool) void {
        const was_hidden = self._hidden.items[idx];
        if (was_hidden == hidden) return;
        self._hidden.items[idx] = hidden;
        if (hidden) {
            self._saved_display.items[idx] = self.elements.layout.items[idx].display;
            self.elements.layout.items[idx].display = .none;
        } else {
            self.elements.layout.items[idx].display = self._saved_display.items[idx];
        }
        self.elements.dirty.set(idx);
    }
```

### Serializer — skipping hidden elements

In `buildDrawList`, the existing check for `computed.w == 0 && computed.h == 0` naturally
skips hidden elements (they have `display = .none` → `computed = {0,0,0,0}` from R51).
No additional change is needed in the serializer.

### `if=` literal value at instantiate time

When `if="true"`, the element is visible (hidden = false, no action). When `if="false"` or
any other literal, the element is hidden. This is a compile-time-known value; no binding
entry is created. Useful for temporarily hiding UI during development.

### Wiring in `App` / application code

For markup-level `if="{bind ...}"` to fully work, the application must call `bindCond`
after instantiate:

```zig
// After scene.instantiate(&desc, tokens):
try app.bindings.bindCond(AppState, "show_details", &state, details_col_id.index, gpa);
```

The relationship between markup `if="{bind show_details}"` and the `bindCond` call is
**by convention**, not enforced by the framework. The parse-time bind path (`"show_details"`)
is recorded in `NodeDesc.attrs` but is not automatically connected to a `Signal(bool)` field.
Automatic wiring requires the build-time codegen tool (M5-06) to resolve paths. For v1,
the application author manually calls `bindCond` for each conditional element.

### Behavioral contract

| Situation | Behavior |
|---|---|
| `if="false"` literal | Element and subtree hidden at instantiate time |
| `if="true"` literal | Element visible (default behavior, no hidden entry) |
| `Signal(bool).set(true)` | `refresh()` calls `setHidden(idx, false)` → element shown |
| `Signal(bool).set(false)` | `refresh()` calls `setHidden(idx, true)` → element hidden |
| Hidden element | `display = .none`; zero layout rect; no draw commands |
| Hidden element with children | All children also have zero layout rect (parent = none → children inherit none space) |

### Module location

```
src/app/binding.zig       — CondBinding, bindCond, refresh() extension
src/app/types.zig         — Scene._hidden, Scene._saved_display, isHidden, setHidden
docs/specs/07.types.zig   — _hidden, isHidden, setHidden
src/07/types.zig          — instantiate: if= attribute handling
docs/requirements/R52_conditional_rendering.md
```

## Public API

New in `BindingSet` (`binding.zig`):

```zig
pub const CondBinding = struct { element_idx: u32, signal_ptr: *anyopaque, read_fn: *const fn(*const anyopaque) bool }
pub fn bindCond(self, comptime StateType, comptime field_name, state, element_idx, gpa) !void
// refresh() extended to apply cond bindings
```

New in `Scene` (module 07):

```zig
pub fn isHidden(self: *const Scene, idx: u32) bool
pub fn setHidden(self: *Scene, idx: u32, hidden: bool) void
```

## Non-goals (DO NOT implement — INV-5.4)

- **No automatic bind-path resolution** — the `if="{bind path}"` path is not automatically
  matched to a `Signal(bool)` field; the application calls `bindCond` manually. Automatic
  wiring is a M5-06 (codegen) concern.
- **No `else` branch** — there is no `<X if="{bind cond}">` / `<Y else>` pair; show/hide
  is one element at a time.
- **No animated show/hide** — visibility changes are instantaneous.
- **No `v-show` vs `v-if` distinction** — the element always exists in the store (not
  removed on hide); this is equivalent to CSS `visibility: hidden` + `display: none`.
- **No group-if** — the `if=` applies to one element; hiding a parent naturally hides its
  children because the parent's `display = .none` gives them zero space.
- **No `unless=`** — use a `Computed(bool)` that inverts the source signal.

## Acceptance criteria

1. `zig build test-binding` passes. New test cases:
   - `bindCond` with `Signal(bool) = true` → element visible (`isHidden = false`).
   - `Signal.set(false)` → after `refresh`, `isHidden = true` and element has `display = .none`.
   - `Signal.set(true)` → after `refresh`, `isHidden = false` and display is restored.
   - `bindCond` with a non-`Signal(bool)` field causes a **compile error**.

2. `zig build test-scene` passes. New test cases:
   - `if="false"` literal → `isHidden(idx) == true` after instantiate.
   - `if="true"` literal → `isHidden(idx) == false` after instantiate.
   - `setHidden(idx, true)` → `display = .none`; `setHidden(idx, false)` → original display restored.
   - `setHidden` marks the element dirty.

3. Integration: a form with a `<Column if="{bind show_details}">` section. Toggle the signal
   and verify the section appears/disappears without layout artifacts.

4. `CondBinding.deinit` (via `BindingSet.deinit`) frees without leaks.

5. Checklist fully ticked.

## Open questions

None. The "display = .none as hidden proxy" approach cleanly reuses the existing layout-engine
`none` path from R51 without coupling Scene to the layout engine. The `_saved_display` array
adds one byte per element but is negligible for the element counts this framework targets.
