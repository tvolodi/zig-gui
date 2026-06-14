// Pure-Zig bspatch implementation (BSDFRAW1 format — uncompressed variant)
// M19-02: applies binary patches produced by a companion bsdiff tool.
//
// Patch format (BSDFRAW1 — our uncompressed variant; avoids bzip2 dependency):
//
//   [8 bytes]  magic: "BSDFRAW1"
//   [8 bytes]  new_size:  u64 little-endian — size of the output binary
//   [8 bytes]  ctrl_len:  u64 — byte length of the control block
//   [8 bytes]  diff_len:  u64 — byte length of the diff block
//   [ctrl_len] control triples: each 24 bytes: (x: i64, y: i64, z: i64)
//              x = copy x bytes from diff block + old, byte-by-byte add
//              y = copy y extra bytes verbatim
//              z = advance old_pos by z (can be negative for back-seeks)
//   [diff_len] diff block: byte sequence, XOR-added to old[old_pos]
//   [rest]     extra block: bytes copied verbatim into output
//
// This is a subset of the classic bsdiff algorithm (Colin Percival, BSD license)
// re-derived in pure Zig with uncompressed blocks so no bzip2 is needed.

const std = @import("std");

pub const PatchError = error{
    InvalidMagic,
    CorruptPatch,
    OutputSizeMismatch,
    OutOfMemory,
};

pub const MAGIC = "BSDFRAW1";

/// Apply a patch to `old_data`, producing the new binary as a freshly allocated slice.
/// patch_data: the full patch file bytes (starts with "BSDFRAW1" magic)
/// old_data:   the current binary bytes
/// Returns a caller-owned slice; call `allocator.free(result)` when done.
pub fn applyPatch(
    allocator: std.mem.Allocator,
    old_data: []const u8,
    patch_data: []const u8,
) PatchError![]u8 {
    if (patch_data.len < 32) return PatchError.InvalidMagic;
    if (!std.mem.eql(u8, patch_data[0..8], MAGIC)) return PatchError.InvalidMagic;

    const new_size = std.mem.readInt(u64, patch_data[8..16], .little);
    const ctrl_len = std.mem.readInt(u64, patch_data[16..24], .little);
    const diff_len = std.mem.readInt(u64, patch_data[24..32], .little);

    const ctrl_start: usize = 32;
    const diff_start: usize = ctrl_start + @as(usize, @intCast(ctrl_len));
    const extra_start: usize = diff_start + @as(usize, @intCast(diff_len));

    if (patch_data.len < extra_start) return PatchError.CorruptPatch;

    const ctrl_block = patch_data[ctrl_start..diff_start];
    const diff_block = patch_data[diff_start..extra_start];
    const extra_block = patch_data[extra_start..];

    const new_data = allocator.alloc(u8, @as(usize, @intCast(new_size))) catch
        return PatchError.OutOfMemory;
    errdefer allocator.free(new_data);
    @memset(new_data, 0);

    var old_pos: i64 = 0;
    var new_pos: usize = 0;
    var diff_pos: usize = 0;
    var extra_pos: usize = 0;
    var ctrl_pos: usize = 0;

    while (ctrl_pos + 24 <= ctrl_block.len) {
        const x = @as(i64, @bitCast(std.mem.readInt(u64, ctrl_block[ctrl_pos..][0..8], .little)));
        const y = @as(i64, @bitCast(std.mem.readInt(u64, ctrl_block[ctrl_pos + 8 ..][0..8], .little)));
        const z = @as(i64, @bitCast(std.mem.readInt(u64, ctrl_block[ctrl_pos + 16 ..][0..8], .little)));
        ctrl_pos += 24;

        // Byte-add diff bytes onto old bytes (add = diff[i] + old[old_pos+i], wrapping)
        const add_count: usize = if (x >= 0) @as(usize, @intCast(x)) else 0;
        if (new_pos + add_count > new_size) return PatchError.CorruptPatch;
        if (diff_pos + add_count > diff_block.len) return PatchError.CorruptPatch;

        for (0..add_count) |i| {
            const old_byte: u8 = if (old_pos >= 0 and old_pos < @as(i64, @intCast(old_data.len)))
                old_data[@as(usize, @intCast(old_pos))]
            else
                0;
            new_data[new_pos + i] = diff_block[diff_pos + i] +% old_byte;
            old_pos += 1;
        }
        new_pos += add_count;
        diff_pos += add_count;

        // Copy extra bytes verbatim
        const copy_count: usize = if (y >= 0) @as(usize, @intCast(y)) else 0;
        if (new_pos + copy_count > new_size) return PatchError.CorruptPatch;
        if (extra_pos + copy_count > extra_block.len) return PatchError.CorruptPatch;

        @memcpy(new_data[new_pos..][0..copy_count], extra_block[extra_pos..][0..copy_count]);
        new_pos += copy_count;
        extra_pos += copy_count;

        // Adjust old position (z may be negative for backward seeks)
        old_pos += z;
    }

    if (new_pos != new_size) return PatchError.OutputSizeMismatch;
    return new_data;
}
