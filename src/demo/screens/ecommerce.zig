//! ecommerce.zig — TailAdmin-style Ecommerce demo screen (Screen 12).
//!
//! Demonstrates RN9 (gauge chart), RN10 (world map), RN11 (chart_cmds slot).
//! Charts are rendered via renderCharts() called from main.zig per_frame_app_fn.

const std = @import("std");
const mod07 = @import("../07/types.zig");
const mod05 = @import("../05/types.zig");
const mod06 = @import("../06/types.zig");
const app_types = @import("app");

const chart_mod = @import("../../13/chart.zig");

const Scene    = mod07.Scene;
const Tokens   = mod05.Tokens;
const NodeDesc = mod06.NodeDesc;
const Attr     = mod06.Attr;

const shared  = @import("../shared/types.zig");
const sidebar = @import("../shared/sidebar.zig");

pub const EcommerceCtx = struct {
    global: *shared.GlobalState,
};

// ---------------------------------------------------------------------------
// Module-level chart placeholder element indices (reset on each build() call)
// ---------------------------------------------------------------------------

var _bar_chart_idx:  u32 = std.math.maxInt(u32);
var _gauge_idx:      u32 = std.math.maxInt(u32);
var _area_chart_idx: u32 = std.math.maxInt(u32);
var _map_idx:        u32 = std.math.maxInt(u32);

// Static label storage for chart axes (lifetime = program, pointer-stable).
const _bar_months  = [_][]const u8{ "J","F","M","A","M","J","J","A","S","O","N","D" };
const _area_months = [_][]const u8{ "Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec" };

// ---------------------------------------------------------------------------
// NodeDesc tree — module-level static storage for pointer stability
// ---------------------------------------------------------------------------

// KPI card 1 — Customers
var _c_icon_a  = [1]Attr{.{ .name = "text", .value = .{ .literal = "^U" } }};
var _c_lbl_a   = [1]Attr{.{ .name = "text", .value = .{ .literal = "Customers" } }};
var _c_val_a   = [1]Attr{.{ .name = "text", .value = .{ .literal = "3,782" } }};
var _c_trend_a = [1]Attr{.{ .name = "text", .value = .{ .literal = "TREND:C" } }};
var _c_vs_a    = [1]Attr{.{ .name = "text", .value = .{ .literal = "vs last month" } }};

// KPI card 2 — Orders
var _o_icon_a  = [1]Attr{.{ .name = "text", .value = .{ .literal = "^O" } }};
var _o_lbl_a   = [1]Attr{.{ .name = "text", .value = .{ .literal = "Orders" } }};
var _o_val_a   = [1]Attr{.{ .name = "text", .value = .{ .literal = "5,359" } }};
var _o_trend_a = [1]Attr{.{ .name = "text", .value = .{ .literal = "TREND:O" } }};
var _o_vs_a    = [1]Attr{.{ .name = "text", .value = .{ .literal = "vs last month" } }};

// Monthly Sales chart card
var _bar_title_a  = [1]Attr{.{ .name = "text", .value = .{ .literal = "Monthly Sales" } }};
var _bar_ph_a     = [1]Attr{.{ .name = "text", .value = .{ .literal = "CHART:BAR" } }};

// Monthly Target gauge card
var _gauge_title_a  = [1]Attr{.{ .name = "text", .value = .{ .literal = "Monthly Target" } }};
var _gauge_sub_a    = [1]Attr{.{ .name = "text", .value = .{ .literal = "Target you've set for each month" } }};
var _gauge_ph_a     = [1]Attr{.{ .name = "text", .value = .{ .literal = "CHART:GAUGE" } }};
var _tgt_lbl_a      = [1]Attr{.{ .name = "text", .value = .{ .literal = "Target" } }};
var _tgt_val_a      = [1]Attr{.{ .name = "text", .value = .{ .literal = "$20K" } }};
var _rev_lbl_a      = [1]Attr{.{ .name = "text", .value = .{ .literal = "Revenue" } }};
var _rev_val_a      = [1]Attr{.{ .name = "text", .value = .{ .literal = "$20K" } }};
var _today_lbl_a    = [1]Attr{.{ .name = "text", .value = .{ .literal = "Today" } }};
var _today_val_a    = [1]Attr{.{ .name = "text", .value = .{ .literal = "$20K" } }};

// Statistics area chart card
var _stat_title_a   = [1]Attr{.{ .name = "text", .value = .{ .literal = "Statistics" } }};
var _stat_sub_a     = [1]Attr{.{ .name = "text", .value = .{ .literal = "Revenue and sales over time" } }};
var _stat_ph_a      = [1]Attr{.{ .name = "text", .value = .{ .literal = "CHART:AREA" } }};

