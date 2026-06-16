//! dashboard.zig — Dashboard demo screen (Screen 11).
//!
//! Demonstrates M27 features: MaskableValue, TrendBadge in a Finova-style
//! financial dashboard layout. Currency values shown as static strings
//! (locale.zig is not exposed as a named module in the demo build).

const std = @import("std");
const mod07 = @import("../07/types.zig");
const mod05 = @import("../05/types.zig");
const mod06 = @import("../06/types.zig");

const Scene          = mod07.Scene;
const Tokens         = mod05.Tokens;
const NodeDesc       = mod06.NodeDesc;
const Attr           = mod06.Attr;
const DropdownOption = mod07.DropdownOption;

const shared  = @import("../shared/types.zig");
const sidebar = @import("../shared/sidebar.zig");

pub const DashboardCtx = struct {
    global: *shared.GlobalState,
};

// ---------------------------------------------------------------------------
// Module-level Dropdown option storage (program lifetime — pointer stability).
// ---------------------------------------------------------------------------

var _cur_vals: [4]u8 = .{ 0, 1, 2, 3 };
var _cur_opts: [4]DropdownOption = .{
    .{ .label = "USD", .value = &_cur_vals[0] },
    .{ .label = "SGD", .value = &_cur_vals[1] },
    .{ .label = "EUR", .value = &_cur_vals[2] },
    .{ .label = "ALL", .value = &_cur_vals[3] },
};

var _asset_vals: [7]u8 = .{ 0, 1, 2, 3, 4, 5, 6 };
var _asset_opts: [7]DropdownOption = .{
    .{ .label = "All",         .value = &_asset_vals[0] },
    .{ .label = "Aircraft",    .value = &_asset_vals[1] },
    .{ .label = "Real Estate", .value = &_asset_vals[2] },
    .{ .label = "Vessel",      .value = &_asset_vals[3] },
    .{ .label = "Company",     .value = &_asset_vals[4] },
    .{ .label = "Car",         .value = &_asset_vals[5] },
    .{ .label = "Funds",       .value = &_asset_vals[6] },
};

var _period_vals: [4]u8 = .{ 0, 1, 2, 3 };
var _period_opts: [4]DropdownOption = .{
    .{ .label = "Last 7 days",   .value = &_period_vals[0] },
    .{ .label = "Last 30 days",  .value = &_period_vals[1] },
    .{ .label = "This month",    .value = &_period_vals[2] },
    .{ .label = "Last 3 months", .value = &_period_vals[3] },
};

var _stat_vals: [3]u8 = .{ 0, 1, 2 };
var _stat_opts: [3]DropdownOption = .{
    .{ .label = "Monthly", .value = &_stat_vals[0] },
    .{ .label = "Weekly",  .value = &_stat_vals[1] },
    .{ .label = "Daily",   .value = &_stat_vals[2] },
};

