# RH4 — M18-04: `dependentRequired` keyword for conditional field requirements

> Roadmap item: M18-04  
> Depends on: M8 (module 08 schema forms complete)  
> Read `00_constitution.md` before this file.

## Purpose

Enable JSON Schema `dependentRequired` keyword, which conditionally requires certain fields to be present based on the presence of other fields. Example:

```json
{
  "type": "object",
  "properties": {
    "name": { "type": "string" },
    "credit_card": { "type": "string" },
    "cvv": { "type": "string" }
  },
  "dependentRequired": {
    "credit_card": ["cvv", "name"]
  }
}
```

Interpretation: If `credit_card` is present, then `cvv` and `name` must also be present.

## What to build

### 1. Schema types extension — `docs/specs/08.types.zig`

```zig
pub const Schema = struct {
    // ... existing fields ...
    dependent_required: ?std.StringHashMap([]const []const u8) = null,
    // ^ Maps a property name to a list of properties that must be present if the key is present.
    // Example: dependent_required["credit_card"] = ["cvv", "name"]
};
```

### 2. Validator extension — `src/08/validator.zig`

Add validation logic:

```zig
pub fn validate(alloc: Allocator, schema: *const Schema, value: *const Value) ![]ValidationError {
    var errors = std.ArrayListUnmanaged(ValidationError){};
    
    // ... existing validation ...
    
    // NEW: dependentRequired — if key is present, then required properties must also be present
    if (schema.dependent_required) |deps| {
        if (value.* == .object) {
            var iter = deps.iterator();
            while (iter.next()) |entry| {
                const dep_key = entry.key_ptr.*;
                const required_props = entry.value_ptr.*;
                
                // If dep_key is present in the object, require all properties in required_props
                if (value.object.get(dep_key)) |_| {
                    for (required_props) |required_prop| {
                        if (value.object.get(required_prop) == null) {
                            try errors.append(alloc, .{
                                .path = path,
                                .kind = .dependent_required_missing,  // NEW error kind
                                .message = try std.fmt.allocPrint(alloc,
                                    "property '{}' is required when '{}' is present",
                                    .{ required_prop, dep_key }),
                            });
                        }
                    }
                }
            }
        }
    }
    
    return errors.items;
}
```

### 3. Parser extension — `src/08/types.zig`

Update `parseSchema` to recognize `dependentRequired`:

```zig
fn parseSchema(alloc: Allocator, json_value: json.Value) !Schema {
    // ... existing parsing ...
    
    // NEW: Parse dependentRequired object
    if (json_obj.get("dependentRequired")) |dep_obj| {
        var deps = std.StringHashMap([]const []const u8){};
        var iter = dep_obj.object.iterator();
        while (iter.next()) |entry| {
            const key = entry.key_ptr.*;
            const required_array = entry.value_ptr.*;
            
            var props = std.ArrayListUnmanaged([]const u8){};
            for (required_array.array.items) |prop_val| {
                if (prop_val.string) |prop_name| {
                    try props.append(alloc, prop_name);
                }
            }
            try deps.put(alloc, key, props.items);
        }
        schema.dependent_required = deps;
    }
    
    return schema;
}
```

### 4. Validator error types extension — `src/08/validator.zig`

```zig
pub const ValidationError = struct {
    path: []const u8,
    kind: enum {
        // ... existing ...
        required_missing,
        dependent_required_missing,  // NEW: dependentRequired condition failed
    },
    message: []const u8,
};
```

### 5. Tests

**Unit tests** — `src/08/dependent_required_test.zig`:
- Schema with `dependentRequired: { "credit_card": ["cvv"] }`
- Object with `credit_card` but no `cvv` → error
- Object with `credit_card` and `cvv` → pass
- Object with no `credit_card` → pass (no dependency triggered)
- Multiple dependencies: `dependentRequired: { "credit_card": ["cvv", "name"] }`
  - Missing `cvv` → error
  - Missing `name` → error
  - Missing both → two errors
- Multiple keys in `dependentRequired` (e.g., both `credit_card` and `gift_card`)

**Integration tests** — `src/08/08_test.zig`:
- Schema with `dependentRequired` and other required fields
- Validation combines base `required` and `dependentRequired` checks
- Error messages distinguish between missing base-required and dependent-required

## Non-goals (DO NOT implement — INV-5.4)

- **No dependentSchema** — conditional sub-schemas based on property presence (post-v1; see RH5 for `if`/`then`/`else`)
- **No transitive dependencies** — no "if A then B, and if B then C" chaining (single-hop only)
- **No UI branching** — form renderer does not dynamically show/hide fields based on dependency rules (static form in v1)

## Acceptance criteria

1. **Unit tests pass:**
   - `zig test src/08/dependent_required_test.zig` runs without error
   - All cases (presence, absence, multiple deps) handled correctly

2. **Integration with validator:**
   - `zig build test-08` passes
   - Schema with `dependentRequired` validates correctly
   - Errors include the dependency message

3. **Parser:**
   - `parseSchema` recognizes and parses `dependentRequired` from JSON
   - String array values are parsed correctly

4. **Documentation:**
   - `glossary.md` updated with `dependentRequired` term
   - Example in HOW_TO_USE.md showing a schema with dependency rules
   - Comment in validator code documents the trigger condition

5. **No regression:**
   - All existing module 08 tests pass
   - All downstream tests pass

---

## Glossary entry to add

### dependentRequired

A JSON Schema keyword (M18-04) that conditionally requires certain properties to be present based on the presence of other properties. Maps a "trigger" property name to a list of required properties. If the trigger property exists in an object, all required properties in the list must also exist. Stored in `Schema.dependent_required` as a map.

Example: `dependentRequired: { "credit_card": ["cvv", "name"] }` means: "If credit_card is present, cvv and name must also be present."

See: M18-04 (RH4), `src/08/validator.zig`.
