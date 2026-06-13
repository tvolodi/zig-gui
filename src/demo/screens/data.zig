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
    const table = NodeDesc{ .tag = "DataTable", .classes = "h-64 shrink-0" };

    const table_sect_children = [3]NodeDesc{ sub, table, NodeDesc{ .tag = "Separator" } };
    const table_sect = NodeDesc{ .tag = "Column", .classes = "gap-2", .children = &table_sect_children };

    // --- Assemble ---
    const body_children = [1]NodeDesc{table_sect};
    const body = NodeDesc{ .tag = "Column", .classes = "gap-4", .children = &body_children };
    const scroll = NodeDesc{ .tag = "ScrollView", .classes = "flex-1", .children = &[1]NodeDesc{
        NodeDesc{ .tag = "Column", .classes = "p-2", .children = &[1]NodeDesc{body} },
    } };

    const content_children = [4]NodeDesc{ heading, sep, scroll, NodeDesc{ .tag = "Separator" } };
    const content = NodeDesc{ .tag = "Column", .classes = "flex-1 gap-3 p-6", .children = &content_children };

    const root_children = [2]NodeDesc{ sidebar.buildSidebar(), content };
    const root = NodeDesc{ .tag = "Row", .classes = "w-full h-full", .children = &root_children };

    _ = try scene.instantiate(root, tokens);
    try shared.wireSidebarCallbacks(scene, c.global, tokens, 5); // 5 = Data button

    // DFS: 0=root,1=sidebar,2-9=btns,10=content,11=heading,12=sep,13=scroll,
    //      14=inner-col,15=body,16=table_sect,17=sub,18=table,19=sep2
    scene.setTableData(18, &_table_rows);
    scene.setTableColumns(18, &_columns);


}
