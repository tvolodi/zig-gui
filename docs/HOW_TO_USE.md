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

**Available tags (M7 Phase 3 — 24 kinds):** `Text`, `Button`, `Input`, `Card`, `Row`, `Column`, `Dropdown`, `Checkbox`, `ScrollView`, `Image`, `Icon`, `Textarea`, `Separator`, `Radio`, `Slider`, `ProgressBar`, `Spinner`, `Tabs`+`TabItem`, `Accordion`, `DatePicker`, `Avatar`, `Badge`, `DataTable`

**`Separator`:** Renders a 1 px horizontal rule using `tokens.border_default`. No children. No interactive state.

**`Radio`:** Circular radio button. Attributes: `group="name"` (required — determines which radios are mutually exclusive), `value="string"` (optional label for the selected value), `selected="true"` (initial selected state). Use `scene.selectRadio(idx)` to change selection; `scene.selectNextInGroup` / `scene.selectPrevInGroup` for keyboard cycling.

**`Slider`:** Horizontal range slider. Attributes: `min="0"` `max="100"` `step="1"` `value="50"`. Use `scene.setSliderValue(idx, value)` and `scene.getSliderValue(idx)` to read/write. Value is snapped to the nearest step.

**`ProgressBar`:** Horizontal progress bar. Attributes: `value="0.75"` (0.0–1.0, default 0), `indeterminate="true"` (animated moving band). Use `scene.setProgress(idx, value)` and `scene.setIndeterminate(idx, true)`. Animation runs automatically when `App.run()` is used (idle loop switches to polling when animated elements are present).

```xml
<ProgressBar value="0.4" class="w-full h-8"/>
<ProgressBar indeterminate="true" class="w-full h-8"/>
```

**`Spinner`:** Circular loading indicator (8 rotating tick marks). No extra attributes. Animates automatically.

```xml
<Spinner class="w-32 h-32"/>
```

**`Tabs` + `TabItem`:** Tab bar with switchable panels. `Tabs` is the container; each `TabItem` is one panel. The `text=` attribute on `TabItem` is the tab label.

```xml
<Tabs>
  <TabItem text="Home">
    <Text text="Home content"/>
  </TabItem>
  <TabItem text="Settings">
    <Text text="Settings content"/>
  </TabItem>
</Tabs>
```

Use `scene.selectTab(tabs_idx, 1)` to switch to the second tab programmatically. `scene.tabsStateOf(tabs_idx).active_idx` gives the current tab.

**`Accordion`:** Collapsible section. The first child is the header; the second child is the body (shown/hidden on click). The header renders with a chevron indicator (▶ closed, ▼ open).

```xml
<Accordion>
  <Row><Text text="Click to expand"/></Row>
  <Column class="p-4">
    <Text text="Hidden content revealed on click"/>
  </Column>
</Accordion>
```

Use `scene.toggleAccordion(idx)` to open/close programmatically. `scene.isAccordionOpen(idx)` reads state.

**Available class names (Tailwind subset):**

| Class | Effect |
|---|---|
| `flex` | `display: flex` |
| `flex-row` | flex direction = row (default for `Row`) |
| `flex-col` | flex direction = column (default for `Column`) |
| `gap-N` | gap = N × 4 px (e.g. `gap-2` = 8 px) |
| `grow` | `flex_grow: 1` |
| `grow-0` | `flex_grow: 0` (no grow, even in flex container) |
| `shrink` | `flex_shrink: 1` |
| `shrink-0` | `flex_shrink: 0` (no shrink) |
| `self-start` / `self-center` / `self-end` / `self-stretch` / `self-auto` | align-self for this element |
| `bg-canvas` | background = `tokens.bg_canvas` |
| `bg-surface` | background = `tokens.bg_surface` |
| `bg-accent` | background = `tokens.accent` |
| `text-body` | text color = `tokens.text_body` |
| `text-muted` | text color = `tokens.text_muted` |
| `text-sm` / `text-base` / `text-lg` | font size = 12 / 14 / 16 px |
| `font-bold` | `font_bold = true` (use bold face from FontFamily) |
| `font-normal` | `font_bold = false` |
| `font-italic` / `italic` | `font_italic = true` (use italic face from FontFamily) |
| `not-italic` | `font_italic = false` |
| `p-N` | padding all sides = N × 4 px |
| `rounded` / `rounded-lg` | border radius = 4 / 8 px |
| `w-full` | width = 100% |
| `h-full` | height = 100% |
| `w-N`, `h-N` | width/height = N px (e.g. `w-100` = 100px) |
| `min-w-N`, `max-w-N` | min/max width = N px |
| `hidden` | `display: none` |
| `overflow-hidden` | clip children to bounds |
| `mx-auto` | horizontal auto margin (center) |
| `m-N` | margin all sides = N × 4 px |
| `col-span-N` | grid column span = N |
| `row-span-N` | grid row span = N |
| `opacity-0` through `opacity-100` | alpha = N / 100 |

**Attribute bindings:** `text="{bind some.path}"` records the path as a `bind` variant of
`AttrValue`; it is NOT evaluated by the parser or scene — evaluation is the caller's job.

### Step 2b — Inline style attributes (M5-01)

For dynamic styling on individual elements, use `style:*` attributes to override token-derived defaults:

```zig
const markup_str = 
    \\<Column class="gap-2">
    \\  <Text text="Dynamic color" style:color="#FF5733"/>
    \\  <Button text="Custom BG" style:background="#0088FF" class="text-body"/>
    \\  <Row class="gap-4" style:opacity="0.8"/>
    \\</Column>
;
```

Supported `style:*` attributes:
- `style:color` — hex color override for text (`#RRGGBB` or `#RRGGBBAA`)
- `style:background` — hex color override for background
- `style:opacity` — alpha value as float in `[0.0, 1.0]`; clamped if out of range

Style attributes take precedence over class-derived styles. Unknown `style:*` properties are silently ignored.

### Step 2c — Conditional rendering (M5-03)

Hide or show a subtree based on a binding:

```zig
const markup_str = 
    \\<Column class="gap-2">
    \\  <Text text="Always visible"/>
    \\  <Row if="false">
    \\    <Text text="Never shown (literal false)"/>
    \\  </Row>
    \\  <Button text="Show if verbose" if="{bind settings.verbose}"/>
    \\</Column>
;
```

- `if="true"` — element always shown
- `if="false"` — element always hidden (hidden at instantiation; cannot be shown without rebuilding)
- `if="{bind path}"` — element initially hidden; shown/hidden dynamically when the binding is updated via `refreshBindings()`

The hidden state is saved separately from the element's display CSS property, so toggling visibility does not lose the original computed style.

### Step 2d — List rendering (M5-04)

Repeat a child template over a collection:

```zig
const markup_str = 
    \\<Column class="gap-2">
    \\  <Text text="Item list:"/>
    \\  <Column for="{bind items}">
    \\    <Row class="gap-2">
    \\      <Text text="{bind .name}"/>
    \\      <Text text="{bind .count}" class="text-muted"/>
    \\    </Row>
    \\  </Column>
    \\</Column>
;
```

- `for="{bind path.to.collection}"` — the container becomes a list binding; its one child (the template) is repeated once per item in the collection
- Inside the template, `.fieldname` bindings are relative to the current item
- Calling `refreshBindings()` will re-instantiate the list if its length or content changes
- Notes: No virtual DOM diffing (always re-instantiates); no nested `for=` (one level only); no `key=` attribute (order-based identity)

### Step 2e — Conditional and list attributes work with signals

Both `if=` and `for=` accept binding paths. After instantiation, changes to the bound signal automatically trigger:
- For `if=`: `refreshBindings()` evaluates the signal and calls `scene.setHidden()` accordingly
- For `for=`: `refreshBindings()` detects length changes and re-instantiates the list

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

