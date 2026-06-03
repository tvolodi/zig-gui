# R53 — M5-04: List rendering

> Roadmap item: M5-04  
> Depends on: M2-04 (static binding, `BindingSet`), module 06 (markup parser), module 07 (`Scene.instantiate`)  
> Read `00_constitution.md` before this file.

## Purpose

A markup element with `for="{bind items}"` repeats its child subtree once per item in a
bound `Signal([]T)` slice. Each iteration produces real instantiated elements in the
element store, using the item's data to fill text and style values. When the signal changes
(items added, removed, or reordered), the scene is reset and re-instantiated from the
current slice — no virtual DOM diffing, no patch algorithm. This is consistent with
INV-3.3 (dirty bitset, not diff) and INV-3.5 (arena reset).

## What to build

### Attribute syntax

```html
<Column for="{bind contacts}">
    <Card class="p-4">
        <Text text="{bind item.name}" />
        <Text class="text-muted" text="{bind item.email}" />
    </Card>
</Column>
```

`for=` accepts only a `{bind ...}` path. The bound path refers to a `Signal` whose value
is a slice (`[]T`). Inside the repeated subtree, `{bind item.*}` paths refer to fields on
the current item. The exact field accessor syntax is convention; resolution is performed by
the `ListBinding` refresh mechanism.

`for=` on a non-container element (a `<Text>`, `<Button>`) is legal but unusual; the
framework does not restrict it.

### Design: re-instantiate on change (v1)

v1 does **not** maintain a keyed list of element subtrees or perform structural diffing.
Instead:

1. The `ListBinding` stores the `for`-element's `NodeDesc` template (the child subtree
   before the `for=` element itself) and its `ElementId`.
2. On `refresh()`, if the signal value has changed (detected by version number), `Scene`
   removes all existing children of the `for`-element and re-instantiates the child
   template once per item.
3. The parent scene's other elements are unaffected.

This is `O(items * template_depth)` per change but is correct, simple, and safe under
INV-3.5. For small to medium lists (< 500 items) this is fast enough for v1.

### `ListBinding` type

Add to `src/app/binding.zig`:

```zig
/// A registered `for=` binding. When the signal changes, the bound element's children
/// are cleared and re-instantiated from the template for each item in the new slice.
pub const ListBinding = struct {
    /// Element index of the `for=` container element.
    container_idx: u32,
    /// The NodeDesc of ONE child template (the single child of the `for=` element in markup).
    template: NodeDesc,
    /// Type-erased pointer to the `Signal([]T)`.
    signal_ptr: *anyopaque,
    /// Returns the current slice length.
    len_fn: *const fn (*const anyopaque) usize,
    /// Calls `instantiate_fn` once per item, passing the item index and a pointer to the
    /// slice element. The instantiate_fn fills the template's `{bind item.*}` placeholders
    /// before calling `scene.instantiate`.
    refresh_fn: *const fn (
        scene: *Scene,
        container: u32,
        template: *const NodeDesc,
        signal_ptr: *const anyopaque,
        tokens: Tokens,
    ) anyerror!void,
    /// Last observed signal version. Used to detect changes.
    last_version: u64,
};
```

### `BindingSet` extension

```zig
pub const BindingSet = struct {
    text: std.ArrayListUnmanaged(TextBinding) = .empty,
    cond: std.ArrayListUnmanaged(CondBinding) = .empty,
    list: std.ArrayListUnmanaged(ListBinding) = .empty,  // NEW

    pub fn bindList(
        self: *BindingSet,
        comptime T: type,
        comptime field_name: []const u8,
        state: *anytype,
        container_idx: u32,
        template: NodeDesc,
        /// Caller-provided function that instantiates one item.
        /// Signature: fn(scene, container_id, item: *const T, tokens) !void
        comptime item_instantiate_fn: anytype,
        gpa: std.mem.Allocator,
    ) !void

    pub fn refresh(self: *BindingSet, scene: *Scene, tokens: Tokens) void
};
```

