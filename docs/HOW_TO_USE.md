# How to use zig-gui — API usage guide

> This document is for agents that need to **build UI with the framework** (write screens,
> wire forms, query the element tree). For agents that need to **implement or modify the
> framework itself**, read `docs/AGENT_GUIDE.md` and `docs/specs/00_constitution.md` first.

---

## 1. Concepts in 60 seconds

| Concept | What it is |
|---|---|
| `Palette` | Raw hex values — the only thing that changes between brand themes |
| `Tokens` | Semantic roles (`bg_canvas`, `accent`, `text_body`, …) derived from a `Palette` |
| `ComputedStyle` | Fully resolved per-element style (colors, font size, border, padding, radius) |
| `NodeDesc` | Parser output — tag + classes + attrs + children. Throwaway (per-frame). |
| `Scene` | Live element tree. Owns the `ElementStore` + parallel `kind/style/text` arrays. |
| `ElementId` | `{ index: u32, gen: u32 }` — generational handle. Never store a pointer. |
| `LayoutNode` | Per-element layout data (flex/grid/block props, computed `Rect`). |
| `Form` | Schema-driven form: JSON Schema → flat field list → widgets mounted into a `Scene`. |
| `Value` | Dynamic JSON-like union (`null/bool/int/float/string/array/object`). |

---

## 2. Step-by-step: building a static screen

### Step 1 — Create a theme

```zig
const theme = @import("05/types.zig");

const tokens = theme.Tokens.light(theme.Palette.default());
// or: theme.Tokens.dark(theme.Palette.default())
// or: theme.Tokens.light(my_custom_palette)
```

`Palette.default()` gives a working gray + teal-accent palette immediately.

### Step 2 — Write markup

Markup uses XML-like syntax. Text is always an attribute, never element content.

```zig
const markup = @import("06/types.zig");

// Arena owns all parser allocations; reset it when you rebuild the screen.
var arena = std.heap.ArenaAllocator.init(allocator);
defer arena.deinit();

const desc = try markup.parse(arena.allocator(),
    \\<Column class="flex flex-col gap-2">
    \\  <Text text="Hello, world"/>
    \\  <Row class="gap-4">
    \\    <Button text="Save"/>
    \\    <Button text="Cancel"/>
    \\  </Row>
    \\</Column>
);
```

**Available tags:** `Text`, `Button`, `Input`, `Card`, `Row`, `Column`, `Dropdown`

**Available class names (Tailwind subset):**

| Class | Effect |
|---|---|
| `flex` | `display: flex` |
| `flex-row` | flex direction = row (default for `Row`) |
| `flex-col` | flex direction = column (default for `Column`) |
| `gap-N` | gap = N × 4 px (e.g. `gap-2` = 8 px) |
| `grow` | `flex_grow: 1` |
| `shrink` | `flex_shrink: 1` |
| `bg-canvas` | background = `tokens.bg_canvas` |
| `bg-surface` | background = `tokens.bg_surface` |
| `bg-accent` | background = `tokens.accent` |
| `text-body` | text color = `tokens.text_body` |
| `text-muted` | text color = `tokens.text_muted` |
| `text-sm` / `text-base` / `text-lg` | font size = 12 / 14 / 16 px |
| `p-N` | padding all sides = N × 4 px |
| `rounded` / `rounded-lg` | border radius = 4 / 8 px |
| `w-full` | width = 100% |
| `h-full` | height = 100% |

**Attribute bindings:** `text="{bind some.path}"` records the path as a `bind` variant of
`AttrValue`; it is NOT evaluated by the parser or scene — evaluation is the caller's job.

### Step 3 — Instantiate a Scene

```zig
const C = @import("07/types.zig");

var scene = C.Scene.init(allocator);
defer scene.deinit();

// Parse the markup and build the live element tree.
const root = try scene.instantiate(desc, tokens);
// Errors: InstantiateError.UnknownTag, InstantiateError.OutOfMemory
```

