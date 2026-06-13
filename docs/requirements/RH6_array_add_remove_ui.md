# RH6 — M18-06: Array field add/remove UI controls

> Roadmap item: M18-06  
> Depends on: M8 (module 08 schema forms complete), M7 (component library)  
> Read `00_constitution.md` before this file.

## Purpose

Enable array-type fields in schema forms to display add (`+`) and remove (`−`) buttons, allowing users to manage the array size interactively. Each array item renders as a sub-form, with add/remove controls to grow or shrink the array.

Example form schema:

```json
{
  "type": "object",
  "properties": {
    "email_addresses": {
      "type": "array",
      "items": { "type": "string", "format": "email" },
      "minItems": 1,
      "maxItems": 5
    }
  }
}
```

Renders as:
```
email_addresses: [
  [ email_1_input ] [−]
  [ email_2_input ] [−]
  [ empty ]         [+]
]
```

User can click `[+]` to add a new empty item or `[−]` to remove an item.

## What to build

### 1. Scene state extension — `src/07/types.zig`

Add an array-manipulation state array to Scene:

```zig
pub const ArrayFieldState = struct {
    item_count: u32,
    min_items: u32 = 0,
    max_items: u32 = std.math.maxInt(u32),
};

pub const Scene = struct {
    // ... existing fields ...
    _array_field_state: std.ArrayListUnmanaged(ArrayFieldState) = .empty,
    
    pub fn arrayFieldStateOf(self: *Scene, idx: u32) *ArrayFieldState
    
    /// Add a new empty item to the array.
    pub fn addArrayItem(self: *Scene, idx: u32) void
    
    /// Remove the item at position `item_idx` from the array.
    pub fn removeArrayItem(self: *Scene, idx: u32, item_idx: u32) void
};
```

### 2. Form builder extension — `src/08/types.zig`

Update `buildForm` and `Form.mount` to handle array fields:

```zig
pub const FieldSpec = struct {
    // ... existing fields ...
    is_array: bool = false,           // NEW: this field represents an array
    array_item_schema: ?*Schema = null,  // NEW: schema for each array item
    array_min_items: u32 = 0,         // NEW: minimum number of items
    array_max_items: u32 = std.math.maxInt(u32),  // NEW: maximum number of items
};

pub fn buildForm(alloc: Allocator, schema: *const Schema) ![]FieldSpec {
    // ... existing parsing ...
    
    // If schema.type == "array":
    if (schema.items) |item_schema| {
        const field = FieldSpec{
            .path = path,
            .label = schema.title orelse "Items",
            .is_array = true,
            .array_item_schema = item_schema,
            .array_min_items = schema.min_items orelse 0,
            .array_max_items = schema.max_items orelse std.math.maxInt(u32),
            // ... other fields ...
        };
        try fields.append(alloc, field);
    }
}

pub const Form = struct {
    // ... existing fields ...
    
    pub fn mount(self: *Form, scene: *Scene, tokens: Tokens) !void {
        // ... existing mounting ...
        
        // For each array field:
        // 1. Create a container (column) element
        // 2. For each item in the value array:
        //    a. Instantiate a sub-form for the item
        //    b. Create a [−] remove button
        // 3. Create an add button [+] at the end (if not at max_items)
        
        for (self.fields, 0..) |field, field_idx| {
            if (field.is_array) {
                const array_value = self.getValue(field.path) orelse continue;
                if (array_value.* != .array) continue;
                
                const item_count = array_value.array.len;
                
                // Record array state
                const array_state_idx = try scene.addRoot();
                try scene._array_field_state.append(alloc, .{
                    .item_count = @intCast(item_count),
                    .min_items = field.array_min_items,
                    .max_items = field.array_max_items,
                });
                self.field_to_element[field_idx] = array_state_idx;
                
                // Mount each item
                for (0..item_count) |item_idx| {
                    // Build sub-form for item
                    // Mount item elements
                    // Add remove button
                }
                
                // Add button (if not at max)
                if (item_count < field.array_max_items) {
                    // Create [+] button
                }
            }
        }
    }
};
```

### 3. Value tree extension — `src/08/types.zig`

Update the `Value` type to support array operations:

```zig
pub const Value = union(enum) {
    // ... existing variants ...
    array: std.ArrayListUnmanaged(Value),
};

pub fn setPath(alloc: Allocator, root: *Value, path: []const u8, new_value: Value) !void {
    // ... existing path resolution ...
    
    // When path points to an array element (e.g., "items.0"):
    // Grow the array if needed and insert the value
}

pub fn getPath(root: *const Value, path: []const u8) ?*const Value {
    // ... existing path resolution ...
}
```

