//! m13.zig — M13 rendering quality features showcase screen (Screen 10).
//!
//! Demonstrates:
//!   RD0 — gradient fills (horizontal, vertical, diagonal)
//!   RD4 — anti-aliased filled shapes (rects and circles)
//!   RD1 — rounded content clipping (rounded-xl overflow-hidden)
//!   RD3 — SDF vector icons (chevron-down, check, cross, search, menu)
//!   RD5 — HiDPI display-scale awareness (informational)
//!   RD2 — subpixel glyph rendering (informational note)

const mod07 = @import("../07/types.zig");
const mod05 = @import("../05/types.zig");
const mod06 = @import("../06/types.zig");

const Scene = mod07.Scene;
const Tokens = mod05.Tokens;
const NodeDesc = mod06.NodeDesc;
const Attr = mod06.Attr;

const shared = @import("../shared/types.zig");
const sidebar = @import("../shared/sidebar.zig");

pub const M13Ctx = struct {
    global: *shared.GlobalState,
};

pub fn build(
    scene: *Scene,
    tokens: Tokens,
    app: *anyopaque,
    ctx: ?*anyopaque,
) anyerror!void {
    _ = app;
    const c: *M13Ctx = @ptrCast(@alignCast(ctx.?));

    const h_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "M13 \xe2\x80\x94 Rendering Quality" } }};
    const heading = NodeDesc{ .tag = "Text", .classes = "text-xl", .attrs = &h_attrs };
    const sep = NodeDesc{ .tag = "Separator" };

    // =======================================================================
    // RD0 — Gradient fills
    // =======================================================================
    const rd0_h_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "RD0 \xe2\x80\x94 Gradient Fills" } }};
    const rd0_h = NodeDesc{ .tag = "Text", .classes = "font-bold", .attrs = &rd0_h_attrs };
    const rd0_note_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "bg-gradient-to-{r,b,br} with bg_canvas \xe2\x86\x92 bg_surface stops" } }};
    const rd0_note = NodeDesc{ .tag = "Text", .classes = "text-muted text-sm", .attrs = &rd0_note_attrs };

    const grad_r_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "to-r" } }};
    const grad_r = NodeDesc{ .tag = "Card", .classes = "bg-gradient-to-r p-4 w-40 h-16", .attrs = &grad_r_attrs };

    const grad_b_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "to-b" } }};
    const grad_b = NodeDesc{ .tag = "Card", .classes = "bg-gradient-to-b p-4 w-40 h-16", .attrs = &grad_b_attrs };

    const grad_br_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "to-br" } }};
    const grad_br = NodeDesc{ .tag = "Card", .classes = "bg-gradient-to-br p-4 w-40 h-16", .attrs = &grad_br_attrs };

    const grad_row_children = [3]NodeDesc{ grad_r, grad_b, grad_br };
    const grad_row = NodeDesc{ .tag = "Row", .classes = "gap-4", .children = &grad_row_children };

    const rd0_sect_children = [3]NodeDesc{ rd0_h, rd0_note, grad_row };
    const rd0_sect = NodeDesc{ .tag = "Column", .classes = "gap-2", .children = &rd0_sect_children };

    // =======================================================================
    // RD4 — Anti-aliased filled shapes
    // =======================================================================
    const rd4_h_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "RD4 \xe2\x80\x94 Anti-Aliased Filled Shapes" } }};
    const rd4_h = NodeDesc{ .tag = "Text", .classes = "font-bold", .attrs = &rd4_h_attrs };
    const rd4_note_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Smooth 1-px edges on filled rects and circles. Cards with rounded-full create circular shapes." } }};
    const rd4_note = NodeDesc{ .tag = "Text", .classes = "text-muted text-sm", .attrs = &rd4_note_attrs };

    // Several rects at various sizes
    const rect_s_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "16" } }};
    const rect_s = NodeDesc{ .tag = "Card", .classes = "w-4 h-4 bg-raised", .attrs = &rect_s_attrs };

    const rect_m_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "32" } }};
    const rect_m = NodeDesc{ .tag = "Card", .classes = "w-8 h-8 bg-raised", .attrs = &rect_m_attrs };

    const rect_l_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "48" } }};
    const rect_l = NodeDesc{ .tag = "Card", .classes = "w-12 h-12 bg-raised", .attrs = &rect_l_attrs };

    const rect_xl_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "64" } }};
    const rect_xl = NodeDesc{ .tag = "Card", .classes = "w-16 h-16 bg-raised", .attrs = &rect_xl_attrs };

    const rect_row_children = [4]NodeDesc{ rect_s, rect_m, rect_l, rect_xl };
    const rect_row = NodeDesc{ .tag = "Row", .classes = "gap-3 items-end", .children = &rect_row_children };

    // Rounded rects (anti-aliased corners)
    const rr_s_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "r-sm" } }};
    const rr_s = NodeDesc{ .tag = "Card", .classes = "rounded p-1 w-12 h-8 bg-raised", .attrs = &rr_s_attrs };

    const rr_l_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "r-lg" } }};
    const rr_l = NodeDesc{ .tag = "Card", .classes = "rounded-lg p-2 w-20 h-12 bg-raised", .attrs = &rr_l_attrs };

    const rr_xl_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "r-xl" } }};
    const rr_xl = NodeDesc{ .tag = "Card", .classes = "rounded-xl p-3 w-24 h-16 bg-raised", .attrs = &rr_xl_attrs };

    const rr_row_children = [3]NodeDesc{ rr_s, rr_l, rr_xl };
    const rr_row = NodeDesc{ .tag = "Row", .classes = "gap-3 items-end", .children = &rr_row_children };

    // Filled circles (rounded-full with equal w/h)
    const circle_s_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "c" } }};
    const circle_s = NodeDesc{ .tag = "Card", .classes = "rounded-full w-8 h-8 bg-raised", .attrs = &circle_s_attrs };

    const circle_m_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "c" } }};
    const circle_m = NodeDesc{ .tag = "Card", .classes = "rounded-full w-12 h-12 bg-raised", .attrs = &circle_m_attrs };

    const circle_l_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "c" } }};
    const circle_l = NodeDesc{ .tag = "Card", .classes = "rounded-full w-16 h-16 bg-raised", .attrs = &circle_l_attrs };

    const circle_row_children = [3]NodeDesc{ circle_s, circle_m, circle_l };
    const circle_row = NodeDesc{ .tag = "Row", .classes = "gap-3 items-center", .children = &circle_row_children };

    const rd4_sect_children = [5]NodeDesc{ rd4_h, rd4_note, rect_row, rr_row, circle_row };
    const rd4_sect = NodeDesc{ .tag = "Column", .classes = "gap-2", .children = &rd4_sect_children };

    // =======================================================================
    // RD1 — Rounded content clipping
    // =======================================================================
    const rd1_h_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "RD1 \xe2\x80\x94 Rounded Content Clipping" } }};
    const rd1_h = NodeDesc{ .tag = "Text", .classes = "font-bold", .attrs = &rd1_h_attrs };
    const rd1_note_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "rounded-xl overflow-hidden: child cards extend to corners but are clipped at the rounded border." } }};
    const rd1_note = NodeDesc{ .tag = "Text", .classes = "text-muted text-sm", .attrs = &rd1_note_attrs };

    // Child elements inside a rounded + overflow-hidden container
    const clip_child1_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Child 1" } }};
    const clip_child1 = NodeDesc{ .tag = "Card", .classes = "p-2 bg-raised", .attrs = &clip_child1_attrs };

    const clip_child2_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Child 2 extends to corners" } }};
    const clip_child2 = NodeDesc{ .tag = "Card", .classes = "p-2 bg-raised", .attrs = &clip_child2_attrs };

    const clip_child3_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Child 3" } }};
    const clip_child3 = NodeDesc{ .tag = "Card", .classes = "p-2 bg-raised", .attrs = &clip_child3_attrs };

    const clip_children = [3]NodeDesc{ clip_child1, clip_child2, clip_child3 };
    const clip_container = NodeDesc{ .tag = "Card", .classes = "rounded-xl overflow-hidden p-0 gap-0 w-64", .children = &clip_children };

    const rd1_sect_children = [3]NodeDesc{ rd1_h, rd1_note, clip_container };
    const rd1_sect = NodeDesc{ .tag = "Column", .classes = "gap-2", .children = &rd1_sect_children };

    // =======================================================================
    // RD3 — SDF vector icons
    // =======================================================================
    const rd3_h_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "RD3 \xe2\x80\x94 SDF Vector Icons" } }};
    const rd3_h = NodeDesc{ .tag = "Text", .classes = "font-bold", .attrs = &rd3_h_attrs };
    const rd3_note_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Signed-distance-field icons at 16, 24, and 48 px. Smooth edges at any scale." } }};
    const rd3_note = NodeDesc{ .tag = "Text", .classes = "text-muted text-sm", .attrs = &rd3_note_attrs };

    // Icon row 1: small (16px)
    const ic16_1_attrs = [1]Attr{.{ .name = "icon_name", .value = .{ .literal = "chevron-down" } }};
    const ic16_2_attrs = [1]Attr{.{ .name = "icon_name", .value = .{ .literal = "check" } }};
    const ic16_3_attrs = [1]Attr{.{ .name = "icon_name", .value = .{ .literal = "cross" } }};
    const ic16_4_attrs = [1]Attr{.{ .name = "icon_name", .value = .{ .literal = "search" } }};
    const ic16_5_attrs = [1]Attr{.{ .name = "icon_name", .value = .{ .literal = "menu" } }};
    const ic16_1 = NodeDesc{ .tag = "Icon", .classes = "w-4 h-4", .attrs = &ic16_1_attrs };
    const ic16_2 = NodeDesc{ .tag = "Icon", .classes = "w-4 h-4", .attrs = &ic16_2_attrs };
    const ic16_3 = NodeDesc{ .tag = "Icon", .classes = "w-4 h-4", .attrs = &ic16_3_attrs };
    const ic16_4 = NodeDesc{ .tag = "Icon", .classes = "w-4 h-4", .attrs = &ic16_4_attrs };
    const ic16_5 = NodeDesc{ .tag = "Icon", .classes = "w-4 h-4", .attrs = &ic16_5_attrs };
    const ic16_label_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "16px" } }};
    const ic16_label = NodeDesc{ .tag = "Text", .classes = "text-sm text-muted w-10", .attrs = &ic16_label_attrs };
    const ic16_row_children = [6]NodeDesc{ ic16_label, ic16_1, ic16_2, ic16_3, ic16_4, ic16_5 };
    const ic16_row = NodeDesc{ .tag = "Row", .classes = "gap-2 items-center", .children = &ic16_row_children };

    // Icon row 2: medium (24px)
    const ic24_1_attrs = [1]Attr{.{ .name = "icon_name", .value = .{ .literal = "chevron-down" } }};
    const ic24_2_attrs = [1]Attr{.{ .name = "icon_name", .value = .{ .literal = "check" } }};
    const ic24_3_attrs = [1]Attr{.{ .name = "icon_name", .value = .{ .literal = "cross" } }};
    const ic24_4_attrs = [1]Attr{.{ .name = "icon_name", .value = .{ .literal = "search" } }};
    const ic24_5_attrs = [1]Attr{.{ .name = "icon_name", .value = .{ .literal = "menu" } }};
    const ic24_1 = NodeDesc{ .tag = "Icon", .classes = "w-6 h-6", .attrs = &ic24_1_attrs };
    const ic24_2 = NodeDesc{ .tag = "Icon", .classes = "w-6 h-6", .attrs = &ic24_2_attrs };
    const ic24_3 = NodeDesc{ .tag = "Icon", .classes = "w-6 h-6", .attrs = &ic24_3_attrs };
    const ic24_4 = NodeDesc{ .tag = "Icon", .classes = "w-6 h-6", .attrs = &ic24_4_attrs };
    const ic24_5 = NodeDesc{ .tag = "Icon", .classes = "w-6 h-6", .attrs = &ic24_5_attrs };
    const ic24_label_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "24px" } }};
    const ic24_label = NodeDesc{ .tag = "Text", .classes = "text-sm text-muted w-10", .attrs = &ic24_label_attrs };
    const ic24_row_children = [6]NodeDesc{ ic24_label, ic24_1, ic24_2, ic24_3, ic24_4, ic24_5 };
    const ic24_row = NodeDesc{ .tag = "Row", .classes = "gap-2 items-center", .children = &ic24_row_children };

    // Icon row 3: large (48px)
    const ic48_1_attrs = [1]Attr{.{ .name = "icon_name", .value = .{ .literal = "chevron-down" } }};
    const ic48_2_attrs = [1]Attr{.{ .name = "icon_name", .value = .{ .literal = "check" } }};
    const ic48_3_attrs = [1]Attr{.{ .name = "icon_name", .value = .{ .literal = "cross" } }};
    const ic48_4_attrs = [1]Attr{.{ .name = "icon_name", .value = .{ .literal = "search" } }};
    const ic48_5_attrs = [1]Attr{.{ .name = "icon_name", .value = .{ .literal = "menu" } }};
    const ic48_1 = NodeDesc{ .tag = "Icon", .classes = "w-12 h-12", .attrs = &ic48_1_attrs };
    const ic48_2 = NodeDesc{ .tag = "Icon", .classes = "w-12 h-12", .attrs = &ic48_2_attrs };
    const ic48_3 = NodeDesc{ .tag = "Icon", .classes = "w-12 h-12", .attrs = &ic48_3_attrs };
    const ic48_4 = NodeDesc{ .tag = "Icon", .classes = "w-12 h-12", .attrs = &ic48_4_attrs };
    const ic48_5 = NodeDesc{ .tag = "Icon", .classes = "w-12 h-12", .attrs = &ic48_5_attrs };
    const ic48_label_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "48px" } }};
    const ic48_label = NodeDesc{ .tag = "Text", .classes = "text-sm text-muted w-10", .attrs = &ic48_label_attrs };
    const ic48_row_children = [6]NodeDesc{ ic48_label, ic48_1, ic48_2, ic48_3, ic48_4, ic48_5 };
    const ic48_row = NodeDesc{ .tag = "Row", .classes = "gap-2 items-center", .children = &ic48_row_children };

    const rd3_sect_children = [5]NodeDesc{ rd3_h, rd3_note, ic16_row, ic24_row, ic48_row };
    const rd3_sect = NodeDesc{ .tag = "Column", .classes = "gap-2", .children = &rd3_sect_children };

    // =======================================================================
    // RD5 — HiDPI display-scale awareness
    // =======================================================================
    const rd5_h_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "RD5 \xe2\x80\x94 HiDPI Display Scale" } }};
    const rd5_h = NodeDesc{ .tag = "Text", .classes = "font-bold", .attrs = &rd5_h_attrs };
    const rd5_note_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "All layout px values multiplied by dpi_scale from GLFW monitor content scale. On a standard display this is 1.0; on HiDPI (Retina/4K) it is typically 2.0. The dpi_scale is read once at startup from the primary monitor." } }};
    const rd5_note = NodeDesc{ .tag = "Text", .classes = "text-muted text-sm", .attrs = &rd5_note_attrs };

    const rd5_sect_children = [2]NodeDesc{ rd5_h, rd5_note };
    const rd5_sect = NodeDesc{ .tag = "Column", .classes = "gap-2", .children = &rd5_sect_children };

    // =======================================================================
    // RD2 — Subpixel glyph rendering (informational)
    // =======================================================================
    const rd2_h_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "RD2 \xe2\x80\x94 Subpixel Glyph Rendering" } }};
    const rd2_h = NodeDesc{ .tag = "Text", .classes = "font-bold", .attrs = &rd2_h_attrs };
    const rd2_note_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Subpixel text rendering uses RGB subpixel anti-aliasing for sharper glyphs at 12-14 px. Gated by AppOptions.subpixel_text (default: false). Requires -Dsubpixel-text build flag to activate. Without this flag, standard grayscale anti-aliasing is used." } }};
    const rd2_note = NodeDesc{ .tag = "Text", .classes = "text-muted text-sm", .attrs = &rd2_note_attrs };

    const rd2_sect_children = [2]NodeDesc{ rd2_h, rd2_note };
    const rd2_sect = NodeDesc{ .tag = "Column", .classes = "gap-2", .children = &rd2_sect_children };

    // =======================================================================
    // Assemble all sections in a ScrollView
    // =======================================================================
    const body_children = [11]NodeDesc{
        rd4_sect,
        NodeDesc{ .tag = "Separator" },
        rd0_sect,
        NodeDesc{ .tag = "Separator" },
        rd1_sect,
        NodeDesc{ .tag = "Separator" },
        rd3_sect,
        NodeDesc{ .tag = "Separator" },
        rd5_sect,
        NodeDesc{ .tag = "Separator" },
        rd2_sect,
    };
    const body = NodeDesc{ .tag = "Column", .classes = "gap-4", .children = &body_children };
    const scroll = NodeDesc{ .tag = "ScrollView", .classes = "flex-1", .children = &[1]NodeDesc{
        NodeDesc{ .tag = "Column", .classes = "p-2", .children = &[1]NodeDesc{body} },
    } };

    const content_children = [3]NodeDesc{ heading, sep, scroll };
    const content = NodeDesc{ .tag = "Column", .classes = "flex-1 gap-3 p-6", .children = &content_children };

    const root_children = [2]NodeDesc{ sidebar.buildSidebar(), content };
    const root = NodeDesc{ .tag = "Row", .classes = "w-full h-full", .children = &root_children };

    _ = try scene.instantiate(root, tokens);
    try shared.wireSidebarCallbacks(scene, c.global, tokens, 11); // 11 = M13 button (buttons 2-11 are sidebar)
}
