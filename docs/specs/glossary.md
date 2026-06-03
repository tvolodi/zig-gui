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
