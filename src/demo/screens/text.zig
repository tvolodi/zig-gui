//! text.zig — Text rendering showcase screen (Screen 2).

const mod07 = @import("../07/types.zig");
const mod05 = @import("../05/types.zig");
const mod06 = @import("../06/types.zig");

const Scene = mod07.Scene;
const Tokens = mod05.Tokens;
const NodeDesc = mod06.NodeDesc;
const Attr = mod06.Attr;

const shared = @import("../shared/types.zig");
const sidebar = @import("../shared/sidebar.zig");

pub const TextCtx = struct {
    global: *shared.GlobalState,
};

pub fn build(
    scene: *Scene,
    tokens: Tokens,
    app: *anyopaque,
    ctx: ?*anyopaque,
) anyerror!void {
    _ = app;
    const c: *TextCtx = @ptrCast(@alignCast(ctx.?));

    // --- Heading ---
    const h_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Text Rendering" } }};
    const heading = NodeDesc{ .tag = "Text", .classes = "text-xl", .attrs = &h_attrs };
    const sep = NodeDesc{ .tag = "Separator" };

    // -----------------------------------------------------------------------
    // 2a. Type scale
    // -----------------------------------------------------------------------
    const scale_lbl_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Type scale" } }};
    const scale_lbl = NodeDesc{ .tag = "Text", .classes = "font-bold", .attrs = &scale_lbl_attrs };

    const xs_attrs   = [1]Attr{.{ .name = "text", .value = .{ .literal = "text-xs  — Extra small — 10 px" } }};
    const sm_attrs   = [1]Attr{.{ .name = "text", .value = .{ .literal = "text-sm  — Small — 12 px" } }};
    const base_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "text-base — Base — 14 px" } }};
    const lg_attrs   = [1]Attr{.{ .name = "text", .value = .{ .literal = "text-lg  — Large — 18 px" } }};
    const xl_attrs   = [1]Attr{.{ .name = "text", .value = .{ .literal = "text-xl  — Extra large — 24 px" } }};

    const xs_node   = NodeDesc{ .tag = "Text", .classes = "text-xs",   .attrs = &xs_attrs };
    const sm_node   = NodeDesc{ .tag = "Text", .classes = "text-sm",   .attrs = &sm_attrs };
    const base_node = NodeDesc{ .tag = "Text",                         .attrs = &base_attrs };
    const lg_node   = NodeDesc{ .tag = "Text", .classes = "text-lg",   .attrs = &lg_attrs };
    const xl_node   = NodeDesc{ .tag = "Text", .classes = "text-xl",   .attrs = &xl_attrs };

    const scale_items = [5]NodeDesc{ xs_node, sm_node, base_node, lg_node, xl_node };
    const scale_col   = NodeDesc{ .tag = "Column", .classes = "gap-2", .children = &scale_items };
    const scale_sect_children = [2]NodeDesc{ scale_lbl, scale_col };
    const scale_sect = NodeDesc{ .tag = "Column", .classes = "gap-2", .children = &scale_sect_children };

    // -----------------------------------------------------------------------
    // 2b. Font variants
    // -----------------------------------------------------------------------
    const variants_lbl_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Font variants" } }};
    const variants_lbl = NodeDesc{ .tag = "Text", .classes = "font-bold", .attrs = &variants_lbl_attrs };

    const sentence = "The quick brown fox jumps over the lazy dog";
    const reg_attrs  = [1]Attr{.{ .name = "text", .value = .{ .literal = sentence } }};
    const bold_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = sentence } }};
    const ital_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = sentence } }};

    const reg_node  = NodeDesc{ .tag = "Text",                              .attrs = &reg_attrs };
    const bold_node = NodeDesc{ .tag = "Text", .classes = "font-bold",      .attrs = &bold_attrs };
    const ital_node = NodeDesc{ .tag = "Text", .classes = "font-italic",    .attrs = &ital_attrs };

    const variant_items = [3]NodeDesc{ reg_node, bold_node, ital_node };
    const variant_col   = NodeDesc{ .tag = "Column", .classes = "gap-2", .children = &variant_items };
    const variants_sect_children = [2]NodeDesc{ variants_lbl, variant_col };
    const variants_sect = NodeDesc{ .tag = "Column", .classes = "gap-2", .children = &variants_sect_children };

    // -----------------------------------------------------------------------
    // 2c. Text colors
    // -----------------------------------------------------------------------
    const colors_lbl_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Text colors" } }};
    const colors_lbl = NodeDesc{ .tag = "Text", .classes = "font-bold", .attrs = &colors_lbl_attrs };

    const c_body_attrs    = [1]Attr{.{ .name = "text", .value = .{ .literal = "text-body — regular body text" } }};
    const c_muted_attrs   = [1]Attr{.{ .name = "text", .value = .{ .literal = "text-muted — secondary / helper text" } }};
    const c_accent_attrs  = [1]Attr{.{ .name = "text", .value = .{ .literal = "text-accent — accent / brand color" } }};

    const c_body   = NodeDesc{ .tag = "Text", .classes = "text-body",   .attrs = &c_body_attrs };
    const c_muted  = NodeDesc{ .tag = "Text", .classes = "text-muted",  .attrs = &c_muted_attrs };
    const c_accent = NodeDesc{ .tag = "Text", .classes = "text-accent", .attrs = &c_accent_attrs };

    const color_items = [3]NodeDesc{ c_body, c_muted, c_accent };
    const color_col   = NodeDesc{ .tag = "Column", .classes = "gap-2", .children = &color_items };
    const colors_sect_children = [2]NodeDesc{ colors_lbl, color_col };
    const colors_sect = NodeDesc{ .tag = "Column", .classes = "gap-2", .children = &colors_sect_children };

    // -----------------------------------------------------------------------
    // 2d. Text truncation
    // -----------------------------------------------------------------------
    const trunc_lbl_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Text truncation (w-64 container)" } }};
    const trunc_lbl = NodeDesc{ .tag = "Text", .classes = "font-bold", .attrs = &trunc_lbl_attrs };

    const long_text = "This is a very long sentence that should overflow its container and be truncated with an ellipsis at the edge.";
    const no_trunc_attrs   = [1]Attr{.{ .name = "text", .value = .{ .literal = long_text } }};
    const with_trunc_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = long_text } }};

    const no_trunc   = NodeDesc{ .tag = "Text", .classes = "w-64",          .attrs = &no_trunc_attrs };
    const with_trunc = NodeDesc{ .tag = "Text", .classes = "w-64 truncate", .attrs = &with_trunc_attrs };

    const trunc_items = [2]NodeDesc{ no_trunc, with_trunc };
    const trunc_col   = NodeDesc{ .tag = "Column", .classes = "gap-2", .children = &trunc_items };
    const trunc_sect_children = [2]NodeDesc{ trunc_lbl, trunc_col };
    const trunc_sect = NodeDesc{ .tag = "Column", .classes = "gap-2", .children = &trunc_sect_children };

    // -----------------------------------------------------------------------
    // 2e. Text selection
    // -----------------------------------------------------------------------
    const sel_lbl_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Text selection" } }};
    const sel_lbl = NodeDesc{ .tag = "Text", .classes = "font-bold", .attrs = &sel_lbl_attrs };

    const sel_para_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Click and drag to select text in this paragraph. You can also use keyboard shortcuts: Shift+Arrow to extend, Ctrl+A to select all, Ctrl+C to copy." } }};
    const sel_para = NodeDesc{ .tag = "Text", .attrs = &sel_para_attrs };

    const sel_sect_children = [2]NodeDesc{ sel_lbl, sel_para };
    const sel_sect = NodeDesc{ .tag = "Column", .classes = "gap-2", .children = &sel_sect_children };

    // -----------------------------------------------------------------------
    // 2f. Font fallback
    // -----------------------------------------------------------------------
    const fallback_lbl_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Font fallback (mixed scripts)" } }};
    const fallback_lbl = NodeDesc{ .tag = "Text", .classes = "font-bold", .attrs = &fallback_lbl_attrs };

    const fallback_txt_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Hello \xF0\x9F\x8C\x8D World \xF0\x9F\x8E\x89 \xE2\x80\x94 fallback glyphs via stb_truetype" } }};
    const fallback_txt = NodeDesc{ .tag = "Text", .attrs = &fallback_txt_attrs };

    const fallback_sect_children = [2]NodeDesc{ fallback_lbl, fallback_txt };
    const fallback_sect = NodeDesc{ .tag = "Column", .classes = "gap-2", .children = &fallback_sect_children };

    // -----------------------------------------------------------------------
    // Assemble in a ScrollView
    // -----------------------------------------------------------------------
    const inner_children = [7]NodeDesc{
        scale_sect,
        NodeDesc{ .tag = "Separator" },
        variants_sect,
        NodeDesc{ .tag = "Separator" },
        colors_sect,
        NodeDesc{ .tag = "Separator" },
        trunc_sect,
    };
    const inner_col = NodeDesc{ .tag = "Column", .classes = "gap-5", .children = &inner_children };

    const inner2_children = [4]NodeDesc{
        inner_col,
        NodeDesc{ .tag = "Separator" },
        sel_sect,
        fallback_sect,
    };
    const inner2_col = NodeDesc{ .tag = "Column", .classes = "gap-5", .children = &inner2_children };

    const scroll = NodeDesc{ .tag = "ScrollView", .classes = "flex-1", .children = &[1]NodeDesc{
        NodeDesc{ .tag = "Column", .classes = "gap-5 p-2", .children = &[1]NodeDesc{inner2_col} },
    } };

    const content_children = [3]NodeDesc{ heading, sep, scroll };
    const content = NodeDesc{ .tag = "Column", .classes = "flex-1 gap-3 p-6", .children = &content_children };

    const root_children = [2]NodeDesc{ sidebar.buildSidebar(), content };
    const root = NodeDesc{ .tag = "Row", .classes = "w-full h-full", .children = &root_children };

    _ = try scene.instantiate(root, tokens);
    try shared.wireSidebarCallbacks(scene, c.global, tokens, 3); // 3 = Text button
}
