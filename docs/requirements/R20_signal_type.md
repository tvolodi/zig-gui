# R20 — M2-01: Signal type

> Roadmap item: M2-01  
> Depends on: module 03 (`ElementStore.dirty` bitset), M1 complete  
> Read `00_constitution.md` before this file.

## Purpose

Provide `Signal(T)`, the single reactivity primitive for the framework. Writing a new value
through `set()` immediately marks all bound element indices dirty in the `ElementStore`'s
bitset, enabling the per-frame dirty scan (M2-02) to skip unmodified elements entirely.

A signal does **not** push values and does **not** run callbacks as a change-propagation
path (INV-3.3). It writes one integer per bound element into the `dirty` bitset and stops.
Everything else — re-layout, re-paint, reading the new value — is the frame loop's job.

## What to build

### `Signal(T)` — `src/app/signal.zig`

```zig
pub fn Signal(comptime T: type) type {
    return struct {
        /// Current value. Read via `get()`; written via `set()`.
        value: T,
        /// Points into `ElementStore.dirty`. NOT owned; do not free in `deinit`.
        dirty: *std.DynamicBitSetUnmanaged,
        /// Backing allocator for `subscribers` and `computed_deps`.
        gpa: std.mem.Allocator,
        /// Element indices to mark dirty on every `set()` call.
        subscribers: std.ArrayListUnmanaged(u32) = .empty,
        /// Monotonically increasing version counter. Incremented on every `set()`.
        /// Used by `Computed(T)` (M2-03) to detect staleness without a callback.
        version: u64 = 0,
        /// Type-erased callbacks for `Computed(T)` dependents. See M2-03.
        computed_deps: std.ArrayListUnmanaged(StaleFn) = .empty,

        /// Create a signal with `initial` as its starting value.
        /// `dirty` must point to the `ElementStore.dirty` bitset that will
        /// outlive this signal.
        pub fn init(
            gpa: std.mem.Allocator,
            initial: T,
            dirty: *std.DynamicBitSetUnmanaged,
        ) @This()

        /// Free `subscribers` and `computed_deps`. Does NOT free `dirty`.
        pub fn deinit(self: *@This()) void

        /// Return the current value. O(1), no side-effects.
        pub fn get(self: *const @This()) T

        /// Write a new value, increment `version`, and mark all subscribed
        /// element indices dirty. Also calls `dep.mark(dep.ptr)` for each
        /// entry in `computed_deps` so downstream `Computed` signals know they
        /// are stale (see M2-03).
        pub fn set(self: *@This(), val: T) void

        /// Register `idx` as a subscriber. Appends to `subscribers`; no
        /// duplicate check is performed.
        pub fn subscribe(self: *@This(), idx: u32) !void

        /// Register a `Computed` dependent. Called by `Computed.init` — not
        /// part of the application-facing API but must be exported (visible
        /// within `signal.zig`) so `Computed(T)` can call it.
        pub fn addComputedDep(self: *@This(), dep: StaleFn) !void
    };
}
```

### `StaleFn` — type-erased stale notification for `Computed`

```zig
/// A type-erased callback used by `Signal(T).set()` to notify downstream
/// `Computed(T)` instances that they are stale. This is NOT a general
/// observer/event system (INV-3.3): it only sets a boolean flag; no value
/// is pushed and no layout or paint work is done inside the callback.
pub const StaleFn = struct {
    ptr: *anyopaque,
    mark: *const fn (*anyopaque) void,
};
```

### Behavioral contract

| Method | What it does |
|---|---|
| `init(gpa, initial, dirty)` | Sets `value = initial`, stores `dirty` ptr, zero-inits lists |
| `deinit()` | Calls `subscribers.deinit(gpa)` and `computed_deps.deinit(gpa)` |
| `get()` | Returns `self.value` |
| `set(val)` | `value = val`, `version += 1`, calls `dirty.set(idx)` for each subscriber, calls `dep.mark(dep.ptr)` for each computed dep |
| `subscribe(idx)` | Appends `idx` to `subscribers` |
| `addComputedDep(dep)` | Appends `dep` to `computed_deps` |

**No equality check on `set()`:** subscribers are marked dirty unconditionally on every
`set()` call, even if the value is unchanged. Equality optimization is post-v1.

**No thread safety:** the frame loop is single-threaded (INV-1.1 personal tool).

### Module location

```
src/app/signal.zig        — Signal(T) and StaleFn (Computed(T) added by M2-03, same file)
src/app/signal_test.zig   — unit tests (no GPU, no GLFW)
```

`signal.zig` imports only `std` and module 03 (`ElementStore`, `DynamicBitSetUnmanaged`).
No imports from modules 04–09 or `src/app/app.zig` (signals sit below the rendering and
layout layers; INV-3.4 build order applies even within the app layer).

## Public API

The entire public surface of `signal.zig` after M2-01:

```zig
pub const StaleFn = struct { ptr: *anyopaque, mark: *const fn (*anyopaque) void };
pub fn Signal(comptime T: type) type { ... }
```

`Computed(T)` is added to this file by M2-03.

## Non-goals (DO NOT implement — INV-5.4)

- **No equality check** on `set()` — unconditional dirty marking only.
- **No two-way binding** — signals do not read back from `Scene`.
- **No thread safety** — single-threaded frame loop only.
- **No undo / change history.**
- **No computed/derived signals** — that is M2-03, added to the same file.
- **No binding API** — that is M2-04 (`src/app/binding.zig`).
- **No general observer/event callbacks** beyond the narrowly-scoped `StaleFn` mechanism
  used only by `Computed`. Adding observers for application code violates INV-3.3.

## Acceptance criteria

1. `zig build test-signal` runs `src/app/signal_test.zig`. Tests must cover:
   - `get()` returns the initial value after `init`.
   - `set(v)` makes `get()` return `v`.
   - `set(v)` marks every subscribed element index dirty in the provided bitset.
   - `subscribe(idx)` with the same `idx` twice → element is dirtied twice on next `set`
     (no deduplication).
   - `version` starts at `0`; increments by 1 on each `set()`.
   - `addComputedDep` causes `StaleFn.mark` to be called on the next `set()`.
   - `deinit()` frees all memory without double-free (use `std.testing.allocator`).
2. `Signal(u32)`, `Signal(f32)`, `Signal([]const u8)`, and `Signal(bool)` all compile.
3. The `dirty` pointer passed to `init` is the exact bitset that gets written — verified by
   testing with a stack-allocated `DynamicBitSetUnmanaged`.
4. Checklist fully ticked.

## Open questions

None. If the `DynamicBitSetUnmanaged` index passed to `dirty.set(idx)` is out of bounds at
runtime (element index beyond bitset capacity), that is a programming error in the caller —
do NOT add bounds-checking inside `set()`. Surface any such failure if observed.