// Demographics map card
var _demo_title_a   = [1]Attr{.{ .name = "text", .value = .{ .literal = "Customers Demographic" } }};
var _demo_sub_a     = [1]Attr{.{ .name = "text", .value = .{ .literal = "Number of customers based on country" } }};
var _map_ph_a       = [1]Attr{.{ .name = "text", .value = .{ .literal = "CHART:MAP" } }};
var _usa_name_a     = [1]Attr{.{ .name = "text", .value = .{ .literal = "USA" } }};
var _usa_cnt_a      = [1]Attr{.{ .name = "text", .value = .{ .literal = "2,379 Customers" } }};
var _usa_pct_a      = [1]Attr{.{ .name = "text", .value = .{ .literal = "79%" } }};
var _fr_name_a      = [1]Attr{.{ .name = "text", .value = .{ .literal = "France" } }};
var _fr_cnt_a       = [1]Attr{.{ .name = "text", .value = .{ .literal = "589 Customers" } }};
var _fr_pct_a       = [1]Attr{.{ .name = "text", .value = .{ .literal = "23%" } }};

// Recent Orders card
var _orders_title_a = [1]Attr{.{ .name = "text", .value = .{ .literal = "Recent Orders" } }};
var _see_all_a      = [1]Attr{.{ .name = "text", .value = .{ .literal = "See all" } }};
var _col_prod_a     = [1]Attr{.{ .name = "text", .value = .{ .literal = "Products" } }};
var _col_cat_a      = [1]Attr{.{ .name = "text", .value = .{ .literal = "Category" } }};
var _col_price_a    = [1]Attr{.{ .name = "text", .value = .{ .literal = "Price" } }};
var _col_status_a   = [1]Attr{.{ .name = "text", .value = .{ .literal = "Status" } }};

// Order rows
var _o1_name_a  = [1]Attr{.{ .name = "text", .value = .{ .literal = "MacBook Pro 13\"" } }};
var _o1_var_a   = [1]Attr{.{ .name = "text", .value = .{ .literal = "2 Variants" } }};
var _o1_pr_a    = [1]Attr{.{ .name = "text", .value = .{ .literal = "$2,399" } }};
var _o1_cat_a   = [1]Attr{.{ .name = "text", .value = .{ .literal = "Laptop" } }};
var _o1_sts_a   = [1]Attr{.{ .name = "text", .value = .{ .literal = "Delivered" } }};

var _o2_name_a  = [1]Attr{.{ .name = "text", .value = .{ .literal = "Apple Watch Ultra" } }};
var _o2_var_a   = [1]Attr{.{ .name = "text", .value = .{ .literal = "1 Variant" } }};
var _o2_pr_a    = [1]Attr{.{ .name = "text", .value = .{ .literal = "$879" } }};
var _o2_cat_a   = [1]Attr{.{ .name = "text", .value = .{ .literal = "Watch" } }};
var _o2_sts_a   = [1]Attr{.{ .name = "text", .value = .{ .literal = "Pending" } }};

var _o3_name_a  = [1]Attr{.{ .name = "text", .value = .{ .literal = "iPhone 15 Pro Max" } }};
var _o3_var_a   = [1]Attr{.{ .name = "text", .value = .{ .literal = "2 Variants" } }};
var _o3_pr_a    = [1]Attr{.{ .name = "text", .value = .{ .literal = "$1,869" } }};
var _o3_cat_a   = [1]Attr{.{ .name = "text", .value = .{ .literal = "SmartPhone" } }};
var _o3_sts_a   = [1]Attr{.{ .name = "text", .value = .{ .literal = "Delivered" } }};

var _o4_name_a  = [1]Attr{.{ .name = "text", .value = .{ .literal = "iPad Pro 3rd Gen" } }};
var _o4_var_a   = [1]Attr{.{ .name = "text", .value = .{ .literal = "2 Variants" } }};
var _o4_pr_a    = [1]Attr{.{ .name = "text", .value = .{ .literal = "$1,699" } }};
var _o4_cat_a   = [1]Attr{.{ .name = "text", .value = .{ .literal = "Electronics" } }};
var _o4_sts_a   = [1]Attr{.{ .name = "text", .value = .{ .literal = "Cancelled" } }};

var _o5_name_a  = [1]Attr{.{ .name = "text", .value = .{ .literal = "AirPods Pro 2nd Gen" } }};
var _o5_var_a   = [1]Attr{.{ .name = "text", .value = .{ .literal = "1 Variant" } }};
var _o5_pr_a    = [1]Attr{.{ .name = "text", .value = .{ .literal = "$240" } }};
var _o5_cat_a   = [1]Attr{.{ .name = "text", .value = .{ .literal = "Accessories" } }};
var _o5_sts_a   = [1]Attr{.{ .name = "text", .value = .{ .literal = "Delivered" } }};

// ---------------------------------------------------------------------------
// build() — instantiate the ecommerce screen
// ---------------------------------------------------------------------------

