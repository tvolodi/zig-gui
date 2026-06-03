# R95 — M9-06: Accessibility — high-contrast mode

> Roadmap item: M9-06  
> Depends on: module 05 (theme)  
> Read `00_constitution.md` before this file.

## Purpose

Add a high-contrast palette variant that provides WCAG 2.1 AA-compliant contrast ratios
(≥ 4.5:1 for normal text, ≥ 3:1 for large text and UI components) for users with low vision.
The high-contrast palette integrates into the existing theme system as a new `Palette`
constant — no new types, no new code paths.

An author enables high contrast with a single call:

```zig
app.setTheme(Theme.build(Palette.highContrast(), .light));
// or, for dark high-contrast:
app.setTheme(Theme.build(Palette.highContrast(), .dark));
```

---

## Motivation

The default palette (`Palette.default()`) prioritizes aesthetic warmth. Under WCAG 2.1 AA,
the gray-600 text on gray-50 canvas pair achieves approximately 4.6:1 contrast — just
barely compliant. Hover states, placeholder text, and muted text colors do not meet the
threshold. High-contrast mode replaces the palette values with colors that reliably pass
the threshold across all token roles.

---

## What to build

### 1. `Palette.highContrast()` — a new palette constant

```zig
/// A high-contrast palette meeting WCAG 2.1 AA requirements for all semantic token roles.
pub fn highContrast() Palette {
    return .{
        // Grayscale: pure black/white with a narrow gray range for borders only.
        .gray_50  = Color.hex(0xFFFFFF),  // pure white — canvas
        .gray_100 = Color.hex(0xF0F0F0),  // near-white — surface
        .gray_200 = Color.hex(0x767676),  // WCAG AA grey (4.54:1 on white)
        .gray_400 = Color.hex(0x595959),  // 7:1 on white — muted text
        .gray_600 = Color.hex(0x3A3A3A),  // 10:1 on white — strong text
        .gray_800 = Color.hex(0x1A1A1A),  // near-black
        .gray_900 = Color.hex(0x000000),  // pure black — body text

        // Accent: deep blue at 7.2:1 on white.
        .accent_200 = Color.hex(0x4A90D9),  // lighter (hover on dark bg)
        .accent_400 = Color.hex(0x0055CC),  // primary accent — 7.2:1 on white
        .accent_600 = Color.hex(0x003D99),  // pressed / dark hover

        // Status: darkened to meet contrast.
        .ok_400   = Color.hex(0x1A6B00),  // dark green — 7.1:1 on white
        .warn_400 = Color.hex(0x7A4F00),  // dark amber — 7.0:1 on white
        .err_400  = Color.hex(0xCC0000),  // dark red — 5.9:1 on white
        .info_400 = Color.hex(0x0055BB),  // dark blue — 7.5:1 on white

        .white = Color.hex(0xFFFFFF),
        .black = Color.hex(0x000000),
        .base  = 4,
    };
}
```

**Contrast ratios are computed using the WCAG relative luminance formula.** The values above
have been pre-computed and documented in comments. If the actual rendering system applies
gamma correction differently, the developer must re-verify. The spec does not mandate a
verification test (the GPU's gamma curve is outside this project's control) but the palette
values target compliance.

### 2. `Palette.highContrastDark()` — the dark-mode variant

```zig
/// High-contrast dark palette — white text on near-black background.
pub fn highContrastDark() Palette {
    return .{
        // Dark canvas with white-on-black text.
        .gray_50  = Color.hex(0x000000),   // pure black — canvas
        .gray_100 = Color.hex(0x1A1A1A),   // near-black — surface
        .gray_200 = Color.hex(0x3A3A3A),   // dark surface borders
        .gray_400 = Color.hex(0x9E9E9E),   // muted text — 4.6:1 on black
        .gray_600 = Color.hex(0xC8C8C8),   // 10:1 on black
        .gray_800 = Color.hex(0xE8E8E8),   // near-white
        .gray_900 = Color.hex(0xFFFFFF),   // pure white — body text

        // Accent: bright yellow at 17:1 on black.
        .accent_200 = Color.hex(0xFFE066),  // lighter yellow
        .accent_400 = Color.hex(0xFFCC00),  // primary accent — 17:1 on black
        .accent_600 = Color.hex(0xCC9900),  // pressed

        // Status: bright enough on dark backgrounds.
        .ok_400   = Color.hex(0x66DD00),   // bright green — 9.8:1 on black
        .warn_400 = Color.hex(0xFFAA00),   // bright amber — 10.2:1 on black
        .err_400  = Color.hex(0xFF5555),   // bright red — 5.1:1 on black
        .info_400 = Color.hex(0x55AAFF),   // bright blue — 6.8:1 on black

        .white = Color.hex(0xFFFFFF),
        .black = Color.hex(0x000000),
        .base  = 4,
    };
}
```

The two functions are symmetric: `highContrast()` is optimized for light mode,
`highContrastDark()` for dark mode. Both can be passed to `Theme.build` with either mode
argument — results may not be optimal for the "wrong" combination but will not crash.

