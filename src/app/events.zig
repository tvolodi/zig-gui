//! EventQueue — pre-allocated 256-event ring buffer for GLFW callback delivery.
//! Lives in src/app/events.zig.
//! Event type is InputEvent from module 01 (re-exported as `Event` by types.zig).

const std = @import("std");
const mod01 = @import("../01/types.zig");

pub const Event = mod01.InputEvent;

/// Maximum events buffered per frame. Extras are silently dropped with a log.warn.
pub const CAPACITY: usize = 256;

/// Pre-allocated event queue.  `push` is called from GLFW callbacks (same thread).
/// `drain` / `clear` are called from the frame loop.
pub const EventQueue = struct {
    buf: [CAPACITY]Event = undefined,
    len: usize = 0,
    overflowed: bool = false,

    pub fn init(_gpa: std.mem.Allocator) EventQueue {
        _ = _gpa;
        return EventQueue{};
    }

    pub fn deinit(self: *EventQueue) void {
        _ = self;
        // nothing heap-allocated
    }

    /// Called from GLFW callbacks (via the push_fn indirection).
    /// Drops the event silently (with one warn) when full.
    pub fn push(self: *EventQueue, event: Event) void {
        if (self.len >= CAPACITY) {
            if (!self.overflowed) {
                std.log.warn("EventQueue overflow: extra events dropped this frame", .{});
                self.overflowed = true;
            }
            return;
        }
        self.buf[self.len] = event;
        self.len += 1;
    }

    /// Returns the buffered events as a slice.  Valid until the next call to `clear`.
    /// No allocation.
    pub fn drain(self: *const EventQueue) []const Event {
        return self.buf[0..self.len];
    }

    /// Reset the queue after the frame loop has processed `drain()`.
    pub fn clear(self: *EventQueue) void {
        self.len = 0;
        self.overflowed = false;
    }

    /// Thunk used as PushEventFn — called by GLFW callbacks in module 01.
    /// `queue_ptr` is *anyopaque pointing to EventQueue.
    pub fn pushThunk(queue_ptr: *anyopaque, event: Event) void {
        const q: *EventQueue = @ptrCast(@alignCast(queue_ptr));
        q.push(event);
    }
};
