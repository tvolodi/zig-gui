//! R41 — Overlay / z-layer.
//!
//! OverlayLayer is an ordered list of named DrawCommand slices rendered after the main pass.
//! Callers own the command slices; OverlayLayer does NOT free them.

const std = @import("std");
const mod01 = @import("../01/types.zig");

pub const DrawCommand = mod01.DrawCommand;

/// Opaque identifier for one overlay slot.
pub const OverlayId = u16;

pub const OverlaySlot = struct {
    id: OverlayId,
    commands: []DrawCommand,
};

/// Ordered list of overlay slots. Slots are rendered in insertion order.
pub const OverlayLayer = struct {
    slots: std.ArrayListUnmanaged(OverlaySlot) = .empty,
    next_id: OverlayId = 0,
    gpa: std.mem.Allocator,

    pub fn init(gpa: std.mem.Allocator) OverlayLayer {
        return OverlayLayer{ .gpa = gpa };
    }

    pub fn deinit(self: *OverlayLayer) void {
        self.slots.deinit(self.gpa);
    }

    /// Allocate a new slot ID. Does not set any commands yet.
    pub fn allocId(self: *OverlayLayer) OverlayId {
        const id = self.next_id;
        self.next_id +%= 1;
        return id;
    }

    /// Write or replace the command slice for an existing slot.
    /// If no slot with `id` exists, appends a new entry.
    pub fn setSlot(self: *OverlayLayer, id: OverlayId, commands: []DrawCommand) void {
        for (self.slots.items) |*slot| {
            if (slot.id == id) {
                slot.commands = commands;
                return;
            }
        }
        self.slots.append(self.gpa, .{ .id = id, .commands = commands }) catch {};
    }

    /// Remove the slot entirely.
    pub fn removeSlot(self: *OverlayLayer, id: OverlayId) void {
        for (self.slots.items, 0..) |slot, i| {
            if (slot.id == id) {
                _ = self.slots.swapRemove(i);
                return;
            }
        }
    }

    /// Return a flat view of all slot command slices concatenated in order.
    pub fn flatten(self: *const OverlayLayer, alloc: std.mem.Allocator) error{OutOfMemory}![]DrawCommand {
        var total: usize = 0;
        for (self.slots.items) |slot| total += slot.commands.len;
        if (total == 0) return alloc.alloc(DrawCommand, 0);
        const out = try alloc.alloc(DrawCommand, total);
        var offset: usize = 0;
        for (self.slots.items) |slot| {
            @memcpy(out[offset .. offset + slot.commands.len], slot.commands);
            offset += slot.commands.len;
        }
        return out;
    }
};
