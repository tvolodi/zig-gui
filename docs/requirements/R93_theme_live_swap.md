# R93 — M9-04: Theme live-swap

> Roadmap item: M9-04  
> Depends on: M2-01 (Signal type), module 05 (theme)  
> Read `00_constitution.md` before this file.

## Purpose

Allow the application to switch between light and dark mode, or swap to a different palette,
at runtime without restarting. The change takes effect on the next frame with no scene
rebuild.

An application author wires a toggle button:

```zig
// In main / ScreenFn:
app.setTheme(Theme.build(Palette.default(), .dark));

// Or at runtime from a button callback:
app.toggleTheme();   // switches .light ↔ .dark using the current palette
```

---

## Motivation

Without live swap, testing dark mode requires recompiling with a changed default. Users
expect a theme toggle to be instant. This item delivers that with one field write and a
mark-all-dirty call.

---

## What to build

### 1. `App.setTheme`

```zig
pub fn setTheme(self: *AppInner, theme: Theme) void
```

Steps:
1. Store the new palette+mode: `self.tokens = theme.tokens`.
2. Call `self.scene.elements.markAllDirty()` — every element must be repainted because
   token-derived colors are baked into `ComputedStyle` fields at `instantiate` time and
   must be recomputed.
3. Call `self.rebuildStyles()` (see §3 below).

`setTheme` is a synchronous call — it must only be called from the main thread (the same
thread that runs `App.run`), either from application startup code or from inside a
`CallbackFn` (which fires inside `dispatchEvents`, which is on the main thread).

### 2. `App.toggleTheme`

```zig
pub fn toggleTheme(self: *AppInner) void
```

Reads the current mode from `self._current_mode`, flips it, then calls `setTheme`:

```zig
self._current_mode = switch (self._current_mode) {
    .light => .dark,
    .dark => .light,
};
self.setTheme(Theme.build(self._current_palette, self._current_mode));
```

`AppInner` gains two new fields:

```zig
_current_palette: Palette,
_current_mode: Mode,
```

Both are initialized in `App.init` to `Palette.default()` and `.light`. They are updated in
`setTheme`.

`toggleTheme` is provided as a convenience. Applications that want a different toggle
behavior (e.g. cycling through multiple palettes) call `setTheme` directly.

### 3. `rebuildStyles` — recompute token-derived styles

When the theme changes, the `ComputedStyle` values stored in `Scene._style` are stale
because they contain baked color values derived from the old tokens. `rebuildStyles` walks
every live element and re-runs the style resolution pass:

```zig
fn rebuildStyles(self: *AppInner) void {
    const s = self.scene.store();
    for (0..s.gen.items.len) |i| {
        const idx = @as(u32, @intCast(i));
        const id = ElementId{ .index = idx, .gen = s.gen.items[idx] };
        if (!s.isValid(id)) continue;
        const kind = self.scene.kindOfIdx(idx);
        // Recompute default style from new tokens, then re-apply any class overrides.
        const base = defaultStyleFor(kind, self.tokens);
        // Re-apply saved class string if available, otherwise use the base style.
        self.scene._style.items[idx] = self.resolveStyleForIdx(idx, base);
    }
}
```

The class string is stored in `Scene._classes` — a new parallel array added by this item:

```zig
_classes: std.ArrayListUnmanaged([]const u8) = .{},
```

populated during `Scene.instantiate` (one entry per element, the `NodeDesc.classes` slice,
which is already owned by the arena — no duplication needed). `resolveStyleForIdx` calls
`resolveClasses(classes, new_tokens)` and merges the result over the kind default.

The existing `instantiate` path already computes and stores the style in `_style`; this
change adds `_classes` as a second parallel store so that `rebuildStyles` can reconstruct
the style from scratch.

### 4. Inline style preservation

Inline `style:*` attributes (M5-01, R50) override token-derived values. These overrides are
applied AFTER the class pass and are NOT token-derived — they are literal color values and
therefore **do not change when the theme changes**.

For v1, inline styles are NOT preserved through a theme swap. An element with
`style:background="#FF0000"` will revert to the token-derived background after a theme
swap. This is acceptable because inline styles are rare and the workaround is clear: use a
token-backed class instead.

