# Glossary

> **INV-5.5**: Every term used in this project comes from this file. Do not invent synonyms.
> If a needed concept has no entry here, add one before using the term.

---

## Signal(T)

A reactive value container defined in `src/app/signal.zig`. Holds one value of type `T`.
Writing a new value through `set()` immediately marks all subscribed element indices dirty
in the `ElementStore.dirty` bitset. A Signal does NOT push values and does NOT run callbacks
as a change-propagation path (INV-3.3). The dirty bitset is the sole propagation mechanism.

See: R20 (M2-01), `src/app/signal.zig`.

---

## Computed(T)

A derived signal whose value is a pure function of one or more upstream `Signal(T)` instances.
Defined in `src/app/signal.zig`. Caches the last result and recomputes lazily — only when
an upstream `Signal.set()` has fired since the last `get()`. Like `Signal(T)`, it marks
subscribed element indices dirty when it recomputes, so the dirty scan picks it up automatically.

See: R22 (M2-03), `src/app/signal.zig`.

---

## StaleFn

A type-erased callback struct (`ptr: *anyopaque`, `mark: *const fn(*anyopaque) void`) used
by `Signal(T).set()` to notify downstream `Computed(T)` instances that their cached value is
stale. `StaleFn.mark` only sets a boolean flag (`Computed.stale = true`) — it does NOT push
a value, does NOT run layout or paint code, and does NOT violate INV-3.3. The stale flag
defers the recompute to the next `Computed.get()` call.

See: R20 (M2-01), R22 (M2-03), `src/app/signal.zig`.

---

## BindingSet

A collection of all active data bindings for a static screen. Lives as a field on `App`.
Currently supports only `TextBinding` entries (M2-04). Established once after
`Scene.instantiate()` and before `App.run()`. `BindingSet.refresh()` copies current signal
values into Scene parallel arrays before each dirty frame.

See: R23 (M2-04), `src/app/binding.zig`.

---

## REPLACEMENT_CODEPOINT

Unicode codepoint U+FFFD (REPLACEMENT CHARACTER) used by `layoutParagraphEx` when no font
in the fallback chain covers a requested codepoint. If U+FFFD itself is also absent from
every font in the chain, the glyph is silently skipped. Defined as
`text.REPLACEMENT_CODEPOINT: u21 = 0xFFFD` in `src/02/types.zig`.

See: R64 (M6-05), `src/02/types.zig`.

---

## TextBinding

A registered connection between one `Signal([]const u8)` and one element index. Stores a
type-erased pointer to the signal and a comptime-generated `read_fn` for zero-overhead
string reading in `BindingSet.refresh()`. Created by `BindingSet.bindText()`.

See: R23 (M2-04), `src/app/binding.zig`.

---

## dirty bitset scan

The per-frame reactivity mechanism (INV-3.3). Each element has one bit in
`ElementStore.dirty`. `Signal.set()` marks subscriber element indices dirty. Each frame,
`ElementStore.hasDirty()` checks whether any bit is set. If no bits are set, the frame is
skipped and the thread blocks via `Platform.waitEvents()`. If any bits are set, the full
layout + paint pipeline runs over all elements. After `endFrame()`, all dirty bits are
cleared. Incremental subtree layout is post-v1.

See: R21 (M2-02), `docs/specs/03.types.zig`, `src/app/app.zig`.

---

## subscribers

The list of element indices registered with a `Signal(T)` or `Computed(T)`. When the signal
produces a new value (via `set()` for Signal, or via recompute in `get()` for Computed),
every subscribed element index is marked dirty in `ElementStore.dirty`. Stored as
`std.ArrayListUnmanaged(u32)` inside the signal.

See: R20 (M2-01), `src/app/signal.zig`.

---

## stale

The boolean flag (`Computed.stale`) that records whether any upstream `Signal` has changed
since the last `Computed.get()` call. Initialized to `true` so the first `get()` always
runs the compute function. Set to `true` by `StaleFn.mark` (called from `Signal.set()`).
Set to `false` inside `Computed.get()` after a successful recompute.

See: R22 (M2-03), `src/app/signal.zig`.

---

## focus ring

A visible border drawn around the element that currently has keyboard focus. The color is
defined by the named constant `FOCUS_RING_COLOR` (defined in `src/07/types.zig`) — never as a
hex literal (INV-4.3). Prior to M4-01 (R40), a hardcoded 2px `BorderRect` was emitted by
`buildDrawList`. After M4-01, the focus ring is driven by the `focus.border_color` and
`focus.border_width` fields of each widget kind's `PseudoStyleSet` (e.g. `buttonPseudo`,
`inputPseudo`), resolved through `resolveStyle`. The hardcoded ring drawing code is removed in
M4-01. The ring is the primary keyboard-navigation affordance (R30).

See: R30, R40 (M4-01), `src/07/types.zig` `FOCUS_RING_COLOR`, `src/09/types.zig` `resolveStyle`.

---

## focused element

The element that currently receives keyboard events. Identified by `Scene.focused_idx` (a
raw element index, `std.math.maxInt(u32)` when no element is focused). Changed via
`Scene.setFocus(idx)`, which also deactivates the previous input widget, closes the previous
dropdown, and marks affected elements dirty. Keyboard Tab/Shift+Tab cycles through
`Scene.focusable_indices` (R30).

See: R30, `src/07/types.zig` `Scene.setFocus`, `src/app/app.zig`.

---

## CallbackFn

A type-erased callback struct (`ptr: *anyopaque`, `call: *const fn(*anyopaque) void`) used
to fire application code when a button is activated. Stored in `ButtonState.on_click` and
copied into `Scene._queued_callbacks` during event dispatch. The queue is drained by
`Scene.fireQueuedCallbacks()`, called once per frame after layout and before rendering
(INV-3.3: callbacks are NOT a reactivity path — they do not mark dirty bits or drive layout).

See: R31, `src/07/types.zig`, `src/app/app.zig`.

---

## pseudo-state

A transient visual modifier applied to an interactive widget based on its current interaction
state: `hovered` (cursor is over the widget), `pressed`/`active` (mouse button held down over
the widget), `focus` (element has keyboard focus), or `disabled`. Prior to M4-01 (R40),
pseudo-states were stored only in per-kind state structs (`ButtonState`, `CheckboxState`) as
boolean fields, and the renderer emitted overlay `FilledRect` commands that darkened (pressed)
or lightened (hovered) the widget's base style. After M4-01, pseudo-states are unified into
the `PseudoState` packed struct stored in `Scene._pseudo`, and style overrides are resolved
through `PseudoStyleSet` via `resolveStyle`. The per-kind state structs remain the authoritative
source but are synced to `PseudoState` after each update.

See: R31, R34, R40 (M4-01), `src/07/types.zig` `ButtonState` / `CheckboxState` / `PseudoState`,
`src/09/types.zig` `resolveStyle`.

---

## overlay

A draw command (or set of draw commands) that renders on top of all normal-layer elements.
Prior to M4-02 (R41), implemented as a hardcoded second pass inside `buildDrawList` for
dropdown option lists (R33). After M4-02, a formal `OverlayLayer` struct owned by `App`
collects `OverlaySlot` entries from any consumer (dropdown, tooltip, modal). Its `flatten()`
output is concatenated after the main `buildDrawList` commands before submission to
`VulkanBackend.drawFrame`. Overlay slots paint unclipped (no scissor from scrollviews).

See: R33, R41 (M4-02), `src/09/types.zig` `buildDrawList`, `src/app/overlay.zig` `OverlayLayer`.

---

## checkbox

A boolean toggle widget (`WidgetKind.checkbox`). Stores state in `CheckboxState` (checked,
hovered, pressed, disabled). Toggled by a left-click or Space/Enter key press when focused.
Rendered as a bordered box with a filled inner rect when checked. Focusable (included in
`Scene.focusable_indices`, B2). Tag in markup: `"Checkbox"`.

See: R34, `src/07/types.zig` `CheckboxState`, `src/09/types.zig`.

---

## scrollview

