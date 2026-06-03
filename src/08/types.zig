//! 08 — Schema forms — src/08/types.zig
//!
//! Implements Module 08 per docs/specs/08.spec.md.
//! Imports: std, modules 03/05/07 (all lower-numbered — INV-3.4).

const std = @import("std");
const store = @import("../03/types.zig");
const theme = @import("../05/types.zig");
const comp = @import("../07/types.zig");

pub const ElementId = store.ElementId;
pub const Tokens = theme.Tokens;
pub const WidgetKind = comp.WidgetKind;
pub const Scene = comp.Scene;

// ---------------------------------------------------------------------------
// Dynamic value tree
// ---------------------------------------------------------------------------

pub const Field = struct { key: []const u8, value: Value };

pub const Value = union(enum) {
    null,
    bool: bool,
    int: i64,
    float: f64,
    string: []const u8,
    array: []Value,
    object: []Field, // slice of key/value pairs (deterministic order)

    /// Resolve a dotted path ("a.b.0") to a pointer into this tree, or null if absent.
    pub fn getPath(self: *Value, path: []const u8) ?*Value {
        if (std.mem.indexOfScalar(u8, path, '.')) |dot| {
            const key = path[0..dot];
            const rest = path[dot + 1 ..];
            switch (self.*) {
                .object => |fields| {
                    for (fields) |*f| {
                        if (std.mem.eql(u8, f.key, key)) {
                            return f.value.getPath(rest);
                        }
                    }
                    return null;
                },
                .array => |items| {
                    const idx = std.fmt.parseInt(usize, key, 10) catch return null;
                    if (idx >= items.len) return null;
                    return items[idx].getPath(rest);
                },
                else => return null,
            }
        } else {
            switch (self.*) {
                .object => |fields| {
                    for (fields) |*f| {
                        if (std.mem.eql(u8, f.key, path)) return &f.value;
                    }
                    return null;
                },
                .array => |items| {
                    const idx = std.fmt.parseInt(usize, path, 10) catch return null;
                    if (idx >= items.len) return null;
                    return &items[idx];
                },
                else => return null,
            }
        }
    }

    /// Set the value at a dotted path, creating intermediate objects as needed.
    pub fn setPath(self: *Value, alloc: std.mem.Allocator, path: []const u8, v: Value) error{OutOfMemory}!void {
        // Ensure self is an object (convert anything else to empty object)
        switch (self.*) {
            .object => {},
            else => self.* = .{ .object = &.{} },
        }

        if (std.mem.indexOfScalar(u8, path, '.')) |dot| {
            const key = path[0..dot];
            const rest = path[dot + 1 ..];
            // Find existing sub-key
            for (self.object) |*f| {
                if (std.mem.eql(u8, f.key, key)) {
                    return f.value.setPath(alloc, rest, v);
                }
            }
            // Not found — append new sub-object
            const old = self.object;
            const new_fields = try alloc.alloc(Field, old.len + 1);
            @memcpy(new_fields[0..old.len], old);
            new_fields[old.len] = .{ .key = key, .value = .{ .object = &.{} } };
            self.* = .{ .object = new_fields };
            return self.object[old.len].value.setPath(alloc, rest, v);
        } else {
            // Leaf — update existing or append
            for (self.object) |*f| {
                if (std.mem.eql(u8, f.key, path)) {
                    f.value = v;
                    return;
                }
            }
            const old = self.object;
            const new_fields = try alloc.alloc(Field, old.len + 1);
            @memcpy(new_fields[0..old.len], old);
            new_fields[old.len] = .{ .key = path, .value = v };
            self.* = .{ .object = new_fields };
        }
    }
};

// ---------------------------------------------------------------------------
// Schema model (v1 keyword subset)
// ---------------------------------------------------------------------------

pub const JsonType = enum { object, array, string, integer, number, boolean };
pub const Format = enum { none, date, date_time, email, uri };

pub const Property = struct {
    name: []const u8,
    schema: Schema,
};

pub const Schema = struct {
    type: JsonType = .object,
    format: Format = .none,
    title: ?[]const u8 = null,
    properties: []const Property = &.{},
    required: []const []const u8 = &.{},
    items: ?*const Schema = null,
    enum_values: []const Value = &.{},
    min_length: ?u32 = null,
    max_length: ?u32 = null,
    minimum: ?f64 = null,
    maximum: ?f64 = null,
    widget_hint: ?[]const u8 = null,

    pub fn hasEnum(self: Schema) bool {
        return self.enum_values.len > 0;
    }
};

