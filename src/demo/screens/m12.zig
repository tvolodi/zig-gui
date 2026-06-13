//! m12.zig — M12 positioning features showcase screen (Screen 9).
//!
//! Demonstrates:
//!   RC0 — absolute positioning (badge overlapping card corner)
//!   RC1 — sticky positioning (sticky header in scroll view)
//!   RC2 — flex-wrap (tag cloud wrapping onto multiple rows)
//!   RC3 — aspect-ratio (square and video placeholders)
//!   RC4 — z-index (two overlapping siblings, higher z on top)

const mod07 = @import("../07/types.zig");
const mod05 = @import("../05/types.zig");
const mod06 = @import("../06/types.zig");

const Scene = mod07.Scene;
const Tokens = mod05.Tokens;
const NodeDesc = mod06.NodeDesc;
const Attr = mod06.Attr;

const shared = @import("../shared/types.zig");
const sidebar = @import("../shared/sidebar.zig");

pub const M12Ctx = struct {
    global: *shared.GlobalState,
};

pub fn build(
    scene: *Scene,
    tokens: Tokens,
    app: *anyopaque,
    ctx: ?*anyopaque,
) anyerror!void {
    _ = app;
    const c: *M12Ctx = @ptrCast(@alignCast(ctx.?));

    const h_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "M12 — Positioning & Layout" } }};
    const heading = NodeDesc{ .tag = "Text", .classes = "text-xl", .attrs = &h_attrs };
    const sep = NodeDesc{ .tag = "Separator" };

    // -----------------------------------------------------------------------
    // RC0 — Absolute positioning: badge in card corner
    // -----------------------------------------------------------------------
    const rc0_h_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "RC0 — Absolute Positioning" } }};
    const rc0_h = NodeDesc{ .tag = "Text", .classes = "font-bold", .attrs = &rc0_h_attrs };

    const card_body_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Card content" } }};
    const card_body = NodeDesc{ .tag = "Text", .classes = "text-muted", .attrs = &card_body_attrs };

    // Badge at top-right corner: absolute top-0 right-0
    const badge_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "TOP-RIGHT" } }};
    const badge_tr = NodeDesc{ .tag = "Card", .classes = "absolute top-0 right-0 p-1 bg-raised", .attrs = &badge_attrs };

    // Badge at bottom-left corner: absolute bottom-0 left-0
    const badge_bl_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "BOTTOM-LEFT" } }};
    const badge_bl = NodeDesc{ .tag = "Card", .classes = "absolute bottom-0 left-0 p-1 bg-raised", .attrs = &badge_bl_attrs };

    const abs_card_children = [3]NodeDesc{ card_body, badge_tr, badge_bl };
    // Parent card with fixed height so absolute children are visible
    const abs_card = NodeDesc{ .tag = "Card", .classes = "p-4 h-24 w-48 bg-raised", .children = &abs_card_children };

    const rc0_sect_children = [2]NodeDesc{ rc0_h, abs_card };
    const rc0_sect = NodeDesc{ .tag = "Column", .classes = "gap-2", .children = &rc0_sect_children };

    // -----------------------------------------------------------------------
    // RC1 — Sticky positioning: sticky header inside a fixed-height scroll area
    // -----------------------------------------------------------------------
    const rc1_h_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "RC1 — Sticky Positioning" } }};
    const rc1_h = NodeDesc{ .tag = "Text", .classes = "font-bold", .attrs = &rc1_h_attrs };

    const sticky_hdr_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Sticky Header" } }};
    const sticky_hdr = NodeDesc{ .tag = "Card", .classes = "sticky top-0 p-2 bg-raised font-bold", .attrs = &sticky_hdr_attrs };

    // Scroll content rows
    const sr1_a = [1]Attr{.{ .name = "text", .value = .{ .literal = "Row 1" } }};
    const sr2_a = [1]Attr{.{ .name = "text", .value = .{ .literal = "Row 2" } }};
    const sr3_a = [1]Attr{.{ .name = "text", .value = .{ .literal = "Row 3" } }};
    const sr4_a = [1]Attr{.{ .name = "text", .value = .{ .literal = "Row 4" } }};
    const sr5_a = [1]Attr{.{ .name = "text", .value = .{ .literal = "Row 5" } }};
    const sr1 = NodeDesc{ .tag = "Text", .classes = "p-2", .attrs = &sr1_a };
    const sr2 = NodeDesc{ .tag = "Text", .classes = "p-2", .attrs = &sr2_a };
    const sr3 = NodeDesc{ .tag = "Text", .classes = "p-2", .attrs = &sr3_a };
    const sr4 = NodeDesc{ .tag = "Text", .classes = "p-2", .attrs = &sr4_a };
    const sr5 = NodeDesc{ .tag = "Text", .classes = "p-2", .attrs = &sr5_a };

    const sticky_col_children = [6]NodeDesc{ sticky_hdr, sr1, sr2, sr3, sr4, sr5 };
    const sticky_col = NodeDesc{ .tag = "Column", .classes = "gap-1", .children = &sticky_col_children };
    // Fixed-height scroll container so sticky behavior is visible
    const sticky_scroll = NodeDesc{ .tag = "ScrollView", .classes = "h-32", .children = &[1]NodeDesc{sticky_col} };

    const rc1_sect_children = [2]NodeDesc{ rc1_h, sticky_scroll };
    const rc1_sect = NodeDesc{ .tag = "Column", .classes = "gap-2", .children = &rc1_sect_children };

    // -----------------------------------------------------------------------
    // RC2 — Flex-wrap: tag cloud with 10 chips
    // -----------------------------------------------------------------------
    const rc2_h_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "RC2 — Flex Wrap (tag cloud)" } }};
    const rc2_h = NodeDesc{ .tag = "Text", .classes = "font-bold", .attrs = &rc2_h_attrs };

    const t1_a  = [1]Attr{.{ .name = "text", .value = .{ .literal = "Zig" } }};
    const t2_a  = [1]Attr{.{ .name = "text", .value = .{ .literal = "Vulkan" } }};
    const t3_a  = [1]Attr{.{ .name = "text", .value = .{ .literal = "GPU" } }};
    const t4_a  = [1]Attr{.{ .name = "text", .value = .{ .literal = "Layout" } }};
    const t5_a  = [1]Attr{.{ .name = "text", .value = .{ .literal = "Flex-Wrap" } }};
    const t6_a  = [1]Attr{.{ .name = "text", .value = .{ .literal = "Absolute" } }};
    const t7_a  = [1]Attr{.{ .name = "text", .value = .{ .literal = "Sticky" } }};
    const t8_a  = [1]Attr{.{ .name = "text", .value = .{ .literal = "Z-Index" } }};
    const t9_a  = [1]Attr{.{ .name = "text", .value = .{ .literal = "Aspect" } }};
    const t10_a = [1]Attr{.{ .name = "text", .value = .{ .literal = "Demo" } }};

    // w-32=128px per tag, h-8=32px, shrink-0. Full content width ~720px → 5 fit per row (5×128+4×8=672≤720; 6th=808>720).
    // Result: 2 rows of 5 tags each — clearly showing flex-wrap working.
    const t1  = NodeDesc{ .tag = "Card", .classes = "p-2 w-32 h-8 shrink-0 bg-raised", .attrs = &t1_a  };
    const t2  = NodeDesc{ .tag = "Card", .classes = "p-2 w-32 h-8 shrink-0 bg-raised", .attrs = &t2_a  };
    const t3  = NodeDesc{ .tag = "Card", .classes = "p-2 w-32 h-8 shrink-0 bg-raised", .attrs = &t3_a  };
    const t4  = NodeDesc{ .tag = "Card", .classes = "p-2 w-32 h-8 shrink-0 bg-raised", .attrs = &t4_a  };
    const t5  = NodeDesc{ .tag = "Card", .classes = "p-2 w-32 h-8 shrink-0 bg-raised", .attrs = &t5_a  };
    const t6  = NodeDesc{ .tag = "Card", .classes = "p-2 w-32 h-8 shrink-0 bg-raised", .attrs = &t6_a  };
    const t7  = NodeDesc{ .tag = "Card", .classes = "p-2 w-32 h-8 shrink-0 bg-raised", .attrs = &t7_a  };
    const t8  = NodeDesc{ .tag = "Card", .classes = "p-2 w-32 h-8 shrink-0 bg-raised", .attrs = &t8_a  };
    const t9  = NodeDesc{ .tag = "Card", .classes = "p-2 w-32 h-8 shrink-0 bg-raised", .attrs = &t9_a  };
    const t10 = NodeDesc{ .tag = "Card", .classes = "p-2 w-32 h-8 shrink-0 bg-raised", .attrs = &t10_a };

    const tags_children = [10]NodeDesc{ t1, t2, t3, t4, t5, t6, t7, t8, t9, t10 };
    // flex-wrap: the content column is ~720px wide. 5 tags × 128px + 4 × 8px gap = 672px fits;
    // 6 tags × 128px + 5 × 8px gap = 808px > 720px → 6th tag wraps to row 2.
    const tags_row = NodeDesc{ .tag = "Row", .classes = "flex-wrap gap-2", .children = &tags_children };

    const rc2_sect_children = [2]NodeDesc{ rc2_h, tags_row };
    const rc2_sect = NodeDesc{ .tag = "Column", .classes = "gap-2", .children = &rc2_sect_children };

    // -----------------------------------------------------------------------
    // RC3 — Aspect ratio: square (100x100) and video (160x90) placeholders
    // -----------------------------------------------------------------------
    const rc3_h_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "RC3 — Aspect Ratio" } }};
    const rc3_h = NodeDesc{ .tag = "Text", .classes = "font-bold", .attrs = &rc3_h_attrs };

    const sq_lbl_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "aspect-square (100x100)" } }};
    const sq_lbl = NodeDesc{ .tag = "Text", .classes = "text-sm text-muted", .attrs = &sq_lbl_attrs };
    const sq_box_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "1:1" } }};
    const sq_box = NodeDesc{ .tag = "Card", .classes = "w-24 aspect-square bg-raised p-2", .attrs = &sq_box_attrs };
    const sq_col_children = [2]NodeDesc{ sq_lbl, sq_box };
    const sq_col = NodeDesc{ .tag = "Column", .classes = "gap-1", .children = &sq_col_children };

    const vid_lbl_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "aspect-video (160x90)" } }};
    const vid_lbl = NodeDesc{ .tag = "Text", .classes = "text-sm text-muted", .attrs = &vid_lbl_attrs };
    const vid_box_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "16:9" } }};
    const vid_box = NodeDesc{ .tag = "Card", .classes = "w-40 aspect-video bg-raised p-2", .attrs = &vid_box_attrs };
    const vid_col_children = [2]NodeDesc{ vid_lbl, vid_box };
    const vid_col = NodeDesc{ .tag = "Column", .classes = "gap-1", .children = &vid_col_children };

    const aspect_row_children = [2]NodeDesc{ sq_col, vid_col };
    const aspect_row = NodeDesc{ .tag = "Row", .classes = "gap-6 items-start", .children = &aspect_row_children };

    const rc3_sect_children = [2]NodeDesc{ rc3_h, aspect_row };
    const rc3_sect = NodeDesc{ .tag = "Column", .classes = "gap-2", .children = &rc3_sect_children };

    // -----------------------------------------------------------------------
    // RC4 — Z-index: two overlapping siblings; z-10 draws on top of z-0
    // -----------------------------------------------------------------------
    const rc4_h_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "RC4 — Z-Index (z-10 overlaps z-0)" } }};
    const rc4_h = NodeDesc{ .tag = "Text", .classes = "font-bold", .attrs = &rc4_h_attrs };

    // z-0 sibling (drawn first, behind)
    const z0_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "z-0 (behind)" } }};
    const z0_card = NodeDesc{ .tag = "Card", .classes = "z-0 p-4 w-32 bg-raised", .attrs = &z0_attrs };

    // z-10 sibling (drawn on top)
    const z10_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "z-10 (on top)" } }};
    const z10_card = NodeDesc{ .tag = "Card", .classes = "z-10 p-4 w-32 bg-raised", .attrs = &z10_attrs };

    const z_row_children = [2]NodeDesc{ z0_card, z10_card };
    const z_row = NodeDesc{ .tag = "Row", .classes = "gap-2", .children = &z_row_children };

    const rc4_sect_children = [2]NodeDesc{ rc4_h, z_row };
    const rc4_sect = NodeDesc{ .tag = "Column", .classes = "gap-2", .children = &rc4_sect_children };

    // -----------------------------------------------------------------------
    // Assemble all sections in a ScrollView
    // -----------------------------------------------------------------------
    const body_children = [9]NodeDesc{
        rc0_sect,
        NodeDesc{ .tag = "Separator" },
        rc1_sect,
        NodeDesc{ .tag = "Separator" },
        rc2_sect,
        NodeDesc{ .tag = "Separator" },
        rc3_sect,
        NodeDesc{ .tag = "Separator" },
        rc4_sect,
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
    try shared.wireSidebarCallbacks(scene, c.global, tokens, 10); // 10 = M12 button (buttons 2-10 are sidebar)
}
