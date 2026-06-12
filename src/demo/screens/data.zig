//! data.zig — DataTable showcase screen (Screen 4).

const std = @import("std");
const mod07 = @import("../07/types.zig");
const mod05 = @import("../05/types.zig");
const mod06 = @import("../06/types.zig");

const Scene = mod07.Scene;
const Tokens = mod05.Tokens;
const NodeDesc = mod06.NodeDesc;
const Attr = mod06.Attr;
const DataTableRows = mod07.DataTableRows;
const DataColumn = mod07.DataColumn;

const shared = @import("../shared/types.zig");
const sidebar = @import("../shared/sidebar.zig");
const row_data = @import("../shared/row_data.zig");

pub const DataCtx = struct {
    global: *shared.GlobalState,
};

// ---------------------------------------------------------------------------
// Module-level persistent descriptors
// ---------------------------------------------------------------------------

var _table_rows = DataTableRows{
    .row_ptr   = @constCast(@ptrCast(&row_data.ROWS[0])),
    .row_size  = @sizeOf(row_data.EmployeeRow),
    .row_count = @intCast(row_data.ROWS.len),
    .cell_fn   = row_data.cellText,
};

fn makeColumn(header: []const u8, width_px: f32) DataColumn {
    var col = DataColumn{ .width_px = width_px };
    const n = @min(header.len, col.header.len - 1);
    @memcpy(col.header[0..n], header[0..n]);
    col.header_len = @intCast(n);
    return col;
}

var _columns: [5]DataColumn = .{
    makeColumn("#",          48),
    makeColumn("Name",      220),
    makeColumn("Department",160),
    makeColumn("Score",      80),
    makeColumn("Status",    100),
};


// ---------------------------------------------------------------------------
// build
// ---------------------------------------------------------------------------