### `bindList` implementation pattern

`bindList` is more complex than `bindText`/`bindCond` because the "item" is a struct of
unknown shape `T`. The caller provides `item_instantiate_fn` — a comptime function that
knows the item type and performs the per-item scene instantiation. This avoids needing a
reflection system for arbitrary item fields.

```zig
// Application code:
const Contact = struct { name: []const u8, email: []const u8 };

try app.bindings.bindList(
    Contact,
    "contacts",
    &state,
    contacts_column_id.index,
    contact_template_desc,
    struct {
        fn instantiate(
            scene: *Scene,
            container: ElementId,
            item: *const Contact,
            tokens: Tokens,
        ) !void {
            // Build a NodeDesc on the stack or arena with item.name / item.email filled in.
            var card_desc = NodeDesc{
                .tag = "Card",
                .classes = "p-4",
                .attrs = &.{},
                .children = &.{
                    NodeDesc{ .tag = "Text", .attrs = &.{
                        .{ .name = "text", .value = .{ .literal = item.name } }
                    }},
                    NodeDesc{ .tag = "Text", .classes = "text-muted", .attrs = &.{
                        .{ .name = "text", .value = .{ .literal = item.email } }
                    }},
                },
            };
            const child_id = try scene.instantiate(&card_desc, tokens);
            // Re-parent child_id under container.
            // (addChild to the container is handled internally by scene.instantiateUnder)
            _ = child_id;
        }
    }.instantiate,
    gpa,
);
```

The `refresh_fn` stored in `ListBinding` wraps `item_instantiate_fn` in a closure that:

1. Reads the current slice from the signal.
2. Removes all existing children of the `for=` container element from the scene.
3. For each item in the slice, calls `item_instantiate_fn`.

### `Scene.removeChildren` and `Scene.instantiateUnder`

Add two new `Scene` methods:

```zig
pub const Scene = struct {
    // ...

    /// Remove all direct children of `parent_idx` (and their subtrees) from the scene.
    /// Recycles element indices. Called before re-instantiating a `for=` list.
    pub fn removeChildren(self: *Scene, parent_idx: u32) void

    /// Instantiate `desc` as a child of `parent_id`. Like `instantiate` but appends the
    /// result as a child of `parent_id` in the element store rather than adding a root.
    pub fn instantiateUnder(
        self: *Scene,
        parent_id: ElementId,
        desc: NodeDesc,
        tokens: Tokens,
    ) InstantiateError!ElementId
};
```

### `refresh` extension for list bindings

```zig
pub fn refresh(self: *const BindingSet, scene: *Scene, tokens: Tokens) void {
    // Text and cond bindings (existing):
    for (self.text.items) |b| { ... }
    for (self.cond.items) |b| { ... }

    // List bindings (new):
    for (self.list.items) |*b| {
        // Check if signal version has changed since last refresh.
        // (Requires Signal to expose `version: u64` — already present per R20.)
        const sig = @as(*const Signal([]u8), @ptrCast(@alignCast(b.signal_ptr)));
        if (sig.version == b.last_version) continue;
        b.last_version = sig.version;

        // Re-build the child list.
        const container_id = ElementId{
            .index = b.container_idx,
            .gen   = scene.elements.gen.items[b.container_idx],
        };
        scene.removeChildren(b.container_idx);
        b.refresh_fn(scene, b.container_idx, &b.template, b.signal_ptr, tokens)
            catch |err| {
                std.log.err("list refresh failed: {}", .{err});
            };
        scene.elements.dirty.set(b.container_idx);
        _ = container_id;
    }
}
```

Note: `refresh` gains a `tokens: Tokens` parameter to support re-instantiation.
Update all call sites in `App.run()` accordingly.

### Handling `{bind item.*}` paths