Call `measurePass` **before** `layout.solve`. Pass a `*Font` (the regular face); if
`scene.font_family` is set (R60), per-element bold/italic face selection happens automatically.

```zig
const text_mod = @import("02/types.zig");

const font_bytes = try std.fs.cwd().readFileAlloc(allocator, "Regular.ttf", 16*1024*1024);
defer allocator.free(font_bytes);
var font = try text_mod.Font.initFromBytes(allocator, font_bytes);
defer font.deinit();
var atlas = try text_mod.GlyphAtlas.init(allocator, 512, 512);
defer atlas.deinit();

// For bold/italic support: set scene.font_family before calling measurePass.
// scene.font_family = &my_font_family;  // FontFamily from app/font_family.zig
try scene.measurePass(&font, &atlas);
// Now call layout_mod.solve(...)
```

### FontFamily and font fallback (R60 + R64)

`FontFamily` (defined in `src/02/types.zig`, re-exported by `src/app/font_family.zig`) holds
up to three faces (regular/bold/italic) plus up to four fallback fonts for extended Unicode
coverage (emoji, CJK symbols, etc.).

```zig
const text_mod = @import("02/types.zig");

// Load the primary family (regular required; bold/italic optional)
const regular_bytes = try std.fs.cwd().readFileAlloc(allocator, "DejaVuSans.ttf", 16*1024*1024);
const bold_bytes    = try std.fs.cwd().readFileAlloc(allocator, "DejaVuSans-Bold.ttf", 16*1024*1024);
defer allocator.free(regular_bytes);
defer allocator.free(bold_bytes);

var family = try text_mod.FontFamily.init(allocator, regular_bytes, bold_bytes, null);
defer family.deinit();

// Add a fallback font for emoji / extended Unicode (R64)
const emoji_bytes = try std.fs.cwd().readFileAlloc(allocator, "NotoEmoji.ttf", 32*1024*1024);
defer allocator.free(emoji_bytes);
try family.addFallback(emoji_bytes);
// Bytes are copied into the family; you can free emoji_bytes after addFallback returns.

// Wire into the scene
scene.font_family = &family;
try scene.measurePass(family.face(false, false), &atlas);
```

**Fallback behavior (R64):** `layoutParagraphEx` is called internally with `family`. For each
codepoint, `FontFamily.fontForCodepoint` selects the first font in the chain that has the
glyph. If no font covers a codepoint, U+FFFD (`text_mod.REPLACEMENT_CODEPOINT`) is rendered
instead. If even U+FFFD is absent from all fonts, the glyph is silently skipped.