pub fn build(
    scene: *Scene,
    tokens: Tokens,
    app: *anyopaque,
    ctx: ?*anyopaque,
) anyerror!void {
    _ = app;
    const c: *EcommerceCtx = @ptrCast(@alignCast(ctx.?));

    // Reset chart placeholder indices.
    _bar_chart_idx  = std.math.maxInt(u32);
    _gauge_idx      = std.math.maxInt(u32);
    _area_chart_idx = std.math.maxInt(u32);
    _map_idx        = std.math.maxInt(u32);

    // -----------------------------------------------------------------------
    // Row 1 — KPI cards
    // -----------------------------------------------------------------------
    const c_icon  = NodeDesc{ .tag = "Card",   .classes = "w-12 h-12 bg-raised", .attrs = &_c_icon_a };
    const c_lbl   = NodeDesc{ .tag = "Text",   .classes = "text-sm text-muted",  .attrs = &_c_lbl_a  };
    const c_val   = NodeDesc{ .tag = "Text",   .classes = "text-xl font-bold",   .attrs = &_c_val_a  };
    const c_badge = NodeDesc{ .tag = "Text",   .classes = "text-xs font-bold",   .attrs = &_c_trend_a };
    const c_vs    = NodeDesc{ .tag = "Text",   .classes = "text-xs text-muted",  .attrs = &_c_vs_a   };

    const c_info_ch = [2]NodeDesc{ c_lbl, c_val };
    const c_info    = NodeDesc{ .tag = "Column", .classes = "grow", .children = &c_info_ch };
    const c_top_ch  = [2]NodeDesc{ c_icon, c_info };
    const c_top     = NodeDesc{ .tag = "Row", .classes = "items-center gap-4", .children = &c_top_ch };
    const c_trend_ch = [2]NodeDesc{ c_badge, c_vs };
    const c_trend   = NodeDesc{ .tag = "Row", .classes = "items-center gap-2", .children = &c_trend_ch };
    const kpi1_ch   = [2]NodeDesc{ c_top, c_trend };
    const kpi1_card = NodeDesc{ .tag = "Card", .classes = "p-6 grow shadow", .children = &kpi1_ch };

    const o_icon  = NodeDesc{ .tag = "Card",   .classes = "w-12 h-12 bg-raised", .attrs = &_o_icon_a };
    const o_lbl   = NodeDesc{ .tag = "Text",   .classes = "text-sm text-muted",  .attrs = &_o_lbl_a  };
    const o_val   = NodeDesc{ .tag = "Text",   .classes = "text-xl font-bold",   .attrs = &_o_val_a  };
    const o_badge = NodeDesc{ .tag = "Text",   .classes = "text-xs font-bold",   .attrs = &_o_trend_a };
    const o_vs    = NodeDesc{ .tag = "Text",   .classes = "text-xs text-muted",  .attrs = &_o_vs_a   };

    const o_info_ch = [2]NodeDesc{ o_lbl, o_val };
    const o_info    = NodeDesc{ .tag = "Column", .classes = "grow", .children = &o_info_ch };
    const o_top_ch  = [2]NodeDesc{ o_icon, o_info };
    const o_top     = NodeDesc{ .tag = "Row", .classes = "items-center gap-4", .children = &o_top_ch };
    const o_trend_ch = [2]NodeDesc{ o_badge, o_vs };
    const o_trend   = NodeDesc{ .tag = "Row", .classes = "items-center gap-2", .children = &o_trend_ch };
    const kpi2_ch   = [2]NodeDesc{ o_top, o_trend };
    const kpi2_card = NodeDesc{ .tag = "Card", .classes = "p-6 grow shadow", .children = &kpi2_ch };

    const row1_ch = [2]NodeDesc{ kpi1_card, kpi2_card };
    const row1    = NodeDesc{ .tag = "Row", .classes = "gap-4", .children = &row1_ch };

    // -----------------------------------------------------------------------
    // Row 2 — Monthly Sales (bar) + Monthly Target (gauge)
    // -----------------------------------------------------------------------
    const bar_title  = NodeDesc{ .tag = "Text", .classes = "font-bold", .attrs = &_bar_title_a };
    const bar_ph     = NodeDesc{ .tag = "Card", .classes = "h-48 w-full bg-surface", .attrs = &_bar_ph_a };
    const bar_card_ch = [2]NodeDesc{ bar_title, bar_ph };
    const bar_card   = NodeDesc{ .tag = "Card", .classes = "p-4 shadow grow", .children = &bar_card_ch };

    const gauge_title = NodeDesc{ .tag = "Text", .classes = "font-bold", .attrs = &_gauge_title_a };
    const gauge_sub   = NodeDesc{ .tag = "Text", .classes = "text-sm text-muted", .attrs = &_gauge_sub_a };
    const gauge_ph    = NodeDesc{ .tag = "Card", .classes = "h-48 w-full bg-surface", .attrs = &_gauge_ph_a };

    const tgt_lbl   = NodeDesc{ .tag = "Text", .classes = "text-xs text-muted", .attrs = &_tgt_lbl_a };
    const tgt_val   = NodeDesc{ .tag = "Text", .classes = "text-sm font-bold", .attrs = &_tgt_val_a };
    const tgt_badge = NodeDesc{ .tag = "TrendBadge", .classes = "text-xs w-14 h-4" };
    const tgt_row_ch = [2]NodeDesc{ tgt_val, tgt_badge };
    const tgt_row   = NodeDesc{ .tag = "Row", .classes = "items-center gap-1", .children = &tgt_row_ch };
    const tgt_col_ch = [2]NodeDesc{ tgt_lbl, tgt_row };
    const tgt_col   = NodeDesc{ .tag = "Column", .classes = "items-center", .children = &tgt_col_ch };

    const rev_lbl   = NodeDesc{ .tag = "Text", .classes = "text-xs text-muted", .attrs = &_rev_lbl_a };
    const rev_val   = NodeDesc{ .tag = "Text", .classes = "text-sm font-bold", .attrs = &_rev_val_a };
    const rev_badge = NodeDesc{ .tag = "TrendBadge", .classes = "text-xs w-14 h-4" };
    const rev_row_ch = [2]NodeDesc{ rev_val, rev_badge };
    const rev_row   = NodeDesc{ .tag = "Row", .classes = "items-center gap-1", .children = &rev_row_ch };
    const rev_col_ch = [2]NodeDesc{ rev_lbl, rev_row };
    const rev_col   = NodeDesc{ .tag = "Column", .classes = "items-center", .children = &rev_col_ch };

    const today_lbl   = NodeDesc{ .tag = "Text", .classes = "text-xs text-muted", .attrs = &_today_lbl_a };
    const today_val   = NodeDesc{ .tag = "Text", .classes = "text-sm font-bold", .attrs = &_today_val_a };
    const today_badge = NodeDesc{ .tag = "TrendBadge", .classes = "text-xs w-14 h-4" };
    const today_row_ch = [2]NodeDesc{ today_val, today_badge };
    const today_row   = NodeDesc{ .tag = "Row", .classes = "items-center gap-1", .children = &today_row_ch };
    const today_col_ch = [2]NodeDesc{ today_lbl, today_row };
    const today_col   = NodeDesc{ .tag = "Column", .classes = "items-center", .children = &today_col_ch };

    const stats_row_ch = [3]NodeDesc{ tgt_col, rev_col, today_col };
    const stats_row   = NodeDesc{ .tag = "Row", .classes = "justify-around", .children = &stats_row_ch };
    const gauge_card_ch = [4]NodeDesc{ gauge_title, gauge_sub, gauge_ph, stats_row };
    const gauge_card  = NodeDesc{ .tag = "Card", .classes = "p-4 shadow w-72", .children = &gauge_card_ch };

    const row2_ch = [2]NodeDesc{ bar_card, gauge_card };
    const row2    = NodeDesc{ .tag = "Row", .classes = "gap-4", .children = &row2_ch };

    // -----------------------------------------------------------------------
    // Row 3 — Statistics (area chart, full width)
    // -----------------------------------------------------------------------
    const stat_title = NodeDesc{ .tag = "Text", .classes = "font-bold", .attrs = &_stat_title_a };
    const stat_sub   = NodeDesc{ .tag = "Text", .classes = "text-sm text-muted", .attrs = &_stat_sub_a };
    const stat_ph    = NodeDesc{ .tag = "Card", .classes = "h-56 w-full bg-surface", .attrs = &_stat_ph_a };
    const stat_hdr_ch = [2]NodeDesc{ stat_title, stat_sub };
    const stat_hdr   = NodeDesc{ .tag = "Column", .children = &stat_hdr_ch };
    const stat_card_ch = [2]NodeDesc{ stat_hdr, stat_ph };
    const stat_card  = NodeDesc{ .tag = "Card", .classes = "p-4 shadow", .children = &stat_card_ch };

    // -----------------------------------------------------------------------
    // Row 4 — Demographics map + Recent Orders table
    // -----------------------------------------------------------------------

    // Map card
    const demo_title = NodeDesc{ .tag = "Text", .classes = "font-bold", .attrs = &_demo_title_a };
    const demo_sub   = NodeDesc{ .tag = "Text", .classes = "text-sm text-muted", .attrs = &_demo_sub_a };
    const map_ph     = NodeDesc{ .tag = "Card", .classes = "h-48 w-full bg-surface", .attrs = &_map_ph_a };
    const sep1       = NodeDesc{ .tag = "Separator" };

    const usa_name = NodeDesc{ .tag = "Text", .classes = "text-sm font-bold", .attrs = &_usa_name_a };
    const usa_cnt  = NodeDesc{ .tag = "Text", .classes = "text-xs text-muted", .attrs = &_usa_cnt_a };
    const usa_col_ch = [2]NodeDesc{ usa_name, usa_cnt };
    const usa_col  = NodeDesc{ .tag = "Column", .children = &usa_col_ch };
    const usa_pct  = NodeDesc{ .tag = "Text", .classes = "text-sm font-bold", .attrs = &_usa_pct_a };
    const usa_row_ch = [2]NodeDesc{ usa_col, usa_pct };
    const usa_row  = NodeDesc{ .tag = "Row", .classes = "justify-between items-center", .children = &usa_row_ch };

    const fr_name  = NodeDesc{ .tag = "Text", .classes = "text-sm font-bold", .attrs = &_fr_name_a };
    const fr_cnt   = NodeDesc{ .tag = "Text", .classes = "text-xs text-muted", .attrs = &_fr_cnt_a };
    const fr_col_ch = [2]NodeDesc{ fr_name, fr_cnt };
    const fr_col   = NodeDesc{ .tag = "Column", .children = &fr_col_ch };
    const fr_pct   = NodeDesc{ .tag = "Text", .classes = "text-sm font-bold", .attrs = &_fr_pct_a };
    const fr_row_ch = [2]NodeDesc{ fr_col, fr_pct };
    const fr_row   = NodeDesc{ .tag = "Row", .classes = "justify-between items-center", .children = &fr_row_ch };

    const countries_ch = [2]NodeDesc{ usa_row, fr_row };
    const countries    = NodeDesc{ .tag = "Column", .classes = "gap-2", .children = &countries_ch };

    const map_card_ch = [5]NodeDesc{ demo_title, demo_sub, map_ph, sep1, countries };
    const map_card   = NodeDesc{ .tag = "Card", .classes = "p-4 shadow grow", .children = &map_card_ch };

    // Recent Orders card — header
    const orders_title = NodeDesc{ .tag = "Text", .classes = "font-bold", .attrs = &_orders_title_a };
    const see_all_btn  = NodeDesc{ .tag = "Button", .classes = "text-xs", .attrs = &_see_all_a };
    const orders_hdr_ch = [2]NodeDesc{ orders_title, see_all_btn };
    const orders_hdr   = NodeDesc{ .tag = "Row", .classes = "justify-between items-center", .children = &orders_hdr_ch };
    const sep2         = NodeDesc{ .tag = "Separator" };
    const col_hdr_ch   = [4]NodeDesc{
        NodeDesc{ .tag = "Text", .classes = "text-xs text-muted grow", .attrs = &_col_prod_a },
        NodeDesc{ .tag = "Text", .classes = "text-xs text-muted", .attrs = &_col_cat_a },
        NodeDesc{ .tag = "Text", .classes = "text-xs text-muted", .attrs = &_col_price_a },
        NodeDesc{ .tag = "Text", .classes = "text-xs text-muted", .attrs = &_col_status_a },
    };
    const col_hdr = NodeDesc{ .tag = "Row", .classes = "gap-2 p-2", .children = &col_hdr_ch };

    // Order rows (simplified: name + price + status)
    const o1_info_ch = [2]NodeDesc{
        NodeDesc{ .tag = "Text", .classes = "text-sm font-bold", .attrs = &_o1_name_a },
        NodeDesc{ .tag = "Text", .classes = "text-xs text-muted", .attrs = &_o1_var_a },
    };
    const o1_info   = NodeDesc{ .tag = "Column", .classes = "grow", .children = &o1_info_ch };
    const o1_row_ch = [4]NodeDesc{
        o1_info,
        NodeDesc{ .tag = "Text", .classes = "text-xs text-muted", .attrs = &_o1_cat_a },
        NodeDesc{ .tag = "Text", .classes = "text-sm", .attrs = &_o1_pr_a },
        NodeDesc{ .tag = "Text", .classes = "text-xs", .attrs = &_o1_sts_a },
    };
    const o1_row = NodeDesc{ .tag = "Row", .classes = "items-center gap-2 p-2", .children = &o1_row_ch };

    const o2_info_ch = [2]NodeDesc{
        NodeDesc{ .tag = "Text", .classes = "text-sm font-bold", .attrs = &_o2_name_a },
        NodeDesc{ .tag = "Text", .classes = "text-xs text-muted", .attrs = &_o2_var_a },
    };
    const o2_info   = NodeDesc{ .tag = "Column", .classes = "grow", .children = &o2_info_ch };
    const o2_row_ch = [4]NodeDesc{
        o2_info,
        NodeDesc{ .tag = "Text", .classes = "text-xs text-muted", .attrs = &_o2_cat_a },
        NodeDesc{ .tag = "Text", .classes = "text-sm", .attrs = &_o2_pr_a },
        NodeDesc{ .tag = "Text", .classes = "text-xs", .attrs = &_o2_sts_a },
    };
    const o2_row = NodeDesc{ .tag = "Row", .classes = "items-center gap-2 p-2", .children = &o2_row_ch };

    const o3_info_ch = [2]NodeDesc{
        NodeDesc{ .tag = "Text", .classes = "text-sm font-bold", .attrs = &_o3_name_a },
        NodeDesc{ .tag = "Text", .classes = "text-xs text-muted", .attrs = &_o3_var_a },
    };
    const o3_info   = NodeDesc{ .tag = "Column", .classes = "grow", .children = &o3_info_ch };
    const o3_row_ch = [4]NodeDesc{
        o3_info,
        NodeDesc{ .tag = "Text", .classes = "text-xs text-muted", .attrs = &_o3_cat_a },
        NodeDesc{ .tag = "Text", .classes = "text-sm", .attrs = &_o3_pr_a },
        NodeDesc{ .tag = "Text", .classes = "text-xs", .attrs = &_o3_sts_a },
    };
    const o3_row = NodeDesc{ .tag = "Row", .classes = "items-center gap-2 p-2", .children = &o3_row_ch };

    const o4_info_ch = [2]NodeDesc{
        NodeDesc{ .tag = "Text", .classes = "text-sm font-bold", .attrs = &_o4_name_a },
        NodeDesc{ .tag = "Text", .classes = "text-xs text-muted", .attrs = &_o4_var_a },
    };
    const o4_info   = NodeDesc{ .tag = "Column", .classes = "grow", .children = &o4_info_ch };
    const o4_row_ch = [4]NodeDesc{
        o4_info,
        NodeDesc{ .tag = "Text", .classes = "text-xs text-muted", .attrs = &_o4_cat_a },
        NodeDesc{ .tag = "Text", .classes = "text-sm", .attrs = &_o4_pr_a },
        NodeDesc{ .tag = "Text", .classes = "text-xs", .attrs = &_o4_sts_a },
    };
    const o4_row = NodeDesc{ .tag = "Row", .classes = "items-center gap-2 p-2", .children = &o4_row_ch };

    const o5_info_ch = [2]NodeDesc{
        NodeDesc{ .tag = "Text", .classes = "text-sm font-bold", .attrs = &_o5_name_a },
        NodeDesc{ .tag = "Text", .classes = "text-xs text-muted", .attrs = &_o5_var_a },
    };
    const o5_info   = NodeDesc{ .tag = "Column", .classes = "grow", .children = &o5_info_ch };
    const o5_row_ch = [4]NodeDesc{
        o5_info,
        NodeDesc{ .tag = "Text", .classes = "text-xs text-muted", .attrs = &_o5_cat_a },
        NodeDesc{ .tag = "Text", .classes = "text-sm", .attrs = &_o5_pr_a },
        NodeDesc{ .tag = "Text", .classes = "text-xs", .attrs = &_o5_sts_a },
    };
    const o5_row = NodeDesc{ .tag = "Row", .classes = "items-center gap-2 p-2", .children = &o5_row_ch };

    const orders_body_ch2 = [8]NodeDesc{ orders_hdr, sep2, col_hdr, o1_row, o2_row, o3_row, o4_row, o5_row };
    const orders_card = NodeDesc{ .tag = "Card", .classes = "p-4 shadow w-96", .children = &orders_body_ch2 };

    const row4_ch = [2]NodeDesc{ map_card, orders_card };
    const row4    = NodeDesc{ .tag = "Row", .classes = "gap-4", .children = &row4_ch };

    // -----------------------------------------------------------------------
    // Assemble content in a ScrollView
    // -----------------------------------------------------------------------
    const content_col_ch = [4]NodeDesc{ row1, row2, stat_card, row4 };
    const content_col   = NodeDesc{ .tag = "Column", .classes = "gap-4 p-4", .children = &content_col_ch };
    const scroll        = NodeDesc{ .tag = "ScrollView", .classes = "flex-1", .children = &[1]NodeDesc{content_col} };

    const root_children = [2]NodeDesc{ sidebar.buildSidebar(), scroll };
    const root = NodeDesc{ .tag = "Row", .classes = "w-full h-full", .children = &root_children };

    _ = try scene.instantiate(root, tokens);

    // -----------------------------------------------------------------------
    // Post-instantiation: find chart placeholder elements by text.
    // -----------------------------------------------------------------------
    var i: u32 = 0;
    while (i < scene._kind.items.len) : (i += 1) {
        if (scene._text.items[i]) |txt| {
            if (std.mem.eql(u8, txt, "CHART:BAR"))   _bar_chart_idx  = i;
            if (std.mem.eql(u8, txt, "CHART:GAUGE")) _gauge_idx      = i;
            if (std.mem.eql(u8, txt, "CHART:AREA"))  _area_chart_idx = i;
            if (std.mem.eql(u8, txt, "CHART:MAP"))   _map_idx        = i;
        }
    }

    // -----------------------------------------------------------------------
    // Set KPI trend badge text and color (Text elements, not TrendBadge).
    // Scan for marker text "TREND:C" and "TREND:O" set during instantiation.
    // -----------------------------------------------------------------------
    i = 0;
    while (i < scene._kind.items.len) : (i += 1) {
        if (scene._text.items[i]) |txt| {
            if (std.mem.eql(u8, txt, "TREND:C")) {
                scene._text.items[i] = "+11.01%";
                scene._style.items[i].text_color = tokens.ok;
            } else if (std.mem.eql(u8, txt, "TREND:O")) {
                scene._text.items[i] = "-9.05%";
                scene._style.items[i].text_color = tokens.err;
            }
        }
    }

    // -----------------------------------------------------------------------
    // Set TrendBadge values (gauge stats) in DFS order.
    // Badges in order (only 3 remain): Target -5.0, Revenue +5.0, Today +5.0
    // -----------------------------------------------------------------------
    const trend_vals = [_]f32{ -5.0, 5.0, 5.0 };
    var trend_count: u32 = 0;
    i = 0;
    while (i < scene._kind.items.len) : (i += 1) {
        if (scene.kindOfIdx(i) == .trend_badge) {
            if (trend_count < trend_vals.len) {
                scene.setTrendValue(i, trend_vals[trend_count]);
            }
            trend_count += 1;
        }
    }

    // -----------------------------------------------------------------------
    // Set order status text colors.
    // -----------------------------------------------------------------------
    i = 0;
    while (i < scene._kind.items.len) : (i += 1) {
        if (scene._text.items[i]) |txt| {
            if (std.mem.eql(u8, txt, "Delivered")) {
                scene._style.items[i].text_color = tokens.ok;
            } else if (std.mem.eql(u8, txt, "Pending")) {
                scene._style.items[i].text_color = tokens.warn;
            } else if (std.mem.eql(u8, txt, "Cancelled")) {
                scene._style.items[i].text_color = tokens.err;
            }
        }
    }

    // Wire sidebar — ecommerce is button index 13 (12th button, 0-based index 11).
    try shared.wireSidebarCallbacks(scene, c.global, tokens, 13);
}