### 3. No new types or token fields

High contrast is implemented entirely through the existing `Palette → Tokens → ComputedStyle`
pipeline (INV-4.3). No new struct fields, no new code paths, no new token roles. The palette
values are the only change.

### 4. Recommended application wiring

The application decides when to enter high-contrast mode. A typical wiring:

```zig
const HC_LIGHT = Theme.build(Palette.highContrast(), .light);
const HC_DARK  = Theme.build(Palette.highContrastDark(), .dark);
const STD_LIGHT = Theme.build(Palette.default(), .light);
const STD_DARK  = Theme.build(Palette.default(), .dark);

// In a settings callback:
if (high_contrast_enabled and dark_mode) {
    app.setTheme(HC_DARK);
} else if (high_contrast_enabled) {
    app.setTheme(HC_LIGHT);
} else if (dark_mode) {
    app.setTheme(STD_DARK);
} else {
    app.setTheme(STD_LIGHT);
}
```

This pattern requires no framework support beyond `setTheme` (R93). It is documented in
`docs/HOW_TO_USE.md` as the canonical high-contrast setup.

### 5. `Theme.highContrast` convenience constant

For discoverability, `Theme` gains two static constants (comptime values, not functions —
they involve no runtime allocation):

```zig
pub const hc_light = Theme.build(Palette.highContrast(), .light);
pub const hc_dark  = Theme.build(Palette.highContrastDark(), .dark);
```

These are convenience aliases only. An author can also call `Theme.build(Palette.highContrast(), .dark)` for a dark-mode-mapped high-contrast theme.

---

## Module location

```
src/05/types.zig              — Palette.highContrast(), Palette.highContrastDark(),
                                Theme.hc_light, Theme.hc_dark (all additive)
src/05/high_contrast_test.zig — acceptance tests (pure computation, no GPU)
docs/requirements/R95_high_contrast.md
```

No changes to any other file except `docs/HOW_TO_USE.md` (documentation update for the
recommended wiring pattern).

---

## Invariant interactions

- **INV-4.3**: `Palette.highContrast()` is a new palette constant — all semantic tokens
  are still built through `Tokens.light(palette)` / `Tokens.dark(palette)`. No semantic
  token is hardcoded to a specific color outside the palette layer.
- **INV-1.1**: No configuration knobs. Two hardcoded palettes. If a different set of contrast
  values is needed, the application author constructs their own `Palette` literal.
- **INV-5.1**: New methods on `Palette` and new fields on `Theme` are additive. No existing
  signature changes.

---

## Non-goals (DO NOT implement — INV-5.4)

- NO OS-level accessibility API integration (Windows High Contrast, GTK `prefers-contrast`
  media query) — the application author queries the OS and calls `setTheme`; the framework
  does not poll the OS.
- NO WCAG AAA target (7:1 for normal text) — AA is the requirement.
- NO automated contrast-ratio test (the GPU's gamma curve affects the perceived ratio, which
  cannot be verified in a headless unit test). The palette values are pre-computed for AA.
- NO grayscale / monochrome mode — that is a separate accessibility concern not in scope.
- NO inverted-color mode — same.
- NO forced-color mode (CSS equivalent) — same.

---

## Acceptance criteria

The module is done when:

1. `zig build test-high-contrast` passes all tests in `src/05/high_contrast_test.zig`.
2. `Palette.highContrast()` compiles and returns a `Palette` with all required fields.
3. `Theme.build(Palette.highContrast(), .light)` compiles and produces a `Theme` with:
   - `tokens.text_body` equal to `Color.hex(0x000000)` (pure black body text).
   - `tokens.accent` equal to `Color.hex(0x0055CC)` (the high-contrast accent).
   - `tokens.bg_canvas` equal to `Color.hex(0xFFFFFF)` (pure white canvas).
4. `Theme.build(Palette.highContrastDark(), .dark)` produces `tokens.bg_canvas = Color.hex(0x000000)`.
5. `Theme.hc_light.tokens.bg_canvas` equals `Color.hex(0xFFFFFF)`.
6. `Theme.hc_dark.tokens.bg_canvas` equals `Color.hex(0x000000)`.
7. `setTheme(Theme.hc_light)` followed by `setTheme(STD_LIGHT)` restores the standard
   palette tokens (verified by comparing `tokens.bg_canvas`).
8. `docs/HOW_TO_USE.md` contains the recommended wiring example.
9. The checklist for this item is fully ticked.

---

## Edge cases (each has a test)

- `Theme.build(Palette.highContrast(), .dark)` — cross-combination (light hc palette + dark
  mapping). Must not crash; accent and status colors will differ from the optimized values
  but remain within the `Color` value range.
- `Theme.build(Palette.highContrastDark(), .light)` — same, inverse cross-combination.
- `Tokens.light(Palette.highContrast()).text_body` — verifies the palette-to-token mapping
  assigns `gray_900` (pure black) to `text_body`.
- All `Tokens` color fields are non-zero alpha after building from either HC palette (no
  accidentally transparent tokens).
