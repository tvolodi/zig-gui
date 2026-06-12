//! row_data.zig — Deterministic fake employee table data for the Data screen.
//!
//! 200 rows, 5 columns: #, Name, Department, Score, Status.
//! No heap allocation: all data is comptime-constant.

const std = @import("std");

pub const EmployeeRow = struct {
    id: u32,
    name: []const u8,
    department: []const u8,
    score: u32,
    active: bool,
};

const NAMES = [20][]const u8{
    "Alice Chen",    "Bob Martinez",  "Carol Singh",   "David Lee",
    "Eva Novak",     "Frank Adeyemi", "Grace Park",    "Hugo Berger",
    "Irene Costa",   "James Okafor",  "Kate Wilson",   "Liam Brown",
    "Maya Patel",    "Noah Kim",      "Olivia Russo",  "Pedro Alves",
    "Quinn Taylor",  "Rosa Muñoz",    "Sam Johansson", "Tara O'Brien",
};

const DEPTS = [5][]const u8{
    "Engineering", "Design", "Marketing", "HR", "Finance",
};

fn makeRow(i: u32) EmployeeRow {
    return .{
        .id         = i + 1,
        .name       = NAMES[i % 20],
        .department = DEPTS[i % 5],
        .score      = 60 + (i * 7 + i / 3) % 41,  // deterministic 60–100
        .active     = (i % 5) != 3,                 // ~80% active
    };
}

fn makeRows() [200]EmployeeRow {
    var rows: [200]EmployeeRow = undefined;
    var i: u32 = 0;
    while (i < 200) : (i += 1) rows[i] = makeRow(i);
    return rows;
}

pub const ROWS: [200]EmployeeRow = makeRows();

/// CellTextFn: col 0=#, col 1=Name, col 2=Department, col 3=Score, col 4=Status.
pub fn cellText(row_ptr: *anyopaque, col: u8, buf: []u8) u8 {
    const row: *const EmployeeRow = @ptrCast(@alignCast(row_ptr));
    const text: []const u8 = switch (col) {
        0 => {
            const written = std.fmt.bufPrint(buf, "{d}", .{row.id}) catch return 0;
            return @intCast(written.len);
        },
        1 => row.name,
        2 => row.department,
        3 => {
            const written = std.fmt.bufPrint(buf, "{d}", .{row.score}) catch return 0;
            return @intCast(written.len);
        },
        4 => if (row.active) "Active" else "Inactive",
        else => "",
    };
    const len = @min(text.len, buf.len);
    @memcpy(buf[0..len], text[0..len]);
    return @intCast(len);
}