A clipping container widget (`WidgetKind.scrollview`). Stores scroll position and content
dimensions in `ScrollState`. Children overflow the visible area; the renderer clips child
content and draws a vertical scrollbar track and thumb when `content_height > container_height`.
Tag in markup: `"ScrollView"`. Default layout: `{ .display = .block, .overflow = .hidden }`.

See: R35, `src/07/types.zig` `ScrollState`, `src/09/types.zig`.

---

## PseudoState

A packed struct (`src/07/types.zig`) holding four boolean flags — `hover`, `focus`, `active`, `disabled` — that describe the current interaction state of one element. Stored in `Scene._pseudo`, a parallel array indexed by element index. All flags default to `false`. A `PseudoState` is kept in a single byte (packed struct) with no padding overhead. Updated by the input handler after each widget state change; always synced to `Scene.dirty` via `Scene.setPseudo`.

See: R40 (M4-01), `src/07/types.zig` `Scene.pseudoOf`, `Scene.setPseudo`.

---

## PseudoOverride

A struct (`src/05/types.zig`) holding optional style-field overrides applied when a widget is in a specific pseudo-state. All fields are `?T` (nullable); a `null` field means "inherit from base style." The five overrideable fields are `background`, `text_color`, `border_color`, `border_width`, and `radius`. All non-null values must be sourced from `Tokens` (INV-4.3).

See: R40 (M4-01), `src/05/types.zig` `PseudoStyleSet`.

---

## PseudoStyleSet

A struct (`src/05/types.zig`) bundling four `PseudoOverride` entries — one each for `hover`, `focus`, `active`, and `disabled`. Built by per-kind builder functions (`buttonPseudo`, `inputPseudo`, `dropdownPseudo`, `checkboxPseudo`) which derive all values from `Tokens` (INV-4.3). Passed to `resolveStyle` in the renderer to apply the correct override layer for each element.

See: R40 (M4-01), `src/05/types.zig` `buttonPseudo`, `src/09/types.zig` `resolveStyle`.

---

## OverlayLayer

