# RH2 — M18-02: `$ref` URI resolution within schema document

> Roadmap item: M18-02  
> Depends on: M8 (module 08 schema forms complete)  
> Read `00_constitution.md` before this file.

## Purpose

Enable JSON Schema `$ref` keyword to resolve schema references within the same document. A field with `$ref: "#/definitions/Address"` reuses a schema fragment defined elsewhere in the document, avoiding duplication in complex forms.

Example:

```json
{
  "type": "object",
  "properties": {
    "shipping_address": { "$ref": "#/definitions/Address" },
    "billing_address": { "$ref": "#/definitions/Address" }
  },
  "definitions": {
    "Address": {
      "type": "object",
      "properties": {
        "street": { "type": "string" },
        "city": { "type": "string" },
        "zip": { "type": "string" }
      },
      "required": ["street", "city"]
    }
  }
}
```

## What to build

### 1. Ref resolver module — `src/08/ref_resolver.zig`

A pure resolver that dereferences `$ref` URIs:

```zig
/// Navigate a JSON pointer path (#/definitions/Address → ["definitions", "Address"])
/// and return a reference to the target schema.
pub fn resolveRef(root: *const Schema, ref_uri: []const u8) !?*const Schema

/// Example: resolveRef(schema, "#/definitions/Address") 
/// → pointer to schema.definitions["Address"]
/// Returns null if path does not exist.
```

**Design:**
- Support JSON Pointer syntax per RFC 6901: `#/<key>/<key>/<key>…`
- Unescape special characters: `~0` → `~`, `~1` → `/`
- No network refs (no `http://` or `file://` schemes) — this is deferred
- Walk the schema tree by following property keys in order
- No cyclic-ref detection (assume input is well-formed; post-v1 to add safeguards)

**Limitations:**
- No external refs (URIs outside the current document)
- No scheme variations (`file://`, `http://`)
- No anchor refs (`#anchor` without leading `/`)
- Cyclic refs are not detected (will infinite-loop if present)

### 2. Schema parser extension — `src/08/types.zig`

Add `$ref` support to the schema type:

```zig
pub const Schema = struct {
    // ... existing fields ...
    ref: ?[]const u8 = null,  // NEW: reference to a schema fragment, e.g. "#/definitions/Address"
    definitions: ?std.StringHashMap(*Schema) = null,  // NEW: named schema fragments
};
```

Also update `parseSchema` to populate `ref` and `definitions`:

```zig
pub fn parseSchema(alloc: Allocator, json_text: []const u8) !Schema {
    // ... existing parsing ...
    
    // NEW: After parsing, resolve $ref pointers
    // If a property contains "$ref", extract it and set schema.ref
    // If the root has a "definitions" object, index it for quick lookup
    
    // Then recursively dereference all $ref encountered during field building
}
```

### 3. Form builder extension — `src/08/types.zig`

Update `buildForm` to dereference `$ref` when encountered:

```zig
pub fn buildForm(alloc: Allocator, root_schema: *const Schema) ![]FieldSpec {
    // ... existing logic ...
    
    // When a schema has $ref:
    if (schema.ref) |ref_uri| {
        const resolved = try resolveRef(root_schema, ref_uri);
        if (resolved) |target| {
            // Recurse with the target schema instead
            return buildForm(alloc, target);  // Or inline the target's fields
        } else {
            // Broken reference — emit a validation error or skip
            // For v1: skip and emit a warning comment
        }
    }
    
    // ... normal field building ...
}
```

### 4. Validator extension — `src/08/validator.zig`

Update `validate` to dereference `$ref`:

```zig
pub fn validate(alloc: Allocator, schema: *const Schema, value: *const Value) ![]ValidationError {
    var current_schema = schema;
    
    // Dereference $ref if present
    if (current_schema.ref) |ref_uri| {
        if (resolveRef(schema, ref_uri)) |resolved| {
            current_schema = resolved;
        } else {
            // Broken ref: emit error or warn
            // For v1: treat as a no-op reference (pass validation)
        }
    }
    
    // ... normal validation using dereferenced schema ...
}
```

### 5. Tests

**Unit tests** — `src/08/ref_resolver_test.zig`:
- Resolve `#/definitions/Address` from a schema with a `definitions` key
- Resolve nested paths: `#/definitions/Person/properties/address`
- Unescape special characters: `#/x~0y` (key = "x~y"), `#/a~1b` (key = "a/b")
- Missing path: `#/undefined/path` returns null (no error)
- Invalid syntax: `#notapointer` (doesn't start with `#/`) returns error or null

**Integration tests** — `src/08/08_test.zig`:
- Schema with a `definitions.Address` and two properties referencing it
- `buildForm` produces one `FieldSpec` per address field (not duplicated)
- `validate` accepts valid address data for both fields
- Rejects invalid address data with appropriate error messages

## Non-goals (DO NOT implement — INV-5.4)

- **No external refs** — URLs and file paths outside the document (`http://`, `file://`) are post-v1
- **No anchor refs** — plain `#anchor` syntax without JSON Pointer (post-v1)
- **No cyclic-ref detection** — assume well-formed input; detecting cycles is deferred
- **No ref coalescing** — each $ref is resolved independently; no caching or memoization in v1
- **No schema composition** — `allOf`, `anyOf`, `oneOf` are separate from $ref (see RH3)
- **No `$id` / `$schema` fields** — metadata for external ref resolution, deferred

## Acceptance criteria

1. **Ref resolver tests pass:**
   - `zig test src/08/ref_resolver_test.zig` runs without error
   - All path navigation, unescaping, and error cases handled correctly

2. **Schema parser and types:**
   - `zig build test-08` passes
   - Schema with `definitions` parses correctly
   - Fields with `$ref` are recognized and marked (no parse error)

3. **Form builder:**
   - `buildForm` on a schema with referenced definitions produces fields from the target schema
   - No field duplication if multiple properties reference the same definition

4. **Validator:**
   - `validate` dereferences `$ref` and validates against the target schema
   - Validation errors include the fully-resolved path (not the `$ref` URI)

5. **Documentation:**
   - `glossary.md` updated with `$ref` resolution term if needed
   - Example in HOW_TO_USE.md showing a schema with definitions and $ref

6. **No regression:**
   - All module 08 existing tests pass
   - All downstream tests pass

---

## Edge case handling

| Case | Behavior |
|---|---|
| `$ref` points to undefined definition | Treat as "pass" in validator; skip in form builder with warning comment |
| Nested `$ref` (reference points to another ref) | Resolve recursively (up to 10 levels deep to avoid infinite loops) |
| `$ref` with sibling properties | In v1, `$ref` takes precedence; sibling properties are ignored (standard JSON Schema behavior) |
| Circular reference (`A` refs `B` refs `A`) | Will infinite-loop; post-v1 to add cycle detection |
