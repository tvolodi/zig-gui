//! png_writer.zig — Minimal uncompressed PNG encoder.
//!
//! Writes an 8-bit RGBA PNG using zlib store blocks (compression level 0).
//! No external dependencies — pure Zig std only.
//! Only used by the visual-check screenshot path; not in production binary.

const std = @import("std");

/// Write a raw RGBA image (4 bytes per pixel, top-to-bottom) as a PNG file.
/// Write a PNG file at `path`. Uses a heap-allocated buffer then writes in one call.
pub fn writePng(
    gpa: std.mem.Allocator,
    path: []const u8,
    pixels: []const u8,
    width: u32,
    height: u32,
) !void {
    // Compute an upper bound on encoded size and allocate.
    // zlib header(2) + per-row(5+1+w*4) * h + adler32(4) + PNG overhead ~200 bytes
    const row_bytes: u64 = @as(u64, width) * 4;
    const max_size: usize = @intCast(200 + (5 + 1 + row_bytes) * height + 4);
    const buf = try gpa.alloc(u8, max_size);
    defer gpa.free(buf);

    var cursor: usize = 0;
    const BufWriter = struct {
        slice: []u8,
        pos: *usize,
        pub const Error = error{NoSpaceLeft};
        pub fn writeAll(self: @This(), data: []const u8) Error!void {
            if (self.pos.* + data.len > self.slice.len) return error.NoSpaceLeft;
            @memcpy(self.slice[self.pos.*..][0..data.len], data);
            self.pos.* += data.len;
        }
        pub fn writeByte(self: @This(), byte: u8) Error!void {
            return self.writeAll(&[1]u8{byte});
        }
    };
    const w = BufWriter{ .slice = buf, .pos = &cursor };
    try writePngToWriter(w, pixels, width, height);
    const written = cursor;

    const sio = std.Io.Threaded.global_single_threaded.io();
    const file = try std.Io.Dir.createFile(.cwd(), sio, path, .{ .truncate = true });
    defer file.close(sio);
    try std.Io.File.writeStreamingAll(file, sio, buf[0..written]);
}

pub fn writePngToWriter(writer: anytype, pixels: []const u8, width: u32, height: u32) !void {
    // PNG signature
    try writer.writeAll(&[_]u8{ 137, 80, 78, 71, 13, 10, 26, 10 });

    // IHDR chunk
    var ihdr: [13]u8 = undefined;
    std.mem.writeInt(u32, ihdr[0..4], width, .big);
    std.mem.writeInt(u32, ihdr[4..8], height, .big);
    ihdr[8] = 8;  // bit depth
    ihdr[9] = 2;  // color type: RGB (drop alpha for simplicity — use 6 for RGBA)
    // Use RGBA (color type 6) for full fidelity
    ihdr[9] = 6;
    ihdr[10] = 0; // compression method
    ihdr[11] = 0; // filter method
    ihdr[12] = 0; // interlace method
    try writeChunk(writer, "IHDR", &ihdr);

    // IDAT chunk — zlib-wrapped filtered scanlines
    // Use a single zlib STORE block per row for simplicity.
    const row_bytes: u32 = width * 4; // RGBA
    // Pre-compute total IDAT payload size to write chunk length upfront.
    // zlib header (2) + per-row STORE blocks + adler32 (4)
    // Each STORE block: 1 (BFINAL+BTYPE) + 2 (LEN) + 2 (NLEN) + (1 filter byte + row_bytes) data
    const block_data_size: u32 = 1 + row_bytes; // filter byte + row
    const block_size: u32 = 5 + block_data_size; // deflate block overhead
    const idat_size: u32 = 2 + height * block_size + 4; // zlib header + blocks + adler32

    // Write IDAT chunk length + type
    var len_buf: [4]u8 = undefined;
    std.mem.writeInt(u32, &len_buf, idat_size, .big);
    try writer.writeAll(&len_buf);
    try writer.writeAll("IDAT");

    // CRC accumulator (covers type + data)
    var crc = Crc32.init();
    crc.update("IDAT");

    // zlib header: CMF=0x78 (deflate, window=32K), FLG such that CMF*256+FLG % 31 == 0
    // 0x78 * 256 = 30720, 30720 % 31 = 30720 - 991*31 = 30720 - 30721 = -1 → use 0x78, 0x01
    // Actually: (0x78*256 + FLG) % 31 == 0 → 30720 + FLG ≡ 0 mod 31
    // 30720 mod 31 = 30720 - 990*31 = 30720 - 30690 = 30; so FLG = 31-30 = 1
    const zlib_header = [2]u8{ 0x78, 0x01 };
    try writer.writeAll(&zlib_header);
    crc.update(&zlib_header);

    // Adler32 for zlib checksum
    var adler = Adler32.init();

    // Emit one DEFLATE STORE block per scanline
    for (0..height) |y| {
        const is_last: bool = (y == height - 1);
        const bfinal: u8 = if (is_last) 0x01 else 0x00; // BTYPE=00 (STORE), BFINAL=last?
        const block_hdr = [_]u8{
            bfinal,
            @truncate(block_data_size & 0xFF),
            @truncate((block_data_size >> 8) & 0xFF),
            @truncate((~block_data_size) & 0xFF),
            @truncate(((~block_data_size) >> 8) & 0xFF),
        };
        try writer.writeAll(&block_hdr);
        crc.update(&block_hdr);

        // Filter byte 0 (None)
        const filter_byte = [1]u8{0};
        try writer.writeAll(&filter_byte);
        crc.update(&filter_byte);
        adler.update(&filter_byte);

        const row = pixels[y * row_bytes .. (y + 1) * row_bytes];
        try writer.writeAll(row);
        crc.update(row);
        adler.update(row);
    }

    // Adler32 checksum (big-endian)
    var adler_buf: [4]u8 = undefined;
    std.mem.writeInt(u32, &adler_buf, adler.final(), .big);
    try writer.writeAll(&adler_buf);
    crc.update(&adler_buf);

    // CRC32 for IDAT
    var crc_buf: [4]u8 = undefined;
    std.mem.writeInt(u32, &crc_buf, crc.final(), .big);
    try writer.writeAll(&crc_buf);

    // IEND chunk
    try writeChunk(writer, "IEND", &[_]u8{});
}