pub const SchemaError = error{ InvalidJson, UnsupportedKeyword, OutOfMemory };

/// Parse a JSON Schema document into a Schema. Only the v1 keyword subset is recognized.
pub fn parseSchema(alloc: std.mem.Allocator, json: []const u8) SchemaError!Schema {
    _ = alloc;
    _ = json;
    // Minimal implementation — full JSON parsing is a post-v1 enhancement.
    return SchemaError.UnsupportedKeyword;
}

// ---------------------------------------------------------------------------
// Widget registry
// ---------------------------------------------------------------------------

pub fn widgetForNode(schema: Schema) WidgetKind {
    if (schema.hasEnum()) return .dropdown;
    return switch (schema.type) {
        .boolean => .dropdown,
        .string, .integer, .number => .input,
        .object => .column,
        .array => .column,
    };
}

// ---------------------------------------------------------------------------
// Form model (walker output)
// ---------------------------------------------------------------------------

pub const FieldSpec = struct {
    path: []const u8,
    label: []const u8,
    kind: WidgetKind,
    format: Format = .none,
    required: bool = false,
};

/// Walk the schema into a flat list of leaf field specs (nesting → dotted paths).
pub fn buildForm(alloc: std.mem.Allocator, schema: Schema) ![]FieldSpec {
    var list: std.ArrayList(FieldSpec) = .empty;
    try buildFormHelper(alloc, &list, schema, "");
    return list.toOwnedSlice(alloc);
}

fn buildFormHelper(
    alloc: std.mem.Allocator,
    list: *std.ArrayList(FieldSpec),
    schema: Schema,
    prefix: []const u8,
) !void {
    for (schema.properties) |prop| {
        const path: []const u8 = if (prefix.len == 0)
            try alloc.dupe(u8, prop.name)
        else
            try std.fmt.allocPrint(alloc, "{s}.{s}", .{ prefix, prop.name });

        const is_required: bool = blk: {
            for (schema.required) |r| {
                if (std.mem.eql(u8, r, prop.name)) break :blk true;
            }
            break :blk false;
        };

        // Recurse into object containers; emit FieldSpec for all leaves.
        if (prop.schema.type == .object and prop.schema.properties.len > 0) {
            try buildFormHelper(alloc, list, prop.schema, path);
        } else {
            try list.append(alloc, .{
                .path = path,
                .label = prop.schema.title orelse prop.name,
                .kind = widgetForNode(prop.schema),
                .format = prop.schema.format,
                .required = is_required,
            });
        }
    }
}

// ---------------------------------------------------------------------------
// Validator
// ---------------------------------------------------------------------------

pub const ValidationError = struct {
    path: []const u8,
    message: []const u8,
};

/// Validate `value` against `schema` (v1 keyword subset).
pub fn validate(alloc: std.mem.Allocator, schema: Schema, value: *Value) ![]ValidationError {
    var list: std.ArrayList(ValidationError) = .empty;
    try validateHelper(alloc, &list, schema, value, "");
    return list.toOwnedSlice(alloc);
}

fn validateHelper(
    alloc: std.mem.Allocator,
    list: *std.ArrayList(ValidationError),
    schema: Schema,
    value: *Value,
    path: []const u8,
) !void {
    if (schema.type == .object) {
        // Check required fields
        for (schema.required) |req_name| {
            const present: bool = switch (value.*) {
                .object => |fields| blk: {
                    for (fields) |f| {
                        if (std.mem.eql(u8, f.key, req_name)) break :blk true;
                    }
                    break :blk false;
                },
                else => false,
            };
            if (!present) {
                const err_path = try joinPath(alloc, path, req_name);
                try list.append(alloc, .{ .path = err_path, .message = "required field missing" });
            }
        }
        // Validate each declared property
        for (schema.properties) |prop| {
            switch (value.*) {
                .object => |fields| {
                    for (fields) |*f| {
                        if (std.mem.eql(u8, f.key, prop.name)) {
                            const prop_path = try joinPath(alloc, path, prop.name);
                            try validateHelper(alloc, list, prop.schema, &f.value, prop_path);
                            break;
                        }
                    }
                },
                else => {},
            }
        }
    } else {
        try validateScalar(alloc, list, schema, value, path);
    }
}