// ---------------------------------------------------------------------------
// renderCharts — called each frame from per_frame_app_fn in main.zig
// ---------------------------------------------------------------------------

/// RN11 — Render chart draw commands into ai.chart_cmds for injection
/// between main and overlay draw passes.
pub fn renderCharts(ai: *app_types.app_impl.AppInner) anyerror!void {
    // Guard: only run when ecommerce screen is active (i.e., build() has been called).
    if (_bar_chart_idx == std.math.maxInt(u32) and
        _gauge_idx      == std.math.maxInt(u32) and
        _area_chart_idx == std.math.maxInt(u32) and
        _map_idx        == std.math.maxInt(u32)) return;

    const alloc = ai.gpa;
    var cmds = std.ArrayListUnmanaged(chart_mod.DrawCmd).empty;
    errdefer cmds.deinit(alloc);

    // Helper: get computed rect for an element index.
    const elem_count = ai.scene.elements.layout.items.len;

    // --- Bar chart (Monthly Sales) ---
    if (_bar_chart_idx != std.math.maxInt(u32) and _bar_chart_idx < elem_count) {
        const rect = ai.scene.elements.layout.items[_bar_chart_idx].computed;
        if (rect.w > 10 and rect.h > 10) {
            const pad: f32 = 8.0;
            const outer = chart_mod.Rect09{ .x = rect.x + pad, .y = rect.y + pad, .w = rect.w - pad * 2, .h = rect.h - pad * 2 };
            const x_sc = chart_mod.Scale{ .band = .{
                .categories = &_bar_months,
                .range_min  = outer.x + 30,
                .range_max  = outer.x + outer.w,
                .padding    = 0.2,
            }};
            const y_sc = chart_mod.Scale{ .linear = .{
                .domain_min = 0, .domain_max = 400,
                .range_min  = outer.y, .range_max = outer.y + outer.h - 24,
            }};
            const frame = chart_mod.makeFrame(outer, x_sc, y_sc, .{
                .gutter_left = 30, .gutter_bottom = 24,
                .show_x = false, .show_y = true, .show_grid = true,
            });
            try chart_mod.drawAxes(&frame, .{
                .gutter_left = 30, .gutter_bottom = 24,
                .show_x = false, .show_y = true, .show_grid = true,
            }, &cmds, alloc);

            const bar_vals = [_]f64{ 150, 280, 200, 240, 180, 320, 260, 200, 170, 210, 290, 340 };
            const bar_series = [1]chart_mod.Series{.{ .name = "Sales", .values = &bar_vals, .color_token = "accent" }};
            const bar_chart = chart_mod.Chart{
                .kind = .bar, .series = &bar_series, .x = .{ .categories = &_bar_months },
            };
            try bar_chart.render(&frame, &cmds, alloc);
        }
    }

    // --- Gauge chart (Monthly Target) ---
    if (_gauge_idx != std.math.maxInt(u32) and _gauge_idx < elem_count) {
        const rect = ai.scene.elements.layout.items[_gauge_idx].computed;
        if (rect.w > 10 and rect.h > 10) {
            const outer = chart_mod.Rect09{ .x = rect.x, .y = rect.y, .w = rect.w, .h = rect.h };
            const dummy_sc = chart_mod.Scale{ .linear = .{ .domain_min = 0, .domain_max = 1, .range_min = 0, .range_max = 1 }};
            const frame = chart_mod.ChartFrame{ .outer_rect = outer, .plot_rect = outer, .x = dummy_sc, .y = dummy_sc };
            const gauge_chart = chart_mod.Chart{
                .kind = .gauge, .series = &.{}, .x = .{ .numeric = &[_]f64{} },
                .gauge_value = 0.7555, .gauge_bg_token = "axis", .gauge_fill_token = "accent",
            };
            try gauge_chart.render(&frame, &cmds, alloc);
        }
    }

    // --- Area chart (Statistics) ---
    if (_area_chart_idx != std.math.maxInt(u32) and _area_chart_idx < elem_count) {
        const rect = ai.scene.elements.layout.items[_area_chart_idx].computed;
        if (rect.w > 10 and rect.h > 10) {
            const pad: f32 = 8.0;
            const outer = chart_mod.Rect09{ .x = rect.x + pad, .y = rect.y + pad, .w = rect.w - pad * 2, .h = rect.h - pad * 2 };
            const frame_left = outer.x + 40;
            const frame_right = outer.x + outer.w;
            const x_sc = chart_mod.Scale{ .linear = .{
                .domain_min = 0, .domain_max = 11,
                .range_min  = frame_left,
                .range_max  = frame_right,
            }};
            const y_sc = chart_mod.Scale{ .linear = .{
                .domain_min = 0, .domain_max = 300,
                .range_min  = outer.y, .range_max = outer.y + outer.h - 24,
            }};
            const frame = chart_mod.makeFrame(outer, x_sc, y_sc, .{
                .gutter_left = 40, .gutter_bottom = 24,
            });
            try chart_mod.drawAxes(&frame, .{ .gutter_left = 40, .gutter_bottom = 24 }, &cmds, alloc);

            const area_vals  = [_]f64{ 160,170,165,180,175,200,210,205,215,225,230,240 };
            const area_vals2 = [_]f64{ 50, 60, 55, 70, 65, 80, 85, 90, 85, 95,100,105 };
            const area_series = [2]chart_mod.Series{
                .{ .name = "Revenue", .values = &area_vals,  .color_token = "series0" },
                .{ .name = "Sales",   .values = &area_vals2, .color_token = "series1" },
            };
            const area_x_data = [_]f64{0,1,2,3,4,5,6,7,8,9,10,11};
            const area_chart = chart_mod.Chart{
                .kind = .area, .series = &area_series, .x = .{ .numeric = &area_x_data },
            };
            try area_chart.render(&frame, &cmds, alloc);
        }
    }

    // --- World map (Customers Demographic) ---
    if (_map_idx != std.math.maxInt(u32) and _map_idx < elem_count) {
        const rect = ai.scene.elements.layout.items[_map_idx].computed;
        if (rect.w > 10 and rect.h > 10) {
            const outer = chart_mod.Rect09{ .x = rect.x, .y = rect.y, .w = rect.w, .h = rect.h };
            const dummy_sc = chart_mod.Scale{ .linear = .{ .domain_min = 0, .domain_max = 1, .range_min = 0, .range_max = 1 }};
            const frame = chart_mod.ChartFrame{ .outer_rect = outer, .plot_rect = outer, .x = dummy_sc, .y = dummy_sc };
            const map_markers = [_]chart_mod.MapMarker{
                .{ .norm_x = 0.21, .norm_y = 0.38, .radius = 5.0, .color_token = "accent" },
                .{ .norm_x = 0.49, .norm_y = 0.28, .radius = 4.0, .color_token = "series1" },
            };
            const map_chart = chart_mod.Chart{
                .kind = .map, .series = &.{}, .x = .{ .numeric = &[_]f64{} },
                .map_markers = &map_markers,
                .map_ocean_token = "surface", .map_land_token = "axis",
            };
            try map_chart.render(&frame, &cmds, alloc);
        }
    }

    if (cmds.items.len > 0) {
        ai.chart_cmds = try cmds.toOwnedSlice(alloc);
    } else {
        cmds.deinit(alloc);
    }
}
