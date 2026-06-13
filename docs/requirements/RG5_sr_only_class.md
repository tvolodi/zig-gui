# RG5 — M17-05: Screen-reader-only text

> Roadmap item: M17-05
> Depends on: M17-01 (AccessNode), Module 06 (markup), Module 05 (theme)
> Read `00_constitution.md` before this file.

## Purpose

Add an `sr-only` Tailwind utility class that renders an element visually hidden but present in the accessibility tree and DOM. This is used for:

- **Hidden labels:** `<input aria-label="Search" class="sr-only" />` — the label is announced by screen readers but not drawn.
- **Skip links:** `<Link href="#main" class="sr-only">Skip to main content</Link>` — normally invisible, only visible on focus.
- **Status announcements:** `<Text class="sr-only" id="status">Loading...</Text>` — updated dynamically, announced when changes occur.

The element is removed from the visual rendering (opacity=0, or display-like behavior) but remains in the accessibility tree and continues to occupy layout space (or takes zero space, depending on variant).

## What to build

### Tailwind `sr-only` class resolution — `src/06/types.zig`

Extend `resolveClasses()` to recognize the `sr-only` class:

```zig
pub fn resolveClasses(classes: []const u8, tokens: Tokens) ComputedStyle {
    var style = ComputedStyle{ /* defaults */ };
    
    // ... iterate over class tokens ...
    
    if (std.mem.eql(u8, class, "sr-only")) {
        // Set visual hiding without removing from layout/accessibility tree
        style.opacity = 0.0;              // Fully transparent
        style.position = .absolute;       // Or use display:none-like semantics
        style.width = 0;                  // Zero-width
        style.height = 0;                 // Zero-height
        style.overflow = .hidden;         // Clip any overflow
        style.pointer_events = .none;     // Don't capture input
    }
    
    // ... other classes ...
    
    return style;
}
```

**Alternative implementations:**

1. **Opacity-based (recommended for v1):** Set `opacity = 0.0`. Element remains in layout, just transparent. Cursor clicks pass through (pointer_events=none).
2. **Position-based:** Set `position = absolute`, `width = 0`, `height = 0`, `overflow = hidden`. Element is removed from layout entirely.
3. **Visibility-based:** Use a `visibility: hidden` style (if added to `ComputedStyle`). Different from opacity: element takes no layout space.

**Recommendation:** Use opacity-based for v1 (simplest, fewest changes to layout engine). Element remains in the viewport flow but is 100% transparent. The renderer already supports `opacity` (R45).

### Layout and rendering behavior

- **Layout:** The element participates in layout as normal (takes up space). Setting `width=0; height=0` makes it take zero space, which is often desired for `sr-only`.
- **Rendering:** The renderer applies the opacity (0.0), so no pixels are drawn. Even if the element has visible children, they are clipped because the parent is invisible.
- **Input:** Pointer events are disabled (`pointer_events: none`), so clicks pass through to elements below.
- **Accessibility tree:** The element remains in the `AccessNode` tree. Screen readers can find and navigate to it, and its content is announced.

### Example markup

```
<!-- Search input with hidden label -->
<Row>
    <Input 
        id="search"
        placeholder="Enter search terms"
    />
    <Label for="search" class="sr-only">
        Search the catalog
    </Label>
</Row>

<!-- Skip link (normally hidden, visible on focus) -->
<Link href="#main-content" class="sr-only focus:not-sr-only">
    Skip to main content
</Link>

<!-- Live status region (off-screen) -->
<Text class="sr-only" role="status" aria-live="polite">
    Saving changes...
</Text>
```

### `sr-only` variants and combinations

**Base `sr-only`:** Element is invisible and takes zero space.

**With `focus:not-sr-only`:** Element is invisible normally but becomes visible (opacity=1, width/height restored) on focus. Useful for skip links.

```zig
// In class resolver:
if (std.mem.eql(u8, class, "focus:not-sr-only")) {
    // When the element has focus pseudo-state, override sr-only
    // pseudo_style_set[.focus] = ComputedStyle{ opacity = 1.0, width = auto, height = auto, ... }
}
```

This requires coordinating with the pseudo-state system (module 05 / 09). For v1, `focus:not-sr-only` may be a post-release refinement.

### Module 05 — no changes required

The `sr-only` class resolves purely through Tailwind class resolution in module 06. No changes to `Tokens` or theme are needed.

### Module 06 — integration

In `resolveClasses()` and/or the Tailwind lexer:

