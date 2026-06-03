# R91 — M9-02: Scene dump

> Roadmap item: M9-02  
> Depends on: module 07 (Scene)  
> Read `00_constitution.md` before this file.

## Purpose

Add `Scene.debugPrint()` — a single function that writes a human-readable, indented
representation of the element tree to `stderr`. Called by the developer during debugging;
never called in a hot path.

An author diagnosing a layout problem calls:

```zig
scene.debugPrint();
```

and sees on stderr:

```
[0] column  x=0 y=0 w=1280 h=800  bg=#F9F9F8 text=transparent border=0px  (dirty)
  [1] row  x=16 y=16 w=1248 h=48  bg=transparent text=transparent border=0px
    [2] text "Hello, world"  x=16 y=24 w=120 h=20  font=14px
    [3] button  x=152 y=20 w=80 h=28  bg=#1D9E75 text=#FFFFFF  (focused)
  [4] card  x=16 y=80 w=1248 h=200  bg=#F1EFE8 border=1px #D3D1C7
```

---

## Motivation

`buildDrawList` is opaque; the only way to know what a scene contains is to step through the
draw command list in a debugger. `Scene.debugPrint()` gives an instant, readable snapshot
that works before any GPU involvement.

---

## What to build

### 1. `Scene.debugPrint()` method

```zig
pub fn debugPrint(self: *const Scene) void
```

Writes to `std.io.getStdErr().writer()`. No allocator is required — uses the stack and
`std.fmt.format` with a fixed-size buffer.

`debugPrint` is NOT a public contract method (not in `src/07/types.zig` as a stub — it is
added as a real implementation in `src/07/types.zig` directly, or in a companion file
`src/07/debug.zig` imported from there). If adding it to `types.zig` would cause a contract
violation (INV-5.1), add it to `src/app/scene_debug.zig` as a free function:

```zig
pub fn debugPrintScene(scene: *const Scene) void
```

Either form is acceptable; the function must be callable from the app layer without importing
any module higher than 07.

### 2. Output format

Each live element is printed as one line with the following fixed layout:

```
<indent>[<idx>] <kind>  <text_summary>  x=<x> y=<y> w=<w> h=<h>  <style_summary>  <flags>
```

Fields:

| Field | Content | Format |
|---|---|---|
| `<indent>` | 2 spaces per depth level | spaces |
| `<idx>` | element index | decimal |
| `<kind>` | `WidgetKind` tag name, lowercase | e.g. `text`, `button`, `card` |
| `<text_summary>` | for `.text` elements only: `"<text content>"` truncated to 24 chars; omitted otherwise | quoted string |
| `x=`, `y=`, `w=`, `h=` | computed layout rect values | one decimal place, e.g. `12.0` |
| `<style_summary>` | see below | |
| `<flags>` | space-separated optional flags | `(dirty)`, `(focused)`, `(hidden)` |

Style summary fields (in this fixed order, omitting a field if it equals the zero/default):

- `bg=#RRGGBB` if `background.a > 0`
- `text=#RRGGBB` if `text_color.a > 0`
- `border=<width>px` if `border_width > 0`, append ` #RRGGBB` for the border color
- `radius=<radius>` if `radius > 0`
- `font=<font_size>px` always (always present)

Colors are formatted as `#RRGGBB` (no alpha in output — alpha is rarely useful at a glance).

Flags (appended at end of line, space-separated):
- `(dirty)` — if the element's dirty bit is set
- `(focused)` — if `scene.focused_idx == idx`
- `(hidden)` — if `scene.isHidden(idx)` is true

### 3. Traversal

Depth-first pre-order, same as `buildDrawList`. Depth is computed by following parent
pointers from `ElementStore`. Elements that are not live (invalid generation) are skipped
without printing.

### 4. Stack-local formatting

No heap allocation. Use a fixed `[256]u8` line buffer per element and write it to stderr
with one `writer.writeAll` call. If a line would exceed 255 characters it is truncated at
255 and `"..."` is appended (total 256 bytes). This bound is never hit in practice for
reasonable element counts and class names.

### 5. `Scene.debugPrintStats()` — summary line

A companion function (same module location) prints a one-line summary:

```zig
pub fn debugPrintStats(self: *const Scene) void
```

Output format:

```
Scene: <live> live / <total> total elements, <dirty_count> dirty, focused=<idx|none>
```

Where:
- `<live>` = number of valid live elements
- `<total>` = `elements.gen.items.len`
- `<dirty_count>` = number of set bits in `elements.dirty`
- `<idx|none>` = `focused_idx` as decimal, or `none` if `== NONE`

---

## Module location

```
src/07/debug.zig               — debugPrintScene, debugPrintSceneStats (free functions)
src/07/debug_test.zig          — acceptance tests (capture stderr via writer injection)
docs/requirements/R91_scene_dump.md
```

`src/07/types.zig` adds two forwarding methods that call the free functions:

```zig
pub fn debugPrint(self: *const Scene) void { debug.debugPrintScene(self); }
pub fn debugPrintStats(self: *const Scene) void { debug.debugPrintSceneStats(self); }
```

These two methods ARE added to the `Scene` struct in `src/07/types.zig` (they are trivial
wrappers; they do not change any existing signature — additive only).

---

## Invariant interactions

- **INV-2.3**: No GPU involvement. Reads only CPU-side scene state.
- **INV-5.1**: `debugPrint` and `debugPrintStats` are additive — no existing signature is
  changed. The implementation may live in a separate file to keep `types.zig` clean.
- **INV-3.1**: No heap allocation in the hot path. Fixed stack buffer per line.

---

## Non-goals (DO NOT implement — INV-5.4)

- NO JSON or structured output format — plain text only.
- NO file output — stderr only; redirection is the shell's responsibility.
- NO filtering by element kind or depth.
- NO diff between two scene snapshots.
- NO periodic/automatic invocation — call only when the developer explicitly invokes it.

---

## Acceptance criteria

The module is done when:

1. `zig build test-scene-dump` passes all tests in `src/07/debug_test.zig`.
2. `debugPrint` on a scene with three elements (column → row → text) produces three lines
   with correct indentation (0, 2, 4 spaces), kind names, and computed rects.
3. The `(dirty)` flag appears on exactly the elements whose dirty bit is set.
4. The `(focused)` flag appears on exactly the focused element.
5. The `(hidden)` flag appears on exactly hidden elements.
6. A `.text` element's content appears truncated at 24 chars with `...` suffix if longer.
7. `debugPrintStats` output matches the actual live/dirty counts of the scene.
8. The line buffer does not overflow for any element with a 24-char text summary and all
   style fields set (verified by unit test constructing the worst-case line).
9. The checklist for this item is fully ticked.

---

## Edge cases (each has a test)

- Empty scene (zero live elements) — `debugPrint` writes nothing; `debugPrintStats` shows
  `0 live / 0 total elements`.
- Element with all style fields at defaults — style summary is empty string (no fields
  printed except `font=<size>px`).
- Text element with exactly 24 characters — printed verbatim, no truncation.
- Text element with 25+ characters — truncated to 24 + `"..."`.
- Deeply nested element (depth 10) — 20-space indent; line fits in 256 bytes for typical
  content.
- All elements dirty — every line shows `(dirty)` flag.
