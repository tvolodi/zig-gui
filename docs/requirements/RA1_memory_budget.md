# RA1 — M10-02: Memory budget enforcement

> Roadmap item: M10-02  
> Depends on: M0 (Element store — arena allocator; modules 03, 07)  
> Read `00_constitution.md` before this file.

## Purpose

Enforce a configurable ceiling on the per-screen arena allocator. When the arena would
exceed the budget, return a graceful `error.OutOfMemory` instead of silently consuming
unbounded memory or triggering undefined behavior in release builds.

---

## Motivation

The per-screen arena (INV-3.5) currently grows without bound. On embedded or memory-
constrained targets, a runaway scene (thousands of elements, huge text arrays) can exhaust
memory without any signal. A budget ceiling allows the application author to discover
over-allocation early (debug) and handle it gracefully (release).

---

## What to build

### 1. `BudgetedArena` — `src/app/budgeted_arena.zig`

```zig
const std = @import("std");

pub const BudgetedArena = struct {
    inner: std.heap.ArenaAllocator,
    budget_bytes: usize,
    used_bytes: usize,

    /// Initialise with a fixed byte budget. `budget_bytes == 0` means unlimited
    /// (identical behavior to a plain ArenaAllocator).
    pub fn init(child: std.mem.Allocator, budget_bytes: usize) BudgetedArena;

    /// Release all memory. Resets `used_bytes` to zero.
    pub fn deinit(self: *BudgetedArena) void;

    /// Reset the arena (same as ArenaAllocator.reset). Resets `used_bytes` to zero.
    pub fn reset(self: *BudgetedArena) void;

    /// Return an `std.mem.Allocator` backed by this arena that enforces the budget.
    pub fn allocator(self: *BudgetedArena) std.mem.Allocator;

    /// Current number of bytes allocated since the last reset.
    pub fn usedBytes(self: *const BudgetedArena) usize;

    /// Configured budget in bytes (0 = unlimited).
    pub fn budgetBytes(self: *const BudgetedArena) usize;
};
```

The `allocator()` return value wraps `inner.allocator()`. The `alloc` vtable function:
1. Adds the requested size to `used_bytes`.
2. If `budget_bytes > 0` and `used_bytes > budget_bytes`: subtracts the size back
   (does NOT count the failed allocation), then returns `error.OutOfMemory`.
3. Otherwise: delegates to `inner.allocator().alloc(...)`.

`free` and `resize` are delegated unconditionally to `inner.allocator()`.

### 2. `AppOptions` addition

```zig
/// Memory budget for the per-screen arena allocator, in bytes.
/// 0 means unlimited (default). When set, Scene.reset() calls BudgetedArena.reset().
/// When a scene builder exceeds the budget, the Navigator error boundary (if enabled)
/// catches the OutOfMemory and displays the fallback screen.
arena_budget_bytes: usize = 0,
```

### 3. `AppInner` integration

`AppInner` gains a `budget_arena: ?BudgetedArena = null` field.

When `opts.arena_budget_bytes > 0`:
- `AppInner.init` constructs a `BudgetedArena` and stores it in `budget_arena`.
- The `Scene` is initialised with `budget_arena.?.allocator()` instead of the raw `gpa`.
- On each call to `scene.reset()`, `budget_arena.?.reset()` is called first.

When `opts.arena_budget_bytes == 0`, `budget_arena` is null and behavior is unchanged.

### 4. Logging on budget exceeded

When allocation fails due to budget enforcement, the wrapper logs at `std.log.err`:

```
[zig-gui] arena budget exceeded: {d} bytes used of {d} byte limit
```

This log line is written before returning `error.OutOfMemory`.

---

## Module location

```
src/app/budgeted_arena.zig       — BudgetedArena implementation
src/app/budgeted_arena_test.zig  — unit tests
docs/requirements/RA1_memory_budget.md
```

`src/app/types.zig` must re-export `BudgetedArena`.

---

## Invariant interactions

- **INV-3.5**: `BudgetedArena` wraps `ArenaAllocator` and calls its `reset()` on screen
  close. The arena-per-screen contract is preserved exactly.
- **INV-3.1**: No per-widget heap allocation is introduced. The arena remains the sole
  allocator for scene data.
- **INV-5.6**: No new dependencies. Uses only `std.heap.ArenaAllocator` and `std.mem.Allocator`.
- **INV-1.1**: `arena_budget_bytes = 0` (default) produces zero overhead.

---

## Glossary addition

Add to `docs/specs/glossary.md`:

```
## BudgetedArena

An `ArenaAllocator` wrapper that enforces a configurable byte ceiling. When an allocation
would exceed `budget_bytes`, it returns `error.OutOfMemory` and logs the overage. A budget
of 0 means unlimited. Reset behavior is identical to the underlying `ArenaAllocator`.
Defined in `src/app/budgeted_arena.zig`. See: RA1 (M10-02).
```

---

## Non-goals (DO NOT implement — INV-5.4)

- NO per-widget or per-array granular tracking. Only total arena usage is tracked.
- NO automatic shrinking or GC. The arena is bump-allocated; reset is the only reclamation.
- NO configurable OOM handler callback. `error.OutOfMemory` propagation through the call
  stack is the only recovery path.
- NO memory profiling or flamegraph output. `usedBytes()` is the only introspection.
- NO fractional budgets (e.g., % of system RAM). Only absolute byte counts.

---

## Acceptance criteria

The module is done when:

1. `zig build test-budget-arena` runs `src/app/budgeted_arena_test.zig` and all tests pass.
2. Allocating within the budget succeeds.
3. Allocating past the budget returns `error.OutOfMemory` without corrupting the arena.
4. `reset()` resets `usedBytes()` to zero.
5. `budget_bytes == 0` allows unlimited allocation (no budget check).
6. The log line is produced on budget exhaustion.
7. `AppInner` with `arena_budget_bytes > 0` initialises with `BudgetedArena`.
8. No memory leaks (tested with `std.testing.allocator`).

---

## Edge cases (each has a test)

- First allocation exactly equals budget → succeeds.
- Second allocation would exceed budget → returns `error.OutOfMemory`; first allocation
  still readable.
- `reset()` then allocate again within budget → succeeds (budget resets).
- `budget_bytes = 0` → no limit, arbitrary allocations succeed.
- Multiple small allocations accumulating past budget → correct cumulative tracking.