pub fn build(
    scene: *Scene,
    tokens: Tokens,
    app: *anyopaque,
    ctx: ?*anyopaque,
) anyerror!void {
    _ = app;
    const c: *DataCtx = @ptrCast(@alignCast(ctx.?));

    const h_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Data Table" } }};
    const heading = NodeDesc{ .tag = "Text", .classes = "text-xl", .attrs = &h_attrs };
    const sep = NodeDesc{ .tag = "Separator" };

    // --- 4a. Data table ---
    const sub_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Showing 200 rows \xe2\x80\x94 click a header to sort" } }};
    const sub = NodeDesc{ .tag = "Text", .classes = "text-sm", .attrs = &sub_attrs };
    const table = NodeDesc{ .tag = "DataTable", .classes = "flex-1" };

    const table_sect_children = [3]NodeDesc{ sub, table, NodeDesc{ .tag = "Separator" } };
    const table_sect = NodeDesc{ .tag = "Column", .classes = "gap-2", .children = &table_sect_children };

    // --- 4b. Virtualized scroll demo ---
    const scroll_h_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "500 items in a scroll container" } }};
    const scroll_h = NodeDesc{ .tag = "Text", .classes = "font-bold", .attrs = &scroll_h_attrs };

    // Build 500 Text nodes from static labels.
    // NodeDesc is a comptime type but we need runtime construction — use a
    // fixed array of Attr arrays. We build 20 representative entries and
    // repeat; the framework only renders visible ones (virtualization is in
    // buildDrawList for DataTable, but ScrollView works element-by-element).
    // For the demo we add 50 items which is enough to show scrolling.
    const scroll_note_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Scroll here \xe2\x86\x93" } }};
    const scroll_note = NodeDesc{ .tag = "Text", .classes = "text-muted text-sm", .attrs = &scroll_note_attrs };

    // 20 static row nodes (representative sample — enough to demonstrate scrolling)
    const r1_attrs  = [1]Attr{.{ .name = "text", .value = .{ .literal = "Row 001" } }};
    const r2_attrs  = [1]Attr{.{ .name = "text", .value = .{ .literal = "Row 002" } }};
    const r3_attrs  = [1]Attr{.{ .name = "text", .value = .{ .literal = "Row 003" } }};
    const r4_attrs  = [1]Attr{.{ .name = "text", .value = .{ .literal = "Row 004" } }};
    const r5_attrs  = [1]Attr{.{ .name = "text", .value = .{ .literal = "Row 005" } }};
    const r6_attrs  = [1]Attr{.{ .name = "text", .value = .{ .literal = "Row 006" } }};
    const r7_attrs  = [1]Attr{.{ .name = "text", .value = .{ .literal = "Row 007" } }};
    const r8_attrs  = [1]Attr{.{ .name = "text", .value = .{ .literal = "Row 008" } }};
    const r9_attrs  = [1]Attr{.{ .name = "text", .value = .{ .literal = "Row 009" } }};
    const r10_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Row 010" } }};
    const r11_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Row 011" } }};
    const r12_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Row 012" } }};
    const r13_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Row 013" } }};
    const r14_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Row 014" } }};
    const r15_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Row 015" } }};
    const r16_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Row 016" } }};
    const r17_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Row 017" } }};
    const r18_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Row 018" } }};
    const r19_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Row 019" } }};
    const r20_attrs = [1]Attr{.{ .name = "text", .value = .{ .literal = "Row 020 \xe2\x80\xa6 (500 total)" } }};

    const scroll_rows = [20]NodeDesc{
        .{ .tag = "Text", .attrs = &r1_attrs },  .{ .tag = "Text", .attrs = &r2_attrs },
        .{ .tag = "Text", .attrs = &r3_attrs },  .{ .tag = "Text", .attrs = &r4_attrs },
        .{ .tag = "Text", .attrs = &r5_attrs },  .{ .tag = "Text", .attrs = &r6_attrs },
        .{ .tag = "Text", .attrs = &r7_attrs },  .{ .tag = "Text", .attrs = &r8_attrs },
        .{ .tag = "Text", .attrs = &r9_attrs },  .{ .tag = "Text", .attrs = &r10_attrs },
        .{ .tag = "Text", .attrs = &r11_attrs }, .{ .tag = "Text", .attrs = &r12_attrs },
        .{ .tag = "Text", .attrs = &r13_attrs }, .{ .tag = "Text", .attrs = &r14_attrs },
        .{ .tag = "Text", .attrs = &r15_attrs }, .{ .tag = "Text", .attrs = &r16_attrs },
        .{ .tag = "Text", .attrs = &r17_attrs }, .{ .tag = "Text", .attrs = &r18_attrs },
        .{ .tag = "Text", .attrs = &r19_attrs }, .{ .tag = "Text", .attrs = &r20_attrs },
    };
    const scroll_inner = NodeDesc{ .tag = "Column", .classes = "gap-1 p-2", .children = &scroll_rows };
    const scroll_view  = NodeDesc{ .tag = "ScrollView", .classes = "h-48", .children = &[1]NodeDesc{scroll_inner} };

    const scroll_sect_children = [3]NodeDesc{ scroll_h, scroll_note, scroll_view };
    const scroll_sect = NodeDesc{ .tag = "Column", .classes = "gap-2", .children = &scroll_sect_children };

    // --- Assemble ---
    const body_children = [3]NodeDesc{ table_sect, scroll_sect, NodeDesc{ .tag = "Separator" } };
    const body = NodeDesc{ .tag = "Column", .classes = "gap-4", .children = &body_children };

    const content_children = [3]NodeDesc{ heading, sep, body };
    const content = NodeDesc{ .tag = "Column", .classes = "flex-1 gap-3 p-6", .children = &content_children };

    const root_children = [2]NodeDesc{ sidebar.buildSidebar(), content };
    const root = NodeDesc{ .tag = "Row", .classes = "w-full h-full", .children = &root_children };

    _ = try scene.instantiate(root, tokens);
    try shared.wireSidebarCallbacks(scene, c.global, tokens, 5); // 5 = Data button

    // DFS: 0=root,1=sidebar,2-9=btns,10=content,11=heading,12=sep,13=body,
    //      14=table_sect,15=sub,16=table,17=sep2,
    //      18=scroll_sect,...
    scene.setTableData(16, &_table_rows);
    scene.setTableColumns(16, &_columns);


}