fn writeChunk(writer: anytype, tag: *const [4]u8, data: []const u8) !void {
    var len_buf: [4]u8 = undefined;
    std.mem.writeInt(u32, &len_buf, @intCast(data.len), .big);
    try writer.writeAll(&len_buf);
    try writer.writeAll(tag);
    try writer.writeAll(data);

    var crc = Crc32.init();
    crc.update(tag);
    crc.update(data);
    var crc_buf: [4]u8 = undefined;
    std.mem.writeInt(u32, &crc_buf, crc.final(), .big);
    try writer.writeAll(&crc_buf);
}

// ---------------------------------------------------------------------------
// Minimal CRC-32 and Adler-32
// ---------------------------------------------------------------------------

const Crc32 = struct {
    value: u32,

    fn init() Crc32 {
        return .{ .value = 0xFFFFFFFF };
    }
    fn update(self: *Crc32, data: []const u8) void {
        for (data) |byte| {
            self.value = crc32_table[(self.value ^ byte) & 0xFF] ^ (self.value >> 8);
        }
    }
    fn final(self: Crc32) u32 {
        return self.value ^ 0xFFFFFFFF;
    }
};

const crc32_table: [256]u32 = blk: {
    @setEvalBranchQuota(10000);
    var table: [256]u32 = undefined;
    var i: u32 = 0;
    while (i < 256) : (i += 1) {
        var c: u32 = i;
        var k: u32 = 0;
        while (k < 8) : (k += 1) {
            if (c & 1 != 0) {
                c = 0xEDB88320 ^ (c >> 1);
            } else {
                c = c >> 1;
            }
        }
        table[i] = c;
    }
    break :blk table;
};

const Adler32 = struct {
    s1: u32,
    s2: u32,

    fn init() Adler32 {
        return .{ .s1 = 1, .s2 = 0 };
    }
    fn update(self: *Adler32, data: []const u8) void {
        for (data) |byte| {
            self.s1 = (self.s1 + byte) % 65521;
            self.s2 = (self.s2 + self.s1) % 65521;
        }
    }
    fn final(self: Adler32) u32 {
        return (self.s2 << 16) | self.s1;
    }
};
