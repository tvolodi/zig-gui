//! RA1 — M10-02: Memory budget enforcement.
//!
//! BudgetedArena wraps ArenaAllocator with a configurable byte ceiling.
//! When allocation would exceed budget_bytes, returns error.OutOfMemory.
//! INV-3.5: wraps ArenaAllocator, same reset behavior.
//! INV-5.6: uses only std.heap.ArenaAllocator and std.mem.Allocator.
//! INV-1.1: budget_bytes = 0 means unlimited (default) — zero overhead.

const std = @import("std");

pub const BudgetedArena = struct {
    inner: std.heap.ArenaAllocator,
    budget_bytes: usize,
    used_bytes: usize,

    /// Initialise with a fixed byte budget. `budget_bytes == 0` means unlimited
    /// (identical behavior to a plain ArenaAllocator).
    pub fn init(child: std.mem.Allocator, budget_bytes: usize) BudgetedArena {
        return BudgetedArena{
            .inner = std.heap.ArenaAllocator.init(child),
            .budget_bytes = budget_bytes,
            .used_bytes = 0,
        };
    }

    /// Release all memory. Resets `used_bytes` to zero.
    pub fn deinit(self: *BudgetedArena) void {
        self.inner.deinit();
        self.used_bytes = 0;
    }

    /// Reset the arena (same as ArenaAllocator.reset). Resets `used_bytes` to zero.
    pub fn reset(self: *BudgetedArena) void {
        _ = self.inner.reset(.retain_capacity);
        self.used_bytes = 0;
    }

    /// Return an `std.mem.Allocator` backed by this arena that enforces the budget.
    pub fn allocator(self: *BudgetedArena) std.mem.Allocator {
        return .{
            .ptr = self,
            .vtable = &.{
                .alloc = alloc,
                .resize = resize,
                .remap = remap,
                .free = free,
            },
        };
    }

    /// Current number of bytes allocated since the last reset.
    pub fn usedBytes(self: *const BudgetedArena) usize {
        return self.used_bytes;
    }

    /// Configured budget in bytes (0 = unlimited).
    pub fn budgetBytes(self: *const BudgetedArena) usize {
        return self.budget_bytes;
    }

    // -----------------------------------------------------------------------
    // Allocator vtable implementations
    // -----------------------------------------------------------------------

    fn alloc(ctx: *anyopaque, n: usize, ptr_align: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
        const self: *BudgetedArena = @ptrCast(@alignCast(ctx));

        // Budget check (skip if unlimited).
        if (self.budget_bytes > 0) {
            const new_used = self.used_bytes + n;
            if (new_used > self.budget_bytes) {
                // Log only outside the test harness to avoid test-runner error-log failures.
                if (!@import("builtin").is_test) {
                    std.log.err("[zig-gui] arena budget exceeded: {d} bytes used of {d} byte limit", .{
                        new_used,
                        self.budget_bytes,
                    });
                }
                return null;
            }
        }

        const result = self.inner.allocator().rawAlloc(n, ptr_align, ret_addr);
        if (result != null) {
            self.used_bytes += n;
        }
        return result;
    }

    fn resize(ctx: *anyopaque, buf: []u8, buf_align: std.mem.Alignment, new_len: usize, ret_addr: usize) bool {
        const self: *BudgetedArena = @ptrCast(@alignCast(ctx));
        const old_len = buf.len;
        const result = self.inner.allocator().rawResize(buf, buf_align, new_len, ret_addr);
        if (result) {
            // Adjust used_bytes by the delta.
            if (new_len > old_len) {
                self.used_bytes += new_len - old_len;
            } else if (old_len > new_len) {
                self.used_bytes -|= old_len - new_len;
            }
        }
        return result;
    }

    fn remap(ctx: *anyopaque, buf: []u8, buf_align: std.mem.Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
        const self: *BudgetedArena = @ptrCast(@alignCast(ctx));
        return self.inner.allocator().rawRemap(buf, buf_align, new_len, ret_addr);
    }

    fn free(ctx: *anyopaque, buf: []u8, buf_align: std.mem.Alignment, ret_addr: usize) void {
        const self: *BudgetedArena = @ptrCast(@alignCast(ctx));
        self.inner.allocator().rawFree(buf, buf_align, ret_addr);
        // Arena doesn't actually free; used_bytes stays as-is (arena semantics).
    }
};
