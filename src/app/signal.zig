//! Signal(T) and Computed(T) — reactivity primitives for the framework (R20 / M2-01).
//!
//! INV-3.3: All reactivity flows through signals → dirty bitset → linear scan.
//! A Signal write marks affected element indices dirty in the ElementStore bitset.
//! No value is pushed and no callbacks propagate layout or paint work.
//! The dirty bitset remains the sole propagation path to the rendered frame.

const std = @import("std");

/// A type-erased callback used by Signal(T).set() to notify downstream
/// Computed(T) instances that they are stale.
///
/// INV-3.3 compliance: StaleFn.mark does NOT violate INV-3.3. It only sets a
/// boolean flag (Computed.stale = true). No value is pushed, no layout or paint
/// work happens inside the callback, and the dirty bitset remains the sole
/// propagation path to the rendered frame. The stale flag merely defers the
/// recompute to the next get() call, which itself marks dirty bits through the
/// normal bitset mechanism.
pub const StaleFn = struct {
    ptr: *anyopaque,
    mark: *const fn (*anyopaque) void,
};

/// A reactive value container (M2-01).
/// Writing a new value through set() immediately marks all bound element indices
/// dirty in the ElementStore's bitset, enabling the per-frame dirty scan (M2-02)
/// to skip unmodified elements entirely.
pub fn Signal(comptime T: type) type {
    return struct {
        /// Current value. Read via get(); written via set().
        value: T,
        /// Points into ElementStore.dirty. NOT owned; do not free in deinit.
        dirty: *std.DynamicBitSetUnmanaged,
        /// Backing allocator for subscribers and computed_deps.
        gpa: std.mem.Allocator,
        /// Element indices to mark dirty on every set() call.
        subscribers: std.ArrayListUnmanaged(u32) = .empty,
        /// Monotonically increasing version counter. Incremented on every set().
        /// Used by Computed(T) (M2-03) to detect staleness without a callback.
        version: u64 = 0,
        /// Type-erased callbacks for Computed(T) dependents. See M2-03.
        computed_deps: std.ArrayListUnmanaged(StaleFn) = .empty,

        /// Create a signal with initial as its starting value.
        /// dirty must point to the ElementStore.dirty bitset that will
        /// outlive this signal.
        pub fn init(
            gpa: std.mem.Allocator,
            initial: T,
            dirty: *std.DynamicBitSetUnmanaged,
        ) @This() {
            return .{
                .value = initial,
                .dirty = dirty,
                .gpa = gpa,
            };
        }

        /// Free subscribers and computed_deps. Does NOT free dirty.
        pub fn deinit(self: *@This()) void {
            self.subscribers.deinit(self.gpa);
            self.computed_deps.deinit(self.gpa);
        }

        /// Return the current value. O(1), no side-effects.
        pub fn get(self: *const @This()) T {
            return self.value;
        }

        /// Write a new value, increment version, and mark all subscribed
        /// element indices dirty. Also calls dep.mark(dep.ptr) for each
        /// entry in computed_deps so downstream Computed signals know they
        /// are stale (see M2-03).
        ///
        /// No equality check: subscribers are marked dirty unconditionally on
        /// every set() call, even if the value is unchanged. Equality
        /// optimization is post-v1.
        pub fn set(self: *@This(), val: T) void {
            self.value = val;
            self.version += 1;
            for (self.subscribers.items) |idx| {
                self.dirty.set(idx);
            }
            for (self.computed_deps.items) |dep| {
                dep.mark(dep.ptr);
            }
        }

        /// Register idx as a subscriber. Appends to subscribers; no
        /// duplicate check is performed.
        pub fn subscribe(self: *@This(), idx: u32) !void {
            try self.subscribers.append(self.gpa, idx);
        }

        /// Register a Computed dependent. Called by Computed.init — not
        /// part of the application-facing API but must be exported so
        /// Computed(T) can call it.
        pub fn addComputedDep(self: *@This(), dep: StaleFn) !void {
            try self.computed_deps.append(self.gpa, dep);
        }
    };
}

/// A derived signal whose value is a pure function of one or more upstream
/// Signal(T) instances (M2-03). Caches the last result and only recomputes
/// when an upstream Signal.set() has fired since the last get().
///
/// NOTE: Computed cannot depend on another Computed. Calling other_computed.get()
/// inside a compute function would trigger that computed's recompute as a side
/// effect of the inner get(), producing surprising behavior. This constraint is
/// not enforced at runtime.
pub fn Computed(comptime T: type) type {
    return struct {
        /// Last computed value. Valid when stale == false.
        cached: T,
        /// True when any upstream signal has changed since last get().
        /// Initialized to true so the first get() always runs compute.
        stale: bool,
        /// Points into ElementStore.dirty. NOT owned; do not free in deinit.
        dirty: *std.DynamicBitSetUnmanaged,
        gpa: std.mem.Allocator,
        /// Element indices to mark dirty when get() recomputes.
        subscribers: std.ArrayListUnmanaged(u32) = .empty,
        /// Type-erased compute context and function. The function must be a
        /// pure function of its inputs — no side effects.
        ctx: *anyopaque,
        compute: *const fn (*anyopaque) T,

        /// Initialize a Computed. initial is the value returned before the
        /// first get() triggers a recompute; it does NOT call compute.
        /// Wire upstream signals AFTER this call via Signal.addComputedDep.
        pub fn init(
            gpa: std.mem.Allocator,
            initial: T,
            dirty: *std.DynamicBitSetUnmanaged,
            ctx: *anyopaque,
            compute: *const fn (*anyopaque) T,
        ) @This() {
            return .{
                .cached = initial,
                .stale = true,
                .dirty = dirty,
                .gpa = gpa,
                .ctx = ctx,
                .compute = compute,
            };
        }

        /// Free subscribers. Does NOT free dirty, ctx, or compute.
        pub fn deinit(self: *@This()) void {
            self.subscribers.deinit(self.gpa);
        }

        /// Return the cached value, recomputing if stale == true.
        /// When it recomputes, all subscribed element indices are marked dirty.
        /// Calling get() when not stale does NOT touch the dirty bitset.
        pub fn get(self: *@This()) T {
            if (self.stale) {
                self.cached = self.compute(self.ctx);
                self.stale = false;
                for (self.subscribers.items) |idx| {
                    self.dirty.set(idx);
                }
            }
            return self.cached;
        }

        /// Register idx as an element subscriber. Appends without dedup.
        pub fn subscribe(self: *@This(), idx: u32) !void {
            try self.subscribers.append(self.gpa, idx);
        }

        /// Set stale = true. Called by upstream Signal.set() via StaleFn.
        /// Does NOT trigger a recompute — recompute is lazy, on the next get().
        pub fn markStale(self: *@This()) void {
            self.stale = true;
        }

        /// Return a StaleFn that, when called, invokes markStale on this
        /// Computed. Pass the returned value to Signal.addComputedDep(...).
        pub fn staleFn(self: *@This()) StaleFn {
            return StaleFn{ .ptr = self, .mark = &markStaleFn };
        }

        fn markStaleFn(ptr: *anyopaque) void {
            const self: *@This() = @ptrCast(@alignCast(ptr));
            self.markStale();
        }
    };
}
