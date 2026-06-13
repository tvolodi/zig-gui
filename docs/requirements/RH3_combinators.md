# RH3 — M18-03: `allOf`, `anyOf`, `oneOf` schema combinators

> Roadmap item: M18-03  
> Depends on: M8 (module 08 schema forms complete), RH2 ($ref resolution)  
> Read `00_constitution.md` before this file.

## Purpose

Enable JSON Schema composition keywords that combine multiple sub-schemas:
- `allOf` — value must be valid against ALL sub-schemas (intersection/conjunction)
- `anyOf` — value must be valid against AT LEAST ONE sub-schema (union/disjunction)
- `oneOf` — value must be valid against EXACTLY ONE sub-schema (exclusive union)

Example:

```json
{
  "allOf": [
    { "type": "object", "properties": { "name": { "type": "string" } } },
    { "required": ["name"] }
  ]
}
```

## What to build

### 1. Schema types extension — `docs/specs/08.types.zig`

```zig
pub const Schema = struct {
    // ... existing fields ...
    all_of: ?[]const Schema = null,      // NEW: must satisfy all schemas
    any_of: ?[]const Schema = null,      // NEW: must satisfy at least one schema
    one_of: ?[]const Schema = null,      // NEW: must satisfy exactly one schema
};
```

### 2. Form builder extension — `src/08/validator.zig`

Extend the validator to check all three combinators:

```zig
pub fn validate(alloc: Allocator, schema: *const Schema, value: *const Value) ![]ValidationError {
    var errors = std.ArrayListUnmanaged(ValidationError){};
    
    // ... existing validation ...
    
    // NEW: allOf — all sub-schemas must pass
    if (schema.all_of) |sub_schemas| {
        for (sub_schemas) |sub| {
            const sub_errors = try validate(alloc, &sub, value);
            defer alloc.free(sub_errors);
            try errors.appendSlice(alloc, sub_errors);
        }
    }
    
    // NEW: anyOf — at least one sub-schema must pass
    if (schema.any_of) |sub_schemas| {
        var any_passed = false;
        for (sub_schemas) |sub| {
            const sub_errors = try validate(alloc, &sub, value);
            defer alloc.free(sub_errors);
            if (sub_errors.len == 0) {
                any_passed = true;
                break;
            }
        }
        if (!any_passed) {
            try errors.append(alloc, .{
                .path = path,
                .kind = .any_of_mismatch,  // NEW error kind
                .message = "value must be valid for at least one schema in anyOf",
            });
        }
    }
    
    // NEW: oneOf — exactly one sub-schema must pass
    if (schema.one_of) |sub_schemas| {
        var passed_count: u32 = 0;
        for (sub_schemas) |sub| {
            const sub_errors = try validate(alloc, &sub, value);
            defer alloc.free(sub_errors);
            if (sub_errors.len == 0) {
                passed_count += 1;
            }
        }
        if (passed_count != 1) {
            try errors.append(alloc, .{
                .path = path,
                .kind = .one_of_mismatch,  // NEW error kind
                .message = try std.fmt.allocPrint(alloc, 
                    "value must be valid for exactly 1 schema; {} matched", .{passed_count}),
            });
        }
    }
    
    return errors.items;
}
```

### 3. Form builder handling — `src/08/types.zig`

Update `buildForm` to handle combinators:

```zig
pub fn buildForm(alloc: Allocator, schema: *const Schema) ![]FieldSpec {
    // If the schema is a combinator (allOf, anyOf, oneOf), merge the fields
    
    if (schema.all_of) |sub_schemas| {
        // Merge all sub-schema fields
        var all_fields = std.ArrayListUnmanaged(FieldSpec){};
        for (sub_schemas) |sub| {
            const sub_fields = try buildForm(alloc, &sub);
            try all_fields.appendSlice(alloc, sub_fields);
        }
        return all_fields.items;
    }
    
    if (schema.any_of) |sub_schemas| {
        // For form UI, treat anyOf as "pick one schema to follow"
        // In v1, use the first valid schema
        for (sub_schemas) |sub| {
            // Try to build form; return first that succeeds without errors
            const sub_fields = try buildForm(alloc, &sub);
            if (sub_fields.len > 0) return sub_fields;
        }
        return &.{};  // None succeeded
    }
    
    if (schema.one_of) |sub_schemas| {
        // For form UI, treat oneOf as anyOf (pick one; we don't enforce mutual exclusion in UI)
        for (sub_schemas) |sub| {
            const sub_fields = try buildForm(alloc, &sub);
            if (sub_fields.len > 0) return sub_fields;
        }
        return &.{};
    }
    
    // ... normal field building ...
}
```

