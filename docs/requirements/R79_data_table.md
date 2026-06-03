# R79 — M7-10: Data table

> Roadmap item: M7-10  
> Depends on: M3-06 (scroll container), M4-03 (overflow-hidden clipping), M4-05 (text truncation)  
> Read `00_constitution.md` before this file.

## Purpose

A `<DataTable>` renders a scrollable, sortable table of rows with typed columns. Rows are
virtualized: only the rows currently in the viewport are instantiated as elements; the rest
are represented as raw data in `DataTableState`. Sorting reorders an index array; no data
copy. Column headers are clickable to toggle sort direction.

## What to build

### Widget kind

```zig
pub const WidgetKind = enum { /* ...existing... */ data_table };

// tagToKind: "DataTable" → .data_table
// defaultLayoutFor: .data_table → { .display = .block, .overflow = .hidden }
```

### Column definition

```zig
pub const ColumnAlign = enum { left, center, right };

pub const DataColumn = struct {
    header:    [64]u8      = .{0} ** 64,
    header_len: u8         = 0,
    width_px:  f32         = 120,
    align:     ColumnAlign = .left,
    sortable:  bool        = true,
};

pub const MAX_COLUMNS: u8 = 16;
```

### `DataTableState` and `DataTableRows`

Data is kept outside `Scene` in a caller-managed `DataTableRows` struct, which holds a
pointer to the raw data plus column accessor functions:

```zig
pub const CellTextFn = *const fn (row_ptr: *anyopaque, col: u8, buf: []u8) u8;
// Writes the cell's display string into `buf` and returns the byte count.
// `row_ptr` points to one element of the caller's row slice.

pub const DataTableRows = struct {
    row_ptr:     *anyopaque,   // pointer to first element of caller's row array
    row_size:    u32,          // sizeof one row in bytes
    row_count:   u32,
    cell_text:   CellTextFn,
};

pub const SortDir = enum { none, asc, desc };

pub const DataTableState = struct {
    columns:      [MAX_COLUMNS]DataColumn = .{.{}} ** MAX_COLUMNS,
    col_count:    u8 = 0,
    sort_col:     u8 = 0xFF,  // 0xFF = unsorted
    sort_dir:     SortDir = .none,
    /// Index permutation for sorted view. `sorted_indices[i]` is the original row index.
    sorted_indices: std.ArrayListUnmanaged(u32) = .empty,
    /// Scroll offset (pixels scrolled down in the data area).
    scroll_y:     f32 = 0,
    /// Row height (all rows the same height — virtualization requires this).
    row_height:   f32 = 32,
    /// Rows pointer (set by application; not owned by DataTableState).
    rows:         ?*const DataTableRows = null,
};

pub const Scene = struct {
    _table_state: std.ArrayListUnmanaged(DataTableState) = .empty,

    pub fn tableStateOf(self: *Scene, idx: u32) *DataTableState

    /// Set the data source. Does not copy data; caller must keep `rows` alive.
    pub fn setTableData(self: *Scene, idx: u32,
                        rows: *const DataTableRows, row_height: f32) void

    /// Set column definitions.
    pub fn setTableColumns(self: *Scene, idx: u32,
                           columns: []const DataColumn) void

    /// Sort by `col_idx`. Toggles direction if already sorted by the same column.
    /// Rebuilds `sorted_indices`. Marks dirty.
    pub fn sortTable(self: *Scene, idx: u32, col_idx: u8) void
};
```

### Virtualization — `buildDrawList` for `data_table`

The serializer does NOT use the element tree for row/cell children. Instead, it calls the
`cell_text` function directly and emits draw commands on the fly. Only the header row has
real elements (for focus/click handling); data rows are pure draw commands.

