//! Unit tests for Signal(T), Computed(T), and StaleFn (R20/R22 / M2-01/M2-03).
//!
//! No random, no wall-clock time. All tests use std.testing.allocator for leak detection.
//! These tests go deeper than acceptance tests: edge cases, error paths, and the
//! INV-3.3 dirty-bitset invariant (stale get must NOT touch the bitset).

const std = @import("std");
const signal_mod = @import("signal.zig");

const Signal = signal_mod.Signal;
const Computed = signal_mod.Computed;
const StaleFn = signal_mod.StaleFn;

// ---------------------------------------------------------------------------
// Helper: allocate a DynamicBitSetUnmanaged with `n` bits, all unset.
// ---------------------------------------------------------------------------

fn makeBitset(gpa: std.mem.Allocator, n: usize) !std.DynamicBitSetUnmanaged {
    var bs = std.DynamicBitSetUnmanaged{};
    try bs.resize(gpa, n, false);
    return bs;
}

// ---------------------------------------------------------------------------
// Compute-function contexts used by Computed(T) tests.
// Must be file-level so their addresses are stable function pointers.
// ---------------------------------------------------------------------------

const ConstCtx = struct { value: u32 };

fn constCompute(raw: *anyopaque) u32 {
    const c: *ConstCtx = @ptrCast(@alignCast(raw));
    return c.value;
}

/// Context that tracks how many times compute() was called.
const CountCtx = struct { value: u32, calls: u32 };

fn countingCompute(raw: *anyopaque) u32 {
    const c: *CountCtx = @ptrCast(@alignCast(raw));
    c.calls += 1;
    return c.value;
}

/// Context that reads the current value from an upstream Signal(u32).
const SigReadCtx = struct { sig: *Signal(u32) };

fn readFromSignal(raw: *anyopaque) u32 {
    const c: *SigReadCtx = @ptrCast(@alignCast(raw));
    return c.sig.get();
}

// ===========================================================================
// Signal(T) — basics
// ===========================================================================

test "Signal.init: initial value and version=0" {
    const gpa = std.testing.allocator;
    var bs = try makeBitset(gpa, 8);
    defer bs.deinit(gpa);

    var sig = Signal(u32).init(gpa, 42, &bs);
    defer sig.deinit();

    try std.testing.expectEqual(@as(u32, 42), sig.get());
    try std.testing.expectEqual(@as(u64, 0), sig.version);
}

test "Signal.get: O(1), no side effects on value/version/dirty" {
    const gpa = std.testing.allocator;
    var bs = try makeBitset(gpa, 8);
    defer bs.deinit(gpa);

    var sig = Signal(u32).init(gpa, 10, &bs);
    defer sig.deinit();

    // Repeated gets must not mutate any state.
    _ = sig.get();
    _ = sig.get();
    try std.testing.expectEqual(@as(u64, 0), sig.version);
    try std.testing.expectEqual(@as(u32, 10), sig.get());
    try std.testing.expectEqual(@as(usize, 0), bs.count()); // bitset untouched
}

test "Signal.set: updates stored value" {
    const gpa = std.testing.allocator;
    var bs = try makeBitset(gpa, 8);
    defer bs.deinit(gpa);

    var sig = Signal(u32).init(gpa, 0, &bs);
    defer sig.deinit();

    sig.set(99);
    try std.testing.expectEqual(@as(u32, 99), sig.get());
}

test "Signal.set: increments version on every call, including repeated values" {
    const gpa = std.testing.allocator;
    var bs = try makeBitset(gpa, 8);
    defer bs.deinit(gpa);

    var sig = Signal(u32).init(gpa, 0, &bs);
    defer sig.deinit();

    sig.set(1);
    try std.testing.expectEqual(@as(u64, 1), sig.version);
    sig.set(2);
    try std.testing.expectEqual(@as(u64, 2), sig.version);
    sig.set(2); // same value — version must still increment
    try std.testing.expectEqual(@as(u64, 3), sig.version);
}

test "Signal.subscribe + set: marks the subscribed index dirty" {
    const gpa = std.testing.allocator;
    var bs = try makeBitset(gpa, 16);
    defer bs.deinit(gpa);

    var sig = Signal(u32).init(gpa, 0, &bs);
    defer sig.deinit();

    try sig.subscribe(7);
    try std.testing.expect(!bs.isSet(7)); // clean before set()

    sig.set(1);
    try std.testing.expect(bs.isSet(7)); // dirty after set()
}

