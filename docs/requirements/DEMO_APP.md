# Demo Application — Requirements

> This document specifies a self-contained demonstration application that exercises every
> major capability of the zig-gui framework in one runnable binary. It is the "show, don't
> tell" proof that the framework works end-to-end.
>
> The application is named **Showcase** and lives at `src/demo/main.zig`.
> It must build and run without any external assets beyond a single `.ttf` font file
> (the same `testdata/DejaVuSans.ttf` already used by the test suite).
>
> **This document is part of the definition of done for every milestone.**
> Updating it is a required step in the implementation workflow (see `docs/AGENT_GUIDE.md §7`).
> When a milestone completes, the implementing agent adds the new feature to the appropriate
> screen below, or adds a new screen if no existing screen fits. Do not leave a completed
> feature undocumented here.
>
> **Read `docs/specs/00_constitution.md` before implementing any part of this.**

---

## 1. Purpose

Showcase is not a toy. It is a living verification that the framework holds together under
real usage. Every screen exercises a specific slice of the API so that a developer looking
at a broken widget can open the corresponding screen, reproduce the problem, and fix it
without grep-searching the codebase.

Secondary goal: be good enough looking that it can be shown to someone who has never seen
the framework and make them want to use it.

---

## 2. Application structure

Showcase is a **multi-screen application** using the Navigator (M8-01). The main window
is 1024 × 768 px. A persistent left sidebar (140 px wide) lists all screens; clicking a
name navigates to it. The content area (884 px wide) fills the remaining space.

```
┌──────────┬───────────────────────────────────────────────────────┐
│ SIDEBAR  │  CONTENT AREA                                         │
│          │                                                        │
│ • Home   │  (active screen renders here)                         │
│ • Text   │                                                        │
│ • Forms  │                                                        │
│ • Data   │                                                        │
│ • Theme  │                                                        │
│ • Notify │                                                        │
│ • Layout │                                                        │
│ • State  │                                                        │
└──────────┴───────────────────────────────────────────────────────┘
```

The sidebar is always visible; it is NOT part of the Navigator stack (it does not reset on
screen changes). The active sidebar item is highlighted with `tokens.accent` background and
`tokens.accent_text` text.

---

## 3. Screens

### Screen 1 — Home

**Purpose:** First impression. Conveys what the framework is in a few sentences.

**Content:**
- Large bold title: `"zig-gui Showcase"`
- Subtitle (`text-muted`): `"A native GUI framework — GPU-rendered, Zig-native, web-familiar syntax"`
- Horizontal separator
- A 3-column card grid (`grid-cols-3 gap-4`) with one card per framework pillar:
  - **Fast** — `"Vulkan-backed GPU rendering. No intermediate DOM. One flat draw-command list per frame."`
  - **Small** — `"Zero runtime deps beyond GLFW + Vulkan. Ships as a single binary."`
  - **Familiar** — `"HTML-like markup. Tailwind-subset classes. Reactive signals."`
- Footer text (`text-muted text-sm`): `"Open a screen from the sidebar to explore each feature."`

**Framework features exercised:** `Card`, `Row`, `Column`, `Text`, `Separator`, grid layout, token-derived styling.

---

### Screen 2 — Text

**Purpose:** Demonstrate all text rendering capabilities.

**Sections (rendered top-to-bottom in a ScrollView):**

#### 2a. Type scale
All five sizes in a vertical list, each showing its class name and rendered at that size:
- `text-xs` — "Extra small — 10 px"
- `text-sm` — "Small — 12 px"
- `text-base` — "Base — 14 px"
- `text-lg` — "Large — 18 px"
- `text-xl` — "Extra large — 24 px"

#### 2b. Font variants
Three rows, same sentence rendered in each variant:
- Regular: `"The quick brown fox jumps over the lazy dog"`
- Bold (`font-bold`): same sentence
- Italic (`font-italic`): same sentence

#### 2c. Text colors
Six rows showing token-named colors:
`text-body`, `text-muted`, `text-disabled` (via inline style), `accent`, `ok`, `err` colors
each with a label on the left and a sample sentence on the right.

#### 2d. Text truncation
A fixed-width container (`w-96`) showing:
- Normal text (no truncation)
- Same text with `truncate` class — ellipsis at the container edge
- A label explaining the class used

#### 2e. Text selection
A read-only paragraph:
> `"Click and drag to select text in this paragraph. You can also use keyboard shortcuts: Shift+Arrow to extend, Ctrl+A to select all, Ctrl+C to copy."`
The element is focusable; selection highlight is visible.