### 4. Button rendering — `src/09/types.zig`

Array field rendering in `buildDrawList`:

```zig
// Inside buildDrawList, for array container elements:
// 1. Render each item's form elements
// 2. Render remove button [−] for each item
// 3. Render add button [+] at the end (if not at max)

const add_button_rect = .{ .x = ..., .y = ..., .w = 24, .h = 24 };
try cmds.append(.{
    .text = .{
        .rect = add_button_rect,
        .text = "+",
        .color = tokens.accent,
        .font_size = 16,
    },
});

const remove_button_rect = .{ ... };
try cmds.append(.{
    .text = .{
        .rect = remove_button_rect,
        .text = "−",
        .color = tokens.err,
        .font_size = 14,
    },
});
```

### 5. Event handling — `src/app/app.zig`

Handle clicks on add/remove buttons:

```zig
fn handleArrayButtonClick(app: *App, element_idx: u32, is_add: bool) !void {
    const form = app.current_form;
    
    if (is_add) {
        // Find which array field this belongs to
        const field_spec = form.field_for_element[element_idx];
        
        // Append a new empty value to the array
        try form.getValue(field_spec.path).?.array.append(app.allocator, .{ .null = {} });
        
        // Re-mount the form
        try form.mount(&app.scene, app.tokens);
        
        // Mark dirty
        app.scene.markAllDirty();
    } else if (is_remove) {
        // Remove the item at this index
        // Re-mount the form
        // Mark dirty
    }
}
```

### 6. Tests

**Unit tests** — `src/08/array_field_test.zig`:
- Schema with `type: "array"`, `items: { type: "string" }`
- `buildForm` produces an `is_array=true` field spec
- Array with 3 items renders 3 item forms + 3 remove buttons + 1 add button
- Array at max_items hides the add button
- Array at min_items disables remove buttons
- Adding an item increments item_count
- Removing an item decrements item_count

**Integration tests** — `src/08/08_test.zig`:
- Form with array field (email addresses)
- User adds an item → array grows
- User removes an item → array shrinks
- Validation enforces min/max items constraints
- Array bounds are respected (no add button at max, no remove when at min)

## Non-goals (DO NOT implement — INV-5.4)

- **No drag-to-reorder** — items have a fixed order; user cannot reorder via drag (post-v1)
- **No nested arrays** — `type: "array"` with `items: { type: "array" }` not supported in v1
- **No custom item templates** — all array items use the same `items` schema (no `prefixItems` support)
- **No undo/redo** — array changes are immediate and not reversible
- **No lazy rendering** — all items rendered even if array is very large (virtualization is post-v1)

## Acceptance criteria

1. **Array state tests pass:**
   - `zig test src/08/array_field_test.zig` runs without error
   - Add/remove operations update item count
   - Min/max constraints are enforced

2. **Form builder:**
   - `zig build test-08` passes
   - Array fields are recognized and flagged with `is_array = true`
   - Sub-schema is captured in `array_item_schema`

3. **UI rendering:**
   - Array form renders without crash
   - Add button visible when item count < max
   - Remove buttons visible when item count > min
   - Button clicks trigger add/remove operations

4. **Value tree:**
   - Array values can be read and written via path resolution
   - Appending items grows the array value

5. **Validation:**
   - `validate` checks `minItems` and `maxItems` constraints
   - Item values are validated against `items` schema

6. **Documentation:**
   - `glossary.md` updated with `ArrayFieldState` term
   - Example in HOW_TO_USE.md showing an array field form
   - Comment in form builder code documents array handling

7. **No regression:**
   - All existing module 08 tests pass
   - All downstream tests pass

---

## Module placement

```
src/07/types.zig   — ArrayFieldState, Scene.addArrayItem, Scene.removeArrayItem, Scene._array_field_state
src/08/types.zig   — FieldSpec.is_array, Form array mounting, array Value operations
src/09/types.zig   — Array item rendering (add/remove buttons), buildDrawList handling
src/app/app.zig    — Event routing for add/remove button clicks
docs/requirements/RH6_array_add_remove_ui.md
```

---

## Glossary entry to add

### ArrayFieldState

Per-element state stored in `Scene._array_field_state` (M18-06) tracking the current item count and min/max bounds for an array-type form field. Updated by `Scene.addArrayItem()` and `Scene.removeArrayItem()`. Accessed via `Scene.arrayFieldStateOf(idx)`.

See: M18-06 (RH6), `src/07/types.zig`.
