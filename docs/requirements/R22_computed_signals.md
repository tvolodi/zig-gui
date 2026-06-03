# R22 — M2-03: Computed / derived signals

> Roadmap item: M2-03  
> Depends on: M2-01 (Signal type, `StaleFn`)  
> Read `00_constitution.md` before this file.

## Purpose

`Computed(T)` is a signal whose value is a pure function of one or more upstream `Signal(T)`
instances. It caches the last result and only recomputes when an upstream `Signal.set()` has
fired since the last `get()`. Like `Signal(T)`, it marks subscribed element indices dirty
when it recomputes — so the dirty scan (M2-02) picks it up automatically.

## What to build

Add `Computed(T)` to `src/app/signal.zig` — the same file as `Signal(T)`. No new file is
needed.

### `Computed(T)`

```zig
pub fn Computed(comptime T: type) type {
    return struct {
        /// Last computed value. Valid when `stale == false`.
        cached: T,
        /// True when any upstream signal has changed since last `get()`.
        /// Initialized to `true` so the first `get()` always runs `compute`.
        stale: bool,
        /// Points into `ElementStore.dirty`. NOT owned; do not free in `deinit`.
        dirty: *std.DynamicBitSetUnmanaged,
        gpa: std.mem.Allocator,
        /// Element indices to mark dirty when `get()` recomputes.
        subscribers: std.ArrayListUnmanaged(u32) = .empty,
        /// Type-erased compute context and function. The function must be a
        /// pure function of its inputs — no side effects.
        ctx: *anyopaque,
        compute: *const fn (*anyopaque) T,

        /// Initialize a Computed. `initial` is the value returned before the
        /// first `get()` triggers a recompute; it does NOT call `compute`.
        /// Wire upstream signals AFTER this call (see §Wiring below).
        pub fn init(
            gpa: std.mem.Allocator,
            initial: T,
            dirty: *std.DynamicBitSetUnmanaged,
            ctx: *anyopaque,
            compute: *const fn (*anyopaque) T,
        ) @This()

        /// Free `subscribers`. Does NOT free `dirty`, `ctx`, or `compute`.
        pub fn deinit(self: *@This()) void

        /// Return the cached value, recomputing if `stale == true`.
        /// When it recomputes, all subscribed element indices are marked dirty.
        pub fn get(self: *@This()) T

        /// Register `idx` as an element subscriber. Appends without dedup.
        pub fn subscribe(self: *@This(), idx: u32) !void

        /// Set `stale = true`. Called by upstream `Signal.set()` via `StaleFn`.
        /// Does NOT trigger a recompute — recompute is lazy, on the next `get()`.
        pub fn markStale(self: *@This()) void

        /// Return a `StaleFn` that, when called, invokes `markStale` on this
        /// `Computed`. Pass the returned value to `Signal.addComputedDep(...)`.
        pub fn staleFn(self: *@This()) StaleFn
    };
}
```

### Behavioral contract

| Method | What it does |
|---|---|
| `init(gpa, initial, dirty, ctx, compute)` | `cached = initial`, `stale = true`, stores ptrs, zero-inits `subscribers` |
| `deinit()` | `subscribers.deinit(gpa)` |
| `get()` | If `stale`: call `compute(ctx)`, store in `cached`, set `stale = false`, dirty all subscribers. Return `cached`. |
| `subscribe(idx)` | Append `idx` to `subscribers` |
| `markStale()` | `stale = true` |
| `staleFn()` | Return `StaleFn{ .ptr = self, .mark = &markStaleFn }` |

`markStaleFn` is a file-private function with the `StaleFn.mark` signature:

```zig
fn markStaleFn(ptr: *anyopaque) void {
    const self: *Computed(T) = @ptrCast(@alignCast(ptr));
    self.markStale();
}
```

Because `Computed(T)` is a generic, `markStaleFn` is also inside the `Computed(T)` function
body to close over `T`.

### `get()` invariant

```
get():
  if stale == false: return cached          // O(1), no side-effects
  cached = compute(ctx)                     // pure function call
  stale  = false
  for each idx in subscribers: dirty.set(idx)
  return cached
```