#### 2f. Font fallback
A line containing mixed Latin and emoji characters:
`"Hello 🌍 World 🎉 — fallback glyphs via stb_truetype"`
If the primary font lacks emoji glyphs, U+FFFD is rendered; the line must not crash.

**Framework features exercised:** `Text`, `ScrollView`, font variants, type scale, `truncate`, text selection (M6-03), font fallback (M6-05).

---

### Screen 3 — Forms

**Purpose:** Demonstrate every interactive input widget.

**Layout:** A single centered column (`max-w-lg mx-auto`), two visual sub-sections:

#### 3a. Native widgets
Each widget is labeled above it. In order:

1. **Text input** — label: `"Full name"`, placeholder behavior (initial empty text)
2. **Text input** — label: `"Email address"`
3. **Textarea** — label: `"Notes"`, `h-32`, initial text `"Type here…"`
4. **Dropdown** — label: `"Country"`, options: `["Australia", "Brazil", "Canada", "Germany", "Japan", "United Kingdom", "United States"]`
5. **Checkbox** — label: `"Subscribe to newsletter"`
6. **Radio group** — label: `"Preferred contact"`, options: `["Email", "Phone", "Post"]`
7. **Slider** — label: `"Volume"`, min 0, max 100, step 1, initial 50. A live readout to the right shows the current value as `"50"`
8. **Submit button** — label: `"Submit"`, primary style. On click: shows a success toast `"Form submitted!"`.
9. **Reset button** — label: `"Reset"`, ghost style. On click: clears all fields to their initial values.

A live **summary panel** below the button row (gray card, `text-sm`) reads:
```
Name: <current value>
Email: <current value>
Country: <selected label>
Newsletter: Yes / No
Contact: <selected radio>
Volume: <slider value>
```
Updated reactively on every keystroke / selection change.

#### 3b. Schema-driven form
Below a separator and a heading `"Schema-driven form (module 08)"`:
- A `Form` built from this JSON Schema at compile time (embedded as a string literal):
  ```json
  {
    "type": "object",
    "title": "Product",
    "required": ["name", "price"],
    "properties": {
      "name":        { "type": "string",  "title": "Product name", "minLength": 1 },
      "sku":         { "type": "string",  "title": "SKU" },
      "price":       { "type": "number",  "title": "Price (USD)", "minimum": 0 },
      "in_stock":    { "type": "boolean", "title": "In stock" },
      "category":    { "type": "string",  "title": "Category",
                       "enum": ["Electronics", "Clothing", "Books", "Food"] }
    }
  }
  ```
- A `"Validate"` button. On click: calls `form.validate(alloc)`. If errors exist, shows an
  error toast per field. If none, shows a success toast `"Product is valid"`.

**Framework features exercised:** `Input`, `Textarea`, `Dropdown`, `Checkbox`, `Radio`, `Slider`, `Button`, `Form` (module 08), `ToastManager`, reactive summary via `Signal`, focus model (Tab navigation through all fields).

---

### Screen 4 — Data

**Purpose:** Demonstrate the `DataTable` widget and `ScrollView`.

**Layout:** Two sub-sections separated by a header row with a sort-direction indicator.

#### 4a. Data table
A `DataTable` (`w-full h-300`) with 5 columns and 200 synthetic rows:

| Column | Header | Width |
|---|---|---|
| 0 | `#` | 48 px |
| 1 | `Name` | 220 px |
| 2 | `Department` | 160 px |
| 3 | `Score` | 80 px |
| 4 | `Status` | 100 px |

Row data is generated at startup: names from a fixed 20-word list, departments from 5 options,
score 0–100, status `"Active"` / `"Inactive"`. No file I/O; all data lives in a static array
in `main.zig`.

Clicking a column header sorts ascending → descending → unsorted (cycling). The column header
cell shows `▲` (asc), `▼` (desc), or nothing (unsorted).

A `Text` element above the table reads: `"Showing 200 rows — click a header to sort"`.

#### 4b. Virtualized scroll demo
A `ScrollView` (`h-200`) containing 500 `Text` elements generated with index labels
(`"Row 001"` … `"Row 500"`). A counter above shows: `"500 items in a scroll container"`.
This intentionally stress-tests the draw list with many elements.

**Framework features exercised:** `DataTable` (M7-10), `ScrollView`, `Separator`, sorting, virtualization, large element count.

---

### Screen 5 — Theme