pub fn build(
    scene: *Scene,
    tokens: Tokens,
    app: *anyopaque,
    ctx: ?*anyopaque,
) anyerror!void {
    _ = app;
    const c: *DashboardCtx = @ptrCast(@alignCast(ctx.?));

    // -----------------------------------------------------------------------
    // Section 1 — Overview header
    // -----------------------------------------------------------------------
    const s1_title_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Overview" } }};
    const s1_title = NodeDesc{ .tag = "Text", .classes = "text-xl font-bold", .attrs = &s1_title_attrs };

    const cur_dd   = NodeDesc{ .tag = "Dropdown", .classes = "w-20" };
    const asset_dd = NodeDesc{ .tag = "Dropdown", .classes = "w-28" };
    const per_dd   = NodeDesc{ .tag = "Dropdown", .classes = "w-36" };

    const s1_right_children = [3]NodeDesc{ cur_dd, asset_dd, per_dd };
    const s1_right = NodeDesc{ .tag = "Row", .classes = "gap-2", .children = &s1_right_children };

    const s1_children = [2]NodeDesc{ s1_title, s1_right };
    const s1 = NodeDesc{ .tag = "Row", .classes = "justify-between items-center gap-4", .children = &s1_children };

    // -----------------------------------------------------------------------
    // Section 2 — KPI cards
    // -----------------------------------------------------------------------

    // Card 1 — Asset Total (MaskableValue)
    const kpi1_lbl_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Asset Total" } }};
    const kpi1_lbl = NodeDesc{ .tag = "Text", .classes = "text-sm text-muted", .attrs = &kpi1_lbl_attrs };
    const kpi1_mv  = NodeDesc{ .tag = "MaskableValue", .classes = "font-bold" };
    const kpi1_vs_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "vs last month" } }};
    const kpi1_vs    = NodeDesc{ .tag = "Text", .classes = "text-xs text-muted", .attrs = &kpi1_vs_attrs };
    const kpi1_badge = NodeDesc{ .tag = "TrendBadge", .classes = "text-xs" };
    const kpi1_trend_children = [2]NodeDesc{ kpi1_badge, kpi1_vs };
    const kpi1_trend = NodeDesc{ .tag = "Row", .classes = "items-center gap-2", .children = &kpi1_trend_children };
    const kpi1_children = [3]NodeDesc{ kpi1_lbl, kpi1_mv, kpi1_trend };
    const kpi1 = NodeDesc{ .tag = "Card", .classes = "p-4 flex-1 gap-2", .children = &kpi1_children };

    // Card 2 — Asset in USD  (formatCurrency($9,732.58, .usd) → "$9,732.58")
    const kpi2_lbl_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Asset in USD" } }};
    const kpi2_lbl = NodeDesc{ .tag = "Text", .classes = "text-sm text-muted", .attrs = &kpi2_lbl_attrs };
    const kpi2_val_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "$9,732.58" } }};
    const kpi2_val = NodeDesc{ .tag = "Text", .classes = "font-bold", .attrs = &kpi2_val_attrs };
    const kpi2_sub_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "S$9,732.58 / 30.0%" } }};
    const kpi2_sub   = NodeDesc{ .tag = "Text", .classes = "text-xs text-muted", .attrs = &kpi2_sub_attrs };
    const kpi2_badge = NodeDesc{ .tag = "TrendBadge", .classes = "text-xs" };
    const kpi2_children = [4]NodeDesc{ kpi2_lbl, kpi2_val, kpi2_sub, kpi2_badge };
    const kpi2 = NodeDesc{ .tag = "Card", .classes = "p-4 flex-1 gap-2", .children = &kpi2_children };

    // Card 3 — Asset in SGD  (formatCurrency($11,456.79, .sgd) → "S$11,456.79")
    const kpi3_lbl_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Asset in SGD" } }};
    const kpi3_lbl = NodeDesc{ .tag = "Text", .classes = "text-sm text-muted", .attrs = &kpi3_lbl_attrs };
    const kpi3_val_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "S$11,456.79" } }};
    const kpi3_val   = NodeDesc{ .tag = "Text", .classes = "font-bold", .attrs = &kpi3_val_attrs };
    const kpi3_badge = NodeDesc{ .tag = "TrendBadge", .classes = "text-xs" };
    const kpi3_children = [3]NodeDesc{ kpi3_lbl, kpi3_val, kpi3_badge };
    const kpi3 = NodeDesc{ .tag = "Card", .classes = "p-4 flex-1 gap-2", .children = &kpi3_children };

    // Card 4 — Asset in EUR  (formatCurrency(€11.310,56, .eur, de_DE) → "€11.310,56")
    const kpi4_lbl_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Asset in EUR" } }};
    const kpi4_lbl = NodeDesc{ .tag = "Text", .classes = "text-sm text-muted", .attrs = &kpi4_lbl_attrs };
    // UTF-8 for € = \xe2\x82\xac
    const kpi4_val_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "\xe2\x82\xac11.310,56" } }};
    const kpi4_val   = NodeDesc{ .tag = "Text", .classes = "font-bold", .attrs = &kpi4_val_attrs };
    const kpi4_badge = NodeDesc{ .tag = "TrendBadge", .classes = "text-xs" };
    const kpi4_children = [3]NodeDesc{ kpi4_lbl, kpi4_val, kpi4_badge };
    const kpi4 = NodeDesc{ .tag = "Card", .classes = "p-4 flex-1 gap-2", .children = &kpi4_children };

    const s2_children = [4]NodeDesc{ kpi1, kpi2, kpi3, kpi4 };
    const s2 = NodeDesc{ .tag = "Row", .classes = "gap-4", .children = &s2_children };

    // -----------------------------------------------------------------------
    // Section 3 — Chart area + Top Assets
    // -----------------------------------------------------------------------

    // Left: Chart card
    const ch_hdr_h_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Asset Total Statistic" } }};
    const ch_hdr_h  = NodeDesc{ .tag = "Text", .classes = "font-bold", .attrs = &ch_hdr_h_attrs };
    const ch_hdr_dd = NodeDesc{ .tag = "Dropdown", .classes = "w-28" };
    const ch_hdr_children = [2]NodeDesc{ ch_hdr_h, ch_hdr_dd };
    const ch_hdr = NodeDesc{ .tag = "Row", .classes = "justify-between items-center", .children = &ch_hdr_children };

    const ch_ph_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Asset Total Statistic \xe2\x80\x94 Line Chart\n(Nov 12: $16.2M \xe2\x86\x92 Dec 11: $17.1M)\nModule 13 chart rendering via Chart.render()" } }};
    const ch_ph = NodeDesc{ .tag = "Card", .classes = "bg-surface p-4 h-48 w-full", .attrs = &ch_ph_attrs };

    const chart_card_children = [2]NodeDesc{ ch_hdr, ch_ph };
    const chart_card = NodeDesc{ .tag = "Card", .classes = "p-4 grow gap-3", .children = &chart_card_children };

    // Right: Top Assets card
    const top_h_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Top Assets" } }};
    const top_h = NodeDesc{ .tag = "Text", .classes = "font-bold", .attrs = &top_h_attrs };

    // Asset rows — Row[Column[name,type], value, TrendBadge]
    // a1: PP-DFP 2213dk / Aircraft | $4,215,600 | +8%
    const a1n_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "PP-DFP 2213dk" } }};
    const a1n = NodeDesc{ .tag = "Text", .classes = "text-sm", .attrs = &a1n_attrs };
    const a1t_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Aircraft" } }};
    const a1t = NodeDesc{ .tag = "Text", .classes = "text-xs text-muted", .attrs = &a1t_attrs };
    const a1nc = [2]NodeDesc{ a1n, a1t };
    const a1c = NodeDesc{ .tag = "Column", .classes = "grow", .children = &a1nc };
    const a1v_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "$4,215,600" } }};
    const a1v = NodeDesc{ .tag = "Text", .classes = "text-sm", .attrs = &a1v_attrs };
    const a1b = NodeDesc{ .tag = "TrendBadge", .classes = "text-xs" };
    const a1ch = [3]NodeDesc{ a1c, a1v, a1b };
    const a1 = NodeDesc{ .tag = "Row", .classes = "justify-between items-center p-1 gap-2", .children = &a1ch };

    // a2: PP-KVF / Aircraft | $3,875,200 | -5%
    const a2n_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "PP-KVF" } }};
    const a2n = NodeDesc{ .tag = "Text", .classes = "text-sm", .attrs = &a2n_attrs };
    const a2t_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Aircraft" } }};
    const a2t = NodeDesc{ .tag = "Text", .classes = "text-xs text-muted", .attrs = &a2t_attrs };
    const a2nc = [2]NodeDesc{ a2n, a2t };
    const a2c = NodeDesc{ .tag = "Column", .classes = "grow", .children = &a2nc };
    const a2v_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "$3,875,200" } }};
    const a2v = NodeDesc{ .tag = "Text", .classes = "text-sm", .attrs = &a2v_attrs };
    const a2b = NodeDesc{ .tag = "TrendBadge", .classes = "text-xs" };
    const a2ch = [3]NodeDesc{ a2c, a2v, a2b };
    const a2 = NodeDesc{ .tag = "Row", .classes = "justify-between items-center p-1 gap-2", .children = &a2ch };

    // a3: Casa Praia / Real Estate | $3,654,300 | +6%
    const a3n_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Casa Praia" } }};
    const a3n = NodeDesc{ .tag = "Text", .classes = "text-sm", .attrs = &a3n_attrs };
    const a3t_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Real Estate" } }};
    const a3t = NodeDesc{ .tag = "Text", .classes = "text-xs text-muted", .attrs = &a3t_attrs };
    const a3nc = [2]NodeDesc{ a3n, a3t };
    const a3c = NodeDesc{ .tag = "Column", .classes = "grow", .children = &a3nc };
    const a3v_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "$3,654,300" } }};
    const a3v = NodeDesc{ .tag = "Text", .classes = "text-sm", .attrs = &a3v_attrs };
    const a3b = NodeDesc{ .tag = "TrendBadge", .classes = "text-xs" };
    const a3ch = [3]NodeDesc{ a3c, a3v, a3b };
    const a3 = NodeDesc{ .tag = "Row", .classes = "justify-between items-center p-1 gap-2", .children = &a3ch };

    // a4: Residential Apart. / Real Estate | $4,010,800 | -5%
    const a4n_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Residential Apart." } }};
    const a4n = NodeDesc{ .tag = "Text", .classes = "text-sm", .attrs = &a4n_attrs };
    const a4t_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Real Estate" } }};
    const a4t = NodeDesc{ .tag = "Text", .classes = "text-xs text-muted", .attrs = &a4t_attrs };
    const a4nc = [2]NodeDesc{ a4n, a4t };
    const a4c = NodeDesc{ .tag = "Column", .classes = "grow", .children = &a4nc };
    const a4v_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "$4,010,800" } }};
    const a4v = NodeDesc{ .tag = "Text", .classes = "text-sm", .attrs = &a4v_attrs };
    const a4b = NodeDesc{ .tag = "TrendBadge", .classes = "text-xs" };
    const a4ch = [3]NodeDesc{ a4c, a4v, a4b };
    const a4 = NodeDesc{ .tag = "Row", .classes = "justify-between items-center p-1 gap-2", .children = &a4ch };

    // a5: Z Company / Technology | $3,921,500 | -6%
    const a5n_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Z Company" } }};
    const a5n = NodeDesc{ .tag = "Text", .classes = "text-sm", .attrs = &a5n_attrs };
    const a5t_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Technology" } }};
    const a5t = NodeDesc{ .tag = "Text", .classes = "text-xs text-muted", .attrs = &a5t_attrs };
    const a5nc = [2]NodeDesc{ a5n, a5t };
    const a5c = NodeDesc{ .tag = "Column", .classes = "grow", .children = &a5nc };
    const a5v_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "$3,921,500" } }};
    const a5v = NodeDesc{ .tag = "Text", .classes = "text-sm", .attrs = &a5v_attrs };
    const a5b = NodeDesc{ .tag = "TrendBadge", .classes = "text-xs" };
    const a5ch = [3]NodeDesc{ a5c, a5v, a5b };
    const a5 = NodeDesc{ .tag = "Row", .classes = "justify-between items-center p-1 gap-2", .children = &a5ch };

    const top_children = [6]NodeDesc{ top_h, a1, a2, a3, a4, a5 };
    const top_card = NodeDesc{ .tag = "Card", .classes = "p-4 w-72 gap-1", .children = &top_children };

    const s3_children = [2]NodeDesc{ chart_card, top_card };
    const s3 = NodeDesc{ .tag = "Row", .classes = "gap-4", .children = &s3_children };

    // -----------------------------------------------------------------------
    // Section 4 — Transactions + Types + Members
    // -----------------------------------------------------------------------

    // Transactions card
    const txh_h_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Transactions" } }};
    const txh_h = NodeDesc{ .tag = "Text", .classes = "font-bold", .attrs = &txh_h_attrs };
    const txh_see_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "See All" } }};
    const txh_see = NodeDesc{ .tag = "Button", .classes = "text-sm", .attrs = &txh_see_attrs };
    const txh_row_children = [2]NodeDesc{ txh_h, txh_see };
    const txh_row = NodeDesc{ .tag = "Row", .classes = "justify-between", .children = &txh_row_children };

    const txcol_p_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Provider" } }};
    const txcol_t_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Type" } }};
    const txcol_a_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Amount" } }};
    const txcol_p = NodeDesc{ .tag = "Text", .classes = "text-xs text-muted grow", .attrs = &txcol_p_attrs };
    const txcol_t = NodeDesc{ .tag = "Text", .classes = "text-xs text-muted",      .attrs = &txcol_t_attrs };
    const txcol_a = NodeDesc{ .tag = "Text", .classes = "text-xs text-muted",      .attrs = &txcol_a_attrs };
    const txcol_children = [3]NodeDesc{ txcol_p, txcol_t, txcol_a };
    const txcol = NodeDesc{ .tag = "Row", .classes = "gap-2", .children = &txcol_children };

    // Transaction rows (6)
    const tx1p_a = [1]Attr{.{ .name = "text", .value = .{ .literal = "PE Blue Capital" } }};
    const tx1t_a = [1]Attr{.{ .name = "text", .value = .{ .literal = "Buy" } }};
    const tx1a_a = [1]Attr{.{ .name = "text", .value = .{ .literal = "$120,500,000" } }};
    const tx1p = NodeDesc{ .tag = "Text", .classes = "text-sm grow", .attrs = &tx1p_a };
    const tx1t = NodeDesc{ .tag = "Card", .classes = "p-1 rounded text-xs", .attrs = &tx1t_a };
    const tx1a = NodeDesc{ .tag = "Text", .classes = "text-sm", .attrs = &tx1a_a };
    const tx1c = [3]NodeDesc{ tx1p, tx1t, tx1a };
    const tx1 = NodeDesc{ .tag = "Row", .classes = "justify-between items-center p-1 gap-2", .children = &tx1c };

    const tx2p_a = [1]Attr{.{ .name = "text", .value = .{ .literal = "PE Black Stone..." } }};
    const tx2t_a = [1]Attr{.{ .name = "text", .value = .{ .literal = "Sell" } }};
    const tx2a_a = [1]Attr{.{ .name = "text", .value = .{ .literal = "$98,750,000" } }};
    const tx2p = NodeDesc{ .tag = "Text", .classes = "text-sm grow", .attrs = &tx2p_a };
    const tx2t = NodeDesc{ .tag = "Card", .classes = "p-1 rounded text-xs", .attrs = &tx2t_a };
    const tx2a = NodeDesc{ .tag = "Text", .classes = "text-sm", .attrs = &tx2a_a };
    const tx2c = [3]NodeDesc{ tx2p, tx2t, tx2a };
    const tx2 = NodeDesc{ .tag = "Row", .classes = "justify-between items-center p-1 gap-2", .children = &tx2c };

    const tx3p_a = [1]Attr{.{ .name = "text", .value = .{ .literal = "PE New Wave Inv" } }};
    const tx3t_a = [1]Attr{.{ .name = "text", .value = .{ .literal = "Buy" } }};
    const tx3a_a = [1]Attr{.{ .name = "text", .value = .{ .literal = "$139,474,080" } }};
    const tx3p = NodeDesc{ .tag = "Text", .classes = "text-sm grow", .attrs = &tx3p_a };
    const tx3t = NodeDesc{ .tag = "Card", .classes = "p-1 rounded text-xs", .attrs = &tx3t_a };
    const tx3a = NodeDesc{ .tag = "Text", .classes = "text-sm", .attrs = &tx3a_a };
    const tx3c = [3]NodeDesc{ tx3p, tx3t, tx3a };
    const tx3 = NodeDesc{ .tag = "Row", .classes = "justify-between items-center p-1 gap-2", .children = &tx3c };

    const tx4p_a = [1]Attr{.{ .name = "text", .value = .{ .literal = "PE Green Holdi..." } }};
    const tx4t_a = [1]Attr{.{ .name = "text", .value = .{ .literal = "Buy" } }};
    const tx4a_a = [1]Attr{.{ .name = "text", .value = .{ .literal = "$112,620,500" } }};
    const tx4p = NodeDesc{ .tag = "Text", .classes = "text-sm grow", .attrs = &tx4p_a };
    const tx4t = NodeDesc{ .tag = "Card", .classes = "p-1 rounded text-xs", .attrs = &tx4t_a };
    const tx4a = NodeDesc{ .tag = "Text", .classes = "text-sm", .attrs = &tx4a_a };
    const tx4c = [3]NodeDesc{ tx4p, tx4t, tx4a };
    const tx4 = NodeDesc{ .tag = "Row", .classes = "justify-between items-center p-1 gap-2", .children = &tx4c };

    const tx5p_a = [1]Attr{.{ .name = "text", .value = .{ .literal = "Global Asset Fu..." } }};
    const tx5t_a = [1]Attr{.{ .name = "text", .value = .{ .literal = "Sell" } }};
    const tx5a_a = [1]Attr{.{ .name = "text", .value = .{ .literal = "$75,320,800" } }};
    const tx5p = NodeDesc{ .tag = "Text", .classes = "text-sm grow", .attrs = &tx5p_a };
    const tx5t = NodeDesc{ .tag = "Card", .classes = "p-1 rounded text-xs", .attrs = &tx5t_a };
    const tx5a = NodeDesc{ .tag = "Text", .classes = "text-sm", .attrs = &tx5a_a };
    const tx5c = [3]NodeDesc{ tx5p, tx5t, tx5a };
    const tx5 = NodeDesc{ .tag = "Row", .classes = "justify-between items-center p-1 gap-2", .children = &tx5c };

    const tx6p_a = [1]Attr{.{ .name = "text", .value = .{ .literal = "Future Growth..." } }};
    const tx6t_a = [1]Attr{.{ .name = "text", .value = .{ .literal = "Buy" } }};
    const tx6a_a = [1]Attr{.{ .name = "text", .value = .{ .literal = "$89,750,000" } }};
    const tx6p = NodeDesc{ .tag = "Text", .classes = "text-sm grow", .attrs = &tx6p_a };
    const tx6t = NodeDesc{ .tag = "Card", .classes = "p-1 rounded text-xs", .attrs = &tx6t_a };
    const tx6a = NodeDesc{ .tag = "Text", .classes = "text-sm", .attrs = &tx6a_a };
    const tx6c = [3]NodeDesc{ tx6p, tx6t, tx6a };
    const tx6 = NodeDesc{ .tag = "Row", .classes = "justify-between items-center p-1 gap-2", .children = &tx6c };

    const tx_children = [8]NodeDesc{ txh_row, txcol, tx1, tx2, tx3, tx4, tx5, tx6 };
    const tx_card = NodeDesc{ .tag = "Card", .classes = "p-4 grow gap-1", .children = &tx_children };

    // Types card
    const tyh_h_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Types" } }};
    const tyh_h = NodeDesc{ .tag = "Text", .classes = "font-bold", .attrs = &tyh_h_attrs };
    const tyh_see_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "See All" } }};
    const tyh_see = NodeDesc{ .tag = "Button", .classes = "text-sm", .attrs = &tyh_see_attrs };
    const tyh_row_children = [2]NodeDesc{ tyh_h, tyh_see };
    const tyh_row = NodeDesc{ .tag = "Row", .classes = "justify-between", .children = &tyh_row_children };

    // Category rows — color dots use bg-accent (aircraft) and bg-raised (others)
    // because bg-ok/bg-warn/bg-err are not in the class resolver.
    const ty1d = NodeDesc{ .tag = "Card", .classes = "w-2 h-2 rounded-full bg-accent" };
    const ty1l_a = [1]Attr{.{ .name = "text", .value = .{ .literal = "Aircraft" } }};
    const ty1l = NodeDesc{ .tag = "Text", .classes = "grow", .attrs = &ty1l_a };
    const ty1v_a = [1]Attr{.{ .name = "text", .value = .{ .literal = "$3,421.38" } }};
    const ty1v = NodeDesc{ .tag = "Text", .attrs = &ty1v_a };
    const ty1p_a = [1]Attr{.{ .name = "text", .value = .{ .literal = "30.22%" } }};
    const ty1p = NodeDesc{ .tag = "Text", .classes = "text-muted w-16", .attrs = &ty1p_a };
    const ty1c = [4]NodeDesc{ ty1d, ty1l, ty1v, ty1p };
    const ty1 = NodeDesc{ .tag = "Row", .classes = "items-center gap-2 text-sm p-1", .children = &ty1c };

    const ty2d = NodeDesc{ .tag = "Card", .classes = "w-2 h-2 rounded-full bg-raised" };
    const ty2l_a = [1]Attr{.{ .name = "text", .value = .{ .literal = "Real Estate" } }};
    const ty2l = NodeDesc{ .tag = "Text", .classes = "grow", .attrs = &ty2l_a };
    const ty2v_a = [1]Attr{.{ .name = "text", .value = .{ .literal = "$2,668.50" } }};
    const ty2v = NodeDesc{ .tag = "Text", .attrs = &ty2v_a };
    const ty2p_a = [1]Attr{.{ .name = "text", .value = .{ .literal = "23.57%" } }};
    const ty2p = NodeDesc{ .tag = "Text", .classes = "text-muted w-16", .attrs = &ty2p_a };
    const ty2c = [4]NodeDesc{ ty2d, ty2l, ty2v, ty2p };
    const ty2 = NodeDesc{ .tag = "Row", .classes = "items-center gap-2 text-sm p-1", .children = &ty2c };

    const ty3d = NodeDesc{ .tag = "Card", .classes = "w-2 h-2 rounded-full bg-raised" };
    const ty3l_a = [1]Attr{.{ .name = "text", .value = .{ .literal = "Vessel" } }};
    const ty3l = NodeDesc{ .tag = "Text", .classes = "grow", .attrs = &ty3l_a };
    const ty3v_a = [1]Attr{.{ .name = "text", .value = .{ .literal = "$2,533.77" } }};
    const ty3v = NodeDesc{ .tag = "Text", .attrs = &ty3v_a };
    const ty3p_a = [1]Attr{.{ .name = "text", .value = .{ .literal = "22.38%" } }};
    const ty3p = NodeDesc{ .tag = "Text", .classes = "text-muted w-16", .attrs = &ty3p_a };
    const ty3c = [4]NodeDesc{ ty3d, ty3l, ty3v, ty3p };
    const ty3 = NodeDesc{ .tag = "Row", .classes = "items-center gap-2 text-sm p-1", .children = &ty3c };

    const ty4d = NodeDesc{ .tag = "Card", .classes = "w-2 h-2 rounded-full bg-raised" };
    const ty4l_a = [1]Attr{.{ .name = "text", .value = .{ .literal = "Company" } }};
    const ty4l = NodeDesc{ .tag = "Text", .classes = "grow", .attrs = &ty4l_a };
    const ty4v_a = [1]Attr{.{ .name = "text", .value = .{ .literal = "$2,499.80" } }};
    const ty4v = NodeDesc{ .tag = "Text", .attrs = &ty4v_a };
    const ty4p_a = [1]Attr{.{ .name = "text", .value = .{ .literal = "22.08%" } }};
    const ty4p = NodeDesc{ .tag = "Text", .classes = "text-muted w-16", .attrs = &ty4p_a };
    const ty4c = [4]NodeDesc{ ty4d, ty4l, ty4v, ty4p };
    const ty4 = NodeDesc{ .tag = "Row", .classes = "items-center gap-2 text-sm p-1", .children = &ty4c };

    const ty5d = NodeDesc{ .tag = "Card", .classes = "w-2 h-2 rounded-full bg-raised" };
    const ty5l_a = [1]Attr{.{ .name = "text", .value = .{ .literal = "Car" } }};
    const ty5l = NodeDesc{ .tag = "Text", .classes = "grow", .attrs = &ty5l_a };
    const ty5v_a = [1]Attr{.{ .name = "text", .value = .{ .literal = "$198.13" } }};
    const ty5v = NodeDesc{ .tag = "Text", .attrs = &ty5v_a };
    const ty5p_a = [1]Attr{.{ .name = "text", .value = .{ .literal = "1.00%" } }};
    const ty5p = NodeDesc{ .tag = "Text", .classes = "text-muted w-16", .attrs = &ty5p_a };
    const ty5c = [4]NodeDesc{ ty5d, ty5l, ty5v, ty5p };
    const ty5 = NodeDesc{ .tag = "Row", .classes = "items-center gap-2 text-sm p-1", .children = &ty5c };

    const ty6d = NodeDesc{ .tag = "Card", .classes = "w-2 h-2 rounded-full bg-raised" };
    const ty6l_a = [1]Attr{.{ .name = "text", .value = .{ .literal = "Funds" } }};
    const ty6l = NodeDesc{ .tag = "Text", .classes = "grow", .attrs = &ty6l_a };
    const ty6v_a = [1]Attr{.{ .name = "text", .value = .{ .literal = "$4.21" } }};
    const ty6v = NodeDesc{ .tag = "Text", .attrs = &ty6v_a };
    const ty6p_a = [1]Attr{.{ .name = "text", .value = .{ .literal = "0.75%" } }};
    const ty6p = NodeDesc{ .tag = "Text", .classes = "text-muted w-16", .attrs = &ty6p_a };
    const ty6c = [4]NodeDesc{ ty6d, ty6l, ty6v, ty6p };
    const ty6 = NodeDesc{ .tag = "Row", .classes = "items-center gap-2 text-sm p-1", .children = &ty6c };

    const ty_children = [7]NodeDesc{ tyh_row, ty1, ty2, ty3, ty4, ty5, ty6 };
    const ty_card = NodeDesc{ .tag = "Card", .classes = "p-4 grow gap-1", .children = &ty_children };

    // Members card
    const memh_h_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Members" } }};
    const memh_h = NodeDesc{ .tag = "Text", .classes = "font-bold", .attrs = &memh_h_attrs };
    const memh_see_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "See All" } }};
    const memh_see = NodeDesc{ .tag = "Button", .classes = "text-sm", .attrs = &memh_see_attrs };
    const memh_row_children = [2]NodeDesc{ memh_h, memh_see };
    const memh_row = NodeDesc{ .tag = "Row", .classes = "justify-between", .children = &memh_row_children };

    const donut_ph_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Members Donut Chart (Module 13 RN1+RN2) \xe2\x80\x94 inner_radius=0.6 with callouts" } }};
    const donut_ph = NodeDesc{ .tag = "Card", .classes = "bg-surface p-4 h-40 w-full", .attrs = &donut_ph_attrs };

    // Member rows (5)
    const m1av = NodeDesc{ .tag = "Card", .classes = "w-6 h-6 rounded-full bg-raised" };
    const m1n_a = [1]Attr{.{ .name = "text", .value = .{ .literal = "Mary Smith" } }};
    const m1n = NodeDesc{ .tag = "Text", .classes = "grow", .attrs = &m1n_a };
    const m1p_a = [1]Attr{.{ .name = "text", .value = .{ .literal = "40%" } }};
    const m1p = NodeDesc{ .tag = "Text", .classes = "text-muted", .attrs = &m1p_a };
    const m1c = [3]NodeDesc{ m1av, m1n, m1p };
    const m1 = NodeDesc{ .tag = "Row", .classes = "justify-between items-center text-sm p-1", .children = &m1c };

    const m2av = NodeDesc{ .tag = "Card", .classes = "w-6 h-6 rounded-full bg-raised" };
    const m2n_a = [1]Attr{.{ .name = "text", .value = .{ .literal = "John Smith" } }};
    const m2n = NodeDesc{ .tag = "Text", .classes = "grow", .attrs = &m2n_a };
    const m2p_a = [1]Attr{.{ .name = "text", .value = .{ .literal = "30%" } }};
    const m2p = NodeDesc{ .tag = "Text", .classes = "text-muted", .attrs = &m2p_a };
    const m2c = [3]NodeDesc{ m2av, m2n, m2p };
    const m2 = NodeDesc{ .tag = "Row", .classes = "justify-between items-center text-sm p-1", .children = &m2c };

    const m3av = NodeDesc{ .tag = "Card", .classes = "w-6 h-6 rounded-full bg-raised" };
    const m3n_a = [1]Attr{.{ .name = "text", .value = .{ .literal = "Jane Doe" } }};
    const m3n = NodeDesc{ .tag = "Text", .classes = "grow", .attrs = &m3n_a };
    const m3p_a = [1]Attr{.{ .name = "text", .value = .{ .literal = "15%" } }};
    const m3p = NodeDesc{ .tag = "Text", .classes = "text-muted", .attrs = &m3p_a };
    const m3c = [3]NodeDesc{ m3av, m3n, m3p };
    const m3 = NodeDesc{ .tag = "Row", .classes = "justify-between items-center text-sm p-1", .children = &m3c };

    const m4av = NodeDesc{ .tag = "Card", .classes = "w-6 h-6 rounded-full bg-raised" };
    const m4n_a = [1]Attr{.{ .name = "text", .value = .{ .literal = "Alex Jo" } }};
    const m4n = NodeDesc{ .tag = "Text", .classes = "grow", .attrs = &m4n_a };
    const m4p_a = [1]Attr{.{ .name = "text", .value = .{ .literal = "10%" } }};
    const m4p = NodeDesc{ .tag = "Text", .classes = "text-muted", .attrs = &m4p_a };
    const m4c = [3]NodeDesc{ m4av, m4n, m4p };
    const m4 = NodeDesc{ .tag = "Row", .classes = "justify-between items-center text-sm p-1", .children = &m4c };

    const m5av = NodeDesc{ .tag = "Card", .classes = "w-6 h-6 rounded-full bg-raised" };
    const m5n_a = [1]Attr{.{ .name = "text", .value = .{ .literal = "Harry Doe" } }};
    const m5n = NodeDesc{ .tag = "Text", .classes = "grow", .attrs = &m5n_a };
    const m5p_a = [1]Attr{.{ .name = "text", .value = .{ .literal = "5%" } }};
    const m5p = NodeDesc{ .tag = "Text", .classes = "text-muted", .attrs = &m5p_a };
    const m5c = [3]NodeDesc{ m5av, m5n, m5p };
    const m5 = NodeDesc{ .tag = "Row", .classes = "justify-between items-center text-sm p-1", .children = &m5c };

    const mem_children = [7]NodeDesc{ memh_row, donut_ph, m1, m2, m3, m4, m5 };
    const mem_card = NodeDesc{ .tag = "Card", .classes = "p-4 grow gap-1", .children = &mem_children };

    const s4_children = [3]NodeDesc{ tx_card, ty_card, mem_card };
    const s4 = NodeDesc{ .tag = "Row", .classes = "gap-4", .children = &s4_children };

    // -----------------------------------------------------------------------
    // Assemble full layout
    // -----------------------------------------------------------------------
    const body_children = [4]NodeDesc{ s1, s2, s3, s4 };
    const body = NodeDesc{ .tag = "Column", .classes = "gap-4", .children = &body_children };
    const scroll = NodeDesc{ .tag = "ScrollView", .classes = "flex-1", .children = &[1]NodeDesc{
        NodeDesc{ .tag = "Column", .classes = "p-4", .children = &[1]NodeDesc{body} },
    } };

    const root_children = [2]NodeDesc{ sidebar.buildSidebar(), scroll };
    const root = NodeDesc{ .tag = "Row", .classes = "w-full h-full", .children = &root_children };

    _ = try scene.instantiate(root, tokens);

    // -----------------------------------------------------------------------
    // Post-instantiation: configure M27 widgets and dropdown options.
    //
    // All parallel arrays are indexed by element scene index (same as _kind).
    // Trend values in DFS pre-order:
    //   [0]=Asset Total +18.20%, [1]=USD -0.33%, [2]=SGD +12.95%, [3]=EUR +11.65%,
    //   [4]=PP-DFP +8%, [5]=PP-KVF -5%, [6]=Casa Praia +6%,
    //   [7]=Residential -5%, [8]=Z Company -6%
    // -----------------------------------------------------------------------
    const trend_vals = [9]f32{ 18.20, -0.33, 12.95, 11.65, 8.0, -5.0, 6.0, -5.0, -6.0 };
    var trend_count: u32 = 0;
    var dd_count: u32 = 0;

    var idx: u32 = 0;
    while (idx < scene._kind.items.len) : (idx += 1) {
        switch (scene.kindOfIdx(idx)) {
            .maskable_value => {
                scene.setMaskableValue(idx, "$32,499.93");
                scene.setMaskableVisible(idx, true);
            },
            .trend_badge => {
                if (trend_count < trend_vals.len) {
                    scene.setTrendValue(idx, trend_vals[trend_count]);
                }
                trend_count += 1;
            },
            .dropdown => {
                switch (dd_count) {
                    0 => try scene.setDropdownOptions(idx, &_cur_opts),
                    1 => try scene.setDropdownOptions(idx, &_asset_opts),
                    2 => try scene.setDropdownOptions(idx, &_period_opts),
                    3 => try scene.setDropdownOptions(idx, &_stat_opts),
                    else => {},
                }
                dd_count += 1;
            },
            else => {},
        }
    }

    // Wire sidebar — Dashboard is button index 12 (DFS pre-order).
    try shared.wireSidebarCallbacks(scene, c.global, tokens, 12);
}