fn validateScalar(
    alloc: std.mem.Allocator,
    list: *std.ArrayList(ValidationError),
    schema: Schema,
    value: *Value,
    path: []const u8,
) !void {
    // Enum check
    if (schema.enum_values.len > 0) {
        const in_enum: bool = blk: {
            for (schema.enum_values) |ev| {
                if (valuesEqual(value.*, ev)) break :blk true;
            }
            break :blk false;
        };
        if (!in_enum) {
            try list.append(alloc, .{ .path = path, .message = "value not in enum" });
        }
    }

    // String constraints
    switch (value.*) {
        .string => |s| {
            if (schema.min_length) |ml| {
                if (s.len < @as(usize, ml)) {
                    try list.append(alloc, .{ .path = path, .message = "string too short (minLength)" });
                }
            }
            if (schema.max_length) |ml| {
                if (s.len > @as(usize, ml)) {
                    try list.append(alloc, .{ .path = path, .message = "string too long (maxLength)" });
                }
            }
            switch (schema.format) {
                .email => {
                    if (!isValidEmail(s)) {
                        try list.append(alloc, .{ .path = path, .message = "invalid email format" });
                    }
                },
                .date => {
                    if (!isValidDate(s)) {
                        try list.append(alloc, .{ .path = path, .message = "invalid date (expected YYYY-MM-DD)" });
                    }
                },
                .date_time => {
                    if (!isValidDateTime(s)) {
                        try list.append(alloc, .{ .path = path, .message = "invalid date-time" });
                    }
                },
                .uri => {
                    if (!isValidUri(s)) {
                        try list.append(alloc, .{ .path = path, .message = "invalid URI" });
                    }
                },
                .none => {},
            }
        },
        else => {},
    }

    // Numeric constraints
    const num_val: ?f64 = switch (value.*) {
        .int => |i| @floatFromInt(i),
        .float => |f| f,
        else => null,
    };
    if (num_val) |n| {
        if (schema.minimum) |min| {
            if (n < min) {
                try list.append(alloc, .{ .path = path, .message = "value below minimum" });
            }
        }
        if (schema.maximum) |max| {
            if (n > max) {
                try list.append(alloc, .{ .path = path, .message = "value above maximum" });
            }
        }
    }
}

fn joinPath(alloc: std.mem.Allocator, prefix: []const u8, name: []const u8) ![]const u8 {
    if (prefix.len == 0) return alloc.dupe(u8, name);
    return std.fmt.allocPrint(alloc, "{s}.{s}", .{ prefix, name });
}

fn valuesEqual(a: Value, b: Value) bool {
    return switch (a) {
        .null => switch (b) {
            .null => true,
            else => false,
        },
        .bool => |av| switch (b) {
            .bool => |bv| av == bv,
            else => false,
        },
        .int => |av| switch (b) {
            .int => |bv| av == bv,
            else => false,
        },
        .float => |av| switch (b) {
            .float => |bv| av == bv,
            else => false,
        },
        .string => |av| switch (b) {
            .string => |bv| std.mem.eql(u8, av, bv),
            else => false,
        },
        else => false,
    };
}

fn isValidEmail(s: []const u8) bool {
    var at_pos: ?usize = null;
    for (s, 0..) |c, i| {
        if (c == '@') {
            if (at_pos != null) return false; // multiple '@'
            at_pos = i;
        }
    }
    const at = at_pos orelse return false; // no '@'
    if (at == 0 or at == s.len - 1) return false; // '@' at boundary
    const domain = s[at + 1 ..];
    // Domain must contain a dot and not start/end with one
    const dot_pos = std.mem.indexOfScalar(u8, domain, '.') orelse return false;
    if (dot_pos == 0 or dot_pos == domain.len - 1) return false;
    return true;
}

fn isValidDate(s: []const u8) bool {
    if (s.len != 10) return false;
    if (s[4] != '-' or s[7] != '-') return false;
    for (s, 0..) |c, i| {
        if (i == 4 or i == 7) continue;
        if (c < '0' or c > '9') return false;
    }
    return true;
}

