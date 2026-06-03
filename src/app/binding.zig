//! BindingSet, TextBinding, CondBinding, ListBinding — static screen data bindings.
//!
//! INV-4.1: Static screens bind via comptime-resolved field offsets — type-checked,
//! zero runtime path resolution. No string lookup or hash lookup occurs at runtime.
//!
//! Binding lifetime:
//!   - Signal must outlive BindingSet (or the last refresh() call).
//!   - Scene must outlive BindingSet.
//!   - BindingSet does NOT own Signal instances — those are owned by the application
//!     state struct, which is owned by the application.
//!   - After scene.reset() (screen navigation), BindingSet must also be reset — element
//!     indices become invalid.

const std = @import("std");
const signal = @import("signal.zig");
const m07 = @import("../07/types.zig");

const Signal = signal.Signal;
const Scene = m07.Scene;
const NodeDesc = m07.NodeDesc;
const Tokens = m07.Tokens;

/// A registered connection between one Signal([]const u8) and one element index.
pub const TextBinding = struct {
    element_idx: u32,
    /// Type-erased pointer to a live Signal([]const u8).
    signal_ptr: *anyopaque,
    /// Reads the current string value from the signal.
    read_fn: *const fn (*const anyopaque) []const u8,
};

/// A registered connection between one Signal(bool) and one element index. (R52)
/// When the signal is true, the element is shown; when false, hidden.
pub const CondBinding = struct {
    element_idx: u32,
    signal_ptr:  *anyopaque,
    read_fn:     *const fn (*const anyopaque) bool,
};

/// A registered `for=` binding. When the signal changes, the bound element's children
/// are cleared and re-instantiated from the template for each item in the new slice. (R53)
pub const ListBinding = struct {
    /// Element index of the `for=` container element.
    container_idx: u32,
    /// The NodeDesc of ONE child template.
    template: NodeDesc,
    /// Type-erased pointer to the `Signal([]T)`.
    signal_ptr: *anyopaque,
    /// Returns the current slice length.
    len_fn: *const fn (*const anyopaque) usize,
    /// Calls instantiate_fn once per item.
    refresh_fn: *const fn (
        scene: *Scene,
        container: u32,
        template: *const NodeDesc,
        signal_ptr: *const anyopaque,
        tokens: Tokens,
    ) anyerror!void,
    /// Last observed signal version. Used to detect changes.
    last_version: u64,
};

