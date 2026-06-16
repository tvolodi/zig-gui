# RN0 — Dashboard gap analysis (financial dashboard reference)

> Status: `analysis` — proposed requirements, not yet scheduled
> Reference: "Finova" asset-management dashboard mock (KPI cards, line chart, donut, lists)
> Read `ROADMAP.md` and `docs/specs/00_constitution.md` before this file.

## Purpose

Determine what the framework still lacks to build a dense financial dashboard of the kind
shown in the reference mock. The conclusion up front: **the framework already covers ~90% of
this screen.** Layout (grid/flex), cards, the sidebar, the data table, avatars/badges, images
(flag icons), gradients, box shadow, tooltips, dropdowns, theming, number/date formatting, and
the chart module (line/bar/area/scatter/pie + hover/tooltip/legend) are all `done`.

What follows separates the screen into **(A) already covered by existing requirements**,
**(B) composable from existing features with no new requirement**, and **(C) genuine gaps that
warrant a new requirement.** Only group C needs work.

## A. Already covered (no action)

| Dashboard element | Covered by |
|---|---|
| Multi-region grid layout, responsive cards | 04 layout, RC2 flex-wrap, RC4 z-index |
| Card surfaces with shadow + rounded corners | R46 box shadow, RD1 rounded clipping |
| Left sidebar nav with icons, active highlight | DEMO_APP sidebar pattern, R80 navigation |
| Search box, "Currency"/"Assets"/"Last 30 days" dropdowns | R32 text input, R33 dropdown |
| Line chart with axes, gridlines, $-formatted ticks | RM1 scales/axes, RM2 line mark |
| Line-chart hover tooltip ("$17,800 / Nov 20") | RM3 hover + tooltip |
| "Top Assets" / "Transactions" lists | R53 list rendering, R79 data table |
| Category color dots, Buy/Sell pills, member avatars | R7B avatar/badge, R7A separator |
| Country-flag icons (USD/SGD/EUR) | R43 image/icon rendering (RGBA tiles) |
| Thousands separators, EU decimal comma (11.310,56) | RE0 number formatting (de_DE/fr_FR) |
| Date range label text, month names | RE1 date/time formatting |
| Donut/ring *primitive* (stroked arc) | RM0 `ArcCmd` width > 0 = donut segment |

## B. Composable — no new requirement

These are real screen features but build cleanly from `done` primitives; document the recipe
in `HOW_TO_USE.md` rather than adding a requirement.

- **Collapsible sidebar groups** ("Asset Management ⌄", "Finance ⌄" with sub-items) =
  R77 accordion wrapping R80 nav buttons.
- **Segmented 100%-proportion bar** ("Types" multi-color bar) = a `w-full` flex row of
  rects with `grow` weights from the data, or a one-row stacked bar (RM2 stacked option).
- **"Compared to last month" KPI rows** = R53 list + R7B badge + RE0 formatting.

## C. Genuine gaps — new requirements proposed

Seven items. Each is small and sits at the leaf/component layer; none touches the
data-oriented core or a frozen invariant.

### RN1 — Donut chart kind (pie with inner radius + center label)
RM2 `pie` emits only filled wedges (`ArcCmd` width 0). The mock's "Members" and "Types"
visuals are donuts with a hollow center, and the center often carries a total. The RM0
primitive already supports the ring (`ArcCmd` width > 0); the gap is at the **chart-component**
layer: add `inner_radius` (0 = pie, >0 = donut) to the pie mark and an optional center-label
slot. Acceptance: `values [30,20,50]`, `inner_radius 0.6` → three ring segments leaving a
hole; center text renders centered in the hole.

### RN2 — Chart annotations / leader-line callouts
The "Members" donut places external labels (name + %) connected to their segment by a leader
line, with avatar images positioned around the ring. RM1–RM3 have no annotation layer. Add a
bounded annotation set: a leader line (`PolylineCmd`) from a segment's mid-angle to an outboard
label box, plus image/text placement at a computed radial point. Acceptance: each segment can
emit one callout; leader lines do not overlap labels for ≥5 segments.

### RN3 — Date-range picker
R78 `DatePicker` selects a single ISO date. The toolbar shows a **range**
("18 Oct – 18 Nov 2024") plus preset shortcuts ("Last 30 days", "Last 30 days ⌄"). Extend with
a `DateRangeValue { start, end }`, dual-month calendar or two linked fields, and a preset list
(today / last 7 / last 30 / this month / custom). Acceptance: selecting start then end stores
both; presets set both atomically; end < start is rejected.

### RN4 — Currency formatting
RE0 handles separators but not currency. The mock shows symbol *prefix* ($9,732.58),
*compound prefix* (S$11,456.79), and locale symbol with EU grouping (€11.310,56). Add
`formatCurrency(amount, currency, locale)` resolving symbol, symbol position (pre/post),
spacing, and decimal places per currency, layered on RE0. Acceptance: USD/SGD/EUR each render
with correct symbol, position, and grouping for the active locale.

### RN5 — Maskable / reveal value widget
The "Asset Total" has an eye icon that hides/reveals the figure. Provide a small reusable
pattern: a value bound to a `Signal(bool)` that renders either the formatted value or a
masked glyph run (`••••••`), toggled by an icon button. Acceptance: toggling the signal swaps
masked/clear text through the normal dirty path; masked state never lays out to a different
width that leaks magnitude (fixed-width mask).

### RN6 — Trend / delta indicator component
The "↑ 18.20% Compared to last month" / "↓ 0.33%" rows are a recurring KPI element: an arrow
glyph + percentage + semantic color (positive = up/green, negative = down/red), color sourced
from the theme palette (INV-4.3), not raw hex. Provide a `<TrendBadge value direction>`
component. Acceptance: positive value → up arrow + positive token color; negative → down arrow
+ negative token color; zero → neutral.

### RN7 — Chart crosshair / reference guide on hover
RM3 emphasizes the hovered datum and shows a tooltip, but the line chart also draws a **dashed
vertical guide** across the plot at the hovered x with a value flag pinned to the line. Add an
optional crosshair to RM3: a dashed `PolylineCmd` at the hovered x (and/or y), reusing the
existing hover signal. Acceptance: moving the mouse moves a single dashed vertical line snapped
to the nearest datum x; hides on mouse-out.

## Suggested grouping

These fit a new **Milestone 27 — Dashboard / data-product widgets**, dependent on M26 (charts),
R78 (date picker), RE0/RE1 (formatting), R7B (badge). RN1, RN2, RN7 extend the chart module
(13); RN3 extends the date picker; RN4 extends i18n (15); RN5/RN6 are new leaf components (07).
 
## Out of scope (consistent with v2 non-goals)

Animated chart transitions and zoom/pan remain out of scope (RM2/RM3 non-goals). Real-time
streaming data, websocket/data-source plumbing, and export-to-PDF/CSV are application concerns,
not framework requirements.