**Calling `get()` when not stale must NOT touch the dirty bitset.** A test must verify this.

### Wiring a `Computed` to upstream signals

The caller establishes dependencies at init time by registering the `Computed`'s `StaleFn`
with each upstream `Signal`:

```zig
var sig_a = try Signal(u32).init(gpa, 10, &store.dirty);
var sig_b = try Signal(u32).init(gpa, 20, &store.dirty);

const Ctx = struct { a: *Signal(u32), b: *Signal(u32) };
var ctx = Ctx{ .a = &sig_a, .b = &sig_b };

fn sumFn(raw: *anyopaque) u32 {
    const c: *Ctx = @ptrCast(@alignCast(raw));
    return c.a.get() + c.b.get();
}

var sum = Computed(u32).init(gpa, 0, &store.dirty, &ctx, &sumFn);

// Wire: when sig_a or sig_b change, sum is stale.
try sig_a.addComputedDep(sum.staleFn());
try sig_b.addComputedDep(sum.staleFn());
```

When `sig_a.set(11)` is called:
1. `sig_a.version` increments.
2. `sig_a` marks its own element subscribers dirty.
3. `sig_a` calls `sum.markStale()` via the registered `StaleFn`.
4. `sum.stale = true` — no compute yet.
5. Next call to `sum.get()` recomputes `11 + 20 = 31`, marks `sum`'s element subscribers
   dirty, returns `31`.

### Calling `Signal.get()` inside `compute`

`compute` may call `sig_a.get()` and `sig_b.get()` freely. `Signal.get()` is `O(1)` with
no side-effects. This is the expected usage pattern.

### `Computed` cannot depend on another `Computed`

A `Computed` computes from `Signal` instances directly. Calling `other_computed.get()`
inside a `compute` function would trigger that computed's recompute (possibly re-dirtying
elements) as a side effect of the inner `get()`. This produces surprising behavior and is
out of scope for M2-03. Document with a comment in the source; do NOT add cycle detection.

### Double `markStale` in one frame

If both `sig_a` and `sig_b` fire `set()` in the same frame, `sum.markStale()` is called
twice. This is harmless — `stale` goes `true → true`. Document in a comment.

### Module location

```
src/app/signal.zig        — Signal(T), StaleFn, Computed(T) — all in one file
src/app/signal_test.zig   — unit tests cover both Signal and Computed
```

## Non-goals (DO NOT implement — INV-5.4)

- **No multi-level computed chains** — `Computed` depending on another `Computed` is
  undocumented and unsupported; add support only if a spec requires it.
- **No cycle detection** — programmer error; undefined behavior is acceptable.
- **No async or deferred compute** — `compute` is called synchronously inside `get()`.
- **No equality check after recompute** — always marks dirty on every `get()` when stale,
  even if the computed value is unchanged.
- **No derived `Signal` that can accept `set()` calls** — `Computed` is read-only.

## Acceptance criteria

1. `zig build test-signal` runs `src/app/signal_test.zig`. Computed-specific tests:
   - `get()` on a freshly init'd `Computed` (`stale = true`) calls `compute` and returns
     the computed value (not the `initial` value after the first `get()`).
   - After `sig.set(v)` wired to a `Computed`, `computed.get()` returns the newly derived
     value.
   - After `computed.get()` when stale, every subscribed element index is marked dirty.
   - A second `computed.get()` without an intervening `sig.set()` returns the cached value
     and does NOT touch the dirty bitset (verified by checking bitset unchanged).
   - `deinit()` produces no leaks with `std.testing.allocator`.
   - `staleFn()` returns a `StaleFn` whose `.mark` call sets `stale = true`.
2. `Computed(u32)`, `Computed(f32)`, `Computed([]const u8)`, and `Computed(bool)` all
   compile.
3. Checklist fully ticked.

## Open questions

None. If multi-level `Computed` chains become necessary for a future requirement, surface
the design before implementing — it requires topological sort or a push-based evaluation
strategy, both of which add non-trivial complexity.