This limitation is explicitly documented in the non-goals section below and in the `_classes`
parallel array comment.

### 5. PseudoStyleSet rebuild

`PseudoStyleSet` entries (button hover/focus/active/disabled overrides) are built from tokens
at `instantiate` time and stored nowhere — they are reconstructed from tokens on every
`buildDrawList` call (see module 09's `resolveStyle`). Because `resolveStyle` receives
`self.tokens` from `AppInner`, no extra work is needed: passing the new `tokens` to
`buildDrawList` is sufficient. ✓ No change required to the pseudo-style path.

---

## Module location

No new file. All changes are in:

```
src/app/app.zig               — setTheme, toggleTheme, rebuildStyles, _current_palette,
                                _current_mode fields
src/07/types.zig              — Scene._classes parallel array (additive field)
src/app/theme_swap_test.zig   — acceptance tests (headless)
docs/requirements/R93_theme_live_swap.md
```

`src/app/types.zig` re-exports `setTheme` and `toggleTheme` as public methods of `App`.

---

## Glossary addition

Add to `docs/specs/glossary.md`:

```
## Theme live-swap

The ability to change `AppInner.tokens` at runtime via `setTheme` or `toggleTheme`. Triggers
`rebuildStyles` (recomputes token-derived `ComputedStyle` entries using the new tokens and
the stored `_classes` parallel array) and marks all elements dirty. Takes effect on the
next frame. Inline `style:*` overrides are NOT preserved through a swap (v1 limitation).

See: R93 (M9-04), `src/app/app.zig`.
```

---

## Invariant interactions

- **INV-4.3**: Token values come from `Tokens` built by `Theme.build(palette, mode)`. No raw
  hex literals are introduced in `rebuildStyles`.
- **INV-3.3**: Dirty-bitset mechanism is the sole change-propagation path. `rebuildStyles`
  calls `markAllDirty()` rather than trying to be clever about which elements changed.
- **INV-5.1**: `Scene._classes` is an additive parallel array. No existing `Scene` method
  signature changes.
- **INV-3.5**: The `_classes` slices point into the arena and are valid for the lifetime of
  the scene; no extra allocation.

---

## Non-goals (DO NOT implement — INV-5.4)

- NO per-element theme overrides (elements always derive from the global token set).
- NO CSS custom properties or variable substitution.
- NO animated transition between themes (no timeline model exists — see post-v1 table).
- NO preservation of inline `style:*` attribute overrides through a theme swap (v1 limitation,
  explicitly documented above).
- NO hot-reload of palette values from a file — that is a separate developer-experience
  concern not specified here.

---

## Acceptance criteria

The module is done when:

1. `zig build test-theme-swap` passes all tests in `src/app/theme_swap_test.zig`.
2. After `setTheme(Theme.build(Palette.default(), .dark))`, `app.tokens.bg_canvas` equals
   the dark-mode canvas color from the default palette.
3. After `setTheme`, all elements are dirty (verified by `hasDirty()` returning true).
4. After `rebuildStyles`, a button element's `_style[idx].background` equals the dark-mode
   `tokens.accent` (re-resolved from `defaultStyleFor(.button, new_tokens)`).
5. `toggleTheme` called twice returns to the original mode and token set.
6. `_current_palette` and `_current_mode` are updated correctly by both `setTheme` and
   `toggleTheme`.
7. An element with saved class `"bg-canvas"` gets its background updated to the new
   `tokens.bg_canvas` after `rebuildStyles`.
8. The checklist for this item is fully ticked.

---

## Edge cases (each has a test)

- Scene with zero live elements — `rebuildStyles` is a no-op; `setTheme` still updates
  `self.tokens` and calls `markAllDirty()` without crashing.
- Element with empty class string — style reverts to `defaultStyleFor(kind, new_tokens)`,
  which is correct.
- `setTheme` called with the same theme that is already active — style is rebuilt and all
  elements are dirtied; this is acceptable (idempotent but not no-op).
- `setTheme` called from inside a `CallbackFn` (button click handler) — safe because
  callbacks fire after layout and before render, on the main thread.
