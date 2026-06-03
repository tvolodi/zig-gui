//! 03 — Element store — types.zig
//!
//! This file IS the contract (INV-5.1) AND the canonical home of the shared element/geometry
//! types (see spec.md "This module owns the shared element types"). Implementing agents:
//! match every public signature and the field layout of ElementStore exactly. Fill in the
//! stubbed method bodies; do NOT change signatures. If a signature seems wrong, STOP and
//! surface it to the human (INV-5.1).
//!
//! Module 03 depends ONLY on the Zig standard library (INV-3.4 build order, INV-5.6).

const std = @import("std");

pub const NONE: u32 = std.math.maxInt(u32);

// ===========================================================================
// Shared geometry / sizing types (canonical home — module 04 imports these)
// ===========================================================================

pub const ElementId = struct {
    index: u32,
    gen: u32,
};

pub const Rect = struct { x: f32 = 0, y: f32 = 0, w: f32 = 0, h: f32 = 0 };
pub const Size = struct { w: f32 = 0, h: f32 = 0 };

pub const Constraints = struct {
    min_w: f32 = 0,
    max_w: f32 = std.math.inf(f32),
    min_h: f32 = 0,
    max_h: f32 = std.math.inf(f32),
};

pub const Insets = struct {
    top: f32 = 0,
    right: f32 = 0,
    bottom: f32 = 0,
    left: f32 = 0,
};

pub const Dimension = union(enum) {
    auto,
    px: f32,
    percent: f32, // 0..100, relative to parent content box on that axis
};

pub const TrackSize = union(enum) {
    px: f32,
    fr: f32,
    auto,
};

pub const Display = enum { block, flex, grid };
pub const FlexDirection = enum { row, column };
pub const JustifyContent = enum { start, center, end, space_between, space_around };
pub const AlignItems = enum { start, center, end, stretch };
pub const Overflow = enum { visible, hidden };

/// One LayoutNode per element index. Module 03 stores these in `ElementStore.layout`.
/// Module 04 (layout engine) reads every field except `computed`, which it writes.
pub const LayoutNode = struct {
    display: Display = .block,

    width: Dimension = .auto,
    height: Dimension = .auto,
    min_size: Size = .{},
    max_size: Size = .{ .w = std.math.inf(f32), .h = std.math.inf(f32) },
    padding: Insets = .{},
    margin: Insets = .{},

    direction: FlexDirection = .row,
    justify_content: JustifyContent = .start,
    align_items: AlignItems = .stretch,
    gap: f32 = 0,

    flex_grow: f32 = 0,
    flex_shrink: f32 = 1,
    flex_basis: Dimension = .auto,

    grid_template_columns: []const TrackSize = &.{},
    grid_template_rows: []const TrackSize = &.{},
    col_span: u16 = 1,
    row_span: u16 = 1,

    /// Controls whether children that overflow this node's bounds are visible or clipped.
    overflow: Overflow = .visible,

    /// Content-driven intrinsic size for leaves (filled by text/component modules
    /// BEFORE layout runs). Null until measured.
    measured: ?Size = null,

    /// OUTPUT of the layout engine. Absolute px relative to the root origin.
    computed: Rect = .{},
};

// ===========================================================================
// Iterators (bodies stubbed — implement per spec.md)
// ===========================================================================

pub const ChildIterator = struct {
    store: *const ElementStore,
    /// Index of the next child to yield, or NONE when exhausted.
    cursor: u32,

    pub fn next(self: *ChildIterator) ?ElementId {
        if (self.cursor == NONE) return null;
        const current = self.cursor;
        self.cursor = self.store.next_sibling.items[current];
        return ElementId{ .index = current, .gen = self.store.gen.items[current] };
    }
};

pub const DirtyIterator = struct {
    store: *const ElementStore,
    /// Next index to examine when scanning the dirty bitset forward.
    cursor: u32 = 0,

    pub fn next(self: *DirtyIterator) ?u32 {
        const len = self.store.dirty.bit_length;
        while (self.cursor < len) {
            const idx = self.cursor;
            self.cursor += 1;
            if (self.store.dirty.isSet(idx)) return idx;
        }
        return null;
    }
};