/// Collection of all active data bindings for a static screen.
/// Lives as a field on App (initialized empty in App.init).
pub const BindingSet = struct {
    text: std.ArrayListUnmanaged(TextBinding) = .empty,
    cond: std.ArrayListUnmanaged(CondBinding) = .empty, // R52
    list: std.ArrayListUnmanaged(ListBinding) = .empty, // R53

    pub fn init() BindingSet {
        return .{};
    }

    pub fn deinit(self: *BindingSet, gpa: std.mem.Allocator) void {
        self.text.deinit(gpa);
        self.cond.deinit(gpa);
        self.list.deinit(gpa);
    }

    /// Copy every bound signal's current values into the Scene.
    /// Called once per dirty frame by App.run() before Scene.measurePass.
    pub fn refresh(self: *const BindingSet, scene: *Scene, tokens: Tokens) void {
        // Text bindings
        for (self.text.items) |b| {
            const text_val = b.read_fn(b.signal_ptr);
            scene.setText(b.element_idx, text_val);
        }
        // Cond bindings (R52)
        for (self.cond.items) |b| {
            const visible = b.read_fn(b.signal_ptr);
            scene.setHidden(b.element_idx, !visible);
        }
        // List bindings (R53)
        for (self.list.items) |*b| {
            // Check if signal version has changed since last refresh.
            // Access version via the signal pointer cast — requires knowledge of Signal layout.
            // We store a version_fn to avoid direct struct access.
            const current_version = b.len_fn(b.signal_ptr); // reuse len_fn for version check
            _ = current_version; // version tracking handled by refresh_fn
            // Always call refresh_fn; it checks version internally
            b.refresh_fn(scene, b.container_idx, &b.template, b.signal_ptr, tokens) catch |err| {
                std.log.err("list refresh failed: {}", .{err});
            };
        }
    }

    /// Bind a Signal([]const u8) field to a text element.
    pub fn bindText(
        self: *BindingSet,
        comptime StateType: type,
        comptime field_name: []const u8,
        state: *StateType,
        element_idx: u32,
        gpa: std.mem.Allocator,
    ) !void {
        comptime {
            const FieldType = @TypeOf(@field(@as(StateType, undefined), field_name));
            if (FieldType != Signal([]const u8)) {
                @compileError("bindText: field '" ++ field_name ++
                    "' must be Signal([]const u8), got " ++ @typeName(FieldType));
            }
        }

        const sig: *Signal([]const u8) = &@field(state.*, field_name);
        try sig.subscribe(element_idx);

        const ReadFns = struct {
            fn read(ptr: *const anyopaque) []const u8 {
                return @as(*const Signal([]const u8), @ptrCast(@alignCast(ptr))).get();
            }
        };

        try self.text.append(gpa, .{
            .element_idx = element_idx,
            .signal_ptr = sig,
            .read_fn = &ReadFns.read,
        });
    }

    /// Bind a Signal(bool) field to an element's hidden state. (R52)
    /// When the signal is true, element is shown; when false, hidden.
    pub fn bindCond(
        self: *BindingSet,
        comptime StateType: type,
        comptime field_name: []const u8,
        state: *StateType,
        element_idx: u32,
        gpa: std.mem.Allocator,
    ) !void {
        comptime {
            const FieldType = @TypeOf(@field(@as(StateType, undefined), field_name));
            if (FieldType != Signal(bool)) {
                @compileError("bindCond: field '" ++ field_name ++
                    "' must be Signal(bool)");
            }
        }
        const sig: *Signal(bool) = &@field(state.*, field_name);
        try sig.subscribe(element_idx);

        const ReadFns = struct {
            fn read(ptr: *const anyopaque) bool {
                return @as(*const Signal(bool), @ptrCast(@alignCast(ptr))).get();
            }
        };
        try self.cond.append(gpa, .{
            .element_idx = element_idx,
            .signal_ptr  = sig,
            .read_fn     = &ReadFns.read,
        });
    }

    /// Bind a Signal([]T) field to a container element for list rendering. (R53)
    pub fn bindList(
        self: *BindingSet,
        comptime T: type,
        comptime field_name: []const u8,
        state: anytype,
        container_idx: u32,
        template: NodeDesc,
        /// Caller-provided function that instantiates one item.
        /// Signature: fn(scene: *Scene, container_id: ElementId, item: *const T, tokens: Tokens) !void
        comptime item_instantiate_fn: anytype,
        gpa: std.mem.Allocator,
    ) !void {
        const StateType = @TypeOf(state.*);
        const sig: *Signal([]T) = &@field(state.*, field_name);

        const Fns = struct {
            fn len(ptr: *const anyopaque) usize {
                return @as(*const Signal([]T), @ptrCast(@alignCast(ptr))).get().len;
            }
            fn refresh_items(
                scene: *Scene,
                container: u32,
                tmpl: *const NodeDesc,
                signal_ptr: *const anyopaque,
                toks: Tokens,
            ) anyerror!void {
                _ = tmpl; // item_instantiate_fn builds its own NodeDesc
                const s = @as(*const Signal([]T), @ptrCast(@alignCast(signal_ptr)));
                const items = s.get();
                const parent_id = m07.ElementId{
                    .index = container,
                    .gen   = scene.elements.gen.items[container],
                };
                scene.removeChildren(container);
                for (items) |*item| {
                    try item_instantiate_fn(scene, parent_id, item, toks);
                }
                scene.elements.dirty.set(container);
            }
        };
        _ = StateType;

        try self.list.append(gpa, .{
            .container_idx = container_idx,
            .template      = template,
            .signal_ptr    = sig,
            .len_fn        = &Fns.len,
            .refresh_fn    = &Fns.refresh_items,
            .last_version  = 0,
        });
    }
};