### 4. Parser extension — `src/08/types.zig`

Update `parseSchema` to recognize and parse combinators:

```zig
fn parseSchema(alloc: Allocator, json_value: json.Value) !Schema {
    // ... existing parsing ...
    
    // NEW: Check for allOf/anyOf/oneOf at root level
    if (json_obj.get("allOf")) |all_of_array| {
        const sub_schemas = try parseSchemaArray(alloc, all_of_array);
        schema.all_of = sub_schemas;
    }
    
    if (json_obj.get("anyOf")) |any_of_array| {
        const sub_schemas = try parseSchemaArray(alloc, any_of_array);
        schema.any_of = sub_schemas;
    }
    
    if (json_obj.get("oneOf")) |one_of_array| {
        const sub_schemas = try parseSchemaArray(alloc, one_of_array);
        schema.one_of = sub_schemas;
    }
    
    return schema;
}

fn parseSchemaArray(alloc: Allocator, array: json.Array) ![]Schema {
    var schemas = std.ArrayListUnmanaged(Schema){};
    for (array.items) |item| {
        const sub = try parseSchema(alloc, item);
        try schemas.append(alloc, sub);
    }
    return schemas.items;
}
```

### 5. Validator error types extension — `src/08/validator.zig`

```zig
pub const ValidationError = struct {
    path: []const u8,
    kind: enum {
        // ... existing ...
        required_missing,
        type_mismatch,
        pattern_mismatch,  // from RH1
        any_of_mismatch,   // NEW: anyOf condition failed
        one_of_mismatch,   // NEW: oneOf condition failed
    },
    message: []const u8,
};
```

### 6. Tests

**Unit tests** — `src/08/combinator_test.zig`:
- `allOf` with two schemas: both pass → overall pass; one fails → overall fail
- `anyOf` with three schemas: none pass → fail; one pass → pass; all pass → pass
- `oneOf` with two schemas: none pass → fail; one pass → pass; both pass → fail (exactly one)
- Nested combinators: `allOf([anyOf([schema1, schema2]), schema3])`
- Empty combinator arrays: treated as no constraint (pass)

**Integration tests** — `src/08/08_test.zig`:
- Schema combining a "person" object schema with a "requires name" constraint via `allOf`
- `buildForm` merges fields from all sub-schemas
- `validate` enforces all constraints
- `anyOf` selecting the first matching schema for form building

## Non-goals (DO NOT implement — INV-5.4)

- **No conditional combinators** — `if`/`then`/`else` are separate (see RH5)
- **No discriminator support** — no `discriminator` field to optimize oneOf selection (post-v1)
- **No error aggregation by combinator** — error messages are simple; per-sub-schema error details are deferred
- **No UI widget selection by combinator** — form uses first valid schema; intelligent widget selection per constraint is post-v1

## Acceptance criteria

1. **Combinator validator tests pass:**
   - `zig test src/08/combinator_test.zig` runs without error
   - All allOf/anyOf/oneOf logic correct (pass/fail by count)

2. **Integration with validator:**
   - `zig build test-08` passes
   - Schema with `allOf`, `anyOf`, `oneOf` validates correctly
   - Errors include the combinator kind (e.g., "anyOf", "oneOf")

3. **Form builder:**
   - `buildForm` on a combinator schema merges or selects fields appropriately
   - Form renders without error

4. **Parser:**
   - `parseSchema` recognizes and parses combinator arrays from JSON
   - Nested combinators parse correctly

5. **Documentation:**
   - `glossary.md` updated with `AllOfValidator`, `AnyOfValidator`, `OneOfValidator` terms
   - Example in HOW_TO_USE.md showing a schema with combinators
   - Comment in validator code documents the priority/behavior of each combinator

6. **No regression:**
   - All existing module 08 tests pass
   - All downstream tests pass

---

## Glossary entries to add

### AllOfValidator
A constraint that requires a value to be valid against every sub-schema in the `allOf` array. Added in M18-03 (RH3). All constraints must be satisfied (intersection).

### AnyOfValidator
A constraint that requires a value to be valid against at least one sub-schema in the `anyOf` array. Added in M18-03 (RH3). At least one sub-schema must pass.

### OneOfValidator
A constraint that requires a value to be valid against exactly one sub-schema in the `oneOf` array. Added in M18-03 (RH3). For mutual exclusion — neither zero nor multiple schemas should validate.
