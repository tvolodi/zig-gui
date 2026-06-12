//! layout.zig — Layout engine showcase screen (Screen 7).

const mod07 = @import("../07/types.zig");
const mod05 = @import("../05/types.zig");
const mod06 = @import("../06/types.zig");

const Scene = mod07.Scene;
const Tokens = mod05.Tokens;
const NodeDesc = mod06.NodeDesc;
const Attr = mod06.Attr;

const shared = @import("../shared/types.zig");
const sidebar = @import("../shared/sidebar.zig");

pub const LayoutCtx = struct {
    global: *shared.GlobalState,
};

pub fn build(
    scene: *Scene,
    tokens: Tokens,
    app: *anyopaque,
    ctx: ?*anyopaque,
) anyerror!void {
    _ = app;
    const c: *LayoutCtx = @ptrCast(@alignCast(ctx.?));

    const h_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Layout Engine" } }};
    const heading = NodeDesc{ .tag = "Text", .classes = "text-xl", .attrs = &h_attrs };
    const sep = NodeDesc{ .tag = "Separator" };

    // -----------------------------------------------------------------------
    // 7a. Flex row + justify-between
    // -----------------------------------------------------------------------
    const flex_h_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Flex row \xe2\x80\x94 justify-between" } }};
    const flex_h = NodeDesc{ .tag = "Text", .classes = "font-bold", .attrs = &flex_h_attrs };

    const ba_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "A" } }};
    const bb_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "B" } }};
    const bc_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "C" } }};
    const bd_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "D" } }};
    const be_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "E" } }};
    const box_a = NodeDesc{ .tag = "Card", .classes = "p-4 bg-raised", .attrs = &ba_attrs };
    const box_b = NodeDesc{ .tag = "Card", .classes = "p-4 bg-raised", .attrs = &bb_attrs };
    const box_c = NodeDesc{ .tag = "Card", .classes = "p-4 bg-raised", .attrs = &bc_attrs };
    const box_d = NodeDesc{ .tag = "Card", .classes = "p-4 bg-raised", .attrs = &bd_attrs };
    const box_e = NodeDesc{ .tag = "Card", .classes = "p-4 bg-raised", .attrs = &be_attrs };
    const flex_row_children = [5]NodeDesc{ box_a, box_b, box_c, box_d, box_e };
    const flex_row = NodeDesc{ .tag = "Row", .classes = "justify-between", .children = &flex_row_children };
    const flex_sect_children = [2]NodeDesc{ flex_h, flex_row };
    const flex_sect = NodeDesc{ .tag = "Column", .classes = "gap-2", .children = &flex_sect_children };

    // -----------------------------------------------------------------------
    // 7b. Flex column with middle grow
    // -----------------------------------------------------------------------
    const grow_h_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "flex-1 \xe2\x80\x94 middle box fills remaining height" } }};
    const grow_h = NodeDesc{ .tag = "Text", .classes = "font-bold", .attrs = &grow_h_attrs };
    const gi1_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Fixed" } }};
    const gi2_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "flex-1 (grows)" } }};
    const gi3_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Fixed" } }};
    const gi1 = NodeDesc{ .tag = "Card", .classes = "p-2 bg-raised",        .attrs = &gi1_attrs };
    const gi2 = NodeDesc{ .tag = "Card", .classes = "flex-1 p-2 bg-raised", .attrs = &gi2_attrs };
    const gi3 = NodeDesc{ .tag = "Card", .classes = "p-2 bg-raised",        .attrs = &gi3_attrs };
    const grow_col_children = [3]NodeDesc{ gi1, gi2, gi3 };
    const grow_col = NodeDesc{ .tag = "Column", .classes = "gap-2 h-32", .children = &grow_col_children };
    const grow_sect_children = [2]NodeDesc{ grow_h, grow_col };
    const grow_sect = NodeDesc{ .tag = "Column", .classes = "gap-2", .children = &grow_sect_children };

    // -----------------------------------------------------------------------
    // 7c. Grid — 4 columns, col-span-2
    // -----------------------------------------------------------------------
    const grid_h_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Grid \xe2\x80\x94 4 columns, item 5 spans 2" } }};
    const grid_h = NodeDesc{ .tag = "Text", .classes = "font-bold", .attrs = &grid_h_attrs };

    const g1_a  = [1]Attr{.{ .name = "text", .value = .{ .literal = "1" } }};
    const g2_a  = [1]Attr{.{ .name = "text", .value = .{ .literal = "2" } }};
    const g3_a  = [1]Attr{.{ .name = "text", .value = .{ .literal = "3" } }};
    const g4_a  = [1]Attr{.{ .name = "text", .value = .{ .literal = "4" } }};
    const g5_a  = [1]Attr{.{ .name = "text", .value = .{ .literal = "5 (span 2)" } }};
    const g6_a  = [1]Attr{.{ .name = "text", .value = .{ .literal = "6" } }};
    const g7_a  = [1]Attr{.{ .name = "text", .value = .{ .literal = "7" } }};
    const g8_a  = [1]Attr{.{ .name = "text", .value = .{ .literal = "8" } }};
    const g9_a  = [1]Attr{.{ .name = "text", .value = .{ .literal = "9" } }};
    const g10_a = [1]Attr{.{ .name = "text", .value = .{ .literal = "10" } }};
    const g11_a = [1]Attr{.{ .name = "text", .value = .{ .literal = "11" } }};
    const g12_a = [1]Attr{.{ .name = "text", .value = .{ .literal = "12" } }};

    const g1  = NodeDesc{ .tag = "Card", .classes = "p-2 bg-raised",              .attrs = &g1_a  };
    const g2  = NodeDesc{ .tag = "Card", .classes = "p-2 bg-raised",              .attrs = &g2_a  };
    const g3  = NodeDesc{ .tag = "Card", .classes = "p-2 bg-raised",              .attrs = &g3_a  };
    const g4  = NodeDesc{ .tag = "Card", .classes = "p-2 bg-raised",              .attrs = &g4_a  };
    const g5  = NodeDesc{ .tag = "Card", .classes = "p-2 bg-raised col-span-2",   .attrs = &g5_a  };
    const g6  = NodeDesc{ .tag = "Card", .classes = "p-2 bg-raised",              .attrs = &g6_a  };
    const g7  = NodeDesc{ .tag = "Card", .classes = "p-2 bg-raised",              .attrs = &g7_a  };
    const g8  = NodeDesc{ .tag = "Card", .classes = "p-2 bg-raised",              .attrs = &g8_a  };
    const g9  = NodeDesc{ .tag = "Card", .classes = "p-2 bg-raised",              .attrs = &g9_a  };
    const g10 = NodeDesc{ .tag = "Card", .classes = "p-2 bg-raised",              .attrs = &g10_a };
    const g11 = NodeDesc{ .tag = "Card", .classes = "p-2 bg-raised",              .attrs = &g11_a };
    const g12 = NodeDesc{ .tag = "Card", .classes = "p-2 bg-raised",              .attrs = &g12_a };

    const grid_children = [12]NodeDesc{ g1, g2, g3, g4, g5, g6, g7, g8, g9, g10, g11, g12 };
    const grid = NodeDesc{ .tag = "Row", .classes = "grid-cols-4 gap-2", .children = &grid_children };
    const grid_sect_children = [2]NodeDesc{ grid_h, grid };
    const grid_sect = NodeDesc{ .tag = "Column", .classes = "gap-2", .children = &grid_sect_children };

    // -----------------------------------------------------------------------
    // 7d. Opacity
    // -----------------------------------------------------------------------
    const op_h_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Opacity" } }};
    const op_h = NodeDesc{ .tag = "Text", .classes = "font-bold", .attrs = &op_h_attrs };

    const op100_a = [1]Attr{.{ .name = "text", .value = .{ .literal = "opacity-100" } }};
    const op75_a  = [1]Attr{.{ .name = "text", .value = .{ .literal = "opacity-75" } }};
    const op50_a  = [1]Attr{.{ .name = "text", .value = .{ .literal = "opacity-50" } }};
    const op25_a  = [1]Attr{.{ .name = "text", .value = .{ .literal = "opacity-25" } }};
    const op0_a   = [1]Attr{.{ .name = "text", .value = .{ .literal = "opacity-0" } }};
    const op100 = NodeDesc{ .tag = "Card", .classes = "p-3 flex-1 opacity-100", .attrs = &op100_a };
    const op75  = NodeDesc{ .tag = "Card", .classes = "p-3 flex-1 opacity-75",  .attrs = &op75_a  };
    const op50  = NodeDesc{ .tag = "Card", .classes = "p-3 flex-1 opacity-50",  .attrs = &op50_a  };
    const op25  = NodeDesc{ .tag = "Card", .classes = "p-3 flex-1 opacity-25",  .attrs = &op25_a  };
    const op0   = NodeDesc{ .tag = "Card", .classes = "p-3 flex-1 opacity-0",   .attrs = &op0_a   };
    const op_row_children = [5]NodeDesc{ op100, op75, op50, op25, op0 };
    const op_row = NodeDesc{ .tag = "Row", .classes = "gap-2", .children = &op_row_children };
    const op_sect_children = [2]NodeDesc{ op_h, op_row };
    const op_sect = NodeDesc{ .tag = "Column", .classes = "gap-2", .children = &op_sect_children };

    // -----------------------------------------------------------------------
    // 7e. Box shadow
    // -----------------------------------------------------------------------
    const sh_h_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Box shadow" } }};
    const sh_h = NodeDesc{ .tag = "Text", .classes = "font-bold", .attrs = &sh_h_attrs };

    const sh_sm_a  = [1]Attr{.{ .name = "text", .value = .{ .literal = "shadow-sm" } }};
    const sh_a     = [1]Attr{.{ .name = "text", .value = .{ .literal = "shadow" } }};
    const sh_md_a  = [1]Attr{.{ .name = "text", .value = .{ .literal = "shadow-md" } }};
    const sh_lg_a  = [1]Attr{.{ .name = "text", .value = .{ .literal = "shadow-lg" } }};
    const sh_sm = NodeDesc{ .tag = "Card", .classes = "p-4 flex-1 shadow-sm", .attrs = &sh_sm_a };
    const sh    = NodeDesc{ .tag = "Card", .classes = "p-4 flex-1 shadow",    .attrs = &sh_a    };
    const sh_md = NodeDesc{ .tag = "Card", .classes = "p-4 flex-1 shadow-md", .attrs = &sh_md_a };
    const sh_lg = NodeDesc{ .tag = "Card", .classes = "p-4 flex-1 shadow-lg", .attrs = &sh_lg_a };
    const sh_row_children = [4]NodeDesc{ sh_sm, sh, sh_md, sh_lg };
    const sh_row = NodeDesc{ .tag = "Row", .classes = "gap-4", .children = &sh_row_children };
    const sh_sect_children = [2]NodeDesc{ sh_h, sh_row };
    const sh_sect = NodeDesc{ .tag = "Column", .classes = "gap-2", .children = &sh_sect_children };

    // -----------------------------------------------------------------------
    // Assemble in a ScrollView
    // -----------------------------------------------------------------------
    const body_children = [9]NodeDesc{
        flex_sect,
        NodeDesc{ .tag = "Separator" },
        grow_sect,
        NodeDesc{ .tag = "Separator" },
        grid_sect,
        NodeDesc{ .tag = "Separator" },
        op_sect,
        NodeDesc{ .tag = "Separator" },
        sh_sect,
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
    try shared.wireSidebarCallbacks(scene, c.global, tokens, 8); // 8 = Layout button
}