```zig
// In buildDrawList for .data_table:
const state = scene.tableStateOf(idx);
const rows  = state.rows orelse return;

const HEADER_H: f32 = 36;
const table_rect = layout_rect;
const data_h = table_rect.h - HEADER_H;

// --- Scissor to table bounds ---
try cmds.append(.{ .set_scissor = rectToScissor(table_rect) });

// --- Header row ---
var col_x = table_rect.x;
for (state.columns[0..state.col_count], 0..) |col, ci| {
    const hdr_rect = Rect{ .x = col_x, .y = table_rect.y,
                           .w = col.width_px, .h = HEADER_H };
    // Background:
    try cmds.append(.{ .filled_rect = .{
        .rect = hdr_rect, .color = tokens.bg_surface } });
    // Sort indicator:
    if (state.sort_col == ci) {
        const indicator = if (state.sort_dir == .asc) "▲" else "▼";
        // emit indicator glyph(s) ... (abbreviated)
        _ = indicator;
    }
    // Header text:
    const hdr_text = col.header[0..col.header_len];
    const para = try layoutParagraph(alloc, family.face(false, false), glyph_atlas,
                                     hdr_text, tokens.text_sm, col.width_px - 16,
                                     .regular, null);
    for (para.glyphs) |g| {
        try cmds.append(.{ .glyph = .{
            .dst = .{ .x = col_x + 8 + g.dest_x, .y = table_rect.y + 8 + g.dest_y,
                      .w = g.dest_w, .h = g.dest_h },
            .uv = g.uv, .color = tokens.text_muted,
        }});
    }
    col_x += col.width_px;
}

// --- Data rows (virtualized) ---
const first_row: u32 = @intFromFloat(@max(0, state.scroll_y / state.row_height));
const visible_rows: u32 = @intFromFloat(@ceil(data_h / state.row_height)) + 1;
const last_row: u32 = @min(first_row + visible_rows, rows.row_count);

var ri: u32 = first_row;
while (ri < last_row) : (ri += 1) {
    const orig_ri = if (state.sorted_indices.items.len > 0)
                        state.sorted_indices.items[ri]
                    else ri;
    const row_y = table_rect.y + HEADER_H + @as(f32, @floatFromInt(ri)) * state.row_height
                  - state.scroll_y;

    // Row background (alternating):
    const row_bg = if (ri % 2 == 0) tokens.bg_canvas else tokens.bg_surface;
    try cmds.append(.{ .filled_rect = .{
        .rect = .{ .x = table_rect.x, .y = row_y, .w = table_rect.w, .h = state.row_height },
        .color = row_bg,
    }});

    // Cells:
    col_x = table_rect.x;
    for (state.columns[0..state.col_count], 0..) |col, ci| {
        _ = ci;
        var cell_buf: [256]u8 = undefined;
        const row_data_ptr = @as(*anyopaque, @ptrFromInt(
            @intFromPtr(rows.row_ptr) + @as(usize, orig_ri) * rows.row_size));
        const cell_len = rows.cell_text(row_data_ptr, @intCast(ci), &cell_buf);
        const cell_text = cell_buf[0..cell_len];

        const cell_rect = Rect{ .x = col_x, .y = row_y,
                                .w = col.width_px, .h = state.row_height };
        const para = try layoutParagraph(alloc, family.face(false, false), glyph_atlas,
                                         cell_text, tokens.text_base, col.width_px - 16,
                                         .regular, null);
        for (para.glyphs) |g| {
            const gx = if (g.dest_x + g.dest_w <= col.width_px - 16) g.dest_x else {
                continue;  // clip to cell width (truncation)
            };
            try cmds.append(.{ .glyph = .{
                .dst = .{ .x = cell_rect.x + 8 + gx, .y = row_y + 8 + g.dest_y,
                          .w = g.dest_w, .h = g.dest_h },
                .uv = g.uv, .color = tokens.text_body,
            }});
        }
        col_x += col.width_px;
    }
}

try cmds.append(.{ .restore_scissor = {} });
```

### `sortTable` — index sort

