//! components.zig — Components demo screen (Screen 13 = sidebar index 14).
//! Shows a component gallery styled after shadcn/ui.

const mod07 = @import("../07/types.zig");
const mod05 = @import("../05/types.zig");
const mod06 = @import("../06/types.zig");

const Scene  = mod07.Scene;
const Tokens = mod05.Tokens;
const NodeDesc = mod06.NodeDesc;
const Attr     = mod06.Attr;
const DropdownOption = mod07.DropdownOption;

const shared  = @import("../shared/types.zig");
const sidebar = @import("../shared/sidebar.zig");

// ---------------------------------------------------------------------------
// Persistent option storage (program lifetime)
// ---------------------------------------------------------------------------
var _country_values: [5]u8 = .{ 0, 1, 2, 3, 4 };
var _country_opts: [5]DropdownOption = .{
    .{ .label = "Australia", .value = &_country_values[0] },
    .{ .label = "Canada",    .value = &_country_values[1] },
    .{ .label = "Germany",   .value = &_country_values[2] },
    .{ .label = "Japan",     .value = &_country_values[3] },
    .{ .label = "USA",       .value = &_country_values[4] },
};

pub const ComponentsCtx = struct {
    global: *shared.GlobalState,
};

pub fn build(
    scene: *Scene,
    tokens: Tokens,
    app: *anyopaque,
    ctx: ?*anyopaque,
) anyerror!void {
    _ = app;
    const c: *ComponentsCtx = @ptrCast(@alignCast(ctx.?));

    // -----------------------------------------------------------------------
    // Page header
    // -----------------------------------------------------------------------
    const h1_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Components" } }};
    const h1 = NodeDesc{ .tag = "Text", .classes = "text-xl font-bold", .attrs = &h1_attrs };

    const sub_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "A showcase of UI components styled after shadcn/ui" } }};
    const sub = NodeDesc{ .tag = "Text", .classes = "text-muted text-sm", .attrs = &sub_attrs };

    const sep = NodeDesc{ .tag = "Separator", .classes = "my-2" };

    // -----------------------------------------------------------------------
    // Typography section
    // -----------------------------------------------------------------------
    const typo_h_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Typography" } }};
    const typo_h = NodeDesc{ .tag = "Text", .classes = "font-bold", .attrs = &typo_h_attrs };

    const t1_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Heading — text-xl font-bold" } }};
    const t2_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Large — text-lg" } }};
    const t3_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Base body — text-base (14px)" } }};
    const t4_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Small — text-sm (12px)" } }};
    const t5_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Extra small — text-xs (10px)" } }};
    const t6_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Muted — text-muted" } }};
    const t7_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Bold — font-bold" } }};

    const t1 = NodeDesc{ .tag = "Text", .classes = "text-xl font-bold", .attrs = &t1_attrs };
    const t2 = NodeDesc{ .tag = "Text", .classes = "text-lg",           .attrs = &t2_attrs };
    const t3 = NodeDesc{ .tag = "Text", .classes = "text-base",         .attrs = &t3_attrs };
    const t4 = NodeDesc{ .tag = "Text", .classes = "text-sm",           .attrs = &t4_attrs };
    const t5 = NodeDesc{ .tag = "Text", .classes = "text-xs",           .attrs = &t5_attrs };
    const t6 = NodeDesc{ .tag = "Text", .classes = "text-muted",        .attrs = &t6_attrs };
    const t7 = NodeDesc{ .tag = "Text", .classes = "font-bold",         .attrs = &t7_attrs };

    const typo_items_ch = [7]NodeDesc{ t1, t2, t3, t4, t5, t6, t7 };
    const typo_items = NodeDesc{ .tag = "Column", .classes = "gap-1", .children = &typo_items_ch };

    const typo_sect_ch = [2]NodeDesc{ typo_h, typo_items };
    const typo_sect = NodeDesc{ .tag = "Column", .classes = "gap-2", .children = &typo_sect_ch };

    // -----------------------------------------------------------------------
    // Badges section
    // -----------------------------------------------------------------------
    const badges_h_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Badges" } }};
    const badges_h = NodeDesc{ .tag = "Text", .classes = "font-bold", .attrs = &badges_h_attrs };

    const b1_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Default" } }};
    const b2_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Secondary" } }};
    const b3_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Outline" } }};
    const b4_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Delivered" } }};
    const b5_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Pending" } }};
    const b6_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Cancelled" } }};

    const b1 = NodeDesc{ .tag = "Text", .classes = "rounded-full px-2 h-5 text-xs font-bold bg-accent", .attrs = &b1_attrs };
    const b2 = NodeDesc{ .tag = "Card", .classes = "rounded-full px-2 h-5 text-xs bg-raised",           .attrs = &b2_attrs };
    const b3 = NodeDesc{ .tag = "Card", .classes = "rounded-full px-2 h-5 text-xs border bg-canvas",    .attrs = &b3_attrs };
    const b4 = NodeDesc{ .tag = "Card", .classes = "rounded-full px-2 h-5 text-xs font-bold bg-raised", .attrs = &b4_attrs };
    const b5 = NodeDesc{ .tag = "Card", .classes = "rounded-full px-2 h-5 text-xs font-bold bg-raised", .attrs = &b5_attrs };
    const b6 = NodeDesc{ .tag = "Card", .classes = "rounded-full px-2 h-5 text-xs font-bold bg-raised", .attrs = &b6_attrs };

    const badges_row_ch = [6]NodeDesc{ b1, b2, b3, b4, b5, b6 };
    const badges_row = NodeDesc{ .tag = "Row", .classes = "gap-2 flex-wrap", .children = &badges_row_ch };

    const badges_sect_ch = [2]NodeDesc{ badges_h, badges_row };
    const badges_sect = NodeDesc{ .tag = "Column", .classes = "gap-2", .children = &badges_sect_ch };

    // -----------------------------------------------------------------------
    // Buttons section
    // -----------------------------------------------------------------------
    const btns_h_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Buttons" } }};
    const btns_h = NodeDesc{ .tag = "Text", .classes = "font-bold", .attrs = &btns_h_attrs };

    const btn1_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Primary" } }};
    const btn2_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Secondary" } }};
    const btn3_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Outline" } }};
    const btn4_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Ghost" } }};
    const btn5_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Destructive" } }};

    const btn1 = NodeDesc{ .tag = "Button", .classes = "",              .attrs = &btn1_attrs };
    const btn2 = NodeDesc{ .tag = "Button", .classes = "border bg-raised", .attrs = &btn2_attrs };
    const btn3 = NodeDesc{ .tag = "Button", .classes = "border bg-canvas", .attrs = &btn3_attrs };
    const btn4 = NodeDesc{ .tag = "Button", .classes = "bg-canvas",     .attrs = &btn4_attrs };
    const btn5 = NodeDesc{ .tag = "Button", .classes = "bg-raised",     .attrs = &btn5_attrs };

    const btns_row_ch = [5]NodeDesc{ btn1, btn2, btn3, btn4, btn5 };
    const btns_row = NodeDesc{ .tag = "Row", .classes = "gap-3 flex-wrap", .children = &btns_row_ch };

    const btns_sect_ch = [2]NodeDesc{ btns_h, btns_row };
    const btns_sect = NodeDesc{ .tag = "Column", .classes = "gap-2", .children = &btns_sect_ch };

    // -----------------------------------------------------------------------
    // Form controls section
    // -----------------------------------------------------------------------
    const forms_h_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Form Controls" } }};
    const forms_h = NodeDesc{ .tag = "Text", .classes = "font-bold", .attrs = &forms_h_attrs };

    // Input field
    const inp_lbl_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Full name" } }};
    const inp_lbl = NodeDesc{ .tag = "Text", .classes = "text-sm font-bold", .attrs = &inp_lbl_attrs };
    const inp_ph_attrs = [1]Attr{.{ .name = "placeholder", .value = .{ .literal = "Enter your name..." } }};
    const inp = NodeDesc{ .tag = "Input", .classes = "w-full", .attrs = &inp_ph_attrs };
    const inp_hint_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Enter your name here." } }};
    const inp_hint = NodeDesc{ .tag = "Text", .classes = "text-xs text-muted", .attrs = &inp_hint_attrs };
    const inp_field_ch = [3]NodeDesc{ inp_lbl, inp, inp_hint };
    const inp_field = NodeDesc{ .tag = "Column", .classes = "gap-1 max-w-md", .children = &inp_field_ch };

    // Checkbox
    const cb_attrs = [1]Attr{.{ .name = "label", .value = .{ .literal = "Accept terms and conditions" } }};
    const cb = NodeDesc{ .tag = "Checkbox", .classes = "", .attrs = &cb_attrs };

    // Radio group
    const rg_lbl_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Notification preference" } }};
    const rg_lbl = NodeDesc{ .tag = "Text", .classes = "text-sm font-bold", .attrs = &rg_lbl_attrs };

    const r1_attrs = [1]Attr{.{ .name = "label", .value = .{ .literal = "Email" } }};
    const r2_attrs = [1]Attr{.{ .name = "label", .value = .{ .literal = "SMS" } }};
    const r3_attrs = [1]Attr{.{ .name = "label", .value = .{ .literal = "Push notification" } }};
    const r1 = NodeDesc{ .tag = "Radio", .classes = "", .attrs = &r1_attrs };
    const r2 = NodeDesc{ .tag = "Radio", .classes = "", .attrs = &r2_attrs };
    const r3 = NodeDesc{ .tag = "Radio", .classes = "", .attrs = &r3_attrs };
    const rg_radios_ch = [3]NodeDesc{ r1, r2, r3 };
    const rg_radios = NodeDesc{ .tag = "Column", .classes = "gap-2", .children = &rg_radios_ch };
    const rg_ch = [2]NodeDesc{ rg_lbl, rg_radios };
    const rg = NodeDesc{ .tag = "Column", .classes = "gap-2", .children = &rg_ch };

    // Slider
    const sl_lbl_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Volume" } }};
    const sl_lbl = NodeDesc{ .tag = "Text", .classes = "text-sm font-bold", .attrs = &sl_lbl_attrs };
    const sl = NodeDesc{ .tag = "Slider", .classes = "w-64" };
    const sl_field_ch = [2]NodeDesc{ sl_lbl, sl };
    const sl_field = NodeDesc{ .tag = "Column", .classes = "gap-2", .children = &sl_field_ch };

    // Dropdown
    const dd_lbl_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Country" } }};
    const dd_lbl = NodeDesc{ .tag = "Text", .classes = "text-sm font-bold", .attrs = &dd_lbl_attrs };
    const dd = NodeDesc{ .tag = "Dropdown", .classes = "w-64" };
    const dd_field_ch = [2]NodeDesc{ dd_lbl, dd };
    const dd_field = NodeDesc{ .tag = "Column", .classes = "gap-2", .children = &dd_field_ch };

    const forms_items_ch = [5]NodeDesc{ inp_field, cb, rg, sl_field, dd_field };
    const forms_items = NodeDesc{ .tag = "Column", .classes = "gap-4", .children = &forms_items_ch };
    const forms_sect_ch = [2]NodeDesc{ forms_h, forms_items };
    const forms_sect = NodeDesc{ .tag = "Column", .classes = "gap-3", .children = &forms_sect_ch };

    // -----------------------------------------------------------------------
    // Stat cards section
    // -----------------------------------------------------------------------
    const stat_h_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Stat Cards" } }};
    const stat_h = NodeDesc{ .tag = "Text", .classes = "font-bold", .attrs = &stat_h_attrs };

    // Stat card 1 — Revenue
    const sc1_lbl_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Revenue" } }};
    const sc1_val_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "$45,231.89" } }};
    const sc1_sub_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "+20.1% from last month" } }};
    const sc1_lbl = NodeDesc{ .tag = "Text", .classes = "text-sm text-muted", .attrs = &sc1_lbl_attrs };
    const sc1_val = NodeDesc{ .tag = "Text", .classes = "text-xl font-bold",  .attrs = &sc1_val_attrs };
    const sc1_sub = NodeDesc{ .tag = "Text", .classes = "text-xs text-muted", .attrs = &sc1_sub_attrs };
    const sc1_top_ch = [2]NodeDesc{ sc1_lbl, sc1_val };
    const sc1_top = NodeDesc{ .tag = "Column", .classes = "gap-1 grow", .children = &sc1_top_ch };
    const sc1_inner_ch = [2]NodeDesc{ sc1_top, sc1_sub };
    const sc1_inner = NodeDesc{ .tag = "Column", .classes = "gap-2 grow", .children = &sc1_inner_ch };
    const sc1 = NodeDesc{ .tag = "Card", .classes = "p-4 shadow grow", .children = &[1]NodeDesc{sc1_inner} };

    // Stat card 2 — Active Users
    const sc2_lbl_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Active Users" } }};
    const sc2_val_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "+2,350" } }};
    const sc2_sub_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "+180.1% from last month" } }};
    const sc2_lbl = NodeDesc{ .tag = "Text", .classes = "text-sm text-muted", .attrs = &sc2_lbl_attrs };
    const sc2_val = NodeDesc{ .tag = "Text", .classes = "text-xl font-bold",  .attrs = &sc2_val_attrs };
    const sc2_sub = NodeDesc{ .tag = "Text", .classes = "text-xs text-muted", .attrs = &sc2_sub_attrs };
    const sc2_top_ch = [2]NodeDesc{ sc2_lbl, sc2_val };
    const sc2_top = NodeDesc{ .tag = "Column", .classes = "gap-1 grow", .children = &sc2_top_ch };
    const sc2_inner_ch = [2]NodeDesc{ sc2_top, sc2_sub };
    const sc2_inner = NodeDesc{ .tag = "Column", .classes = "gap-2 grow", .children = &sc2_inner_ch };
    const sc2 = NodeDesc{ .tag = "Card", .classes = "p-4 shadow grow", .children = &[1]NodeDesc{sc2_inner} };

    const stat_cards_ch = [2]NodeDesc{ sc1, sc2 };
    const stat_cards = NodeDesc{ .tag = "Row", .classes = "gap-4", .children = &stat_cards_ch };
    const stat_sect_ch = [2]NodeDesc{ stat_h, stat_cards };
    const stat_sect = NodeDesc{ .tag = "Column", .classes = "gap-3", .children = &stat_sect_ch };

    // -----------------------------------------------------------------------
    // Assemble all sections into a scrollable column
    // -----------------------------------------------------------------------
    const content_ch = [8]NodeDesc{ h1, sub, sep, typo_sect, badges_sect, btns_sect, forms_sect, stat_sect };
    const content = NodeDesc{ .tag = "Column", .classes = "p-4 gap-6", .children = &content_ch };
    const scroll_ch = [1]NodeDesc{content};
    const scroll = NodeDesc{ .tag = "ScrollView", .classes = "flex-1", .children = &scroll_ch };

    // Root layout: sidebar + content
    const root_ch = [2]NodeDesc{ sidebar.buildSidebar(), scroll };
    const root = NodeDesc{ .tag = "Row", .classes = "w-full h-full", .children = &root_ch };

    _ = try scene.instantiate(root, tokens);
    try shared.wireSidebarCallbacks(scene, c.global, tokens, 14); // 14 = Components button

    // Post-instantiation: set dropdown options
    var i: u32 = 0;
    while (i < scene._kind.items.len) : (i += 1) {
        if (scene.kindOfIdx(i) == .dropdown) {
            scene.setDropdownOptions(i, &_country_opts) catch {};
            break;
        }
    }

    // Post-instantiation: color the status badges, Default badge, and fix button text colors
    // b1 = Default (accent bg, accent_text), b4 = Delivered (ok), b5 = Pending (warn), b6 = Cancelled (err)
    // btn2 = Secondary, btn3 = Outline, btn4 = Ghost — all have light bg but inherited white text
    // The badges are Card/Text nodes — scan by text content.
    var j: u32 = 0;
    while (j < scene._kind.items.len) : (j += 1) {
        if (scene.textOf(.{ .index = j, .gen = 0 })) |txt| {
            if (std.mem.eql(u8, txt, "Default")) {
                scene._style.items[j].text_color = tokens.accent_text;
            } else if (std.mem.eql(u8, txt, "Delivered")) {
                scene._style.items[j].text_color = tokens.ok;
            } else if (std.mem.eql(u8, txt, "Pending")) {
                scene._style.items[j].text_color = tokens.warn;
            } else if (std.mem.eql(u8, txt, "Cancelled")) {
                scene._style.items[j].text_color = tokens.err;
            } else if (std.mem.eql(u8, txt, "Destructive")) {
                scene._style.items[j].background = tokens.err;
                scene._style.items[j].text_color = tokens.accent_text;
            } else if (std.mem.eql(u8, txt, "Secondary") or std.mem.eql(u8, txt, "Outline") or std.mem.eql(u8, txt, "Ghost")) {
                // These buttons override background to a light color but inherit white text from
                // buttonPrimary — fix by using the body text color (dark) for contrast.
                if (scene.kindOfIdx(j) == .button) {
                    scene._style.items[j].text_color = tokens.text_body;
                }
            }
        }
    }
}

const std = @import("std");