**Purpose:** Demonstrate theme live-swap (M9-04), font scaling (M9-05), and high-contrast (M9-06).

**Layout:** A settings panel on the left (280 px) and a live preview panel on the right.

#### 5a. Settings panel (left)

**Color scheme:**
Three radio buttons: `"Light"` · `"Dark"` · `"High contrast"`.
Selecting one calls `app.setTheme(...)` immediately. The entire application repaints.

**Font size:**
A `Slider` (min 0.75, max 2.0, step 0.25, initial 1.0).
A live readout shows `"1.0×"`. Changing the slider calls `app.setFontScale(value)`.
Four preset buttons in a row: `"S"` (0.75), `"M"` (1.0), `"L"` (1.5), `"XL"` (2.0).

**Debug overlay:**
A `Checkbox` labeled `"Show debug overlay (F1)"`. Toggling it calls the same path as the
F1 hotkey. The checkbox state stays in sync with `app.debug_overlay.enabled`.

**Performance counters:**
Two read-only `Text` elements updated once per second:
- `"Frame: <smoothed_ms> ms  (<fps> fps)"`
- `"Draw cmds: <count>  Dirty: <count>"`

(Values read from `app.perf_hud.counters`.)

#### 5b. Live preview panel (right)
A card containing a sampler of every token role, so the developer can see the effect of a
theme change immediately:

- Background swatches: `bg_canvas`, `bg_surface`, `bg_raised` — three colored boxes with labels
- Text colors: body / muted / disabled — three sample strings
- Accent: a primary `Button` and a ghost `Button`
- Status: four small pills in `ok`, `warn`, `err`, `info` colors with labels
- An `Input` showing focus ring behavior
- A `Checkbox` (checked) and a `Dropdown` (closed)

Every element in the preview panel derives its colors from `Tokens` (no inline hex), so it
responds automatically when the theme changes.

**Framework features exercised:** Theme live-swap (M9-04), font scaling (M9-05), high-contrast palette (M9-06), debug overlay toggle (M9-01), performance counter display (M9-03), `Radio`, `Slider`, `Checkbox`.

---

### Screen 6 — Notifications

**Purpose:** Demonstrate `ToastManager`, `DialogManager`, and `Tooltip`.

**Layout:** A centered column of trigger buttons.

#### 6a. Toast triggers
Four buttons in a `Row`, one per `ToastKind`:
- `"Info toast"` → `toasts.show("This is an info message", .info, 3000, now)`
- `"Success toast"` → `toasts.show("Operation completed", .success, 3000, now)`
- `"Warning toast"` → `toasts.show("Low disk space", .warning, 5000, now)`
- `"Error toast"` → `toasts.show("Connection failed", .@"error", 5000, now)`

A fifth button: `"Flood (4×)"` — shows all four at once, filling the 4-toast limit.

#### 6b. Modal dialog
A button `"Open modal dialog"`.
On click: opens a `DialogManager` panel with:
- Title: `"Confirm action"`
- Body: `"This is a modal dialog. Focus is trapped inside. Press Escape or click a button to close."`
- Two buttons: `"Cancel"` (closes dialog) and `"Confirm"` (shows a success toast then closes).

While the dialog is open, clicking outside it does nothing (backdrop absorbs clicks).
Tab navigation cycles only within the dialog's two buttons.

#### 6c. Tooltips
A row of icon-like buttons (colored squares 32×32) each with a different `tooltip=` attribute:
`"Copy"`, `"Cut"`, `"Paste"`, `"Delete"`, `"Settings"`.
Hovering for 500 ms reveals the tooltip. Moving the cursor away dismisses it.

**Framework features exercised:** `ToastManager` (R74), `DialogManager` (R75), `Tooltip` (M7-13), `OverlayLayer`.

---

### Screen 7 — Layout

**Purpose:** Demonstrate the layout engine: flexbox, grid, opacity, shadow.

**Layout:** Five labeled sections in a `ScrollView`.

#### 7a. Flex row + alignment
A row of 5 colored boxes (`w-16 h-16`) inside a `Row` with `justify-between`. Controls:
- A `Dropdown` for `align-items`: `start` / `center` / `end` / `stretch`.
  Selecting changes the class on the row container and re-instantiates the subtree.
- A `Checkbox` `"gap-4"` — adds/removes the gap class.

#### 7b. Flex column + grow/shrink
Three boxes in a `Column`. The middle box has `grow` applied. A label explains:
`"Middle box grows to fill remaining height (flex-grow: 1)"`.

