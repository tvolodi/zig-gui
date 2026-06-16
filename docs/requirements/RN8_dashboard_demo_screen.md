# RN8 — Dashboard Demo Screen (Finova financial dashboard reference)

> Status: `planned` — Milestone 27 extension.
> Reference: "Finova" asset-management dashboard mock (attached screenshot).
> Read `docs/specs/00_constitution.md` and `docs/requirements/RN0_dashboard_gap_analysis.md`
> before this file.
> Use project-relative paths only. Never use absolute Windows paths starting with `c:\`.

## 1. Purpose

Add a **Dashboard** screen to the Showcase demo application that demonstrates all M27
features (RN1–RN7) through a realistic financial dashboard layout closely matching the
"Finova" reference mock. This is a demo/showcase screen — all data is static, generated
in Zig at compile time; no file I/O, no network.

The screen lives at `src/demo/screens/dashboard.zig`. It is wired into `main.zig` as an
11th screen, alongside the existing 10. The sidebar expands from 10 to 11 buttons.

---

## 2. Sidebar expansion (prerequisite changes)

The existing sidebar infrastructure supports exactly 10 screens. To add Dashboard as the 11th:

### 2a. `src/demo/shared/types.zig`
- Add `dashboard_ctx: ?*anyopaque = null` to `GlobalState`.
- Add `dashboard: SidebarCb` to `SidebarCbs`.
- Add `if (std.mem.eql(u8, name, "dashboard")) return global.dashboard_ctx;` to `ctxForScreen`.
- Expand `wireSidebarCallbacks` pairs array from 10 to 11 entries, adding
  `.{ .idx = 12, .cb = &global.sidebar_cbs.dashboard }`.
  - Active button range expands to `2 ≤ active_btn_idx ≤ 12`.

### 2b. `src/demo/shared/sidebar.zig`
- Expand `SCREEN_NAMES` and `SCREEN_LABELS` from `[10]` to `[11]` by appending
  `"dashboard"` / `"Dashboard"`.
- Expand `_btn_attrs` and `_btns` from 10 to 11 elements.
- The new button is `NodeDesc{ .tag = "Button", .classes = "w-full", .attrs = &_btn_attrs[10] }`.
- `buildSidebar()` returns a Column with 11 children — no other change.

### 2c. `src/demo/main.zig`
- Add `const dashboard_screen = @import("screens/dashboard.zig");` alongside existing imports.
- Add `var dashboard_ctx = dashboard_screen.DashboardCtx{ .global = undefined };` to ctx
  declarations.
- Wire `global.dashboard_ctx = &dashboard_ctx; dashboard_ctx.global = &global;`.
- Add `global.sidebar_cbs.dashboard = SidebarCb{ .global = &global, .screen_name = "dashboard" };`.
- Register: `try nav.register("dashboard", dashboard_screen.build);`.
- Handle `--initial-screen dashboard` branch: `nav.requestPush("dashboard", &dashboard_ctx);`.
- Wire m13 at the same time (it is already prepared in types.zig/sidebar.zig but missing from
  main.zig): import `screens/m13.zig`, add `m13_ctx`, wire `m13_screen.build`, handle
  `--initial-screen m13`. This completes the existing m13 slot.

---

## 3. Dashboard screen specification (`src/demo/screens/dashboard.zig`)

### 3a. Layout overview

```
┌───────────────────────────────────────────────────────────┐
│ ScrollView (fill content area)                            │
│  Column p-4 gap-4                                         │
│  ┌─────────────────────────────────────────────────────┐  │
│  │ ROW: "Overview" heading + filter dropdowns          │  │
│  ├─────────────────────────────────────────────────────┤  │
│  │ ROW: 4 KPI cards (equal width)                      │  │
│  ├─────────────────────────────────────────────────────┤  │
│  │ ROW: Line chart (2/3 width) + Top Assets (1/3)      │  │
│  ├─────────────────────────────────────────────────────┤  │
│  │ ROW: Transactions (1/3) + Types (1/3) + Members (1/3)│ │
│  └─────────────────────────────────────────────────────┘  │
└───────────────────────────────────────────────────────────┘
```

### 3b. DashboardCtx struct

```zig
pub const DashboardCtx = struct {
    global: *shared.GlobalState,
};
```

State for the maskable value (eye-icon toggle) is managed via `scene.maskableValueStateOf`.
No other mutable state is needed; the screen is largely static.

### 3c. Section 1 — Overview header row

A `Row` with `justify-between items-center gap-4`:

- Left: `Text` with `text = "Overview"`, `classes = "text-xl font-bold"`.
- Right: A `Row gap-2` containing three `Dropdown` widgets:
  - **Currency**: options `["USD", "SGD", "EUR", "ALL"]`, initial index 0.
  - **Assets**: options `["All", "Aircraft", "Real Estate", "Vessel", "Company", "Car", "Funds"]`, initial index 0.
  - **Last 30 days**: options `["Last 7 days", "Last 30 days", "This month", "Last 3 months"]`, initial index 1.

### 3d. Section 2 — KPI cards row

A `Row gap-4` containing four `Card` widgets, each with `p-4 grow`:

**Card 1 — Asset Total (uses `MaskableValue` and eye-icon toggle)**

Static layout built from plain `NodeDesc` nodes:
- Label: `Text "Asset Total" text-sm text-muted`
- Value row: `Row items-center gap-2`
  - `MaskableValue` node with `text = "$32,499.93"`, `classes = "text-xl font-bold"`.
    The eye-button callback calls `scene.setMaskableVisible(idx, !visible)` to toggle.
  - `Button` with `text = "👁"` (or the Unicode eye glyph U+1F441, or just `"•••"` label for
    visibility — whichever renders cleanly; use `"\xf0\x9f\x91\x81"` UTF-8). On click:
    look up the MaskableValue element by scanning for `.maskable_value` kind, toggle
    `scene.setMaskableVisible`.
- Trend row: `TrendBadge` node, initialized via `scene.setTrendValue(idx, 18.20, .up)`.
  Label after: `Text "Compared to last month" text-xs text-muted`.

**Card 2 — Asset in USD**

- Flag/label row: `Row items-center gap-1` — a `Card w-4 h-3 bg-raised` (flag placeholder) +
  `Text "Asset in USD" text-sm text-muted`.
- Value: `Text "$9,732.58" text-lg font-bold`. Use `locale.formatCurrency` in a static
  buffer at build time:
  ```zig
  var usd_buf: [32]u8 = undefined;
  const usd_str = locale.formatCurrency(&usd_buf, 9732.58, .usd, locale.Locale.en_US) orelse "$9,732.58";
  ```
- Sub-label: `Text "$9,732.58 / 30.0%" text-xs text-muted`.
- Trend: `TrendBadge` initialized with `scene.setTrendValue(idx, -0.33, .down)`.
  Label: `Text "Compared to last month" text-xs text-muted`.

**Card 3 — Asset in SGD**

- Flag/label row: flag placeholder + `Text "Asset in SGD"`.
- Value: `formatCurrency(&sgd_buf, 11456.79, .sgd, Locale.en_US)` → `"S$11,456.79"`.
- Sub-label: `Text "S$8,540.32 / 35.3%" text-xs text-muted`.
- Trend: `scene.setTrendValue(idx, 12.95, .up)`.

**Card 4 — Asset in EUR**

- Flag/label row: flag placeholder + `Text "Asset in EUR"`.
- Value: `formatCurrency(&eur_buf, 11310.56, .eur, Locale.de_DE)` → `"€11.310,56"`.
- Sub-label: `Text "€11,852.34 / 34.7%" text-xs text-muted`.
- Trend: `scene.setTrendValue(idx, 11.65, .up)`.

### 3e. Section 3 — Chart + Top Assets row

A `Row gap-4`:

**Left: Asset Total Statistic card** (`Card p-4 grow` taking ~2/3 width via `grow`)

- Header row `Row justify-between items-center`:
  - `Text "Asset Total Statistic" font-bold`
  - `Dropdown` options `["Monthly", "Weekly", "Daily"]` initial 0.
- Chart area: rendered via module 13's `Chart.render()` directly into the scene's draw
  command list. Use a line chart with:
  - `kind = .line`
  - `x = .{ .categories = &[_][]const u8{"Nov 12", "Nov 19", "Nov 26", "Dec 3", "Dec 11"} }`
  - One `Series` with values `[16.2, 17.8, 16.9, 18.5, 17.1]` (millions), color token `"accent"`.
  - `crosshair = .{ .enabled = true, .color_token = "axis" }`.
  - A `ChartFrame` with `width = 420`, `height = 160`, positioned in the card body.
  - Note: The chart is rendered imperatively via `scene.addChartCommands(frame, chart)` or
    equivalent; check `src/13/chart.zig` for the actual public API. If the demo uses a `Chart`
    tag in NodeDesc, use that. If it requires imperative calls, do so in a `buildChart` helper.

**Right: Top Assets card** (`Card p-4` with fixed `w-64`)

- Header row: `Text "Top Assets" font-bold` + `Button "See All" text-sm` (no-op).
- Column headers row `Row justify-between text-xs text-muted`:
  - `Text "Name"`, `Text "Value"`, `Text "Return"`.
- Five asset rows (a `for`-style list via static array, built as separate NodeDescs):

  | Name | Subtitle | Value | Return | Direction |
  |---|---|---|---|---|
  | PP-DFP 2213dk | Aircraft / Aviav | $4,215,600 | 8% | up |
  | PP-KVF | Aircraft / Aviav | $3,875,200 | 5% | down |
  | Casa Praia | Real Estate / Praia / Onshore | $3,654,300 | 6% | up |
  | Residential Apart. | Real Estate / Praia / Onshore | $4,010,800 | 5% | down |
  | Z Company | Company / Technology | $3,921,500 | 6% | down |

  Each row is a `Row justify-between items-center p-1`:
  - Name col `Column`: `Text name font-bold text-sm` + `Text subtitle text-xs text-muted`.
  - Value: `Text value_str text-sm`.
  - Return: `TrendBadge` initialized with `scene.setTrendValue(idx, pct, direction)`.

### 3f. Section 4 — Transactions + Types + Members row

A `Row gap-4`:

**Transactions card** (`Card p-4 grow`)

- Header: `Row justify-between`: `Text "Transactions" font-bold` + `Button "See All" text-sm`.
- Column headers: `Row text-xs text-muted`: `Text "Provider"` + `Text "Type"` + `Text "Amount"`.
- Six transaction rows:

  | Provider | Kind | Amount |
  |---|---|---|
  | PE Blue Capital | Buy | $120,500,000 |
  | PE Black Stone... | Sell | $98,750,000 |
  | PE New Wave Inv | Buy | $139,474,080 |
  | PE Green Holdi... | Buy | $112,620,500 |
  | Global Asset Fu... | Sell | $75,320,800 |
  | Future Growth... | Buy | $89,750,000 |

  Each row is a `Row justify-between items-center p-1 gap-2`:
  - Provider: `Text provider text-sm`.
  - Kind: `Card classes = if Buy then "bg-raised text-sm p-1" else "bg-surface text-sm p-1"`.
    Label text `"Buy"` or `"Sell"`.
  - Amount: `Text amount text-sm`.

**Types card** (`Card p-4 grow`)

- Header: `Row justify-between`: `Text "Types" font-bold` + `Button "See All" text-sm`.
- Stacked proportion bar (a `Row w-full h-2 rounded overflow-hidden`):
  Six colored segments as `Card` children with `grow` proportional to share:
  - Aircraft 30.22% → `Card grow bg-accent h-2`
  - Real Estate 23.57% → `Card grow bg-raised h-2` (different color via inline style)
  - Vessel 22.38% → similar
  - Company 22.08% → similar
  - Car 1.00% → similar
  - Funds 0.75% → similar
  
  Use inline `style:background` set to different palette tokens for each segment.

- Category legend rows (one per type):

  | Color dot | Label | Value | Pct |
  |---|---|---|---|
  | accent | Aircraft | $3,421.38 | 30.22% |
  | raised | Real State | $2,668.50 | 23.57% |
  | ok | Vessel | $2,533.77 | 22.38% |
  | warn | Company | $2,499.80 | 22.08% |
  | err | Car | $198.13 | 1.00% |
  | muted | Funds | $4.21 | 0.75% |

  Each row: `Row items-center gap-2 text-sm`:
  - `Card w-2 h-2 rounded-full bg-{token}` (color dot).
  - `Text label` (grows).
  - `Text value text-muted`.
  - `Text pct text-muted`.

**Members card** (`Card p-4 grow`)

- Header: `Row justify-between`: `Text "Members" font-bold` + `Button "See All" text-sm`.
- Donut chart (RN1 + RN2): A `Chart` with:
  - `kind = .pie`
  - `inner_radius = 0.6`
  - `center_label = "Total"`
  - `series`: one series with values `[40, 30, 15, 10, 5]` (Mary Smith 40%, John Smith 30%,
    Jane Doe 15%, Alex Jo 10%, Harry Doe 5%), color tokens sourced from palette.
  - `callouts`: five entries, one per segment, labels:
    `["Mary Smith\n40%", "John Smith\n15%", "Jane Doe\n30%", "Alex Jo\n10%", "Harry Doe\n5%"]`.
  - `ChartFrame`: `width = 200`, `height = 180`.
  - Note: member avatar images are NOT rendered (avatars require actual image tiles);
    instead use the `Callout` label text only.

---

## 4. Import paths

```zig
const locale = @import("../../app/locale.zig");
const chart_mod = @import("../../13/chart.zig");
const axes_mod = @import("../../13/axes.zig");
const marks_mod = @import("../../13/marks.zig");
```

Check `src/app/locale.zig` for `formatCurrency` signature; it takes `(buf: []u8, amount: f64,
currency: locale.Currency, loc: locale.Locale) ?[]const u8`.

Check `src/13/chart.zig` for `Chart`, `Series`, `Callout`, `CrosshairOptions`, `ChartKind`,
`XData`, `ChartFrame`. Use the same approach as `src/demo/screens/m13.zig` if charts are
rendered imperatively.

---

## 5. Acceptance criteria

- `zig build` compiles without errors.
- The "Dashboard" button appears in the sidebar (11th button, DFS index 12).
- Navigating to Dashboard shows the four-section layout described above.
- The `MaskableValue` for Asset Total toggles between `"$32,499.93"` and `"••••••••••"` on
  button click.
- At least one `TrendBadge` per KPI card shows the correct arrow direction (up/down).
- The line chart renders in the "Asset Total Statistic" card area.
- The donut chart with callouts renders in the "Members" card area.
- `formatCurrency` is used for at least the three KPI card values (USD, SGD, EUR).

---

## 6. Non-goals

- No real data fetching, no file I/O, no network calls.
- No interactive date-range picker in this screen (dropdown for preset is sufficient).
- No member avatar images (callout text labels only).
- No interactive chart zoom/pan.
- No pixel-perfect match to the reference mock (layout structure and feature demonstration
  are the goal, not exact colors or spacing).