test "Signal.set: marks ALL multiple subscribers dirty" {
    const gpa = std.testing.allocator;
    var bs = try makeBitset(gpa, 16);
    defer bs.deinit(gpa);

    var sig = Signal(u32).init(gpa, 0, &bs);
    defer sig.deinit();

    try sig.subscribe(0);
    try sig.subscribe(5);
    try sig.subscribe(15);

    sig.set(1);

    try std.testing.expect(bs.isSet(0));
    try std.testing.expect(bs.isSet(5));
    try std.testing.expect(bs.isSet(15));
}

test "Signal.set: unconditional dirty — marks dirty even when value is unchanged" {
    const gpa = std.testing.allocator;
    var bs = try makeBitset(gpa, 8);
    defer bs.deinit(gpa);

    // Init with value=42 then set(42) again — still marks dirty per R20.
    var sig = Signal(u32).init(gpa, 42, &bs);
    defer sig.deinit();

    try sig.subscribe(0);
    sig.set(42); // same value as initial
    try std.testing.expect(bs.isSet(0)); // must be dirty regardless
}

test "Signal.deinit: no memory leaks (subscribers + computed_deps freed)" {
    const gpa = std.testing.allocator;
    var bs = try makeBitset(gpa, 8);
    defer bs.deinit(gpa);

    var sig = Signal(u32).init(gpa, 0, &bs);
    try sig.subscribe(0);
    try sig.subscribe(1);
    // deinit must free the subscribers ArrayListUnmanaged.
    sig.deinit();
    // std.testing.allocator detects any remaining allocation as a leak.
}

test "Signal.set does not dirty indices that were never subscribed" {
    const gpa = std.testing.allocator;
    var bs = try makeBitset(gpa, 16);
    defer bs.deinit(gpa);

    var sig = Signal(u32).init(gpa, 0, &bs);
    defer sig.deinit();

    try sig.subscribe(3); // only 3 is subscribed

    sig.set(1);

    // 3 should be dirty; all others should remain clean.
    try std.testing.expect(bs.isSet(3));
    try std.testing.expectEqual(@as(usize, 1), bs.count());
}

// ===========================================================================
// Computed(T) — lazy derived signals (R22 / M2-03)
// ===========================================================================

test "Computed.init: stale=true on construction" {
    const gpa = std.testing.allocator;
    var bs = try makeBitset(gpa, 8);
    defer bs.deinit(gpa);

    var ctx = ConstCtx{ .value = 42 };
    var comp = Computed(u32).init(gpa, 0, &bs, &ctx, &constCompute);
    defer comp.deinit();

    try std.testing.expect(comp.stale); // always starts stale per spec
}

test "Computed.get: first call recomputes, clears stale, marks subscribers dirty" {
    const gpa = std.testing.allocator;
    var bs = try makeBitset(gpa, 8);
    defer bs.deinit(gpa);

    var ctx = ConstCtx{ .value = 77 };
    var comp = Computed(u32).init(gpa, 0, &bs, &ctx, &constCompute);
    defer comp.deinit();

    try comp.subscribe(3);
    try std.testing.expect(!bs.isSet(3)); // not dirty yet

    const val = comp.get();

    try std.testing.expectEqual(@as(u32, 77), val); // correct computed value
    try std.testing.expect(!comp.stale); // stale cleared
    try std.testing.expect(bs.isSet(3)); // subscriber marked dirty
}

test "Computed.get: second call when not stale returns cached — does NOT call compute or touch dirty (INV-3.3)" {
    const gpa = std.testing.allocator;
    var bs = try makeBitset(gpa, 8);
    defer bs.deinit(gpa);

    var ctx = CountCtx{ .value = 10, .calls = 0 };
    var comp = Computed(u32).init(gpa, 0, &bs, &ctx, &countingCompute);
    defer comp.deinit();

    try comp.subscribe(2);

    _ = comp.get(); // first call: recomputes, marks bit 2 dirty
    try std.testing.expectEqual(@as(u32, 1), ctx.calls);
    try std.testing.expect(bs.isSet(2));

    bs.unset(2); // manually clear so we can observe the second call
    const dirty_count_before = bs.count();

    _ = comp.get(); // second call: stale=false — must be a no-op on dirty bitset
    try std.testing.expectEqual(@as(u32, 1), ctx.calls); // compute NOT called again
    try std.testing.expectEqual(dirty_count_before, bs.count()); // bitset unchanged
    try std.testing.expect(!bs.isSet(2)); // bit must remain unset
}