`{bind item.*}` paths inside a `for=` template are **not** resolved by the framework — they
are placeholders in the markup that the `item_instantiate_fn` replaces with concrete values.
The parser records them as `AttrValue.bind` entries; `item_instantiate_fn` overrides the
`NodeDesc.attrs` before calling `instantiateUnder`. There is no runtime path-resolution
engine (INV-4.1 forbids it for static screens).

### Signal type for list bindings

The signal holds a `[]T` where `T` is any struct. `Signal([]Contact)` is a valid type.
The framework stores the signal as `*anyopaque` and the `len_fn` / `refresh_fn` closures
know the concrete type at compile time (via `bindList`'s comptime `T` parameter).

### Behavioral contract

| Situation | Behavior |
|---|---|
| `Signal([]T).set(new_slice)` | `refresh()` detects version change, removes old children, instantiates one subtree per item |
| Empty slice | All children removed; container has no children |
| Same slice version (set called with structurally identical data) | `refresh()` skips re-instantiation (version unchanged) |
| Large slice (> 500 items) | Correct but may be slow; virtualization is post-v1 |

### Module location

```
src/app/binding.zig       — ListBinding, bindList, refresh extension
src/app/types.zig         — Scene.removeChildren, Scene.instantiateUnder
docs/specs/07.types.zig   — removeChildren, instantiateUnder signatures
docs/requirements/R53_list_rendering.md
```

## Public API

New in `BindingSet`:

```zig
pub const ListBinding = struct { container_idx, template, signal_ptr, len_fn, refresh_fn, last_version }
pub fn bindList(self, comptime T, comptime field_name, state, container_idx, template, comptime item_fn, gpa) !void
// refresh gains tokens: Tokens parameter
```

New in `Scene`:

```zig
pub fn removeChildren(self: *Scene, parent_idx: u32) void
pub fn instantiateUnder(self: *Scene, parent_id: ElementId, desc: NodeDesc, tokens: Tokens) !ElementId
```

## Non-goals (DO NOT implement — INV-5.4)

- **No virtual DOM / structural diffing** — re-instantiation on every signal change; no
  keyed diffing, no patch algorithm.
- **No virtualized lists** (DataTable-style) — all items are instantiated as real elements;
  virtualization is M7-10 (post-v1).
- **No automatic `{bind item.*}` resolution** — the framework does not interpret bind paths
  inside `for=` templates; the application provides an `item_instantiate_fn`.
- **No nested `for=`** — `for=` inside a `for=` child template is untested and unsupported
  in v1.
- **No sorted/filtered lists** — the framework renders items in order; sorting and filtering
  are application responsibilities (modify the signal value).
- **No `for=` with index variable** — no `{bind index}` in templates; use the item data.
- **No `key=` attribute** — no stable identity for keyed diffing (not needed without diff).

## Acceptance criteria

1. `zig build test-binding` passes. New test cases:
   - `bindList` with a `Signal([]Item)` of 3 items: after `refresh`, the container has 3
     child elements in the store.
   - Setting the signal to a new slice (different version) and calling `refresh` removes
     old children and instantiates the new set.
   - Setting to an empty slice → container has 0 children.
   - Signal version unchanged → `refresh` does not re-instantiate (no store mutations).

2. `zig build test-scene` passes. New test cases:
   - `removeChildren` removes all direct children and their subtrees.
   - `instantiateUnder` appends the new element as a child of the given parent.

3. Integration: a list of contacts rendered with `for=`. Adding an item to the signal and
   calling `refresh` shows the new item in the list without restarting the app.

4. No memory leaks: removed children are properly freed/recycled via the element store
   freelist; `ListBinding.deinit` (via `BindingSet.deinit`) frees without leaks.

5. Checklist fully ticked.

## Open questions

One: `refresh` gaining a `tokens: Tokens` parameter requires updating all call sites in
`App.run()`. Confirm this does not conflict with the module-07 build-order constraint
(scene types must be visible from `binding.zig`; `binding.zig` imports module 07 — already
the case for `TextBinding`).