`scene.instantiate` applies the style-merge rule:
`base_style` (from widget kind) + `resolved_classes` — only non-default class fields override
the base. A `Button` with `class="bg-canvas"` keeps its default padding from `buttonPrimary`
but gets `bg_canvas` as background.

### Step 4 — Query the element tree

```zig
// Widget kind, resolved style, text attribute
const kind  = scene.kindOf(root);          // WidgetKind enum
const style = scene.styleOf(root);         // *ComputedStyle (pointer into array)
const text  = scene.textOf(root);          // ?[]const u8

// Total live element count
const n = scene.count();

// Tree navigation (via the ElementStore)
const store_ptr = scene.store();           // *ElementStore

var it = store_ptr.childrenOf(root);
while (it.next()) |child_id| {
    // ...
}
const parent = store_ptr.parentOf(child_id); // ?ElementId

// Access LayoutNode (LOCAL use only — never store this pointer across frames)
const layout = store_ptr.get(id);           // *LayoutNode
// layout.computed is the resolved pixel Rect after layout.solve()
```

### Step 5 — Run layout

```zig
const layout_mod = @import("04/types.zig");

// available is the screen size in pixels
const available = store_mod.Size{ .w = 1280, .h = 720 };
layout_mod.solve(scene.store(), root, available);

// After solve(), every element's layout.computed is set.
const rect = scene.store().get(root).computed; // Rect{ .x, .y, .w, .h }
```

### Step 6 (optional) — Measure text

Only needed when you have a font file loaded. The `measurePass` fills
`LayoutNode.measured` for every text-bearing element, which `layout.solve` then uses
as the intrinsic size for text nodes.

Call `measurePass` **before** `layout.solve`.

```zig
const text_mod = @import("02/types.zig");

var font  = try text_mod.Font.initFromBytes(allocator, font_bytes);
defer font.deinit();
var atlas = try text_mod.GlyphAtlas.init(allocator, 512, 512);
defer atlas.deinit();

try scene.measurePass(&font, &atlas);
// Now call layout_mod.solve(...)
```

### Step 7 — Rebuild (per frame)

Call `scene.reset()` at the start of each frame to wipe all elements, then
`scene.instantiate(desc, tokens)` again. The allocator is retained; the arena inside
`ElementStore` is reset but not freed.

```zig
scene.reset();
_ = try scene.instantiate(new_desc, tokens);
```

---

## 3. Dynamic forms (Module 08)

Use this when the form shape is known only at runtime (e.g. loaded from a JSON schema).

### Define a schema in code

```zig
const forms = @import("08/types.zig");

const schema = forms.Schema{
    .type = .object,
    .title = "User",
    .properties = &.{
        .{ .name = "name",  .schema = .{ .type = .string,  .title = "Full name",
                                         .min_length = 1, .max_length = 100 } },
        .{ .name = "email", .schema = .{ .type = .string,  .title = "Email",
                                         .format = .email } },
        .{ .name = "age",   .schema = .{ .type = .integer, .title = "Age",
                                         .minimum = 0, .maximum = 150 } },
        .{ .name = "role",  .schema = .{ .type = .string,
                                         .enum_values = &.{
                                             .{ .string = "admin" },
                                             .{ .string = "user" },
                                         } } },
    },
    .required = &.{ "name", "email" },
};
```

Supported `JsonType` values: `.object`, `.array`, `.string`, `.integer`, `.number`, `.boolean`

Supported `Format` values: `.none`, `.date` (YYYY-MM-DD), `.date_time`, `.email`, `.uri`

Fields with `enum_values` get a `Dropdown` widget. Boolean fields also get `Dropdown`.
String/integer/number fields get `Input`. Object fields recurse (nested section).

### Create and mount the form

```zig
var form = try forms.Form.init(allocator, schema);
defer form.deinit();

// Mount creates Column + one widget per leaf field in the scene.
const root = try form.mount(&scene, tokens);
```

`form.model` is a `[]FieldSpec` — the flat list of leaf fields:

```zig
pub const FieldSpec = struct {
    path:     []const u8,   // dotted path, e.g. "address.city"
    label:    []const u8,   // schema title or field name
    kind:     WidgetKind,
    format:   Format,
    required: bool,
};
```

### Read and write values

```zig
// Write
try form.setValue("email", .{ .string = "user@example.com" });
try form.setValue("age",   .{ .int = 30 });

// Read (returns ?*Value — null if path absent)
if (form.getValue("email")) |v| {
    std.debug.print("email = {s}\n", .{v.string});
}
```

`Value` dotted paths: `"a.b.c"` navigates object keys; `"items.0"` indexes into arrays.

### Validate

```zig
const errs = try form.validate(allocator);
defer allocator.free(errs);

for (errs) |e| {
    std.debug.print("  {s}: {s}\n", .{ e.path, e.message });
}
// errs is empty when validation passes.
```

Validation checks: required fields present, enum membership, minLength/maxLength,
minimum/maximum, email/date/uri format.

---

## 4. Build commands reference

```powershell
# Compile everything (no GPU required)
zig build

# Run pure tests (no font, no GPU)
zig build test-03       # element store
zig build test-04       # layout engine
zig build test-05       # theme
zig build test-06       # markup + style
zig build test-07-unit  # components (no font)
zig build test-08       # schema forms

# Run font-dependent tests (needs testdata/DejaVuSans.ttf)
zig build test-07

# Run GPU tests (needs Vulkan display)
zig build test-01

# Required env var (or pass -Dvulkan_sdk=<path>)
# $env:VULKAN_SDK = "C:\VulkanSDK\1.x.y.z"
```

---

## 5. Renderer bridge (module 09)

Module 09 completes the pipeline from `.ui` markup to GPU pixels.

### buildDrawList

```zig
const renderer = @import("src/09/types.zig");
const cmds = try renderer.buildDrawList(allocator, &scene, &atlas);
defer allocator.free(cmds);
```

Walks the solved scene in depth-first pre-order (painter's algorithm) and emits a flat
`[]DrawCommand` containing `filled_rect`, `border_rect`, and `glyph` commands.

**Requires:** `layout.solve()` must be called before `buildDrawList` — the serializer reads
`computed` rects but does not call solve itself.

### GpuAtlas upload

```zig
const impl = try backend._impl_vulkan();
var gpu_atlas = try renderer.GpuAtlas.upload(
    allocator, impl.device, impl.phys_device, impl.cmd_pool, impl.graphics_queue, &atlas,
);
defer gpu_atlas.deinit(impl.device);
```

Re-upload when `atlas.generation` changes (after `scene.measurePass`).

### drawFrame

```zig
try backend.initQuadPipeline(allocator); // once after init
// per-frame loop:
if (backend.beginFrame()) {
    backend.clear(.{ .r = 0.1, .g = 0.1, .b = 0.1, .a = 1.0 });
    backend.drawFrame(cmds, &gpu_atlas);
    backend.endFrame();
}
// cleanup:
backend.deinitQuadPipeline();
```

The triangle pipeline (`drawTriangle`) and quad pipeline (`drawFrame`) coexist — use one or
the other per frame.

---

## 6. Constraints to respect (abridged)

- **No per-widget heap objects.** An element IS an index. Data lives in parallel arrays.
- **Never store `*LayoutNode` across frames.** Resolve it locally, use it, discard it.
- **Markup parser is dev-only in production.** Production code calls `parse` only during
  build-time codegen (behind `-Dhot-reload` flag at runtime).
- **Styling is flat utilities, not a cascade.** No inheritance, no selectors, no specificity.
- **Module import order is enforced.** Higher-numbered modules may not be imported by
  lower-numbered ones. Your application code sits above module 08 and may import anything.
- **Approved dependencies only:** std, GLFW, Vulkan SDK, stb_truetype. No new deps without
  recording them in `docs/specs/00_constitution.md`.

Full constraint list: `docs/specs/00_constitution.md`.