test "Computed.markStale: sets stale=true; next get() recomputes" {
    const gpa = std.testing.allocator;
    var bs = try makeBitset(gpa, 8);
    defer bs.deinit(gpa);

    var ctx = CountCtx{ .value = 5, .calls = 0 };
    var comp = Computed(u32).init(gpa, 0, &bs, &ctx, &countingCompute);
    defer comp.deinit();

    _ = comp.get(); // clear stale
    try std.testing.expect(!comp.stale);
    try std.testing.expectEqual(@as(u32, 1), ctx.calls);

    comp.markStale();
    try std.testing.expect(comp.stale);

    _ = comp.get(); // must recompute because stale=true
    try std.testing.expectEqual(@as(u32, 2), ctx.calls);
    try std.testing.expect(!comp.stale);
}

test "Computed.staleFn: calling the returned StaleFn sets stale=true" {
    const gpa = std.testing.allocator;
    var bs = try makeBitset(gpa, 8);
    defer bs.deinit(gpa);

    var ctx = ConstCtx{ .value = 1 };
    var comp = Computed(u32).init(gpa, 0, &bs, &ctx, &constCompute);
    defer comp.deinit();

    _ = comp.get(); // clear stale
    try std.testing.expect(!comp.stale);

    const sf = comp.staleFn();
    sf.mark(sf.ptr); // invoke the StaleFn
    try std.testing.expect(comp.stale);
}

test "Signal.addComputedDep wiring: signal.set marks computed stale; next get recomputes" {
    const gpa = std.testing.allocator;
    var bs = try makeBitset(gpa, 8);
    defer bs.deinit(gpa);

    var sig = Signal(u32).init(gpa, 10, &bs);
    defer sig.deinit();

    var ctx = SigReadCtx{ .sig = &sig };
    var comp = Computed(u32).init(gpa, 0, &bs, &ctx, &readFromSignal);
    defer comp.deinit();

    try sig.addComputedDep(comp.staleFn()); // wire upstream → downstream

    const v1 = comp.get(); // first get: recomputes from sig=10
    try std.testing.expectEqual(@as(u32, 10), v1);
    try std.testing.expect(!comp.stale);

    sig.set(20); // signal change must mark computed stale via StaleFn
    try std.testing.expect(comp.stale);

    const v2 = comp.get(); // recomputes from sig=20
    try std.testing.expectEqual(@as(u32, 20), v2);
    try std.testing.expect(!comp.stale);
}

test "Computed.deinit: no memory leaks (subscribers freed)" {
    const gpa = std.testing.allocator;
    var bs = try makeBitset(gpa, 8);
    defer bs.deinit(gpa);

    var ctx = ConstCtx{ .value = 0 };
    var comp = Computed(u32).init(gpa, 0, &bs, &ctx, &constCompute);
    try comp.subscribe(0);
    try comp.subscribe(1);
    comp.deinit(); // must free subscribers
    // std.testing.allocator reports any leak.
}

// INV-3.3 explicit: when Computed.get() is called and stale==false, the dirty
// bitset count must not increase.
test "INV-3.3: Computed.get when not stale does not increase dirty count" {
    const gpa = std.testing.allocator;
    var bs = try makeBitset(gpa, 8);
    defer bs.deinit(gpa);

    var ctx = ConstCtx{ .value = 99 };
    var comp = Computed(u32).init(gpa, 0, &bs, &ctx, &constCompute);
    defer comp.deinit();

    try comp.subscribe(4);

    _ = comp.get(); // first call marks bit 4 dirty
    const count_after_first = bs.count();

    _ = comp.get(); // second call — stale=false, must not change dirty count
    try std.testing.expectEqual(count_after_first, bs.count());
}

test "Computed.get: initial cached value is not returned after first get (it recomputes)" {
    const gpa = std.testing.allocator;
    var bs = try makeBitset(gpa, 8);
    defer bs.deinit(gpa);

    // Initial (sentinel) value = 999, but compute always returns 1.
    var ctx = ConstCtx{ .value = 1 };
    var comp = Computed(u32).init(gpa, 999, &bs, &ctx, &constCompute);
    defer comp.deinit();

    // First get must run compute (stale=true from init), ignoring the 999 sentinel.
    const val = comp.get();
    try std.testing.expectEqual(@as(u32, 1), val);
}