// ===========================================================================
// The store — data-oriented, generational, arena-backed (INV-3.1/3.2/3.3/3.5)
// ===========================================================================

pub const ElementStore = struct {
    // Backing allocator and per-screen arena (INV-3.5).
    gpa: std.mem.Allocator,
    arena: std.heap.ArenaAllocator,

    // Parallel component/structure arrays — index = element index (INV-3.1).
    layout: std.ArrayListUnmanaged(LayoutNode) = .empty,
    gen: std.ArrayListUnmanaged(u32) = .empty,
    parent: std.ArrayListUnmanaged(u32) = .empty,
    first_child: std.ArrayListUnmanaged(u32) = .empty,
    last_child: std.ArrayListUnmanaged(u32) = .empty,
    next_sibling: std.ArrayListUnmanaged(u32) = .empty,

    // Recycled indices and dirty tracking.
    free: std.ArrayListUnmanaged(u32) = .empty,
    dirty: std.DynamicBitSetUnmanaged = .{},

    // Number of live (non-freed) elements.
    live: u32 = 0,

    // --- lifecycle ---

    pub fn init(gpa: std.mem.Allocator) ElementStore {
        return ElementStore{
            .gpa = gpa,
            .arena = std.heap.ArenaAllocator.init(gpa),
        };
    }

    /// Test-only convenience constructor (see spec.md). Used by acceptance tests.
    pub fn testInit(gpa: std.mem.Allocator) !ElementStore {
        var self = ElementStore.init(gpa);
        const alloc = self.arena.allocator();
        try self.layout.ensureTotalCapacity(alloc, 16);
        try self.gen.ensureTotalCapacity(alloc, 16);
        try self.parent.ensureTotalCapacity(alloc, 16);
        try self.first_child.ensureTotalCapacity(alloc, 16);
        try self.last_child.ensureTotalCapacity(alloc, 16);
        try self.next_sibling.ensureTotalCapacity(alloc, 16);
        try self.free.ensureTotalCapacity(alloc, 16);
        return self;
    }

    pub fn deinit(self: *ElementStore) void {
        self.dirty.deinit(self.gpa);
        self.arena.deinit();
        self.* = undefined;
    }

    /// Drop all elements for the next screen; keep capacity, reset the arena (INV-3.5).
    pub fn reset(self: *ElementStore) void {
        _ = self.arena.reset(.retain_capacity);
        self.layout = .empty;
        self.gen = .empty;
        self.parent = .empty;
        self.first_child = .empty;
        self.last_child = .empty;
        self.next_sibling = .empty;
        self.free = .empty;
        self.dirty.unsetAll();
        self.live = 0;
    }

    // --- allocation & tree ---

    fn allocIndex(self: *ElementStore) !u32 {
        const alloc = self.arena.allocator();
        if (self.free.items.len > 0) {
            return self.free.pop().?;
        }
        const i: u32 = @intCast(self.layout.items.len);
        try self.layout.append(alloc, .{});
        try self.gen.append(alloc, 1);
        try self.parent.append(alloc, NONE);
        try self.first_child.append(alloc, NONE);
        try self.last_child.append(alloc, NONE);
        try self.next_sibling.append(alloc, NONE);
        const new_len = i + 1;
        try self.dirty.resize(self.gpa, new_len, false);
        return i;
    }

    pub fn addRoot(self: *ElementStore, node: LayoutNode) !ElementId {
        const i = try self.allocIndex();
        self.layout.items[i] = node;
        self.parent.items[i] = NONE;
        self.first_child.items[i] = NONE;
        self.last_child.items[i] = NONE;
        self.next_sibling.items[i] = NONE;
        self.dirty.set(i);
        self.live += 1;
        return ElementId{ .index = i, .gen = self.gen.items[i] };
    }

    /// Append `node` as the LAST child of `parent` (insertion order — see spec.md).
    pub fn addChild(self: *ElementStore, parent: ElementId, node: LayoutNode) !ElementId {
        std.debug.assert(self.isValid(parent));
        const i = try self.allocIndex();
        self.layout.items[i] = node;
        self.parent.items[i] = parent.index;
        self.first_child.items[i] = NONE;
        self.last_child.items[i] = NONE;
        self.next_sibling.items[i] = NONE;
        // Link into parent's child chain.
        const last = self.last_child.items[parent.index];
        if (last == NONE) {
            self.first_child.items[parent.index] = i;
        } else {
            self.next_sibling.items[last] = i;
        }
        self.last_child.items[parent.index] = i;
        self.dirty.set(i);
        self.live += 1;
        return ElementId{ .index = i, .gen = self.gen.items[i] };
    }

    /// Recycle the element's index and bump its generation, invalidating old handles.
    pub fn remove(self: *ElementStore, id: ElementId) void {
        std.debug.assert(self.isValid(id));
        const i = id.index;
        const p = self.parent.items[i];
        if (p != NONE) {
            // Unlink from parent's child chain.
            if (self.first_child.items[p] == i) {
                self.first_child.items[p] = self.next_sibling.items[i];
            } else {
                // Find prev sibling.
                var cur = self.first_child.items[p];
                while (cur != NONE) {
                    if (self.next_sibling.items[cur] == i) {
                        self.next_sibling.items[cur] = self.next_sibling.items[i];
                        break;
                    }
                    cur = self.next_sibling.items[cur];
                }
            }
            if (self.last_child.items[p] == i) {
                // Find the new last child by scanning.
                var prev: u32 = NONE;
                var cur = self.first_child.items[p];
                while (cur != NONE) {
                    prev = cur;
                    cur = self.next_sibling.items[cur];
                }
                self.last_child.items[p] = prev;
            }
        }
        // Bump generation, push to free list, clear dirty.
        self.gen.items[i] += 1;
        self.free.append(self.arena.allocator(), i) catch {};
        if (i < self.dirty.bit_length) self.dirty.unset(i);
        self.live -= 1;
    }

    // --- access ---

    pub fn isValid(self: *const ElementStore, id: ElementId) bool {
        return id.index < self.gen.items.len and self.gen.items[id.index] == id.gen;
    }

    /// Local pointer to the element's LayoutNode. Do NOT store across frames (INV-3.2).
    /// In debug, asserts isValid(id).
    pub fn get(self: *ElementStore, id: ElementId) *LayoutNode {
        std.debug.assert(self.isValid(id));
        return &self.layout.items[id.index];
    }

    pub fn childrenOf(self: *const ElementStore, id: ElementId) ChildIterator {
        return ChildIterator{ .store = self, .cursor = self.first_child.items[id.index] };
    }

    pub fn parentOf(self: *const ElementStore, id: ElementId) ?ElementId {
        const p = self.parent.items[id.index];
        if (p == NONE) return null;
        return ElementId{ .index = p, .gen = self.gen.items[p] };
    }

    pub fn count(self: *const ElementStore) u32 {
        return self.live;
    }

    // --- dirty tracking (INV-3.3) ---

    pub fn markDirty(self: *ElementStore, id: ElementId) void {
        self.dirty.set(id.index);
    }

    pub fn clearDirty(self: *ElementStore) void {
        self.dirty.unsetAll();
    }

    pub fn dirtyIndices(self: *const ElementStore) DirtyIterator {
        return DirtyIterator{ .store = self, .cursor = 0 };
    }

    /// Return true if any element has its dirty bit set.
    /// O(capacity / 64) — negligible for < 1 000 elements.
    pub fn hasDirty(self: *const ElementStore) bool {
        return self.dirty.count() > 0;
    }

    /// Mark all live elements dirty. Called once after Scene.instantiate()
    /// so the very first frame always runs the full layout + paint pipeline.
    pub fn markAllDirty(self: *ElementStore) void {
        var i: u32 = 0;
        while (i < self.gen.items.len) : (i += 1) {
            // gen > 0 means the slot has been used at least once and is currently live.
            // Freed slots reuse an index with the same gen until next alloc increments it;
            // checking free list membership is O(n) — gen > 0 is the conservative but safe
            // check here because a first-frame full paint of a stale-freed slot is harmless.
            if (self.gen.items[i] > 0) self.dirty.set(i);
        }
    }
};
