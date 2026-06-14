// Unit tests for bspatch.zig — M19-02
// Tests the pure patch-application logic with crafted in-memory patches.
// No network, no file I/O required.

const std = @import("std");
const bspatch = @import("bspatch.zig");

test "applyPatch: rejects short input" {
    const allocator = std.testing.allocator;
    const patch = "BSDFRAW1"; // only 8 bytes, too short for header
    const result = bspatch.applyPatch(allocator, &[_]u8{}, patch);
    try std.testing.expectError(bspatch.PatchError.InvalidMagic, result);
}

test "applyPatch: rejects wrong magic" {
    const allocator = std.testing.allocator;
    var patch: [32]u8 = undefined;
    @memset(&patch, 0);
    @memcpy(patch[0..8], "WRONGMAG");
    const result = bspatch.applyPatch(allocator, &[_]u8{}, &patch);
    try std.testing.expectError(bspatch.PatchError.InvalidMagic, result);
}

test "applyPatch: empty old + empty patch produces empty new" {
    const allocator = std.testing.allocator;
    // Craft a minimal valid patch: magic + new_size=0 + ctrl_len=0 + diff_len=0
    var patch: [32]u8 = undefined;
    @memcpy(patch[0..8], "BSDFRAW1");
    std.mem.writeInt(u64, patch[8..16], 0, .little);  // new_size = 0
    std.mem.writeInt(u64, patch[16..24], 0, .little); // ctrl_len = 0
    std.mem.writeInt(u64, patch[24..32], 0, .little); // diff_len = 0
    const result = try bspatch.applyPatch(allocator, &[_]u8{}, &patch);
    defer allocator.free(result);
    try std.testing.expectEqual(@as(usize, 0), result.len);
}

test "applyPatch: copy from extra block verbatim" {
    const allocator = std.testing.allocator;
    // Patch that copies 5 bytes from extra block verbatim (x=0, y=5, z=0)
    // ctrl_len = 24 (one triple), diff_len = 0, extra = "hello"
    var patch_buf: [32 + 24 + 5]u8 = undefined;
    @memcpy(patch_buf[0..8], "BSDFRAW1");
    std.mem.writeInt(u64, patch_buf[8..16], 5, .little);   // new_size = 5
    std.mem.writeInt(u64, patch_buf[16..24], 24, .little); // ctrl_len = 24 (one triple)
    std.mem.writeInt(u64, patch_buf[24..32], 0, .little);  // diff_len = 0
    // ctrl triple: x=0, y=5, z=0
    std.mem.writeInt(u64, patch_buf[32..40], 0, .little);  // x = 0
    std.mem.writeInt(u64, patch_buf[40..48], 5, .little);  // y = 5
    std.mem.writeInt(u64, patch_buf[48..56], 0, .little);  // z = 0
    // extra block: "hello"
    @memcpy(patch_buf[56..61], "hello");
    const result = try bspatch.applyPatch(allocator, &[_]u8{}, &patch_buf);
    defer allocator.free(result);
    try std.testing.expectEqualStrings("hello", result);
}

test "applyPatch: add diff bytes to old bytes (wrapping)" {
    const allocator = std.testing.allocator;
    // old = [0x01, 0x02, 0x03]
    // diff = [0x10, 0x20, 0x30]
    // expected = [0x11, 0x22, 0x33] (byte-wise wrapping add)
    // ctrl: x=3 (add 3), y=0, z=0
    const old: [3]u8 = .{ 0x01, 0x02, 0x03 };
    var patch_buf: [32 + 24 + 3]u8 = undefined;
    @memcpy(patch_buf[0..8], "BSDFRAW1");
    std.mem.writeInt(u64, patch_buf[8..16], 3, .little);   // new_size = 3
    std.mem.writeInt(u64, patch_buf[16..24], 24, .little); // ctrl_len = 24
    std.mem.writeInt(u64, patch_buf[24..32], 3, .little);  // diff_len = 3
    // ctrl triple: x=3, y=0, z=0
    std.mem.writeInt(u64, patch_buf[32..40], 3, .little);  // x = 3
    std.mem.writeInt(u64, patch_buf[40..48], 0, .little);  // y = 0
    std.mem.writeInt(u64, patch_buf[48..56], 0, .little);  // z = 0
    // diff block
    patch_buf[56] = 0x10;
    patch_buf[57] = 0x20;
    patch_buf[58] = 0x30;
    const result = try bspatch.applyPatch(allocator, &old, &patch_buf);
    defer allocator.free(result);
    try std.testing.expectEqual(@as(usize, 3), result.len);
    try std.testing.expectEqual(@as(u8, 0x11), result[0]);
    try std.testing.expectEqual(@as(u8, 0x22), result[1]);
    try std.testing.expectEqual(@as(u8, 0x33), result[2]);
}