**Recommended fallback asset:** place a broad-coverage font such as
[Noto Emoji](https://fonts.google.com/noto/specimen/Noto+Emoji) or
[GNU Unifont](https://unifoundry.com/unifont/) in `testdata/` for integration testing.

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

## 4. Reactive state with Signals and Bindings (Milestone 2)

Use this when you want the UI to update automatically when data changes, without rebuilding
the entire scene every frame.

### What is a Signal?

A `Signal(T)` is a reactive container that holds a value of type `T`. When you call `set(new_value)`,
it automatically marks affected elements dirty in the `ElementStore`, which tells the frame loop
to re-layout and re-paint only those elements on the next frame.

**Key design:** Signals do NOT push values to UI elements or run callbacks. Instead, they mark
a bitset, and the frame loop's dirty scan decides what to re-render. This keeps the reactivity
mechanism simple and predictable.

### Creating and using a Signal

```zig
const signal_mod = @import("app/signal.zig");

var gpa = /* your allocator */;
var scene = /* your Scene */;

// Create a Signal([]const u8) with initial value "Hello"
var greeting = try signal_mod.Signal([]const u8).init(
    gpa,
    "Hello",
    &scene.store().dirty  // pass the dirty bitset from ElementStore
);
defer greeting.deinit();

// Read the current value (O(1), no side effects)
const current = greeting.get();  // returns "Hello"

// Write a new value — marks subscribers dirty automatically
greeting.set("World");

// After the next frame, the UI will update.
```

### Binding a Signal to a text element (static screens)

For **static screens** (app chrome, fixed layouts), use `BindingSet` to connect signals to specific
elements at compile time.

```zig
const binding_mod = @import("app/binding.zig");
const app_mod = @import("app/types.zig");

// Define your app state
const AppState = struct {
    greeting: signal_mod.Signal([]const u8),
    counter: signal_mod.Signal(u32),
};

var state = AppState{
    .greeting = try signal_mod.Signal([]const u8).init(gpa, "Hello", &scene.store().dirty),
    .counter = try signal_mod.Signal(u32).init(gpa, 0, &scene.store().dirty),
};
defer state.greeting.deinit();
defer state.counter.deinit();

// Build your UI
const root = try scene.instantiate(NodeDesc{ /* ... */ }, tokens);

// Find the element IDs for the text elements you want to bind to
const greeting_label_id = /* find via tree traversal */;
const counter_label_id = /* find via tree traversal */;

// Bind signals to elements (at the app level)
var app = try app_mod.App.init(gpa, .{ /* ... */ });
defer app.deinit();

// Use app._inner.bindings to register the bindings
try app._inner.bindings.bindText(AppState, "greeting", &state, greeting_label_id.index, gpa);
// For counter (u32 → string), format it yourself before binding:
// var counter_str = try std.fmt.allocPrint(gpa, "{d}", .{state.counter.get()});
// Try bindText(AppState, "counter", ...) — but u32 is not Signal([]const u8), so this won't compile.
// Instead, use Computed(T) (see below) to derive a formatted string.

// Later, in response to user input or other events:
state.greeting.set("Hi there");  // marks the label dirty; next frame updates the text
```

**Signal update timing (Milestone 2):** When you call `signal.set()`, the new value is stored
immediately, but the UI is updated **on the next frame**. Specifically:
  1. `signal.set()` stores the new value and marks element indices dirty in the `ElementStore`
  2. On the next call to `app.run()`, the dirty check detects the change
  3. `refreshBindings()` copies the new value from the signal to the element's text slot
  4. Layout and render happen, and the UI shows the new text

If no signals changed and no other events fired, the frame loop blocks in `waitEvents()`,
sleeping until the next OS event.

### Computed signals (derived state)

A `Computed(T)` is a signal whose value is a **pure function** of one or more upstream signals.
It caches the result and only recomputes when an upstream signal changes.

Use `Computed` to derive state (e.g. formatting a number as a string, computing a sum, filtering
a list) without manually tracking dependencies.

```zig
// Example: derive a formatted counter string from a u32 signal

var counter = try signal_mod.Signal(u32).init(gpa, 0, &scene.store().dirty);
defer counter.deinit();

// Define a compute context (closure state)
const CounterCtx = struct {
    counter_sig: *signal_mod.Signal(u32),
    gpa: std.mem.Allocator,
};
var ctx = CounterCtx{ .counter_sig = &counter, .gpa = gpa };

// Define the pure compute function
fn formatCounter(raw_ctx: *anyopaque) []const u8 {
    const c: *CounterCtx = @ptrCast(@alignCast(raw_ctx));
    const val = c.counter_sig.get();
    return std.fmt.allocPrint(c.gpa, "Count: {d}", .{val}) catch "error";
    // NOTE: this leaks! Real usage should manage the allocation lifetime.
    // For a real app, use an arena or store the formatted string elsewhere.
}

// Create the computed signal
var counter_display = try signal_mod.Computed([]const u8).init(
    gpa,
    "Count: 0",     // initial cached value
    &scene.store().dirty,
    &ctx,
    &formatCounter,
);
defer counter_display.deinit();

// Wire the dependency: when counter changes, mark counter_display stale
try counter.addComputedDep(counter_display.staleFn());

// Read the computed value — if upstream signal changed, it recomputes
const display_text = counter_display.get();  // calls formatCounter if stale

// Bind the computed signal to a text element
try app._inner.bindings.bindText(
    /* NOT APPLICABLE — bindText only works with Signal([]const u8), not Computed */
    // Computed binding is post-v1; for now, derive state in your app and create a Signal
);
```

### Example: reactive counter app

```zig
const Scene = @import("07/types.zig").Scene;
const signal_mod = @import("app/signal.zig");
const binding_mod = @import("app/binding.zig");

const App = struct {
    counter: signal_mod.Signal(u32),
    // buttons, labels, etc. tracked by element ID
};

pub fn main() !void {
    var gpa_state = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa_state.deinit();
    const gpa = gpa_state.allocator();

    var app = try app_mod.App.init(gpa, .{
        .window = .{ .title = "Counter", .width = 400, .height = 300 },
        .font_path = "testdata/DejaVuSans.ttf",
        .font_size_px = 16,
    });
    defer app.deinit();

    // Create reactive state
    var counter = try signal_mod.Signal(u32).init(
        gpa, 0, &app._inner.scene.store().dirty
    );
    defer counter.deinit();

    // Build UI
    const tokens = /* ... */;
    const root = try app._inner.scene.instantiate(
        NodeDesc{ .tag = "Column", .children = &.{
            NodeDesc{ .tag = "Text", .attrs = &.{
                .{ .name = "text", .value = .{ .literal = "Counter App" } },
            } },
            NodeDesc{ .tag = "Text", .attrs = &.{
                .name = "text", .value = .{ .bind = "counter_display" },
            } },  // bind to signal later
            NodeDesc{ .tag = "Button", .attrs = &.{
                .{ .name = "text", .value = .{ .literal = "+1" } },
            } },
            NodeDesc{ .tag = "Button", .attrs = &.{
                .{ .name = "text", .value = .{ .literal = "-1" } },
            } },
        } },
        tokens,
    );

    // Bind the counter display (use a Computed to format, then bind)
    // ... (elided for brevity)

    // Main loop
    while (!app._inner.platform.shouldClose()) {
        // Collect events
        app._inner.platform.pollEvents();
        const events = app._inner.event_queue.drain();
        defer app._inner.event_queue.clear();

        // Handle button clicks
        for (events) |evt| {
            if (evt == .mouse_button) {
                // Detect which button was clicked and adjust counter
                // counter.set(counter.get() + 1);  // marks text element dirty
            }
        }

        // The rest of the frame loop happens inside app._inner.run().
        // But for now, you manage the frame loop manually.
        // See §7 "Running an application" for the full loop.
    }
}
```

---

## 5. Build commands reference

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
zig build test-app      # App layer unit tests (headless — no GPU)
zig build test-events   # EventQueue unit tests (headless — no GPU)

# Run font-dependent tests (needs testdata/DejaVuSans.ttf)
zig build test-07

# Run GPU tests (needs Vulkan display)
zig build test-01
zig build test-09         # renderer (CPU + GPU tests; all 12 tests pass when run directly)
zig build test-09-unit    # renderer CPU-only tests (no Vulkan required)

# Build-time markup codegen (M5-06)
# Processes all .ui files in src/screens/ and emits .ui.zig struct literals
zig build codegen

# Run the app with hot-reload enabled (M5-07)
# Watches for changes to .ui files and re-parses them without recompiling
zig build run-dev

# Alternative: Run the app with hot-reload via flag (same as run-dev)
zig build --help | grep run-dev    # verify the step exists

# Required env var (or pass -Dvulkan_sdk=<path>)
# $env:VULKAN_SDK = "C:\VulkanSDK\1.x.y.z"

# Build with dev-time hot-reload support
zig build -Dhot-reload=true

# Compile to release (no hot-reload parser in binary)
zig build -Doptimize=ReleaseFast
```

**Hot-reload notes (M5-07):**
- Hot-reload is a **dev-only** feature, enabled via the `-Dhot-reload` build flag
- It allows you to edit `.ui` files in `src/screens/` and see changes **without recompiling**
- The file watcher re-parses changed `.ui` files and calls `scene.reset()` + `instantiate()` automatically
- Production binaries shipped with `-Doptimize=ReleaseFast` have no parser in the binary (INV-4.4)

**Markup error reporting (M5-05):**
When parsing fails, errors now include line number and column information:

```
Error: Unclosed tag at line 5, column 12: expected '>' after tag name
```

Errors are available via the `parseWithDiag` function for custom error handling:

```zig
var diag: markup.ParseDiagnostic = undefined;
const desc = markup.parseWithDiag(allocator, source, &diag) catch {
    std.debug.print("Parse error at {d}:{d}: {s}\n", 
        .{ diag.loc.line, diag.loc.column, diag.message });
    return error.ParseFailed;
};
```

## 6. Renderer bridge (module 09)

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

---

## 7. Widget interaction (Milestone 3 — R30–R36)

Milestone 3 adds full widget interaction. The `App.run()` loop handles all events
automatically when you use `app._inner` APIs.

### Focus model (R30)

Keyboard focus cycles through all focusable widgets (button, input, dropdown, checkbox, textarea)
in document order via Tab/Shift+Tab. `App.run()` dispatches Tab/Shift+Tab automatically —
you only need to call `focusNext`/`focusPrev` for custom navigation. Focus state lives on `Scene`:

```zig
// Read focus
const focused = scene.focused_idx; // u32; std.math.maxInt(u32) = no focus

// Set focus programmatically
scene.setFocus(some_element_idx);

// Clear focus
scene.setFocus(std.math.maxInt(u32));

// Navigate
scene.focusNext(); // Tab
scene.focusPrev(); // Shift+Tab
```

The focused element gets a 2px **focus ring** (blue border) drawn by the renderer using
the named constant `comp_mod.FOCUS_RING_COLOR` (INV-4.3).

### Button callbacks (R31)

```zig
// Wire a callback after instantiate
const MyCtx = struct { count: u32 };
var ctx = MyCtx{ .count = 0 };

fn onButtonClick(ptr: *anyopaque) void {
    const c: *MyCtx = @ptrCast(@alignCast(ptr));
    c.count += 1;
}

try scene.setButtonCallback(button_idx, .{ .ptr = &ctx, .call = onButtonClick });

// Callbacks fire ONCE PER FRAME at most, after layout, before rendering.
// They fire on mouse RELEASE when the element is hovered and not disabled.
// They are NOT a reactivity path — mark signals dirty inside them if needed.
```

### Text input (R32)

The `App.run()` loop dispatches char events and editing keys automatically.
Read the current text at any time:

```zig
const text = scene.getInputText(input_idx); // []const u8, NOT null-terminated
```

Set initial text:

```zig
try scene.setInputText(input_idx, "initial value");
```

Supported editing operations (handled automatically on keypress):
- Backspace/Delete — delete char or selection
- Left/Right/Home/End — move cursor (hold Shift to extend selection)
- Ctrl+A — select all; Ctrl+C — copy; Ctrl+V — paste; Ctrl+X — cut
- Any printable character — insert at cursor

### Multi-line text input / Textarea (R63)

Tag: `<Textarea>`. Multi-line editable text area with scroll and selection.
Extends `<Input>` semantics to multiple lines.

```zig
// Read current text (all lines, newlines included)
const text = scene.getInputText(textarea_idx); // []const u8

// Set initial text
try scene.setInputText(textarea_idx, "line 1\nline 2\nline 3");

// Access per-textarea state
const ts = scene.textareaStateOf(textarea_idx);
const scroll_y = ts.scroll_y;                    // current vertical scroll offset
const content_h = ts.content_h;                  // total content height (updated by renderer)
const container_h = ts.container_h;              // visible height (updated by renderer)
const line_count = ts.line_starts.items.len;     // number of lines
```

Supported editing operations (handled automatically on keypress):
- Backspace/Delete — delete char or selection
- Left/Right/Home/End — move cursor within a line
- **Up/Down arrows** — move cursor up or down one line (hold Shift to extend selection)
- **Enter** — insert newline at cursor
- Ctrl+A — select all; Ctrl+C — copy; Ctrl+V — paste; Ctrl+X — cut
- Any printable character — insert at cursor

Scroll to cursor happens automatically on any key press that moves the cursor.

**Key difference from `<Input>`:** `<Input>` is always a single line; `<Textarea>` is
multi-line and must be given a finite height (e.g. via `h-200` class) to enable scrolling.

### Dropdown (R33)

```zig
// Set options (slices are borrowed — keep them alive)
var opts = [_]scene_mod.DropdownOption{
    .{ .label = "Option A", .value = @ptrCast(&value_a) },
    .{ .label = "Option B", .value = @ptrCast(&value_b) },
};
try scene.setDropdownOptions(dropdown_idx, &opts);

// Read selection
const dd = scene.dropdownStateOf(dropdown_idx);
const selected_label = dd.options.items[dd.selected_idx].label;

// Programmatic control
scene.openDropdown(dropdown_idx);
scene.closeDropdown(dropdown_idx);
scene.toggleDropdown(dropdown_idx);
```

Keyboard: Space/Enter opens or confirms; Up/Down moves highlight; Escape closes.

### Checkbox (R34)

```zig
// Read state
const checked = scene.isCheckboxChecked(checkbox_idx);

// Set state
scene.setCheckboxChecked(checkbox_idx, true);
```

Click or Space/Enter key toggles. Hover and pressed pseudo-states update automatically.

### Scroll container (R35)

Tag: `<ScrollView>`. Children that exceed the container height are scrolled via mouse wheel.
`App.run()` dispatches mouse wheel events automatically. Scroll offsets are clamped to
`[0, content_size - container_size]` automatically.

```zig
// Read scroll position
const scroll = scene.getScrollOffset(scrollview_idx); // .{ .y, .x }

// Set programmatically
scene.setScrollOffset(scrollview_idx, new_y, new_x);

// Update content dimensions so the renderer knows the thumb size
const ss = scene.scrollStateOf(scrollview_idx);
ss.content_height = total_children_height;
ss.container_height = visible_height;
```

### Clipboard (R36)

Platform clipboard access via the `Platform` struct:

```zig
// Copy text to clipboard (borrows; no transfer)
platform.setClipboard("some text");

// Paste from clipboard (caller owns returned slice; null if empty or non-UTF-8)
if (platform.getClipboard(allocator)) |text| {
    defer allocator.free(text);
    // use text...
}
```

The text input widget uses clipboard automatically via Ctrl+C/V/X.

The triangle pipeline (`drawTriangle`) and quad pipeline (`drawFrame`) coexist — use one or
the other per frame.

---

## 7. Running an application (App layer — Milestone 1)

`App` is the single entry point that wires together all modules and drives the frame loop.
Import from `src/app/types.zig`.

### Minimal usage

```zig
const app_mod = @import("app/types.zig");

pub fn main() !void {
    var gpa_state = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa_state.deinit();
    const gpa = gpa_state.allocator();

    var app = try app_mod.App.init(gpa, .{
        .window    = .{ .title = "My App", .width = 1280, .height = 720 },
        .font_path = "testdata/DejaVuSans.ttf",
        .font_size_px = 16,
    });
    defer app.deinit();

    // Build your scene before calling run.
    // app._inner.scene is the live Scene — instantiate your NodeDesc tree into it.

    app.run(); // blocks until the window is closed
}
```

### `AppOptions` fields

| Field | Type | Default | Notes |
|---|---|---|---|
| `window` | `WindowOptions` | `{ title="spike", w=960, h=600 }` | Passed to `Platform.init` |
| `font_path` | `[]const u8` | — | Required. Path to a `.ttf` file; read from disk at init. |
| `font_size_px` | `f32` | `16` | Default glyph rasterization size. |
| `bold_font_path` | `?[]const u8` | `null` | Optional. Path to the bold `.ttf` face. Used by `font-bold` class. Falls back to regular if null. |
| `italic_font_path` | `?[]const u8` | `null` | Optional. Path to the italic `.ttf` face. Used by `font-italic` / `italic` class. Falls back to regular if null. |

### Frame loop (what `App.run` does every frame)

**Optimization gate (Milestone 2):** If no signals have changed and no layout/size changes are pending,
call `platform.waitEvents()` to block until the next OS event (keyboard, mouse, or window resize).
This prevents busy-spinning on idle frames.

**Full frame when dirty:**

1. Poll GLFW events → fill `EventQueue`.
2. Drain `EventQueue` → call `dispatchEvents` (no-op stub until Milestone 3).
3. Apply any pending framebuffer resize → recreate Vulkan swapchain, update layout viewport.
4. **Refresh signal bindings (Milestone 2):** Call `refreshBindings()` to copy current signal
   values to any bound text elements in the scene (via `BindingSet`).
5. `scene.measurePass` — rasterize new glyphs, bump `atlas.generation` if atlas changed.
6. Re-upload GPU atlas if `atlas.generation` changed since last frame.
7. `layout.solve` — fill `computed` rects for all elements.
8. `buildDrawList` — walk the scene depth-first, emit flat `[]DrawCommand`.
9. `backend.clear` → `backend.drawFrame` → `backend.endFrame`.
10. Clear the dirty bitset for the next frame.

**Key detail:** When you call `signal.set(new_value)`, it marks affected element indices dirty
in the `ElementStore`'s bitset. On the next frame, the dirty check at the top of the loop
detects this and proceeds with a full render. The `refreshBindings()` call copies the signal's
new value to its bound text slot before layout and rendering.

**Zero-size guard:** frames where the framebuffer has width=0 or height=0 (minimised window)
are skipped entirely — no Vulkan calls, no crash.

**Frame pacing:** the swapchain uses `VK_PRESENT_MODE_FIFO_KHR` (vsync). `endFrame` blocks
inside the Vulkan driver at the vertical blanking interval — no explicit sleep is needed.

### Event types (R11)

All event types live in `src/app/types.zig` (re-exported from module 01).

```zig
pub const Event = union(enum) {
    mouse_move:   struct { x: f32, y: f32 },
    mouse_button: struct { button: MouseButton, action: Action, x: f32, y: f32 },
    scroll:       struct { dx: f32, dy: f32 },
    key:          struct { key: Key, action: Action, mods: Modifiers },
    char:         struct { codepoint: u21 },
};

pub const MouseButton = enum { left, right, middle };
pub const Action      = enum { press, release };
pub const Modifiers   = packed struct { shift: bool, ctrl: bool, alt: bool, super: bool };
pub const Key         = enum {
    enter, escape, tab, backspace, delete,
    left, right, up, down, home, end, page_up, page_down,
    left_shift, right_shift, left_ctrl, right_ctrl, left_alt, right_alt,
    f1, f2, f3, f4, f5, f6, f7, f8, f9, f10, f11, f12,
    other,
};
```

### `EventQueue` — used by `App` internally, also usable standalone

```zig
pub const EventQueue = struct {
    pub fn init(gpa: std.mem.Allocator) EventQueue
    pub fn deinit(self: *EventQueue) void
    pub fn push(self: *EventQueue, event: Event) void   // called by GLFW callbacks
    pub fn drain(self: *const EventQueue) []const Event // slice valid until clear()
    pub fn clear(self: *EventQueue) void
};
```

Capacity: 256 events per frame. Extras are silently dropped; `std.log.warn` fires once per
overflow frame.

---

## 8. Pseudo-state styling (M4-01 / R40)

Milestone 4 adds hover, focus, active, and disabled style variants that automatically change
a widget's appearance based on its current interaction state. No manual style switching is
needed — the renderer reads `PseudoState` from the parallel array and applies the overrides.

### How it works

Each interactive widget kind (`button`, `input`, `dropdown`, `checkbox`) has a corresponding
`buttonPseudo`/`inputPseudo`/etc. override set defined in module 05. The renderer calls
`resolveStyle(base, overrides, state)` at draw time, layering overrides on top of the base
`ComputedStyle` in priority order: focus < hover < active < disabled.

### Setting pseudo-state manually

The `App.run()` loop updates pseudo-states automatically (hover tracking, focus ring). You
can also set state directly:

```zig
// Enable hover state on an element
scene.setPseudo(element_idx, .{ .hover = true });

// Mark as disabled (disabled overrides all other states)
scene.setPseudo(element_idx, .{ .disabled = true });
```

`setPseudo` marks the element dirty so the next frame re-renders with the new state.

### Token overrides

Override defaults by customising the component-token builders in module 05. The overrides are
defined via `PseudoStyleSet` (a struct of optional-field `PseudoOverride` values):

```zig
// Example: what buttonPseudo returns (simplified)
// .hover    → slightly lighter background
// .active   → darker (pressed) background
// .disabled → muted text color + dimmed background
// .focus    → coloured border matching FOCUS_RING_COLOR
```

---

## 9. Overlay / z-layer (M4-02 / R41)

`OverlayLayer` provides a second draw pass rendered after the main scene. Popups, dropdowns,
and tooltips use this to appear above all other elements.

Import from `src/app/overlay.zig`.

### Usage pattern

```zig
const overlay_mod = @import("app/overlay.zig");

var overlay = overlay_mod.OverlayLayer.init(gpa);
defer overlay.deinit();

// Allocate a slot ID (do this once when the popup is created)
const popup_id = overlay.allocId();

// When the popup should be visible, set its draw commands
const popup_cmds: []DrawCommand = /* build commands for the popup content */;
overlay.setSlot(popup_id, popup_cmds);

// When the popup is dismissed
overlay.removeSlot(popup_id);

// Per-frame: flatten all overlay slots into a single command list and submit
const overlay_cmds = try overlay.flatten(frame_alloc);
defer frame_alloc.free(overlay_cmds);
// Submit overlay_cmds to the renderer after the main draw list.
```

Slots are rendered in insertion order (first `allocId` call is rendered first / lowest).

---

## 9b. Toast notifications (R74)

`ToastManager` queues transient message banners in the overlay layer. Import from
`src/app/toast.zig`.

```zig
const toast_mod = @import("app/toast.zig");

var toasts = toast_mod.ToastManager.init(&overlay);
defer toasts.deinit(allocator);

// Show a toast (duration_ms = 0 means use default 3000 ms)
const now_ms: u64 = @bitCast(std.time.milliTimestamp());
try toasts.show("File saved", .success, 3000, now_ms);
try toasts.show("Network error", .@"error", 5000, now_ms);

// Per-frame update — call after buildDrawList, before drawFrame
try toasts.tick(now_ms, viewport_w, viewport_h, tokens, &font, &atlas, &overlay, allocator);
```

`ToastKind` values: `.info`, `.success`, `.warning`, `.@"error"`.  
Toasts stack vertically in the bottom-right corner. Maximum 4 simultaneous toasts.  
`dismiss(index)` removes a specific toast immediately.

---

## 9c. Modal dialogs (R75)

`DialogManager` shows a full-screen backdrop + centered panel, and traps keyboard focus to
the dialog content while open. Import from `src/app/dialog.zig`.

```zig
const dialog_mod = @import("app/dialog.zig");

var dialog = dialog_mod.DialogManager.init(&overlay);
defer dialog.deinit(allocator);

// Open: content_idx is the element whose subtree becomes the modal panel content.
dialog.open(content_idx, &scene);

// Per-frame update — call after buildDrawList, before drawFrame
try dialog.buildOverlay(viewport_w, viewport_h, tokens, &overlay, allocator);

// Close
dialog.close(&scene);

// Query
const visible = dialog.isOpen();
```

When open, the backdrop (semi-transparent black) fills the viewport and the panel background
is centered. Focus is trapped to `content_idx`'s subtree; closing the dialog restores the
previous focus.

---

## 10. Clipping / overflow-hidden (M4-03 / R42)

`<ScrollView>` elements automatically clip their children to their visible bounds using a GPU
scissor rect. This prevents children that scroll out of view from being drawn outside the
container.

### How it works

- The renderer emits a `scissor` draw command when entering a `scrollview` element.
- Children's computed rects are offset by the current scroll position before drawing.
- A `restore_scissor` sentinel is pushed after all children so subsequent siblings are not
  affected.

### Tailwind

`overflow-hidden` is set automatically by `defaultLayoutFor(.scrollview)` — you do not need
to add the class manually to `<ScrollView>` elements.

```xml
<!-- Children that extend below 300px will be clipped -->
<ScrollView class="h-72">
  <Column class="gap-2">
    <!-- ... many children ... -->
  </Column>
</ScrollView>
```

---

## 11. Image and icon rendering (M4-04 / R43)

Two new widget kinds — `<Image>` and `<Icon>` — display RGBA bitmap tiles from a CPU-side
`ImageAtlas`.

### ImageAtlas

Build an atlas and add images before the render loop:

```zig
const image_atlas_mod = @import("app/image_atlas.zig");

var img_atlas = try image_atlas_mod.ImageAtlas.init(gpa);
defer img_atlas.deinit();

// pixels: []const u8 — RGBA8, row-major, top-to-bottom
// width / height: pixel dimensions
const logo_id = try img_atlas.addImage(pixels, 64, 64);
// logo_id is a u16 ImageId starting at 1; 0 is invalid
```

### Wiring images to elements

```zig
// After scene.instantiate(...):
scene.setImage(image_element_idx, logo_id);

// Optional tint (multiplied per channel, default = white = no tint)
scene.setImageTint(image_element_idx, .{ .r = 255, .g = 80, .b = 80, .a = 255 });
```

### Icons vs. images

`<Icon>` behaves identically to `<Image>` at the API level. By convention, icons are tinted
with the theme text color so they match the surrounding text:

```zig
scene.setImageTint(icon_idx, tokens.text_body);
```

### Available tags

```xml
<Image class="w-16 h-16"/>
<Icon  class="w-6 h-6"/>
```

---

## 12. Text truncation (M4-05 / R44)

Add the `truncate` class to any `Text` element to clip overflowing text with an ellipsis
(`...`). The element **must** have a constrained width, or there is nothing to clip against.

```xml
<Text class="truncate w-48" text="A very long string that won't fit"/>
```

The ellipsis is rendered at the point where the text would exceed `w` pixels, measured using
the glyph atlas. The clipping is purely visual — the full string remains in the element's text
slot.

Pair with `grow` + a flex container to create an auto-sizing truncated label:

```xml
<Row class="gap-2 w-full">
  <Text class="truncate grow" text="{bind label}"/>
  <Text text="✓"/>
</Row>
```

---

## 13. Opacity (M4-06 / R45)

Use Tailwind opacity classes to make an element and its entire subtree partially transparent.
Opacity is **inherited** through the subtree: a child's effective alpha = parent alpha × child
alpha.

### Available classes

| Class | Opacity |
|---|---|
| `opacity-0` | 0% (invisible) |
| `opacity-25` | 25% |
| `opacity-50` | 50% |
| `opacity-75` | 75% |
| `opacity-100` | 100% (default, fully opaque) |

```xml
<!-- Ghost card — everything inside is half-transparent -->
<Card class="opacity-50 p-4">
  <Text text="Dimmed content"/>
  <Button text="Also dimmed"/>
</Card>
```

The alpha multiplier is applied to every `filled_rect`, `border_rect`, `glyph`, and
`image` command emitted for that element and its descendants.

---

## 14. Box shadow (M4-07 / R46)

Box shadows are approximated by emitting 5 concentric filled rectangles behind an element,
with progressively decreasing size and increasing alpha. There is no GPU blur — the effect
is a stepped approximation that works well at typical shadow radii.

### Available classes

| Class | Shadow size |
|---|---|
| `shadow-none` | No shadow |
| `shadow-sm` | Subtle, 2px blur |
| `shadow` | Standard, 4px blur |
| `shadow-md` | Medium, 6px blur |
| `shadow-lg` | Large, 8px blur |
| `shadow-xl` | Extra-large, 16px blur |

```xml
<!-- Elevated card with medium shadow -->
<Card class="shadow-md rounded-lg p-4">
  <Text text="Elevated content"/>
</Card>
```

Shadow commands are emitted **before** the element's background rect so the element draws
on top. Shadow opacity respects the element's accumulated opacity (parent × child).

---

## 16. Text selection (M6-03 / R62)

R62 adds mouse-drag and keyboard selection for both read-only `Text` elements and editable
`Input` elements. Selection is stored as byte offsets in `Scene._selection[]`.

### Selection on read-only Text elements

`Text` elements now support:
- **Mouse drag** — click and drag to select a range; `App.run()` handles this automatically.
- **Keyboard navigation** — while focused, use Left/Right/Home/End (optionally with Shift)
  and Ctrl+A to select all, Ctrl+C to copy.

```zig
// Read current selection on a text element
const sel = scene.selectionOf(text_idx).*;

if (!sel.isEmpty()) {
    const r = sel.range();   // .{ .lo: u32, .hi: u32 } — lo <= hi always
    // r.lo and r.hi are byte offsets into the element's text string
    const text_str = scene.textOf(text_id) orelse "";
    const selected = text_str[r.lo..r.hi];
    std.debug.print("Selected: {s}\n", .{selected});
}

// Set selection programmatically
scene.setSelection(text_idx, anchor_byte, active_byte);  // marks dirty

// Clear selection
scene.clearSelection(text_idx);  // collapses to empty; marks dirty
```

### Selection on Input elements

Input elements already had selection via `Shift` + arrow keys, Ctrl+A, Ctrl+X/C/V.
In R62 these operations now store selection state in `Scene._selection[]` (the
`InputState.selection_start` field was removed). The behavior is unchanged from a user
perspective — the API change is internal.

### `TextSelection` struct

```zig
pub const TextSelection = struct {
    anchor: u32 = 0,  // where the selection started (e.g. mouse-down position)
    active: u32 = 0,  // where the selection currently ends (e.g. mouse-up / arrow key)

    pub fn isEmpty(self: TextSelection) bool;
    // range() always returns {lo, hi} with lo <= hi regardless of drag direction
    pub fn range(self: TextSelection) struct { lo: u32, hi: u32 };
};
```

### Highlight color

The selection highlight uses `tokens.accent` with alpha 80 (out of 255). The renderer
emits a `filled_rect` over each contiguous selected run, between the border and the text
glyphs in the draw list.

---

## 14b. Phase 3 Widgets (M7 Phase 3)

### Date Picker (R78)

Tag: `<DatePicker>`. Displays a date value in an input-style box. Attributes: `value="YYYY-MM-DD"` (initial date), `disabled="true"` (non-interactive).

```xml
<DatePicker value="2025-01-15" class="w-48"/>
```

```zig
// Read the current date
const ds = scene.datePickerStateOf(idx);
const v = scene.getDateValue(idx); // DateValue { year, month, day }

// Set programmatically
scene.setDateValue(idx, .{ .year = 2025, .month = 6, .day = 15 });

// Open / close the popup
scene.openCalendar(idx);
scene.closeCalendar(idx);
```

`DateValue` is `struct { year: u16, month: u8, day: u8 }`.

---

### Avatar + Badge (R7B)

**Avatar** — circular user avatar. Displays either an image or initials with a colored background.

Tag: `<Avatar>`. Attribute: `size="40"` (pixel diameter, default 40), `initials="JD"`.

```xml
<Avatar size="48" initials="AB"/>
```

```zig
// Image mode: set an image from the ImageAtlas
scene.setAvatarImage(avatar_idx, logo_id);

// Initials mode: set two-character initials string
scene.setAvatarInitials(avatar_idx, "JD");

// Access full state
const av = scene.avatarStateOf(idx);
const size_px = av.size_px; // f32
```

Background color is deterministic from the first initial character (4 semantic token colors: accent, ok, warn, err).

**Badge** — small notification badge with text label, typically overlaid on another widget.

Tag: `<Badge>`. No standard attributes; set state after instantiation.

```zig
const bs = scene.badgeStateOf(badge_idx);
// Set text (NUL-terminated, max 8 bytes including NUL)
@memcpy(bs.text[0..2], "3\x00");
bs.color = .error_c; // .default | .success | .warning | .error_c
```

`BadgeColor` values map to semantic tokens: `.default` → `border_strong`, `.success` → `ok`, `.warning` → `warn`, `.error_c` → `err`.

---

### Tooltip (R7C)

Any element can have a tooltip. Set the `tooltip=` attribute in markup, or call `setTooltip` after instantiation.

```xml
<Button text="Save" tooltip="Save changes to disk"/>
<Icon class="w-6 h-6" tooltip="Help"/>
```

```zig
// Set tooltip programmatically (after instantiate)
scene.setTooltip(idx, "Tooltip text"); // text is borrowed — keep it alive

// Read
const tip = scene.tooltipOf(idx); // ?[]const u8

// Tooltip fires automatically after 500 ms hover via TooltipManager in app.zig
// No manual code required when using App.run().
```

---

### Context Menu (R7D)

Register a context menu for a widget. Right-clicking the widget opens the popup.

```zig
const cm_mod = @import("app/context_menu.zig");

// Build items
var items = [_]cm_mod.ContextMenuItem{
    cm_mod.ContextMenuItem.fromSlice("Copy"),
    cm_mod.ContextMenuItem.fromSlice("Paste"),
    .{ .separator = true },
    cm_mod.ContextMenuItem.fromSlice("Delete"),
};

// Register (returns menu_idx: u8; 0xFF if registry is full)
const menu_idx = app._inner.context_menu_manager.register(target_element_idx, &items);

// Wire the menu index to the element
scene.setContextMenuIdx(target_element_idx, menu_idx);

// Right-click is handled automatically by App.run().
// Dismiss manually if needed:
app._inner.context_menu_manager.dismiss(&app._inner.overlay, gpa);
```

Max 16 registered menus (`MAX_REGISTERED_MENUS`). Max 16 items per menu (`MAX_MENU_ITEMS`).

---

### Data Table (R79)

Tag: `<DataTable>`. Virtualized table with column headers, sortable columns, and a data callback.

```xml
<DataTable class="w-full h-200"/>
```

```zig
const comp_mod = @import("07/types.zig");

// Define columns
var cols = [_]comp_mod.DataColumn{
    .{ .header = [_]u8{'N','a','m','e'} ++ [_]u8{0} ** 60, .header_len = 4, .width_px = 200 },
    .{ .header = [_]u8{'A','g','e'}     ++ [_]u8{0} ** 61, .header_len = 3, .width_px = 80  },
};
scene.setTableColumns(table_idx, &cols);

// Provide data via a callback
// row_ptr points to the first element of your row array; row_size is sizeof one element.
// cell_fn receives a pointer to the specific row and writes cell text into buf, returns byte count.
const rows = comp_mod.DataTableRows{
    .row_ptr  = &my_rows[0],
    .row_size = @sizeOf(MyRow),
    .row_count = @intCast(my_rows.len),
    .cell_fn  = myCellFn, // fn(*anyopaque, col: u8, buf: []u8) u8
};
scene.setTableData(table_idx, &rows);

// Sort by column (toggles asc -> desc -> none on repeated calls with same col)
scene.sortTable(table_idx, 0); // sort by column 0

// Access state
const ts = scene.tableStateOf(table_idx);
const sort_col = ts.sort_col;  // 0xFF = unsorted
const sort_dir = ts.sort_dir;  // .none / .asc / .desc
```

Max 16 columns (`MAX_COLUMNS`). Max 1000 rows (`MAX_TABLE_ROWS`). Only visible rows rendered per frame (virtualized).

---

## 17. App-level concerns (Milestone 8 — R80–R83)

### Navigator — screen / navigation model (R80)

`Navigator` provides a stack-based navigation model for multi-screen applications. Import
from `src/app/types.zig` (re-exported from `src/app/navigator.zig`).

```zig
const app_mod = @import("app/types.zig");
const Navigator = app_mod.Navigator;

var nav = Navigator.init(gpa);
defer nav.deinit();

// Register named screens with their builder functions
try nav.register("home", HomeScreen.build);
try nav.register("settings", SettingsScreen.build);

// Push the initial screen and start the frame loop with nav support
try nav.push("home", null, &scene, tokens, &app._inner);
app.runWithNav(&nav);
```

**Deferred navigation** (safe to call from within a button callback, mid-frame):

```zig
// From a callback: request navigation — applied at the start of the next frame
nav.requestPush("settings", null);
nav.requestPop();
nav.requestReplace("home", null);
```

**Direct navigation** (call only outside the frame loop or from `ScreenFn`):

```zig
// Push a screen with a per-screen context pointer
try nav.push("profile", &profile_ctx, &scene, tokens, &app._inner);

// Pop back to the previous screen (returns error.EmptyStack if at depth 1)
try nav.pop(&scene, tokens, &app._inner);

// Replace current screen without adding a history entry
try nav.replace("home", null, &scene, tokens, &app._inner);

// Query the navigator
const name = nav.currentName(); // ?[]const u8
const d = nav.depth();          // usize
```

`ScreenFn` signature — what each registered screen builder must implement:

```zig
pub const ScreenFn = *const fn (
    scene: *Scene,
    tokens: Tokens,
    app: *AppInner,
    ctx: ?*anyopaque,
) anyerror!void;
```

Build steps: `zig build test-nav`

---

### AppState(T) — application state store (R81)

`AppState(T)` is a comptime-generic container for a user-defined struct `T` whose fields
are `Signal` instances (or any type with a `deinit` method). It provides a single source
of truth for data that spans multiple screens. Import from `src/app/types.zig`.

```zig
const signal_mod = @import("app/signal.zig");
const app_mod    = @import("app/types.zig");
const Signal     = signal_mod.Signal;

// 1. Define your state struct
const MyState = struct {
    username: Signal([]const u8),
    count:    Signal(u32),
};

// 2. Initialise — each Signal needs the dirty bitset from a Scene
var state = try app_mod.AppState(MyState).init(gpa, .{
    .username = Signal([]const u8).init(gpa, "", &scene.store().dirty),
    .count    = Signal(u32).init(gpa, 0, &scene.store().dirty),
});
defer state.deinit();  // calls deinit() on every Signal field automatically

// 3. Access and mutate
state.get().count.set(42);
const n = state.get().count.get();  // 42
```

**Passing state to screens via Navigator:**

```zig
const ScreenCtx = struct { state: *app_mod.AppState(MyState) };
var ctx = ScreenCtx{ .state = &state };
try nav.push("home", &ctx, &scene, tokens, &app._inner);

// In the ScreenFn:
const c: *ScreenCtx = @ptrCast(@alignCast(ctx));
const username = c.state.get().username.get();
```

**Optional global singleton pattern:**

```zig
// Register as global (main thread only — no mutex needed per INV-2.1)
state.setGlobal();

// Retrieve from anywhere on the main thread
if (app_mod.AppState(MyState).getGlobal()) |s| {
    s.get().count.set(1);
}
```

Build steps: `zig build test-app-state`

---

### PersistentSettings — key-value store on disk (R82)

`PersistentSettings` reads and writes a small typed key-value store to the platform
user-data directory. The file format is line-oriented text. Import from `src/app/types.zig`.

**Storage paths:**
- Windows: `%APPDATA%\<app_name>\settings.txt`
- Linux: `$XDG_CONFIG_HOME/<app_name>/settings.txt` (falls back to `~/.config/...`)

```zig
const app_mod = @import("app/types.zig");

// Load (creates file + directory if absent)
var prefs = try app_mod.PersistentSettings.load(gpa, "my-app");
defer prefs.deinit();  // does NOT auto-flush; call flush() before deinit if needed

// Read (returns null if key absent or type mismatch)
const w      = prefs.getU32("window_width")  orelse 1280;
const theme  = prefs.getString("theme")      orelse "light";
const muted  = prefs.getBool("muted")        orelse false;
const vol    = prefs.getF32("volume")        orelse 1.0;
const offset = prefs.getI32("scroll_offset") orelse 0;

// Write (in-memory only until flush)
try prefs.setU32("window_width", 1400);
try prefs.setString("theme", "dark");
try prefs.setBool("muted", true);
try prefs.setF32("volume", 0.8);
try prefs.setI32("scroll_offset", -42);

// Remove a key
prefs.remove("old_key");

// Check dirty state
if (prefs.isDirty()) {
    try prefs.flush();  // atomic write (temp file + rename)
}
```

`flush` is a no-op when `isDirty()` is false. The write is atomic: the new content is
written to `<path>.tmp` and then renamed over `<path>`.

Build steps: `zig build test-settings`

---

### MultiWindowApp — multi-window host (R83)

`MultiWindowApp` opens and drives multiple top-level windows from a single frame loop.
All windows share one `VkDevice`, one `GlyphAtlas`, and one `GpuAtlas`. Import from
`src/app/types.zig`.

```zig
const app_mod = @import("app/types.zig");

// Initialise with primary window options
var mw = try app_mod.MultiWindowApp.init(gpa, .{
    .window       = .{ .title = "Primary", .width = 1280, .height = 720 },
    .font_path    = "testdata/DejaVuSans.ttf",
    .font_size_px = 16,
});
defer mw.deinit();

// Open additional windows (share the same GPU device + font atlas)
const sec_id = try mw.openWindow(
    .{ .title = "Inspector", .width = 640, .height = 480 },
    InspectorScreen.build,
    null,  // per-window ctx pointer (optional)
);

// Look up a window by id
if (mw.windowById(sec_id)) |win| {
    _ = win;  // win is a *WindowEntry with .scene, .overlay, .event_queue, etc.
}

// Close a window programmatically (takes effect at the start of the next frame)
mw.closeWindow(sec_id);

// Run — blocks until all windows are closed
mw.run();
```

**`WindowId`** is a `u16` opaque handle. Value `0` is reserved/invalid.

**Shared resources** (do not duplicate): `GlyphAtlas`, `GpuAtlas`, `VkDevice`, `FontFamily`.

**Per-window resources** (each window owns): `Scene`, `VulkanBackend` (surface + swapchain),
`BindingSet`, `OverlayLayer`, `EventQueue`.

`VulkanBackend.initShared` (new in module 01) creates a secondary backend that reuses the
primary device without owning it — `deinit` on a shared backend destroys only its surface
and swapchain.

Build steps: `zig build test-multi-window`

---

## 18. Debug overlay, performance HUD, and developer tools (Milestone 9 — R90–R95)

### Debug overlay (R90)

Press **F1** at runtime to toggle the debug overlay. It draws colored bounding-box borders
over every live scene element and a hover info panel showing the hovered element's computed
rect and style.

- **Hovered element** — accent-colored border (full opacity)
- **Focusable widgets** — info-colored border (button, input, dropdown, …)
- **Containers** — ok-colored border (Row, Column, Card, ScrollView)
- **Other elements** — warn-colored border

The overlay requires no code changes — `App.run()` handles the F1 key automatically.

```zig
// Toggle from code (if you do not use App.run())
app._inner.debug_overlay.toggle();

// Check state
const enabled = app._inner.debug_overlay.isEnabled();

// Produce overlay draw commands (low-level, only when not using App.run())
const overlay_cmds = try app._inner.debug_overlay.buildDebugDrawList(
    alloc, &scene, tokens, font, atlas,
);
defer if (overlay_cmds.len > 0) alloc.free(overlay_cmds);
```

Build steps: no separate step — the overlay is baked into `App.run()`.

---

### Scene dump to stderr (R91)

`Scene.debugPrint()` and `Scene.debugPrintStats()` write diagnostic output to stderr.
No allocation; uses a 256-byte stack buffer per line.

```zig
// Print the full element tree (indented, with rect + style summary per element)
scene.debugPrint();

// Print a one-line summary: live/total/dirty/focused
scene.debugPrintStats();
```

Example output:
```
[0] column x=0.0 y=0.0 w=1280.0 h=720.0  bg=#f9fafb text=#111827  radius=0 font=14px (dirty)
  [1] text "Hello" x=8.0 y=8.0 w=40.0 h=18.0  text=#111827  font=14px
  [2] button "Save" x=8.0 y=32.0 w=80.0 h=36.0  bg=#3b82f6 text=#ffffff  radius=4 font=14px (focused)
Scene: 3 live / 3 total elements, 2 dirty, focused=2
```

---

### Performance counters HUD (R92)

When the debug overlay (F1) is active, a perf HUD panel appears in the top-right corner
showing:
- **frame time** — smoothed over the last 16 frames (milliseconds and FPS)
- **cmds** — draw command count submitted last frame
- **dirty / elements** — dirty bit count vs. live element count

The HUD is updated automatically by `App.run()`. No code required.

```zig
// Access raw counters from code
const c = app._inner.perf_hud.counters;
std.debug.print("frame_ms={d:.2} cmds={d}\n", .{ c.frame_ms, c.cmd_count });

// Smoothed frame time
const smooth = app._inner.perf_hud.smoothFrameMs();
```

---

### Theme live-swap (R93)

Change the active theme at runtime without reinitializing the application or scene.

```zig
// Switch to a custom theme
const mod05 = @import("05/types.zig");
const hc = mod05.Theme.hc_light; // built-in high-contrast light theme
app._inner.setTheme(hc);

// Toggle between light and dark using the current palette
app._inner.toggleTheme();

// Apply a completely new palette (updates _current_palette internally)
const my_palette = mod05.Palette{
    .gray_50 = mod05.Color.hex(0xFFF8F0),
    // ... other fields
};
const warm_theme = mod05.Theme.build(my_palette, .light);
app._inner.setTheme(warm_theme);
```

Built-in themes available as constants on `Theme`:
- `Theme.hc_light` — high-contrast light (R95)
- `Theme.hc_dark` — high-contrast dark (R95)

Build steps: compile only — tested via `zig build`.

---

### Font scaling (R94)

Scale all type sizes up or down uniformly without restarting.

```zig
// Scale to 150% (e.g. for accessibility)
app._inner.setFontScale(1.5);

// Scale back to normal
app._inner.setFontScale(1.0);

// Read current scale
const factor = app._inner.getFontScale(); // f32 in [0.5, 4.0]
```

`setFontScale` clamps the factor to `[0.5, 4.0]`, multiplies all five type-scale token sizes
(`text_xs` through `text_xl`), rebuilds element styles, and marks all elements dirty. The
change takes effect on the next rendered frame.

`Tokens.scaled(factor)` is also available as a standalone helper for computing a scaled token
set without modifying `App` state:

```zig
const scaled_tokens = tokens.scaled(1.25); // 25% larger text everywhere
```

---

### High-contrast themes (R95)

High-contrast themes meet WCAG 2.1 AA requirements. Use them via the `Theme` constants or
build from the high-contrast palettes directly:

```zig
const mod05 = @import("05/types.zig");

// Light high-contrast
app._inner.setTheme(mod05.Theme.hc_light);

// Dark high-contrast
app._inner.setTheme(mod05.Theme.hc_dark);

// Build from palette for custom adjustments
const hcp = mod05.Palette.highContrast(); // or .highContrastDark()
const my_hc = mod05.Theme.build(hcp, .light);
app._inner.setTheme(my_hc);
```

To programmatically check contrast (informational — not enforced by the framework):

```zig
fn contrastRatio(a: mod05.Color, b: mod05.Color) f32 {
    const la = relLuminance(a);
    const lb = relLuminance(b);
    const lighter = @max(la, lb);
    const darker  = @min(la, lb);
    return (lighter + 0.05) / (darker + 0.05);
}
// WCAG AA requires >= 4.5 for normal text, >= 3.0 for large text.
```


---

## 15. Production hardening (Milestone 10)

### Release logging (RA2)

Write all `std.log` output to a rolling file. The file truncates (rolls) when it exceeds
`log_max_bytes`.

```zig
const opts = AppOptions{
    .font_path = "assets/font.ttf",
    .log_path = "logs/app.log",    // create and append; parent dirs auto-created
    .log_max_bytes = 1024 * 1024,  // roll after 1 MiB (default)
};
```

When `log_path` is null (the default), no file is opened and stderr is the only sink.

Log format: `YYYY-MM-DDTHH:MM:SS [level] message`

### Memory budget enforcement (RA1)

Cap the per-screen arena allocator to catch runaway scene builds early.

```zig
const opts = AppOptions{
    .font_path = "assets/font.ttf",
    .arena_budget_bytes = 4 * 1024 * 1024, // 4 MiB limit per screen
};
```

When the budget is exceeded, `error.OutOfMemory` is returned from the scene builder,
a warning is logged, and the error boundary (if enabled) renders the fallback screen.
Default: `0` (unlimited).

### Error boundary (RA0)

Catch errors returned by `ScreenFn` callbacks and display a built-in fallback screen
instead of crashing.

```zig
const opts = AppOptions{
    .font_path = "assets/font.ttf",
    .enable_error_boundary = true,
};
// ...
// Use runWithNav to get boundary-protected navigation:
app.runWithNav(&nav);
```

The fallback screen shows "Something went wrong" and the error name. Panics are NOT
caught (Zig provides no safe user-level panic interception).

### Graceful startup failure (RA3)

Show a native OS dialog when Vulkan is unavailable, instead of crashing to stderr.

```zig
// In your main():
const app = startup_error.initOrDialog(AppInner, AppOptions, gpa, opts) catch |err| {
    // dialog was already shown; err is re-returned for clean exit
    return err;
};
```

On Windows, displays a `MessageBoxW`. On Linux, prints `ERROR: <title>: <message>` to stderr.
Import `startup_error` from `src/app/startup_error.zig`.

### Window state persistence (RA4)

Automatically save and restore window position, size, and maximised state across restarts.

```zig
// Load settings from disk first.
var settings = try PersistentSettings.load(gpa, "myapp");
defer settings.deinit();

const opts = AppOptions{
    .font_path = "assets/font.ttf",
    .persist_window_state = true,
    .persistent_settings = &settings,     // borrowed; must outlive App
    .window_state_key_prefix = "win_",    // default; produces keys: win_x, win_y, win_w, win_h, win_max
};
```

On `init`, saved state is applied (position + size or maximise). On `deinit`, current state
is written and flushed. Has zero overhead when `persist_window_state = false` (the default).

---

## 16. Constraints to respect (abridged)

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