```zig
pub fn sortTable(self: *Scene, idx: u32, col_idx: u8) void {
    const state = self.tableStateOf(idx);
    const rows  = state.rows orelse return;

    // Rebuild sorted_indices if needed.
    if (state.sorted_indices.items.len != rows.row_count) {
        state.sorted_indices.resize(self.gpa, rows.row_count) catch return;
        for (state.sorted_indices.items, 0..) |*v, i| v.* = @intCast(i);
    }

    // Toggle direction.
    if (state.sort_col == col_idx) {
        state.sort_dir = if (state.sort_dir == .asc) .desc else .asc;
    } else {
        state.sort_col = col_idx;
        state.sort_dir = .asc;
    }

    // Sort by cell text (string compare). O(n log n) via std.sort.
    const dir = state.sort_dir;
    std.sort.pdq(u32, state.sorted_indices.items, .{ .rows = rows, .col = col_idx, .dir = dir },
        struct {
            fn lessThan(ctx: @TypeOf(@as(@TypeOf(.{ .rows = rows, .col = col_idx, .dir = dir }), undefined)),
                         a: u32, b: u32) bool {
                var ba: [256]u8 = undefined;
                var bb: [256]u8 = undefined;
                const row_a = ptrAt(ctx.rows, a);
                const row_b = ptrAt(ctx.rows, b);
                const la = ctx.rows.cell_text(row_a, ctx.col, &ba);
                const lb = ctx.rows.cell_text(row_b, ctx.col, &bb);
                const cmp = std.mem.order(u8, ba[0..la], bb[0..lb]);
                return if (ctx.dir == .asc) cmp == .lt else cmp == .gt;
            }
        }.lessThan);
    self.elements.dirty.set(idx);
}
```

### Mouse wheel scrolling

In `App.run()`, mouse wheel over the data table's rect scrolls `state.scroll_y` (same
pattern as the scroll container in R35):

```zig
if (scene.kindOf(idx) == .data_table) {
    const state = scene.tableStateOf(idx);
    if (state.rows) |rows| {
        const total_h = @as(f32, @floatFromInt(rows.row_count)) * state.row_height;
        const max_scroll = @max(0, total_h - (layout_rect.h - 36));
        state.scroll_y = std.math.clamp(
            state.scroll_y - scroll_wheel.y * 40, 0, max_scroll);
        scene.elements.dirty.set(idx);
    }
}
```

### Header click for sort

Column header hit-testing: when left-click on the header row, determine which column was
clicked and call `sortTable(idx, col_idx)`.

### Module location

```
src/07/types.zig   — WidgetKind.data_table, DataColumn, DataTableState, DataTableRows, setTableData, setTableColumns, sortTable
src/09/types.zig   — buildDrawList .data_table branch (virtualized rows)
src/app/app.zig    — wheel scroll, header click for sort
src/app/date_util.zig — reused for nothing here; table sort is string-based
docs/requirements/R79_data_table.md
```

## Non-goals (DO NOT implement — INV-5.4)

- **No row selection** — display only; no highlighted row state.
- **No resizable columns** — fixed column widths set at configuration time.
- **No horizontal virtualization** — all columns are rendered; only vertical is virtualized.
- **No infinite scroll / pagination** — all `row_count` rows are available; scroll reveals them.
- **No editable cells** — read-only display.
- **No frozen columns** — no column pinning.
- **No multi-column sort** — single sort column only.

## Acceptance criteria

1. `zig build test-07` passes. `setTableData` with 1000 rows and `sortTable` on column 0 —
   `sorted_indices[0]` points to the lexicographically first row.
2. `zig build test-09-unit` passes. DataTable with 3 visible rows (viewport = 3×row_height)
   and 1000 rows total emits draw commands for exactly 3 data rows plus header.
3. Integration: 1000-row table renders and scrolls smoothly. Click column header sorts.
   Second click reverses direction. Checklist ticked.
