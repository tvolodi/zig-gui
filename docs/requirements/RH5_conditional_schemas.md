# RH5 — M18-05: `if`/`then`/`else` conditional schemas

> Roadmap item: M18-05  
> Depends on: M8 (module 08 schema forms complete), RH3 (combinators)  
> Read `00_constitution.md` before this file.

## Purpose

Enable JSON Schema `if`/`then`/`else` keywords, which apply different validation schemas based on a condition. Example:

```json
{
  "if": { "properties": { "payment_method": { "const": "credit_card" } } },
  "then": { "required": ["card_number", "cvv"] },
  "else": { "required": ["account_number"] }
}
```

Interpretation: If the object satisfies the `if` schema, apply the `then` schema; otherwise apply the `else` schema (optional).

## What to build

### 1. Schema types extension — `docs/specs/08.types.zig`

```zig
pub const Schema = struct {
    // ... existing fields ...
    if_schema: ?*Schema = null,    // NEW: condition schema
    then_schema: ?*Schema = null,  // NEW: schema to apply if condition is true
    else_schema: ?*Schema = null,  // NEW: schema to apply if condition is false
};
```

### 2. Validator extension — `src/08/validator.zig`

Add conditional validation logic:

```zig
pub fn validate(alloc: Allocator, schema: *const Schema, value: *const Value) ![]ValidationError {
    var errors = std.ArrayListUnmanaged(ValidationError){};
    
    // ... existing validation ...
    
    // NEW: if/then/else — apply sub-schema based on condition
    if (schema.if_schema) |if_schema| {
        // Test whether the value satisfies the if_schema
        const if_errors = try validate(alloc, if_schema, value);
        defer alloc.free(if_errors);
        
        const condition_passes = (if_errors.len == 0);
        
        if (condition_passes) {
            // Condition is true: apply then_schema if present
            if (schema.then_schema) |then_schema| {
                const then_errors = try validate(alloc, then_schema, value);
                defer alloc.free(then_errors);
                try errors.appendSlice(alloc, then_errors);
            }
        } else {
            // Condition is false: apply else_schema if present
            if (schema.else_schema) |else_schema| {
                const else_errors = try validate(alloc, else_schema, value);
                defer alloc.free(else_errors);
                try errors.appendSlice(alloc, else_errors);
            }
        }
    }
    
    return errors.items;
}
```

### 3. Parser extension — `src/08/types.zig`

Update `parseSchema` to recognize `if`/`then`/`else`:

```zig
fn parseSchema(alloc: Allocator, json_value: json.Value) !Schema {
    // ... existing parsing ...
    
    // NEW: Parse if/then/else
    if (json_obj.get("if")) |if_val| {
        schema.if_schema = try alloc.create(Schema);
        schema.if_schema.?.* = try parseSchema(alloc, if_val);
    }
    
    if (json_obj.get("then")) |then_val| {
        schema.then_schema = try alloc.create(Schema);
        schema.then_schema.?.* = try parseSchema(alloc, then_val);
    }
    
    if (json_obj.get("else")) |else_val| {
        schema.else_schema = try alloc.create(Schema);
        schema.else_schema.?.* = try parseSchema(alloc, else_val);
    }
    
    return schema;
}
```

### 4. Form builder handling — `src/08/types.zig`

Update `buildForm` to handle conditional schemas:

```zig
pub fn buildForm(alloc: Allocator, schema: *const Schema, value: *const Value) ![]FieldSpec {
    // If the schema has an if/then/else condition, evaluate and build from the appropriate branch
    
    if (schema.if_schema) |if_schema| {
        const if_errors = try validate(alloc, if_schema, value);
        defer alloc.free(if_errors);
        
        if (if_errors.len == 0 and schema.then_schema != null) {
            // Condition passes: build from then_schema
            return buildForm(alloc, schema.then_schema.?, value);
        } else if (if_errors.len > 0 and schema.else_schema != null) {
            // Condition fails: build from else_schema
            return buildForm(alloc, schema.else_schema.?, value);
        }
    }
    
    // ... normal field building ...
}
```

### 5. Tests

**Unit tests** — `src/08/conditional_test.zig`:
- Schema with `if: { const: "credit_card" }`, `then: { required: ["cvv"] }`, no else
  - Value matches condition → validates `then` schema → requires cvv
  - Value doesn't match condition → skips both schemas → passes (no validation from then/else)
  
- Schema with all three: `if`, `then`, `else`
  - Condition true → apply then
  - Condition false → apply else
  
- Nested conditionals: `if` schema contains another `if/then/else`

- Empty branches: if/then but no else (only then applied when condition is true)

- Condition with a complex schema (not just `const`)

**Integration tests** — `src/08/08_test.zig`:
- Form with conditional payment method: if `payment_method == "credit_card"`, require card fields; else require bank fields
- `buildForm` produces the correct field set based on current value
- `validate` enforces the correct schema based on value

## Non-goals (DO NOT implement — INV-5.4)

- **No dynamic form UI updates** — form doesn't automatically add/remove fields as the value changes (static for v1)
- **No nested if/then/else chains beyond 3 levels** — assumed input is reasonable
- **No optimization for complex conditions** — each validation re-evaluates the condition (no caching)

## Acceptance criteria

1. **Conditional validator tests pass:**
   - `zig test src/08/conditional_test.zig` runs without error
   - All condition/then/else logic correct (branch selected, schema applied)

2. **Integration with validator:**
   - `zig build test-08` passes
   - Schema with `if`/`then`/`else` validates correctly
   - Errors come from the applied branch schema

3. **Form builder:**
   - `buildForm` on a conditional schema builds from the correct branch
   - Form renders without error

4. **Parser:**
   - `parseSchema` recognizes and parses `if`/`then`/`else` from JSON
   - Nested schemas are parsed recursively

5. **Documentation:**
   - `glossary.md` updated with `ConditionalSchema` or similar term if needed
   - Example in HOW_TO_USE.md showing a schema with conditional branches
   - Comment in validator code documents the evaluation order (if → then/else)

6. **No regression:**
   - All existing module 08 tests pass
   - All downstream tests pass

---

## Example: Payment form

```json
{
  "type": "object",
  "properties": {
    "payment_method": {
      "type": "string",
      "enum": ["credit_card", "bank_transfer", "paypal"]
    },
    "card_number": { "type": "string" },
    "cvv": { "type": "string" },
    "account_number": { "type": "string" },
    "routing_number": { "type": "string" }
  },
  "required": ["payment_method"],
  "if": {
    "properties": { "payment_method": { "const": "credit_card" } }
  },
  "then": {
    "required": ["card_number", "cvv"]
  },
  "else": {
    "if": {
      "properties": { "payment_method": { "const": "bank_transfer" } }
    },
    "then": {
      "required": ["account_number", "routing_number"]
    }
  }
}
```

This form validates:
- If `payment_method == "credit_card"`, require `card_number` and `cvv`
- Else if `payment_method == "bank_transfer"`, require `account_number` and `routing_number`
- Else (paypal) require nothing additional

---

## Glossary entry to add

### ConditionalSchema

A JSON Schema using `if`/`then`/`else` keywords (M18-05) to apply different validation schemas based on a condition. The `if` schema is tested; if it validates successfully, the `then` schema is applied; if it fails and `else` is present, the `else` schema is applied instead. Neither `then` nor `else` is required.

See: M18-05 (RH5), `src/08/validator.zig`.
