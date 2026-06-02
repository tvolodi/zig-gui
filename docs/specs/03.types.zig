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
        _ = self;
        @compileError("not implemented — implement per spec.md; do not change this signature");
    }
};

pub const DirtyIterator = struct {
    store: *const ElementStore,
    /// Next index to examine when scanning the dirty bitset forward.
    cursor: u32 = 0,

    pub fn next(self: *DirtyIterator) ?u32 {
        _ = self;
        @compileError("not implemented — implement per spec.md; do not change this signature");
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
    layout: std.ArrayListUnmanaged(LayoutNode) = .{},
    gen: std.ArrayListUnmanaged(u32) = .{},
    parent: std.ArrayListUnmanaged(u32) = .{},
    first_child: std.ArrayListUnmanaged(u32) = .{},
    last_child: std.ArrayListUnmanaged(u32) = .{},
    next_sibling: std.ArrayListUnmanaged(u32) = .{},

    // Recycled indices and dirty tracking.
    free: std.ArrayListUnmanaged(u32) = .{},
    dirty: std.DynamicBitSetUnmanaged = .{},

    // Number of live (non-freed) elements.
    live: u32 = 0,

    // --- lifecycle ---

    pub fn init(gpa: std.mem.Allocator) ElementStore {
        _ = gpa;
        @compileError("not implemented — implement per spec.md; do not change this signature");
    }

    /// Test-only convenience constructor (see spec.md). Used by acceptance tests.
    pub fn testInit(gpa: std.mem.Allocator) !ElementStore {
        _ = gpa;
        @compileError("not implemented — implement per spec.md; do not change this signature");
    }

    pub fn deinit(self: *ElementStore) void {
        _ = self;
        @compileError("not implemented — implement per spec.md; do not change this signature");
    }

    /// Drop all elements for the next screen; keep capacity, reset the arena (INV-3.5).
    pub fn reset(self: *ElementStore) void {
        _ = self;
        @compileError("not implemented — implement per spec.md; do not change this signature");
    }

    // --- allocation & tree ---

    pub fn addRoot(self: *ElementStore, node: LayoutNode) !ElementId {
        _ = self;
        _ = node;
        @compileError("not implemented — implement per spec.md; do not change this signature");
    }

    /// Append `node` as the LAST child of `parent` (insertion order — see spec.md).
    pub fn addChild(self: *ElementStore, parent: ElementId, node: LayoutNode) !ElementId {
        _ = self;
        _ = parent;
        _ = node;
        @compileError("not implemented — implement per spec.md; do not change this signature");
    }

    /// Recycle the element's index and bump its generation, invalidating old handles.
    pub fn remove(self: *ElementStore, id: ElementId) void {
        _ = self;
        _ = id;
        @compileError("not implemented — implement per spec.md; do not change this signature");
    }

    // --- access ---

    pub fn isValid(self: *const ElementStore, id: ElementId) bool {
        _ = self;
        _ = id;
        @compileError("not implemented — implement per spec.md; do not change this signature");
    }

    /// Local pointer to the element's LayoutNode. Do NOT store across frames (INV-3.2).
    /// In debug, asserts isValid(id).
    pub fn get(self: *ElementStore, id: ElementId) *LayoutNode {
        _ = self;
        _ = id;
        @compileError("not implemented — implement per spec.md; do not change this signature");
    }

    pub fn childrenOf(self: *const ElementStore, id: ElementId) ChildIterator {
        _ = self;
        _ = id;
        @compileError("not implemented — implement per spec.md; do not change this signature");
    }

    pub fn parentOf(self: *const ElementStore, id: ElementId) ?ElementId {
        _ = self;
        _ = id;
        @compileError("not implemented — implement per spec.md; do not change this signature");
    }

    pub fn count(self: *const ElementStore) u32 {
        _ = self;
        @compileError("not implemented — implement per spec.md; do not change this signature");
    }

    // --- dirty tracking (INV-3.3) ---

    pub fn markDirty(self: *ElementStore, id: ElementId) void {
        _ = self;
        _ = id;
        @compileError("not implemented — implement per spec.md; do not change this signature");
    }

    pub fn clearDirty(self: *ElementStore) void {
        _ = self;
        @compileError("not implemented — implement per spec.md; do not change this signature");
    }

    pub fn dirtyIndices(self: *const ElementStore) DirtyIterator {
        _ = self;
        @compileError("not implemented — implement per spec.md; do not change this signature");
    }
};