An ordered list of `OverlaySlot` entries owned by `App`. Slots are accumulated before the frame draw call and flattened into a single `[]DrawCommand` slice by `OverlayLayer.flatten()`. The flattened overlay commands are appended after the main-layer commands from `buildDrawList` before being submitted to `VulkanBackend.drawFrame`, so overlay content is always rendered on top (painter's algorithm). Lives in `src/app/overlay.zig`.

See: R41 (M4-02), `src/app/overlay.zig`.

---

## OverlaySlot

A named region owned by a single overlay consumer (e.g. a dropdown, a tooltip). Identified by an `OverlayId` (`u16`). Carries a `[]DrawCommand` slice built by the consumer each frame. Slots are rendered in insertion order (first allocated = lowest z). The `OverlayLayer` does NOT free the command slices — the caller owns them.

See: R41 (M4-02), `src/app/overlay.zig` `OverlayLayer.setSlot`.

---

## OverlayId

A `u16` opaque handle identifying one `OverlaySlot` in an `OverlayLayer`. Allocated once per consumer via `OverlayLayer.allocId()`. IDs are monotonically increasing within the lifetime of an `OverlayLayer`; they are not reused after `removeSlot`.

See: R41 (M4-02), `src/app/overlay.zig`.

---

## ScissorRect

An integer pixel rectangle (`x: i32, y: i32, w: u32, h: u32`) used as the argument to `vkCmdSetScissor`. Origin is top-left; right and bottom edges are exclusive. Used by the `set_scissor` draw command and `intersectScissor`. Converted from float layout `Rect` via `rectToScissor`.

See: R42 (M4-03), `src/09/types.zig` `DrawCommand.set_scissor`, `intersectScissor`, `rectToScissor`.

---

## scissor stack

A fixed-depth array (`max depth 8`) of `ScissorRect` values maintained by `VulkanBackend.drawFrame` while processing the draw-command list. Each `set_scissor` command pushes the current scissor and installs a new one (intersected with the current); each `restore_scissor` command pops the previous value. The full-viewport scissor is pre-loaded at frame start. Nested scrollviews are supported up to depth 8 (non-goal per R35 but handled correctly if they occur).

See: R42 (M4-03), `src/01/types.zig` `VulkanBackend.drawFrame`.

---

## ImageAtlas

A CPU-side RGBA8 texture atlas (`src/app/image_atlas.zig`). Stores pre-rasterized RGBA bitmaps packed with a shelf algorithm into a single 512x512 bitmap. Images are identified by `ImageId`. The `generation` counter increments on each mutation, signalling `GpuImageAtlas` to re-upload. `addImage` accepts raw packed RGBA pixel data; file I/O is the caller's responsibility (INV-5.6: no `stb_image` dependency).

See: R43 (M4-04), `src/app/image_atlas.zig`.

---

## ImageId

A `u16` opaque handle identifying one image within an `ImageAtlas`. Value `0` is reserved as "invalid/not set." Returned by `ImageAtlas.addImage`. Stored in `Scene._image_state` as part of `ImageState`.

See: R43 (M4-04), `src/app/image_atlas.zig`.

---

## GpuImageAtlas

The GPU-side representation of an `ImageAtlas`. Owns a `VK_FORMAT_R8G8B8A8_SRGB` `VkImage`, `VkImageView`, `VkSampler`, and `VkDeviceMemory`. Uploaded via a staging buffer using the same pattern as `GpuAtlas`. Bound to descriptor set binding 1 in the quad pipeline (binding 0 is the glyph atlas). Re-uploaded when `ImageAtlas.generation` changes.

See: R43 (M4-04), `src/09/types.zig` `GpuImageAtlas`.

---

## opacity

A `f32` field on `ComputedStyle` (range `[0.0, 1.0]`, default `1.0`) that scales the alpha channel of every draw command emitted for an element and its children. Opacity is inherited through the DFS walk by multiplying the parent's effective alpha into the child's alpha accumulator. Set by `opacity-{0,25,50,75,100}` Tailwind classes. Implemented as CPU alpha pre-multiplication in `buildDrawList`; no GPU compositing layer is used.

See: R45 (M4-06), `src/05/types.zig` `ComputedStyle.opacity`, `src/09/types.zig` `applyOpacity`.

---

## box shadow

A single-level drop shadow rendered as `N=5` concentric `filled_rect` commands drawn behind an element's background. Approximates Gaussian blur without GPU compute. Parameters (`shadow_blur`, `shadow_offset_x`, `shadow_offset_y`, `shadow_color`) are stored on `ComputedStyle`. Enabled by `shadow-{sm,md,lg,xl}` Tailwind classes. Shadow rects are emitted before the element's background rect in `buildDrawList` (painter's algorithm ensures shadow is behind element).

See: R46 (M4-07), `src/05/types.zig` `ComputedStyle.shadow_blur`, `src/09/types.zig` `emitShadow`.

---

## parseHexColor

A public helper function in `src/06/types.zig` (R50). Parses a `#RRGGBB` or `#RRGGBBAA` hex
color string into a `theme.Color`. Returns `null` if the string is not a valid hex color
(wrong length, non-hex digits, missing `#` prefix). Allocation-free; operates on the input
slice directly. Used by `applyInlineStyle` in module 07 to resolve `style:color`,
`style:background`, and `style:border-color` inline attributes.

See: R50 (M5-01), `src/06/types.zig`.

---

## parseFloat

A public helper function in `src/06/types.zig` (R50). Parses a decimal float string (e.g.
`"12"`, `"1.5"`) into an `f32`. Returns `null` on parse failure. Thin wrapper over
`std.fmt.parseFloat`. Used by `applyInlineStyle` in module 07 to resolve numeric inline style
attributes such as `style:radius`, `style:font-size`, `style:border-width`, `style:opacity`.

See: R50 (M5-01), `src/06/types.zig`.

---

## AlignSelf

An enum added to `src/03/types.zig` (R51) with variants `auto`, `start`, `center`, `end`,
`stretch`. A new field `align_self: AlignSelf = .auto` on `LayoutNode` allows a flex child
to override its parent's `align_items` setting for its own cross-axis placement. `.auto` means
"use the parent's `align_items` value." Set by Tailwind classes `self-auto`, `self-start`,
`self-center`, `self-end`, `self-stretch`.

See: R51 (M5-02), `src/03/types.zig`.

---

## MarginValue

A tagged union added to `src/03/types.zig` (R51). Variants: `zero` (0 px, the default),
`px: f32` (fixed pixel margin), `auto` (fill remaining space — used for `mx-auto` centering).
Replaces the flat `f32` margin fields previously in `Insets`. Used as the type of each field
in `Margin`.

See: R51 (M5-02), `src/03/types.zig`.

---

## Margin

A struct added to `src/03/types.zig` (R51) with four `MarginValue` fields: `top`, `right`,
`bottom`, `left`, all defaulting to `.zero`. Replaces `margin: Insets` on `LayoutNode`.
Supports `auto` margins for horizontal centering (`mx-auto`) in addition to fixed-pixel and
zero margins.

See: R51 (M5-02), `src/03/types.zig`.

---

## CondBinding

A struct in `src/app/binding.zig` (R52) representing a registered connection between one
`Signal(bool)` field and one element index. When the signal is `true` the element is shown;
when `false` the element is hidden (`setHidden(idx, true)`). Stored in `BindingSet.cond`
(a parallel array alongside `BindingSet.text`). Created by `BindingSet.bindCond()`, which
enforces at compile time that the bound field is exactly `Signal(bool)`.

See: R52 (M5-03), `src/app/binding.zig`.

---

## ListBinding

A struct in `src/app/binding.zig` (R53) representing a registered `for=` binding between a
`Signal([]T)` field and a container element. Stores the container element index, a `NodeDesc`
template for one item, type-erased signal pointer, and a `refresh_fn` closure that
re-instantiates the child subtree when the signal's version changes. Created by
`BindingSet.bindList()`. On each `BindingSet.refresh()` call, if the signal version has
changed, the container's children are cleared (`Scene.removeChildren`) and one subtree per
item is instantiated (`Scene.instantiateUnder`).

See: R53 (M5-04), `src/app/binding.zig`.

---

## SourceLoc

A struct in `src/06/types.zig` (R54) carrying a 1-based line and column number within a
`.ui` source file. Used inside `ParseDiagnostic` to point the developer to the exact
character position of a parse error. Column is a byte offset from the line start, not a
Unicode code-point count (Latin+Cyrillic scope, INV-1.3).

See: R54 (M5-05), `src/06/types.zig`.

---

## ParseDiagnostic

A struct in `src/06/types.zig` (R54) emitted by `parse` on failure. Contains a `ParseError`
variant (`err`), a `SourceLoc` (`loc`), and a static `message: []const u8` string literal.
No heap allocation is required; the message is always a string literal. Passed as an optional
out-parameter (`?*ParseDiagnostic`) to `parse`; callers that do not need location info pass
`null`. The hot-reload path and the codegen tool both log the diagnostic to stderr.

See: R54 (M5-05), `src/06/types.zig`.

---

## FileWatcher

A struct in `src/app/file_watcher.zig` (R56, hot-reload only). Holds a list of `WatchEntry`
items and a list of changed entry indices since the last `poll()`. `poll()` stats each watched
file and records those whose mtime has advanced. `drainChanged()` returns the changed-index
slice and resets it for the next poll. Present in the binary only when `-Dhot-reload=true` is
set; compiled out in production builds.

See: R56 (M5-07), `src/app/file_watcher.zig`.

---

## WatchEntry

A struct in `src/app/file_watcher.zig` (R56, hot-reload only). Stores the null-terminated
path of a watched `.ui` file and the nanosecond-precision mtime (`i128`) as seen on the last
`FileWatcher.poll()` call. When `poll()` sees a newer mtime, the entry's index is appended to
`FileWatcher.changed`.

See: R56 (M5-07), `src/app/file_watcher.zig`.

---

## FontVariant

An `enum(u8) { regular, bold, italic }` discriminant stored in `GlyphKey.variant` and `Font.variant`.
Ensures glyphs from different font faces (regular vs bold vs italic) occupy distinct atlas cache entries
even when sharing the same codepoint and pixel size. Set at `FontFamily.init` time; never changed after.

See: R60, `src/02/types.zig`, `src/app/font_family.zig`.

---

## FontFamily

A three-slot font container (regular, bold, italic) defined in `src/app/font_family.zig`.
Owns up to three `Font` instances initialised from TTF bytes. `face(bold, italic)` returns a `*Font`
pointer to the best-matching slot with fallback to regular when a variant is absent.
Bold+italic falls back to bold (no synthesised bold-italic). Each slot's `Font.variant` is fixed
at init time so `layoutParagraph` can construct correct atlas keys without a signature change.

See: R60, `src/app/font_family.zig`.

---

## TextSelection

A byte-offset selection range stored in the `Scene._selection` parallel array (R62).
Contains `anchor` (where the drag/selection started) and `active` (where it currently ends).
When `anchor == active`, the selection is collapsed (no visible highlight).
`isEmpty()` returns true for a collapsed selection; `range()` returns a normalised
`{lo, hi}` struct where `lo <= hi`. Used for both read-only `.text` elements (mouse
drag to select) and editable `.input` elements (replaces `InputState.selection_start`).
Selection highlight is rendered by the R62 block in `buildDrawList` as `filled_rect`
commands using `tokens.accent` with `a = 80`.

See: R62 (M6-03), `src/07/types.zig`.

## TextareaState

Per-element state struct for `.textarea` widgets (R63). Holds:
- `line_starts` — `ArrayListUnmanaged(u32)` of byte offsets for each line's first character (line 0 starts at byte 0).
- `scroll_y` — vertical scroll offset in pixels.
- `content_h` — total rendered content height (line_count × line_h), updated by `buildDrawList`.
- `container_h` — visible area height, set from the computed layout rect.

Indexed by `ElementId.index`, stored in `Scene._textarea_state` (parallel to `InputState`).
Added in R63.

See: R63 (M6-04), `src/07/types.zig`.

---

## accordion

A widget with a clickable header and a collapsible body. Clicking the header toggles the
`AccordionState.open` flag and shows/hides the body element via `setHidden`. Children are
identified by a `slot="header"` / `slot="body"` attribute or by positional order (first child
= header, second child = body). Tag in markup: `"Accordion"`.

See: R77, `src/07/types.zig` `AccordionState`, `src/09/types.zig`.

---

## active tab

The currently selected tab in a `<Tabs>` widget. Its panel is visible while all other tab
panels are hidden via `setHidden`. Tracked by `TabsState.active_tab` (zero-based index of
the visible `<TabItem>`).

See: R76, `src/07/types.zig` `TabsState`.

---

## auto-dismiss

Behavior where a toast notification or tooltip automatically hides after a configured
duration without requiring user interaction. For toasts, the duration is a fixed frame count
(configurable per `ToastManager` instance). For tooltips, the tooltip remains visible as
long as the cursor stays over the element.

See: R74, R7C, `src/app/toast.zig`, `src/app/tooltip.zig`.

---

## avatar

A circular widget showing a user representation: either an image tile drawn from `ImageAtlas`
(when `AvatarState.has_image = true`) or two uppercase initials rendered on a token-derived
background color chosen by `initialsColor()` (initials fallback). State stored in
`AvatarState` in `Scene._avatar_state`. Tag in markup: `"Avatar"`.

See: R7B, `src/07/types.zig` `AvatarState`, `src/09/types.zig`.

---

## backdrop

A semi-transparent full-screen `FilledRect` drawn behind a modal dialog panel via the
`OverlayLayer`. Its purpose is to visually dim the background and signal that the UI is
blocked. Created and owned by `DialogManager`; removed when the dialog closes.

See: R75, `src/app/dialog.zig`.

---

## badge

A small overlay pill showing a short text label (up to 8 bytes) and a `BadgeColor` status.
Used to annotate avatars or other elements. State stored in `BadgeState` in
`Scene._badge_state`. Tag in markup: `"Badge"`.

See: R7B, `src/07/types.zig` `BadgeState`, `src/09/types.zig`.

---

## BadgeColor

An enum `{ default, success, warning, error_c }` controlling the background color of a badge
element. Each variant maps to a theme token color. Stored in `BadgeState.color`.

See: R7B, `src/07/types.zig` `BadgeState`.

---

## calendar grid

The month-view grid inside a date picker popup showing the days of the current navigation
month. Driven by `DatePickerState.nav_year` / `DatePickerState.nav_month`. Day cells are
computed using `date_util.zig` calendar math (first weekday of month, days in month).
Selecting a day writes a `DateValue` into the picker state and closes the popup.

See: R78, `src/07/types.zig` `DatePickerState`, `src/app/date_util.zig`.

---

## CellTextFn

`*const fn(row_ptr: *anyopaque, col: u8, buf: []u8) u8`. A callback that writes the display
text for cell `(row, col)` into `buf` and returns the byte count written. Stored in
`DataTableRows.cell_fn`. Called each frame by the data table renderer for each visible cell.

See: R79, `src/07/types.zig` `DataTableRows`.

---

## context menu

A popup menu triggered by right-clicking an element. Registered via
`ContextMenuManager.register(target_idx, items)`. When the user right-clicks a registered
element the menu opens at the cursor position; clicking an item invokes its `CallbackFn`;
clicking outside or pressing Escape closes it. Managed by `ContextMenuManager` in
`src/app/context_menu.zig`.

See: R7D, `src/app/context_menu.zig`.

---

## ContextMenuItem

`struct { label: []const u8, callback: CallbackFn, disabled: bool }`. One entry in a context
menu. A `disabled` item is rendered with reduced opacity and its `callback` is not invoked
when clicked.

See: R7D, `src/app/context_menu.zig`.

---

## ContextMenuManager

The `src/app/context_menu.zig` struct that stores up to 16 registered context menus, handles
open/close/highlight/invoke state, and builds `OverlayLayer` draw commands for the menu
panel. Held by `App` and ticked each frame. Menus are keyed by element index.

See: R7D, `src/app/context_menu.zig`.

---

## data table

A virtualized tabular widget displaying rows of data via a `CellTextFn` callback. Supports
sortable column headers (clicking a header cycles through ascending/descending/unsorted).
Only visible rows are rendered (virtualized). State stored in `DataTableState` in
`Scene._datatable_state`. Data source passed via `DataTableRows`.

See: R79, `src/07/types.zig` `DataTableState`, `DataTableRows`.

---

## DataTableRows

`struct { row_ptr: *anyopaque, row_size: usize, row_count: u32, cell_fn: CellTextFn }`.
The data source passed to a data table widget. `row_ptr` points to the first element of a
contiguous array of any row type; `row_size` is `@sizeOf` that type. The renderer computes
the pointer to row `i` as `row_ptr + i * row_size`.

See: R79, `src/07/types.zig` `DataTableRows`.

---

## date picker

A widget combining a text input (showing a formatted date string) with a calendar popup for
date selection. Clicking the input opens the popup; selecting a day closes it and stores the
result as a `DateValue`. Navigation arrows change `nav_year`/`nav_month`. State stored in
`DatePickerState` in `Scene._datepicker_state`. Uses `date_util.zig` for calendar math.

See: R78, `src/07/types.zig` `DatePickerState`, `src/app/date_util.zig`.

---

## DateValue

`struct { year: u16, month: u8, day: u8 }`. The value type stored by a date picker widget.
`month` is 1-based (1 = January). Stored in `DatePickerState.value`.

See: R78, `src/07/types.zig` `DatePickerState`.

---

## DialogManager

The `src/app/dialog.zig` struct that opens, maintains, and closes a modal dialog. Stores the
focused element index before opening and restores it on close. Builds a backdrop `FilledRect`
and a panel subtree via `OverlayLayer`. Implements a focus trap while the dialog is open.
Held by `App`.

See: R75, `src/app/dialog.zig`.

---

## focus trap

A behavior where Tab/Shift-Tab keyboard navigation is confined to the elements inside an
open modal dialog. While the dialog is open, `Scene.setFocus` wraps around within
`DialogManager.focusable_indices` instead of cycling through all `Scene.focusable_indices`.
Released when the dialog closes and focus is restored to the previously focused element.

See: R75, `src/app/dialog.zig`.

---

## frame_count

A `u64` counter on `Scene` incremented by exactly 1 each frame by the app run loop. Used by
animated widgets — spinner rotation, indeterminate progress bar fill, and tooltip hover-delay
timing — to derive animation state without requiring wall-clock time. Animations are therefore
deterministic and reproducible.

See: R73, R74, R7C, `src/07/types.zig` `Scene.frame_count`.

---

## group_id

A `u16` value stored in `RadioState` that groups sibling `<Radio>` elements into a
mutually-exclusive selection set. All `<Radio>` elements sharing the same `group_id` in the
same scene form a radio group. Used by `Scene.selectRadio()` to deselect all other radios in
the group when one is selected.

See: R71, `src/07/types.zig` `RadioState`.

---

## hover delay

The 500-frame pause between first hovering over an element and the tooltip appearing.
Implemented by `TooltipManager` using `scene.frame_count`: the manager records the frame at
which hover started and shows the tooltip only after 500 frames have elapsed.

See: R7C, `src/app/tooltip.zig`.

---

## indeterminate

A progress bar mode where the total duration is unknown; the fill animates continuously as a
bouncing block rather than representing a fixed fraction. Activated when
`ProgressState.indeterminate = true`. Animation position is derived from `scene.frame_count`
so it advances exactly one step per frame.

See: R73, `src/07/types.zig` `ProgressState`.

---

## initials fallback

When an avatar has no image (`AvatarState.has_image = false`), two uppercase initials from
`AvatarState.initials` are rendered as text on a background color chosen by `initialsColor()`.
`initialsColor()` derives the color deterministically from the initials bytes using a modulo
index into a small palette of token-sourced colors, so the same initials always produce the
same color.

See: R7B, `src/07/types.zig` `AvatarState`, `src/09/types.zig` `initialsColor`.

---

## label slot

A child element auto-created from a widget's `label` markup attribute during
`Scene.instantiate()`. For example, `<Checkbox label="Accept terms">` auto-creates a
`Text` child element whose content is the value of the `label` attribute. The widget owns
this child; it is positioned and styled as part of the widget's layout.

See: R70, `src/07/types.zig` `Scene.instantiate`.

---

## modal dialog

A blocking overlay that prevents interaction with the rest of the UI until dismissed.
Rendered as a `backdrop` (semi-transparent full-screen rect) plus a panel subtree built from
`OverlayLayer` slots. Managed by `DialogManager` in `src/app/dialog.zig`. While open, a
focus trap confines Tab navigation to the dialog's elements.

See: R75, `src/app/dialog.zig`.

---

## NONE

Sentinel value `u32 = std.math.maxInt(u32)` (4,294,967,295). Used as a "no element" marker
in struct fields that hold element indices (e.g. `Scene.focused_idx` when no element has
focus). Defined as `pub const NONE: u32 = std.math.maxInt(u32)` at module scope in
`src/07/types.zig`.

See: `src/07/types.zig`.

---

## progress bar

A widget showing task completion as a filled rect proportional to a `[0.0, 1.0]` value.
May be *indeterminate* (animated bouncing fill) when the total is unknown. State stored in
`ProgressState` in `Scene._progress_state`. Tag in markup: `"Progress"`.

See: R73, `src/07/types.zig` `ProgressState`, `src/09/types.zig`.

---

## radio group

A set of `<Radio>` elements sharing the same `group_id: u16`. Exactly one radio in a group
may be selected at a time. Selecting one radio calls `Scene.selectRadio()`, which marks that
radio's `RadioState.selected = true` and sets `selected = false` on all other radios in the
group. Tag in markup: `"Radio"`.

See: R71, `src/07/types.zig` `RadioState`, `Scene.selectRadio`.

---

## separator

A stateless widget rendering a single 1 px line — horizontal by default, vertical when its
parent is a row flex container. Styled with `tokens.border_default`. No interaction, no
children, no state struct. Uses `WidgetKind.separator`. Tag in markup: `"Separator"`.

See: R7A, `src/07/types.zig`, `src/09/types.zig`.

---

## slider

A widget that presents a continuous numeric value in a range `[min, max]`. Rendered as a
horizontal track with a filled portion up to the current value and a draggable thumb.
Supports an optional `step` (defaults to 0 meaning continuous). Drag events update
`SliderState.value`, clamped to `[min, max]` and snapped to `step`. State stored in
`SliderState` in `Scene._slider_state`. Tag in markup: `"Slider"`.

See: R72, `src/07/types.zig` `SliderState`, `src/09/types.zig`.

---

## slot attribute

A `slot="header"` or `slot="body"` attribute on a child element inside an `<Accordion>`.
Tells `Scene.instantiate` which child is the accordion header and which is the body.
Falls back to positional order (first child = header, second child = body) when the attribute
is absent.

See: R77, `src/07/types.zig` `Scene.instantiate`.

---

## spinner

A circular loading indicator that rotates based on `scene.frame_count`. Rendered as a
partial arc whose start angle advances each frame. Uses `WidgetKind.spinner`. No user
interaction; no configurable state beyond size/color from the style system.
Tag in markup: `"Spinner"`.

See: R73, `src/07/types.zig`, `src/09/types.zig`.

---

## tab bar

The row of tab header buttons at the top of a `<Tabs>` widget. Each button corresponds to
one `<TabItem>` child. Clicking a button calls `Scene.selectTab(tabs_idx, tab_index)`, which
updates `TabsState.active_tab` and hides all non-active tab panels.

See: R76, `src/07/types.zig` `TabsState`.

---

## tab panel

The content area shown when a tab is active. Corresponds to a `<TabItem>` element. Hidden
via `setHidden(idx, true)` when not the active tab; revealed via `setHidden(idx, false)` when
selected.

See: R76, `src/07/types.zig` `TabsState`.

---

## TabsState

Per-element state for a `<Tabs>` widget. Contains `active_tab: u8`, the zero-based index of
the currently visible `<TabItem>`. Updated by `Scene.selectTab()`. Stored in
`Scene._tabs_state`.

See: R76, `src/07/types.zig` `TabsState`.

---

## thumb

The draggable indicator on a slider widget that shows and sets the current value. Rendered
as a small circle positioned along the slider track at `(value - min) / (max - min)` of the
track width. Drag events on the thumb update `SliderState.value`.

See: R72, `src/07/types.zig` `SliderState`, `src/09/types.zig`.

---

## toast

A transient notification that appears in a screen corner for a fixed frame duration and then
auto-dismisses. Created by `ToastManager.push(message, kind)`. `ToastKind` controls
background color: `info` (blue), `success` (green), `warning` (yellow), `error_` (red).
Rendered via `OverlayLayer`. Managed by `ToastManager` in `src/app/toast.zig`.

See: R74, `src/app/toast.zig`.

---

## ToastKind

Enum `{ info, success, warning, error_ }` controlling the background color of a toast
notification. Each variant maps to a semantic status token from `src/05/types.zig`.

See: R74, `src/app/toast.zig`.

---

## ToastManager

The `src/app/toast.zig` struct that queues, times, and dismisses toast notifications. Holds
up to a fixed number of concurrent toasts. `tick(frame_count)` decrements each toast's
remaining duration and removes expired ones. `buildOverlay()` emits `OverlayLayer` draw
commands for all active toasts. Held by `App`.

See: R74, `src/app/toast.zig`.

---

## tooltip

A small text popup that appears after a 500-frame hover delay over an element that carries a
`tooltip` attribute in markup. The text is the attribute value. Rendered via `OverlayLayer`
near the cursor. Managed by `TooltipManager` in `src/app/tooltip.zig`.

See: R7C, `src/app/tooltip.zig`.

---

## TooltipManager

The `src/app/tooltip.zig` struct that tracks hover state, manages the hover delay timer
using `scene.frame_count`, and renders the tooltip overlay. On each frame, if the hovered
element has a `tooltip` attribute and the delay has elapsed, a draw command is pushed to the
`OverlayLayer`. Held by `App`.

See: R7C, `src/app/tooltip.zig`.

---

## track

The background bar of a slider or progress bar over which the thumb moves (slider) or the
fill advances (progress bar). Rendered as a full-width `FilledRect` using the widget's base
background token; the filled portion is a second `FilledRect` using the accent token drawn
on top.

See: R72, R73, `src/09/types.zig`.

---

## AppState(T)

A comptime-generic container wrapping a user-defined struct `T` whose fields are `Signal`
instances (or any type with a `deinit` method). Owned by the application entry point and
shared across screens via the `ctx` argument to `Navigator.push`. Provides `get()` returning
`*T` for direct signal access. Optionally exposed as a thread-local singleton via
`setGlobal` / `getGlobal`. Defined in `src/app/app_state.zig`.

---

## PersistentSettings

A line-oriented key-value store written to the platform user-data directory
(`%APPDATA%\<app>\settings.txt` on Windows, `~/.config/<app>/settings.txt` on Linux).
Supports u32, i32, f32, bool, and string values. Writes are deferred until `flush()` is
called. Flush is atomic (write-to-tmp then rename). Defined in
`src/app/persistent_settings.zig`.

See: R82 (M8-03).

See: R81 (M8-02).

---

## MultiWindowApp

A top-level application host that owns multiple `WindowEntry` instances and drives a single
frame loop for all of them. Shares one `VkDevice`, one `GlyphAtlas`, and one `GpuAtlas`
across all windows. Secondary windows are created via `VulkanBackend.initShared` so they
do not own the device. Each window has its own `Scene`, `VulkanBackend` (surface +
swapchain), `BindingSet`, and `OverlayLayer`. Defined in `src/app/multi_window.zig`.

See: R83 (M8-04).

## WindowId

A `u16` opaque handle identifying one `WindowEntry` within a `MultiWindowApp`. Value `0`
is reserved/invalid. Allocated monotonically; not reused after `closeWindow`.

See: R83 (M8-04), `src/app/multi_window.zig`.

---

## DebugOverlay

A developer tool struct (`src/app/debug_overlay.zig`) that draws colored bounding-box
borders over every live scene element when enabled. Toggled by the F1 key via
`AppInner.handleKey`. When enabled the matching performance HUD also appears (see PerfHud).
`updateHover(scene, x, y)` finds the topmost element under the cursor by iterating elements
in reverse painter order; `buildDebugDrawList(…)` emits `border_rect` commands for all
elements and, when an element is hovered, a four-line info panel showing computed rect and
style. Border colors encode element role: hovered = accent (a=255), focusable = info (a=180),
container = ok (a=140), other = warn (a=120).

See: R90, `src/app/debug_overlay.zig`, `src/app/app.zig`.

---

## FrameCounters

A plain struct (`src/app/perf_hud.zig`) holding four per-frame metrics collected by
`AppInner` after each rendered frame: `frame_ms: f32`, `cmd_count: u32`, `dirty_count: u32`,
`element_count: u32`. Passed to `PerfHud.record()` at the end of the frame pipeline.

See: R92, `src/app/perf_hud.zig`.

---

## PerfHud

A struct (`src/app/perf_hud.zig`) that tracks the last 16 frame times in a ring buffer,
computes a smoothed frame time via `smoothFrameMs()`, and emits a small three-line HUD panel
in the top-right corner of the viewport when the debug overlay is enabled.
`buildHudDrawList(alloc, enabled, viewport_w, tokens, font, atlas)` returns the draw
commands for the panel; the caller frees the slice.

See: R92, `src/app/perf_hud.zig`.

---

## Theme live-swap

The ability to change the active theme at runtime without restarting the application or
re-instantiating the scene. Implemented by `AppInner.setTheme(theme)` and
`AppInner.toggleTheme()`. `setTheme` scales the new theme's token set by the current font
scale factor, marks all elements dirty, and calls `rebuildStyles()` which re-resolves each
live element's CSS class string against the new tokens. All layout and style changes take
effect on the next frame.

See: R93, `src/app/app.zig`.

---

## FileLogger

A `std.log`-compatible sink that writes timestamped log lines to a file on disk. The file
rolls (truncates to zero) when it exceeds `max_bytes`. Installed globally by `AppInner.init`
when `AppOptions.log_path` is set. Defined in `src/app/file_logger.zig`. See: RA2 (M10-03).

---

## BudgetedArena

An `ArenaAllocator` wrapper that enforces a configurable byte ceiling. When an allocation
would exceed `budget_bytes`, it returns `error.OutOfMemory` and logs the overage. A budget
of 0 means unlimited. Reset behavior is identical to the underlying `ArenaAllocator`.
Defined in `src/app/budgeted_arena.zig`. See: RA1 (M10-02).

---

## showErrorDialog

A platform-specific function that displays a native error message to the user.
On Windows, uses `MessageBoxW`. On Linux, writes to stderr. Used by `initOrDialog`
to surface Vulkan or other startup failures gracefully. Defined in
`src/app/startup_error.zig`. See: RA3 (M10-04).

---

## WindowStateManager

A helper struct that reads and writes window position, size, and maximised state to
`PersistentSettings`. Used by `AppInner` when `AppOptions.persist_window_state = true`.
Reads state from GLFW on `deinit`; applies saved state to GLFW on `init`. Defined in
`src/app/window_state.zig`. See: RA4 (M10-05).

---

## SavedWindowState

A plain struct (`x: i32`, `y: i32`, `width: u32`, `height: u32`, `maximised: bool`)
holding a snapshot of window geometry. Produced by `WindowStateManager.load` and
`readFromPlatform`. See: RA4 (M10-05).

---

## ErrorBoundary

A struct that wraps a `ScreenFn` call in a Zig error-catch block. When the screen function
returns an error, `ErrorBoundary.call` stores the error and returns `false`; the Navigator
then displays a built-in fallback screen. Does NOT catch panics. Defined in
`src/app/error_boundary.zig`. See: RA0 (M10-01).

---

## font scale

A `f32` multiplier (clamped to `[0.5, 4.0]`, default `1.0`) applied to all five type-scale
token sizes (`text_xs` through `text_xl`). Stored as `AppInner._font_scale`. Changed via
`AppInner.setFontScale(factor)`, which rebuilds tokens from the current palette and mode,
scales them, rebuilds element styles, and marks all elements dirty. `Tokens.scaled(factor)`
is the pure function that multiplies each text size and clamps to `[6, 96]`.

See: R94, `src/app/app.zig`, `src/05/types.zig` `Tokens.scaled`.

---

## AnimTimeline

A pure scalar animator (`src/app/anim_timeline.zig`) that drives a `f32` value from 0→1 over a
configurable `duration` (in frames) with an easing function. Supports repeating (loop), yoyo
(ping-pong), and four easing modes (linear, ease-in, ease-out, ease-in-out). The timeline does
NOT hold a subscriber list or dirty-bitset reference — the caller (`AppInner.tickAnimations`)
is responsible for marking elements dirty after each tick. Used as the foundation for style
transitions (M14-02), enter/exit animations (M14-03), and spinner/progress animation (M14-04).

See: RD6 (M14-01), `src/app/anim_timeline.zig`.

---

## TransitionState

Per-element state stored in `Scene._transition_state` (a parallel array) that tracks active
style transitions. For each transitioning property (opacity, background), stores the from/to
values and the index of the driving `AnimTimeline` in `AppInner.anim_timelines`. When a
transition completes, `syncAnimationState` resets the active flag so the renderer uses the
base `_style` value. See: RD7 (M14-02), `src/07/types.zig`.

---

## EnterExitState

Per-element state stored in `Scene._enter_exit_state` (a parallel array) that tracks active
enter/exit animations. When an element with `animate-out` is hidden, the state records
`exiting = true` and `pending_hidden = true` while the exit timeline plays; the actual
`_hidden` bit is set only after the timeline completes. For `animate-in`, the element is
shown immediately but its opacity is animated from 0→1. See: RD8 (M14-03), `src/07/types.zig`.

---

## prefer_reduced_motion

A `bool` flag on `AppInner` (M14-05). When `true`, `AppInner.tickAnimations()` immediately
completes all active `AnimTimeline` instances (setting `value = 1.0`, `running = false`)
instead of advancing them by one frame. This makes all transitions, enter/exit animations, and
spinner/progress animations jump to their end state instantly. Set via
`AppInner.setReducedMotion(bool)`. See: RDA (M14-05), `src/app/app.zig`.

---

## transition-opacity / transition-background / transition-colors

Tailwind utility classes (M14-02) that enable smooth interpolation when the corresponding
`ComputedStyle` field changes. `transition-opacity` enables opacity blending, `transition-background`
enables background color blending, `transition-colors` enables both. The transition duration in
frames is set by the `duration-{n}` class (e.g. `duration-60` = 60 frames ≈ 1 s at 60 fps).
See: RD7 (M14-02), `docs/specs/06.types.zig`.

---

## animate-in / animate-out

Tailwind utility classes (M14-03) that enable fade transitions when an element's visibility
state changes. `animate-in` fades the element from transparent to opaque when `setHidden(false)`
is called. `animate-out` fades the element from opaque to transparent when `setHidden(true)` is
called, deferring the actual `_hidden` bit until the animation completes. Duration is set by
the `duration-{n}` class. Combine with `fade-in`/`fade-out` class. Slide variants
(`slide-in-from-top`, etc.) are defined but not emitted by the renderer in v1.
See: RD8 (M14-03), `docs/specs/06.types.zig`.

---

## lerpColor

A pure helper function (`docs/specs/09.types.zig`) that linearly interpolates between two
`Color` values by a factor `t ∈ [0, 1]`. Used by `syncAnimationState` to blend transition
from/to background colors. Each channel (r, g, b, a) is interpolated independently as floats
and truncated to `u8`. `t` is clamped to [0, 1] internally.
See: RD7 (M14-02), `docs/specs/09.types.zig` `lerpColor`.

---

## Direction

An `enum(u8)` defined in `src/03/types.zig` (M15-04) with variants `.ltr = 0` (default) and
`.rtl = 1`. Controls text/layout direction for an element. When `.rtl`, flex children in a
row-direction container are placed right-to-left and text glyphs are right-aligned within the
element's content rect. The `.ltr` value (0) is the default and maintains the existing
left-to-right behavior.

See: M15-04 (RE3), `docs/specs/03.types.zig`.

---

## layout_direction

A field on `LayoutNode` of type `Direction`, defaulting to `.ltr`. When set to `.rtl` on a
flex container with `direction = .row`, children are placed right-to-left and
`justify-content: flex-start` / `flex-end` meanings are mirrored. When set to `.rtl` on a
text element, glyphs are right-aligned within the content rect. Only affects row-direction
flex containers and text alignment — column containers, grid layout, and icons/images are
unaffected. Set via the `direction-rtl` / `direction-ltr` Tailwind utility classes.

See: M15-04 (RE3), `docs/specs/03.types.zig`, `docs/specs/04.types.zig`.


---

## Tray

`src/app/tray.zig`. System tray icon with optional popup menu. On Windows, backed by Win32
`Shell_NotifyIconW` via a message-only HWND; menu items are registered with `addMenuItem` and
the popup is shown on right-click via `TrackPopupMenu`. On Linux, all methods compile and run
as no-ops — no tray icon is shown until `libnotify` is approved (INV-5.6). One `Tray` per
application; caller retains ownership and passes a `?*Tray` to `AppOptions.tray`.
`AppInner` calls `pumpMessages()` once per frame to drain the Win32 message queue.

See: M16-01 (RF0), `src/app/tray.zig`.

---

## FileDialogFilter

`src/01/types.zig`. `pub const FileDialogFilter = struct { name: []const u8, pattern: []const u8 }`.
Passed to `Platform.showOpenDialog` or `Platform.showSaveDialog` to restrict visible file
types in the native file picker. `name` is the human-readable label shown in the filter
dropdown (e.g. "Zig source files"); `pattern` is the glob pattern (e.g. "*.zig"). An empty
slice means "all files". On Linux (stub path), filters are accepted but have no effect.

See: M16-02 (RF1), M16-03 (RF2), `src/01/types.zig`.

---

## ColorScheme

`src/01/types.zig`. `pub const ColorScheme = enum { light, dark, unknown }`. Returned by
`Platform.getColorScheme()`. On Windows, read from
`HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize\AppsUseLightTheme`
(REG_DWORD: 0 = `.dark`, 1 = `.light`, absent = `.unknown`). On Linux, inferred from the
`GTK_THEME` environment variable suffix (`:dark` / `:light`) or `COLORFGBG` (ends with `;0`
= `.dark`). When `.unknown`, `AppOptions.default_theme_mode` is used as the fallback.
Read once at startup in `AppInner.init`; the app layer maps it to `mod05.Mode` and calls
`setTheme`. Module 01 does NOT import module 05 — the mapping lives in the app layer only.

See: M16-04 (RF3), `src/01/types.zig`, `src/app/app.zig`.

---

## AccessRole

An enum defined in `src/07/types.zig` (M17-01) with 25+ semantic role variants (button, text,
checkbox, list, listitem, slider, dialog, etc.). Each live element gets one `AccessRole` in its
`AccessNode`. The role is either explicit (from `role=` markup attribute) or inferred from the
element's `WidgetKind` via `defaultAccessRoleFor()`. Used by accessibility bridges (RG2, RG3)
to expose the UI semantically to screen readers.

See: M17-01 (RG1), `src/07/types.zig` AccessRole enum.

---

## AccessState

A packed struct defined in `src/07/types.zig` (M17-01) holding seven boolean state flags:
`disabled`, `checked`, `focused`, `expanded`, `hidden`, `selected`, `invalid`. Fits in a single
u8. Stored in each `AccessNode` and synchronized with widget state by `Scene.setAccessState()`.
Used by accessibility bridges to report interactive state to screen readers.

See: M17-01 (RG1), `src/07/types.zig` AccessState struct.

---

## AccessNode

A struct defined in `src/07/types.zig` (M17-01) carrying semantic information for one accessible
element: `role`, `name`, `description`, `state`, `value`, `value_min`, `value_max`. Stored in
a parallel array `Scene._access_nodes` indexed by element index. Built during `Scene.instantiate()`
and kept in sync with the element tree. Queried by accessibility bridges (RG2, RG3) to expose
the UI to screen readers.

See: M17-01 (RG1), M17-04 (RG4), `src/07/types.zig` AccessNode struct.

---

## accessibility tree

A parallel tree of `AccessNode` entries (M17-01) mirroring the visual element tree in `Scene`.
Each live element gets one `AccessNode` containing its semantic role, name, description, and
state. Built during `Scene.instantiate()` and kept in sync with element state changes. Exposed
to screen readers via accessibility bridges (AT-SPI2 on Linux, UIA on Windows).

See: M17-01 (RG1), M17-02 (RG2), M17-03 (RG3), `src/07/types.zig` Scene._access_nodes.

---

## aria-label

An accessibility attribute (M17-04) that assigns a human-readable label to an element. Parsed
from markup as `aria-label="text"` and stored in `AccessNode.name`. Takes precedence over the
element's text content when both are present. Used by screen readers to identify interactive
widgets and regions.

See: M17-04 (RG4), `src/06/types.zig` NodeDesc.aria_label, `src/07/types.zig` AccessNode.name.

---

## aria-description

An accessibility attribute (M17-04) that assigns a longer description to an element. Parsed
from markup as `aria-description="text"` and stored in `AccessNode.description`. Used by
screen readers to provide context or instructions. May be omitted if empty.

See: M17-04 (RG4), `src/06/types.zig` NodeDesc.aria_description, `src/07/types.zig` AccessNode.description.

---

## role= (accessibility attribute)

An accessibility attribute (M17-04) that overrides the semantic role of an element. Parsed from
markup as `role="button"`, `role="list"`, etc., and stored in `AccessNode.role`. Valid values
are the `AccessRole` enum variants. If invalid, a `ParseDiagnostic` is emitted. When absent,
the role is inferred from the element's `WidgetKind` via `defaultAccessRoleFor()`.

See: M17-04 (RG4), M17-01 (RG1), `src/06/types.zig` NodeDesc.role, `src/06/parser.zig` parseRole().

---

## sr-only

A Tailwind utility class (M17-05) that hides an element visually while keeping it in the
accessibility tree. The element is rendered fully transparent (`opacity = 0.0`) and may take
zero layout space. Useful for hidden labels, skip links, and live status regions that screen
readers should announce but sighted users should not see. Variants like `focus:not-sr-only`
make the element visible on focus (skip links).

See: M17-05 (RG5), `src/06/types.zig` resolveClasses.

---

## PatternValidator

A JSON Schema keyword validator (M18-01) that matches a string value against a regex pattern.
Added in RH1. The pattern is compiled into bytecode and matched against the full input string
(anchored to the entire string, not just a substring). Requires a regex engine implementation
(decision pending in INV-5.6).

See: M18-01 (RH1), `src/08/regex.zig`, `src/08/validator.zig`.

---

## AllOfValidator

A constraint (M18-03) that requires a value to be valid against every sub-schema in an
`allOf` array. All sub-schemas must pass validation (intersection/conjunction logic).

See: M18-03 (RH3), `src/08/validator.zig`.

---

## AnyOfValidator

A constraint (M18-03) that requires a value to be valid against at least one sub-schema
in an `anyOf` array. At least one sub-schema must pass validation (union/disjunction logic).

See: M18-03 (RH3), `src/08/validator.zig`.

---

## OneOfValidator

A constraint (M18-03) that requires a value to be valid against exactly one sub-schema
in a `oneOf` array. Neither zero nor multiple sub-schemas should validate (exclusive union).

See: M18-03 (RH3), `src/08/validator.zig`.

---

## dependentRequired

A JSON Schema keyword (M18-04) that conditionally requires certain properties to be present
based on the presence of other properties. Maps a "trigger" property name to a list of
required properties. If the trigger property exists in an object, all required properties
in the list must also exist.

Example: `dependentRequired: { "credit_card": ["cvv", "name"] }` means "If credit_card is
present, cvv and name must also be present."

See: M18-04 (RH4), `src/08/validator.zig`.

---

## ConditionalSchema

A JSON Schema using `if`/`then`/`else` keywords (M18-05) to apply different validation
schemas based on a condition. The `if` schema is tested; if it validates successfully, the
`then` schema is applied; if it fails and `else` is present, the `else` schema is applied
instead. Neither `then` nor `else` is required.

See: M18-05 (RH5), `src/08/validator.zig`.

---

## ArrayFieldState

Per-element state stored in `Scene._array_field_state` (M18-06) tracking the current item count
and min/max bounds for an array-type form field. Updated by `Scene.addArrayItem()` and
`Scene.removeArrayItem()`. Accessed via `Scene.arrayFieldStateOf(idx)`.

See: M18-06 (RH6), `src/07/types.zig`.

---

## UpdateManifest

A JSON-serialized struct (M19-01) containing version information and download metadata:
- `version: string` — semantic version (e.g., "1.0.1")
- `download_url: string` — URL to download the binary package or delta
- `checksum_sha256: string` — hex-encoded SHA256 of the new binary
- `release_notes?: string` — optional human-readable changelog

Fetched by `UpdateManager` from a configured manifest URL. Used by RI1 (update detection)
and passed to RI2 (delta download), RI3 (staging), and RI4 (UI).

See: M19-01 (RI1), `src/app/update_manager.zig`.

---

## UpdateManager

A struct (M19-01, `src/app/update_manager.zig`) that coordinates the entire auto-update
pipeline. Owns: current version string, manifest URL, latest fetched manifest, delta patch,
reconstructed binary, staging info, and error state. Key methods: `startFetch()` (fetch
manifest), `tick()` (poll for completion), `isUpdateAvailable()` (version comparison),
`startDeltaDownload()` (fetch patch), `applyDelta()` (reconstruct binary), `stageUpdate()`
(prepare for installation), `isStagedUpdatePending()` (check boot-time flag).

See: M19-01 (RI1), M19-02 (RI2), M19-03 (RI3), `src/app/update_manager.zig`.

---

## BinaryDelta

A bsdiff patch (M19-02) containing the compressed differences between two binary versions.
Stored in `UpdateManager.current_delta`. When applied to the old binary via `applyDelta()`,
produces the new binary stored in `new_binary_data`. The delta format is typically 10–20%
of the full binary size, reducing download time.

See: M19-02 (RI2), `src/app/update_manager.zig`.

---

## StagedUpdate

A struct (M19-03) holding metadata about an update that has been downloaded and patched
but not yet installed. Owns: current exe path, staged binary path, backup path, SHA256 hash,
size, and staging timestamp. Persisted via a marker file on disk so the staged update
survives application crashes. Installed atomically on the next app launch before any
modules are initialized.

See: M19-03 (RI3), `src/app/update_manager.zig`.

---

## UpdateUiManager

A struct (M19-04, `src/app/update_ui_manager.zig`) that manages all user-facing notifications
and progress indicators for the update pipeline. Integrates with the existing `ToastManager`
(M7-05) to show update-available, update-staged, and error toasts. Shows a download-progress
modal while RI2 is downloading. Reads progress from `UpdateManager` each frame and updates
the UI.

See: M19-04 (RI4), `src/app/update_ui_manager.zig`.

---

## auto-update pipeline

The end-to-end process of detecting, downloading, verifying, staging, and installing
application updates (M19-01 through M19-04):
1. RI1: Fetch manifest, detect newer version, notify user.
2. RI2: Download binary delta, apply patch, reconstruct new binary.
3. RI3: Write binary to temp, verify checksum, stage for atomic install.
4. RI4: Show progress bar and status toasts throughout the process.
5. Boot-time swap: On next app launch, rename staged binary into place before any modules run.

See: M19 (auto-update / delivery), RI1–RI4, `src/app/update_manager.zig`, `src/app/update_ui_manager.zig`.

---

# Version 2 terms

> The following terms are introduced by Version 2 (modules 10–13). They are **provisional**
> until `V2_constitution_amendment.md` is ratified; see that file and `V2_ARCHITECTURE.md`.
> Listed here per INV-5.5 so v2 requirement files reference defined terms, not improvised ones.

## GpuBackend

The single interface every GPU backend implements (module 10). A backend owns the device,
swapchain/drawable, pipelines, atlas uploads, and `drawFrame`. The seam — not any single
backend — is the contract (INV-2.1-v2): all backends consume the identical `DrawCommand` list
(INV-2.3) and the same fragment-mode table. Exactly one backend is selected at build time via
`-Dgpu`; there is no runtime switching. Concrete backends: `VulkanBackend` (reference),
`MetalBackend`, `Dx12Backend`, `WebGpuBackend`.

See: RJ0–RJ4, `src/10/`.

## shader-mode parity table

The canonical list of fragment "modes" (solid rect, glyph, image, SDF icon, gradient, AA
circle, subpixel glyph, curve) that every backend's shaders must implement identically. A
backend may not add a private mode (INV-2.1-v2). A build-time test asserts equal mode counts
across all backend shader sets.

See: RJ0, `src/10/types.zig`.

## Surface (v2)

The per-target drawable handle a backend renders into: `VkSurfaceKHR`, `CAMetalLayer`,
`HWND`+`IDXGISwapChain`, or a web `GPUCanvasContext`. Produced by `Platform.createSurface`.
Per-OS code is confined to the surface layer and module 10 (INV-1.2-v2).

See: RJ5, `src/01/surface.zig`.

## shaping

The stage (module 11) that maps a text run to positioned glyph IDs using HarfBuzz, providing
contextual glyph selection, ligatures, and mark positioning (INV-1.3-v2). Sits between line
breaking and rasterization; its output feeds the existing line-box and glyph-draw path
unchanged. A `ShapedGlyph` carries a `glyph_id`, a `cluster` (source byte offset), and offsets.

See: RK0, `src/11/`.

## bidi (Unicode Bidirectional Algorithm)

Resolution of embedding levels and visual reordering of mixed LTR/RTL text per the UBA
(module 11). `itemize` splits a paragraph into runs by level/script/font in logical order;
`reorderVisual` reorders a line's runs to visual order before shaping. The RE3 `direction`
flag is the paragraph base direction input.

See: RK1, `src/11/bidi.zig`.

## cluster

A HarfBuzz cluster: the unit a caret stops on after shaping. One ligature or combining
sequence is one cluster even when it spans multiple codepoints. Caret movement, hit-testing,
and selection operate on cluster boundaries (mapped to source byte offsets), not codepoints.

See: RK3, `src/11/`.

## ShapedLine

The query API (module 11) widgets use instead of per-codepoint advances: `caretX`, `byteAtX`,
`nextCaret`/`prevCaret` (visual order), and `selectionRects`. Lets text input, textarea, and
selection work correctly under shaping and bidi.

See: RK3, R32, R62, R63, `src/11/types.zig`.

## cascade

The build-time resolver (module 12) that, for each baked element, matches selectors, orders
declarations by specificity then source order, applies the inherited-property set, and folds
the result into the same `ComputedStyle` the renderer consumes. Bounded per INV-4.2-v2: no
`@media`, no sibling combinators, no `!important`. Runs only at build-time codegen
(INV-4.4) — the production binary contains no cascade engine.

See: RL0–RL3, `src/12/`.

## specificity

The ordering key for cascade conflicts: a triple `(id count, class/attribute count, type
count)`, with utility classes at the class tier and inline `style:` above all selector tiers;
ties break by source order. `!important` is rejected at build time.

See: RL1, `src/12/types.zig`.

## inherited-property set

The closed, hardcoded list of properties that inherit parent→child in the cascade: `color`,
`font-family`, `font-size`, `line-height`, `text-align`, `direction`. No other property
inherits; the set is not configurable (INV-1.1). `inherit`/`initial` keywords are the only
per-property escape hatches.

See: RL2, `src/12/`.

## curve primitive

A general GPU drawing command added for charts (module 13, fragment mode 8): `PolylineCmd`
(stroked, with join), `FilledPathCmd` (CPU-triangulated region), and `ArcCmd` (stroked arc or
filled wedge). General primitives in the shared vocabulary (INV-2.3), not a chart-private
path; CPU pre-tessellated to keep all backend shaders in parity.

See: RM0, `src/01/types.zig`, `src/13/tessellate.zig`.

## Scale

A data→pixel mapping for charts (module 13): `linear`, `log`, `band`, or `time`. Provides
`map` (data→pixel), `invert` (pixel→data, for hit-testing), and `ticks` (human-friendly tick
values). Tick labels format through M15 (RE0/RE1) for locale support.

See: RM1, `src/13/scale.zig`.

## ChartFrame

The resolved coordinate context for a chart (module 13): the inner `plot_rect` (frame minus
axis gutters) plus the x and y `Scale`s. Axis gutters are sized from measured label widths so
labels never clip. `drawAxes` emits axis lines, ticks, gridlines, and labels for a frame.

See: RM1, `src/13/axes.zig`.

## Chart

A widget kind (module 13) occupying a layout rect that, given `Series` data and a
`ChartKind` (line/bar/area/scatter/pie), emits curve primitives for its marks. Series colors
come from theme palette tokens (INV-4.3). Re-renders on data change through the normal
signal→dirty→scan path (INV-3.3); hover/legend/selection reuse existing events, overlays, and
signals — no chart-specific interaction mechanism.

See: RM2, RM3, `src/13/chart.zig`.