#### 7c. Grid layout
A `grid-cols-4 gap-2` grid with 12 boxes. One box spans `col-span-2`.
A label: `"12 items in a 4-column grid — item 5 spans 2 columns"`.

#### 7d. Opacity
Five identical cards shown at `opacity-100`, `opacity-75`, `opacity-50`, `opacity-25`,
`opacity-0` (the last is invisible but its space is preserved).
Labels show the opacity value.

#### 7e. Box shadow
Four cards demonstrating `shadow-sm`, `shadow`, `shadow-md`, `shadow-lg`.
Each card contains a label with the class name.

**Framework features exercised:** Flexbox, grid, `col-span`, opacity (M4-06), box shadow (M4-07), dynamic class changes via scene reset, `Dropdown` for live control.

---

### Screen 8 — State

**Purpose:** Demonstrate signals, computed signals, conditional rendering, and list rendering.

**Layout:** Three independent demos stacked vertically in a `ScrollView`.

#### 8a. Counter
Two buttons `"−"` and `"+"` flank a large centered number.
- Clicking `"+"` increments a `Signal(i32)`. Clicking `"−"` decrements.
- The number display is bound to a `Computed([]const u8)` that formats the integer.
- A label below shows `"Even"` or `"Odd"` — driven by a second `Computed(bool)`.
- The `"−"` button is disabled when the value reaches 0 (demonstrated via `PseudoState.disabled`).

#### 8b. Conditional rendering
A `Checkbox` labeled `"Show detail panel"`.
When checked, a detail card appears below it (using `if="{bind show_detail}"`).
When unchecked, the card is hidden. The transition is immediate (no animation in v1).
The card contains: `"This element is conditionally rendered via if= binding."`.

#### 8c. List rendering
An `Input` labeled `"Add item"` + an `"Add"` button.
Clicking `"Add"` appends the input text to a `Signal([]Item)` (max 20 items).
The list is rendered via `for=` binding, one row per item.
Each row shows the item text and a `"×"` button that removes it.
A label above shows `"N items"` (updated reactively).
An empty-state message `"No items yet — add one above"` is shown when the list is empty
(conditional rendering wrapping the list container).

**Framework features exercised:** `Signal(T)`, `Computed(T)`, `BindingSet`, conditional rendering (M5-03), list rendering (M5-04), `Signal.set` → dirty → repaint cycle.

---

## 4. Persistent sidebar

The sidebar is a `Column` (`w-36 bg-surface`) with one `Button` per screen in ghost style.
The active screen's button uses inline `style:background` set to `tokens.accent` and
`style:color` set to `tokens.accent_text`.

Navigation happens through `Navigator.requestPush(name, null)`. The sidebar buttons
set the request; the next frame applies it.

The sidebar is instantiated once at startup and never reset. It is a sibling of the content
`ScrollView` inside the root `Row`.

---

## 5. Global behaviors

### Theme hotkey
`F2` cycles through the three themes: Light → Dark → High-contrast → Light.
This is registered as a global key handler in `dispatchEvents` (same pattern as F1 for the
debug overlay).

### Debug overlay
`F1` toggles the debug overlay (M9-01). This works on every screen.

### Window title
The window title is `"zig-gui Showcase — <Screen Name>"`.
It is updated via `glfwSetWindowTitle` each time `Navigator.push` is called.

### Font
`AppOptions.font_path = "testdata/DejaVuSans.ttf"`.
`AppOptions.bold_font_path = "testdata/DejaVuSans-Bold.ttf"` (if the file exists; falls back
to regular).
`AppOptions.font_size_px = 14`.

---

## 6. File layout

```
src/demo/
  main.zig           — App.init, Navigator setup, sidebar, App.runWithNav
  screens/
    home.zig         — Screen 1 ScreenFn
    text.zig         — Screen 2 ScreenFn
    forms.zig        — Screen 3 ScreenFn + FormState struct
    data.zig         — Screen 4 ScreenFn + row data generation
    theme.zig        — Screen 5 ScreenFn
    notifications.zig — Screen 6 ScreenFn
    layout.zig       — Screen 7 ScreenFn
    state.zig        — Screen 8 ScreenFn + counter/list state
  shared/
    sidebar.zig      — buildSidebar(scene, tokens, active_screen) ScreenFn-compatible helper
    row_data.zig     — deterministic fake data generation (no file I/O)
```

Build step in `build.zig`:

```zig
const demo = b.addExecutable(.{
    .name = "showcase",
    .root_source_file = b.path("src/demo/main.zig"),
    .target = target,
    .optimize = optimize,
});
// imports same as the app layer
b.installArtifact(demo);
const run_demo = b.addRunArtifact(demo);
const run_step = b.step("run-demo", "Run the Showcase demo application");
run_step.dependOn(&run_demo.step);
```

Run with: `zig build run-demo`

---

## 7. State ownership

Each screen owns its own state struct. The struct is stack-allocated in `main.zig` and
passed through `ctx: ?*anyopaque` to the screen's `ScreenFn`. Screens do NOT heap-allocate
their state. The Navigator does not own state structs.

```zig
// In main.zig:
var forms_state = FormsState.init();
var state_state = StateScreenState.init(gpa);
defer state_state.deinit();

try nav.register("forms", FormsScreen.build);
try nav.push("forms", &forms_state, &scene, tokens, app);
```

Global state that survives screen transitions (theme choice, font scale) lives in a small
`GlobalState` struct passed as part of every screen's `ctx` alongside the per-screen state:

```zig
pub const GlobalState = struct {
    theme_idx: u8 = 0,     // 0=light, 1=dark, 2=high-contrast
    font_scale: f32 = 1.0,
};
```

---

## 8. Milestone 8: App-level concerns

### M8-01 Screen Navigation
Navigator demo: the Showcase application itself is the primary demonstration. The persistent
left sidebar calls `nav.requestPush("home")`, `nav.requestPush("forms")`, etc. on each button
click. Navigating between all 8 screens exercises push, replace, and deferred navigation.
For an isolated Navigator smoke test, Screen 8 (State) has a "Go to Forms" shortcut button
that calls `nav.requestPush("forms", null)` and a hypothetical "Back" button that calls
`nav.requestPop()`, demonstrating push/pop/replace and stack depth display.

### M8-02 Application State Store
AppState demo: a `GlobalState` struct (theme index, font scale) is wrapped in
`AppState(GlobalState)` and passed as part of every screen's `ctx`. The Theme screen (Screen 5)
reads and writes `global.get().theme_idx` and `global.get().font_scale`. Both fields update
reactively across all screens when changed, demonstrating a global signal tree shared between
screens via the `ctx` argument.

### M8-03 Persistent Settings
Settings screen (Screen 5) saves the current theme index and font scale to disk via
`PersistentSettings.setU32("theme_idx", ...)` and `PersistentSettings.setF32("font_scale", ...)`
on each change, then calls `prefs.flush()`. Values are reloaded on the next launch from
`%APPDATA%\showcase\settings.txt` (Windows) or `~/.config/showcase/settings.txt` (Linux),
so the user's last theme and font-scale choice are remembered between runs.

### M8-04 Multi-window
An "Open Inspector" button on Screen 5 (Theme) opens a secondary window via
`MultiWindowApp.openWindow` that shares the same GPU device and font atlas as the primary
window. The inspector window displays the current token palette (background swatches, text
colors, accent) and updates when the theme is changed in the primary window, demonstrating
cross-window shared atlas and token access.

---

## 9. Non-goals (DO NOT implement)

- NO network requests, file I/O beyond font + settings files, or OS APIs beyond what the
  framework provides. All data is synthetic.
- NO custom widget kinds — use only the framework's existing widget set.
- NO polished icon assets — colored rectangles substitute for icons throughout.
- NO release packaging — `zig build run-demo` is the only required entry point.

---

## 10. Acceptance criteria

The demo is done when:

1. `zig build run-demo` compiles and launches a 1024×768 window with no Vulkan errors.
2. All 8 screens are reachable via the sidebar without crashing.
3. Screen 3 (Forms): Tab cycles through all inputs in document order; the summary panel
   updates on every change; the schema form validates correctly.
4. Screen 4 (Data): the 200-row table renders and sorting works for all 5 columns.
5. Screen 5 (Theme): switching between Light / Dark / High-contrast immediately repaints
   the entire window including the sidebar.
6. Screen 6 (Notifications): all four toast kinds appear and auto-dismiss; the modal traps
   focus; tooltips appear after 500 ms hover.
7. Screen 7 (Layout): the flex alignment dropdown changes the layout without crashing.
8. Screen 8 (State): adding and removing list items updates the `"N items"` counter and
   the empty-state message reactively.
9. F1 toggles the debug overlay on every screen; F2 cycles themes globally.
10. No memory leaks detected when running with `std.heap.GeneralPurposeAllocator(.{ .safety = true })`.
