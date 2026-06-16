# RN12 — Renderer quality pass: shadcn-equivalent widget visuals

> Status: `planned` — visual polish milestone.
> Motivation: widget primitives don't match modern design system expectations.
> Read `docs/specs/00_constitution.md` before this file.
> Use project-relative paths only.

## 1. Default palette — zinc/neutral

Replace `Palette.default()` in `src/05/types.zig` with a zinc-neutral palette
matching shadcn/ui's default theme.

| Token | Old (teal) | New (zinc) | shadcn reference |
|---|---|---|---|
| gray_50 | #F9F9F8 | #FAFAFA | zinc-50 |
| gray_100 | #F1EFE8 | #F4F4F5 | zinc-100 |
| gray_200 | #D8D5CA | #E4E4E7 | zinc-200 |
| gray_400 | #A09C90 | #A1A1AA | zinc-400 |
| gray_600 | #5A5750 | #52525B | zinc-600 |
| gray_800 | #29271F | #27272A | zinc-800 |
| gray_900 | #0F0E09 | #18181B | zinc-900 |
| accent_200 | #5DCAA5 | #E4E4E7 | zinc-200 (subtle tint) |
| accent_400 | #1D9E75 | #18181B | zinc-900 (shadcn primary) |
| accent_600 | #0F6E56 | #09090B | zinc-950 |
| ok_400 | #639922 | #16A34A | green-600 |
| warn_400 | #BA7517 | #D97706 | amber-600 |
| err_400 | #E24B4A | #DC2626 | red-600 |

white/black: unchanged. This gives all widgets the shadcn look immediately.

## 2. Radio button renderer

In `src/09/types.zig`, radio case:

**Current problems:**
- Size = `font_size * dpi_scale` (≈14px) → too small
- Dot radius = `r * 0.4` (≈2.8px) → looks like a pixel artifact
- Border stays gray even when selected
- No focus ring

**Target (shadcn RadioGroupItem):**
- Fixed outer diameter: 16px
- Border: 1px `border_default` (zinc-200) when unselected, 1px `accent` (zinc-900) when selected
- When selected: 6px solid accent dot (centered)
- When focused: 2px offset ring in accent color
- When hovered: border becomes `border_strong` (zinc-400)

**New code pattern:**
```
S = 16.0  (fixed, ignoring font_size)
r = S / 2 = 8.0
ccx = computed.x + r
ccy = computed.y + computed.h / 2

// Background circle (white/raised)
emitFilledCircle(ccx, ccy, r, bg_raised)

// Border ring (thin, 1px simulated by two circles)
ring_color = if selected → accent elif hovered → border_strong else border_default
emitFilledCircle(ccx, ccy, r, ring_color)          // outer
emitFilledCircle(ccx, ccy, r - 1.5, bg_raised)     // inner (creates 1.5px ring)

// Selection dot (6px = r * 0.75)
if selected:
    emitFilledCircle(ccx, ccy, r * 0.47, accent)

// Focus ring (2px gap, 2px width → outer circle at r+4)
if focused:
    emitFilledCircle(ccx, ccy, r + 4, accent with a=60)   // soft focus halo
    emitFilledCircle(ccx, ccy, r + 2, bg_raised)           // gap

// Label: same as before (r px gap)
```

## 3. Checkbox renderer

**Target (shadcn Checkbox):**
- Fixed 16px × 16px square, 3px border-radius
- Unselected: white bg, 1px zinc-200 border
- Checked: zinc-900 bg, zinc-900 border, white checkmark
- Focus: 2px offset ring

**Changes:**
- Size: use `16.0` fixed instead of `font_size * dpi_scale`
- Radius: `3.0` (not the font-derived value)
- Checkmark: draw as two `aa_filled_rect` strokes at better proportions

## 4. Button renderer

No code change needed in the renderer — buttons look correct once the palette changes
(accent = zinc-900 gives clean dark buttons). Just verify button height in theme.

## 5. Input renderer

Ensure the input border radius is applied: currently border_rect has no radius parameter.
The background rect already uses `style.radius`, so the border visually doesn't match.
Fix: use `aa_filled_rect` for the border (simulated as outer rect minus inner) or add a
`border_radius` field to `border_rect`.

**For now:** ensure `style.radius` for input defaults to `tokens.radius_sm` (4px) so the
background rect corners are visible and match the border.

## 6. Acceptance criteria

- `zig build` exits 0.
- Default palette is zinc-neutral; no existing test hardcodes old palette hex values.
- Radio button: selected state shows a clear centered dot, border changes to accent color.
- Checkbox: 16px square, 3px radius.
- All existing tests pass.
