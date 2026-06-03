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

**Available tags (M3 — 9 kinds):** `Text`, `Button`, `Input`, `Card`, `Row`, `Column`, `Dropdown`, `Checkbox`, `ScrollView`

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

# Required env var (or pass -Dvulkan_sdk=<path>)
# $env:VULKAN_SDK = "C:\VulkanSDK\1.x.y.z"
```

---

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

Keyboard focus cycles through all focusable widgets (button, input, dropdown, checkbox)
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

## 15. Constraints to respect (abridged)

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
