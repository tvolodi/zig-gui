//! 08 — Schema forms — types.zig
//!
//! Contract (INV-5.1). The Value/Schema/FieldSpec/ValidationError shapes and all public
//! signatures are the contract. `widgetForNode` and the `Value` tag helpers are implemented
//! here (mappings/definitions); `getPath`/`setPath`, `parseSchema`, `buildForm`, `validate`,
//! and the `Form` methods are the real work and are stubbed. Implement per spec.md.
//!
//! Imports std (incl. std.json) + modules 03/05/07 — all lower-numbered (INV-3.4).

const std = @import("std");
const store = @import("../03_element_store/types.zig");
const theme = @import("../05_theme/types.zig");
const comp = @import("../07_components/types.zig");

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
        _ = self;
        _ = path;
        @compileError("not implemented — implement per spec.md; do not change this signature");
    }

    /// Set the value at a dotted path, creating intermediate objects as needed.
    pub fn setPath(self: *Value, alloc: std.mem.Allocator, path: []const u8, v: Value) !void {
        _ = self;
        _ = alloc;
        _ = path;
        _ = v;
        @compileError("not implemented — implement per spec.md; do not change this signature");
    }
};

// ---------------------------------------------------------------------------
// Schema model (v1 keyword subset — see spec.md)
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
    title: ?[]const u8 = null, // → field label
    properties: []const Property = &.{}, // object
    required: []const []const u8 = &.{},
    items: ?*const Schema = null, // array
    enum_values: []const Value = &.{},
    min_length: ?u32 = null,
    max_length: ?u32 = null,
    minimum: ?f64 = null,
    maximum: ?f64 = null,
    widget_hint: ?[]const u8 = null, // x-widget

    pub fn hasEnum(self: Schema) bool {
        return self.enum_values.len > 0;
    }
};

pub const SchemaError = error{ InvalidJson, UnsupportedKeyword, OutOfMemory };

/// Parse a JSON Schema document into a Schema (via std.json). Only the v1 keyword subset is
/// recognized; unknown keywords are ignored (not an error).
pub fn parseSchema(alloc: std.mem.Allocator, json: []const u8) SchemaError!Schema {
    _ = alloc;
    _ = json;
    @compileError("not implemented — implement per spec.md; do not change this signature");
}

// ---------------------------------------------------------------------------
// Widget registry (schema node -> module 07 WidgetKind). Implemented (pure mapping).
// ---------------------------------------------------------------------------

pub fn widgetForNode(schema: Schema) WidgetKind {
    if (schema.hasEnum()) return .dropdown;
    return switch (schema.type) {
        .boolean => .dropdown, // no toggle in v1 (spec.md)
        .string, .integer, .number => .input,
        .object => .column,
        .array => .column,
    };
}

// ---------------------------------------------------------------------------
// Form model (walker output)
// ---------------------------------------------------------------------------

pub const FieldSpec = struct {
    path: []const u8, // dotted path into the Value tree
    label: []const u8, // from schema.title, else the property name
    kind: WidgetKind,
    format: Format = .none,
    required: bool = false,
};

/// Walk the schema into a flat list of leaf field specs (nesting → dotted paths).
pub fn buildForm(alloc: std.mem.Allocator, schema: Schema) ![]FieldSpec {
    _ = alloc;
    _ = schema;
    @compileError("not implemented — implement per spec.md; do not change this signature");
}

// ---------------------------------------------------------------------------
// Validator
// ---------------------------------------------------------------------------

pub const ValidationError = struct {
    path: []const u8,
    message: []const u8,
};

/// Validate `value` against `schema` (v1 keyword subset). Returns one error per violation;
/// empty slice means valid.
pub fn validate(alloc: std.mem.Allocator, schema: Schema, value: *Value) ![]ValidationError {
    _ = alloc;
    _ = schema;
    _ = value;
    @compileError("not implemented — implement per spec.md; do not change this signature");
}

// ---------------------------------------------------------------------------
// Form — ties the headless model to the Scene (module 07) via runtime path binding
// ---------------------------------------------------------------------------

pub const Form = struct {
    schema: Schema,
    model: []FieldSpec = &.{},
    values: Value = .null,
    // path -> input ElementId, filled by mount. Implementation-defined backing.
    _bindings: *anyopaque = undefined,
    gpa: std.mem.Allocator,

    pub fn init(alloc: std.mem.Allocator, schema: Schema) !Form {
        _ = alloc;
        _ = schema;
        @compileError("not implemented — implement per spec.md; do not change this signature");
    }

    pub fn deinit(self: *Form) void {
        _ = self;
        @compileError("not implemented — implement per spec.md; do not change this signature");
    }

    /// Build the form's elements into `scene` (no font); record each input's dotted path.
    /// Returns the form's root element id.
    pub fn mount(self: *Form, scene: *Scene, tokens: Tokens) !ElementId {
        _ = self;
        _ = scene;
        _ = tokens;
        @compileError("not implemented — implement per spec.md; do not change this signature");
    }

    pub fn getValue(self: *Form, path: []const u8) ?*Value {
        _ = self;
        _ = path;
        @compileError("not implemented — implement per spec.md; do not change this signature");
    }

    pub fn setValue(self: *Form, path: []const u8, v: Value) !void {
        _ = self;
        _ = path;
        _ = v;
        @compileError("not implemented — implement per spec.md; do not change this signature");
    }

    pub fn validate(self: *Form, alloc: std.mem.Allocator) ![]ValidationError {
        _ = self;
        _ = alloc;
        @compileError("not implemented — implement per spec.md; do not change this signature");
    }
};