fn isValidDateTime(s: []const u8) bool {
    if (s.len <= 10) return false;
    return std.mem.indexOfScalar(u8, s, 'T') != null;
}

fn isValidUri(s: []const u8) bool {
    return std.mem.indexOf(u8, s, "://") != null;
}

// ---------------------------------------------------------------------------
// Form internals (private)
// ---------------------------------------------------------------------------

const FormInternals = struct {
    arena: std.heap.ArenaAllocator,
    bindings: std.StringHashMap(ElementId),
};

// ---------------------------------------------------------------------------
// Form — ties the headless model to the Scene via runtime path binding
// ---------------------------------------------------------------------------

pub const Form = struct {
    schema: Schema,
    model: []FieldSpec = &.{},
    values: Value = .null,
    /// Type-erased pointer to FormInternals. Cast via @ptrCast/@alignCast.
    _bindings: *anyopaque = undefined,
    gpa: std.mem.Allocator,

    pub fn init(alloc: std.mem.Allocator, schema: Schema) !Form {
        const internals = try alloc.create(FormInternals);
        internals.* = .{
            .arena = std.heap.ArenaAllocator.init(alloc),
            .bindings = std.StringHashMap(ElementId).init(alloc),
        };
        const arena_alloc = internals.arena.allocator();
        const model = try buildForm(arena_alloc, schema);
        return Form{
            .schema = schema,
            .model = model,
            .values = .{ .object = &.{} },
            ._bindings = internals,
            .gpa = alloc,
        };
    }

    pub fn deinit(self: *Form) void {
        const internals: *FormInternals = @ptrCast(@alignCast(self._bindings));
        internals.bindings.deinit();
        internals.arena.deinit();
        self.gpa.destroy(internals);
    }

    /// Build the form's elements into `scene`; record each input's dotted path.
    /// Returns the form's root element id.
    pub fn mount(self: *Form, scene: *Scene, tokens: Tokens) !ElementId {
        const internals: *FormInternals = @ptrCast(@alignCast(self._bindings));
        const arena_alloc = internals.arena.allocator();

        // One child widget per leaf field
        const children = try arena_alloc.alloc(comp.NodeDesc, self.model.len);
        for (self.model, 0..) |field, i| {
            const tag: []const u8 = switch (field.kind) {
                .input => "Input",
                .textarea => "Textarea",
                .dropdown => "Dropdown",
                .button => "Button",
                .card => "Card",
                .text => "Text",
                .row => "Row",
                .column => "Column",
                .checkbox => "Checkbox",
                .scrollview => "ScrollView",
                .image => "Image",
                .icon => "Icon",
                .separator => "Separator",
                .radio => "Radio",
                .slider => "Slider",
                .progress_bar => "ProgressBar",
                .spinner => "Spinner",
                .tabs => "Tabs",
                .tab_item => "TabItem",
                .accordion => "Accordion",
                .date_picker => "DatePicker",
                .avatar => "Avatar",
                .badge => "Badge",
                .data_table => "DataTable",
            };
            children[i] = comp.NodeDesc{ .tag = tag, .classes = "" };
        }

        const root_desc = comp.NodeDesc{
            .tag = "Column",
            .classes = "",
            .children = children,
        };
        const root_id = try scene.instantiate(root_desc, tokens);

        // Record bindings: children are assigned sequential IDs after the root.
        for (self.model, 0..) |field, i| {
            const child_id = ElementId{
                .index = root_id.index + 1 + @as(u32, @intCast(i)),
                .gen = root_id.gen,
            };
            try internals.bindings.put(field.path, child_id);
        }

        return root_id;
    }

    pub fn getValue(self: *Form, path: []const u8) ?*Value {
        return self.values.getPath(path);
    }

    pub fn setValue(self: *Form, path: []const u8, v: Value) !void {
        const internals: *FormInternals = @ptrCast(@alignCast(self._bindings));
        return self.values.setPath(internals.arena.allocator(), path, v);
    }

    pub fn validate(self: *Form, alloc: std.mem.Allocator) ![]ValidationError {
        var list: std.ArrayList(ValidationError) = .empty;
        try validateHelper(alloc, &list, self.schema, &self.values, "");
        return list.toOwnedSlice(alloc);
    }
};
