const std = @import("std"); pub fn main() void { const T: type = @Type(.{ .Int = .{ .signedness = .unsigned, .bits = 32 } }); std.debug.print("ok", .{}); }