```zig
pub fn resolveClasses(classes: []const u8, tokens: Tokens) ComputedStyle {
    var style = ComputedStyle{ ./* defaults */ };
    var iter = std.mem.splitSequence(u8, classes, " ");
    
    while (iter.next()) |class| {
        if (std.mem.eql(u8, class, "sr-only")) {
            style.opacity = 0.0;
            style.width = 0;
            style.height = 0;
            style.overflow = .hidden;
            style.pointer_events = .none;
        } else if (/* other Tailwind classes */) {
            // ...
        }
    }
    
    return style;
}
```

### Module 07 — no changes required

The `sr-only` class is pure styling; no special widget logic is needed. The element is instantiated normally, participates in layout, and the renderer applies the opacity as usual.

### Module 09 (renderer) — no changes required

The renderer already handles `opacity`, `width`, `height`, and `pointer_events`. No special case needed for `sr-only`.

### Glossary entry — `docs/specs/glossary.md`

Add:

```
## sr-only

A Tailwind utility class (M17-05) that hides an element visually while keeping it in the
accessibility tree. The element is rendered fully transparent (`opacity = 0.0`) and takes
zero layout space (`width = 0`, `height = 0`). Useful for hidden labels, skip links, and
live status regions that screen readers should announce but sighted users should not see.
Variants like `focus:not-sr-only` make the element visible on focus (skip links).

See: M17-05 (RG5), `src/06/types.zig` resolveClasses.
```

## Non-goals (DO NOT implement — INV-5.4)

- **No aria-live / aria-atomic regions.** Announcement regions that fire when content changes are post-v1.
- **No `focus:not-sr-only` (v1).** Focus-state variants can be added later if needed.
- **No hover/active state variants of sr-only.** Only the base class for v1.
- **No JS/CSS-like `.show()` / `.hide()` methods.** The element's visibility is determined purely by its `class` string at instantiation time.
- **No display-based hiding (post-v1).** v1 uses opacity for simplicity. `display: none` would require layout engine awareness of visibility, which is more complex.
- **No macOS or other platform support.** This is a cross-platform styling feature.

## Acceptance criteria

1. The `sr-only` class is recognized by `resolveClasses()` in module 06.
2. When `sr-only` is present in an element's class string:
   - `ComputedStyle.opacity` is set to `0.0`.
   - `ComputedStyle.width` and `height` are set to `0` (or a layout-based helper sets them to zero).
   - `ComputedStyle.overflow` is set to `.hidden`.
   - `ComputedStyle.pointer_events` is set to `.none` (if that field exists; else render-time clip is acceptable).
3. The element participates in layout but takes zero or minimal space.
4. The renderer does NOT draw any pixels for the element (opacity=0).
5. The element remains in the `AccessNode` tree and can be navigated to by screen readers.
6. Unit tests cover:
   - `resolveClasses("sr-only", tokens)` produces the expected style (opacity=0, size=0).
   - An element with `class="sr-only"` instantiates without error.
   - The element's bounding rect is zero (or minimal).
   - No draw commands are emitted for the element (opacity=0).
   - The element's `AccessNode` is still present and readable.
7. Visual check (`zig build visual-check`) confirms that `sr-only` elements are not visible.
8. Manual test: Create a button with `<Button class="sr-only">Hidden button</Button>` and confirm:
   - The button is not drawn on screen.
   - The button is still focusable via keyboard (Tab).
   - The button's label is announced by a screen reader.
9. No Zig compiler errors or warnings.
10. Hot-reload correctly applies/removes sr-only when the class string changes.

## Open questions

1. **Width/height behavior:** Should `sr-only` set `width=0; height=0` (zero space), or just `opacity=0` (takes up space but invisible)?
   - **v1 choice:** `opacity=0` only. Simpler, no layout changes. Variant `sr-only-space-zero` can be added later for zero-space hiding.
2. **Pointer events:** Should we set a `pointer_events` field on `ComputedStyle`, or rely on the zero-size rect to prevent clicks?
   - **v1 choice:** No new `ComputedStyle` field. Zero size is sufficient; pointer events will naturally miss a zero-size element.
3. **Focus behavior:** Should `sr-only` elements still be focusable (for skip links), or should they be removed from the tab order?
   - **v1 choice:** Focusable by Tab. Sighted users using keyboard-only navigation (accessibility power users) benefit from being able to reach `sr-only` elements. Skip links are a common example.
