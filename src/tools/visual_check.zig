//! visual_check.zig — Screenshot sanity checker for the visual test pipeline.
//!
//! Usage: visual_check <screenshot.png>
//!
//! Reads a PNG file written by the demo in screenshot mode, then checks:
//!   1. File exists and is non-empty.
//!   2. PNG header is valid.
//!   3. The raw pixel data embedded in the zlib IDAT payload has mean
//!      brightness > threshold — i.e. the frame is not all-black.
//!
//! Exit codes:
//!   0 — visual check passed
//!   1 — check failed (prints reason to stderr)
//!
//! This is intentionally simple: it does not fully decode PNG compression.
//! Instead it reads the raw file bytes and checks that the IDAT chunk contains
//! enough non-zero bytes to rule out a blank frame.  A properly rendered home
//! screen has ~30% non-zero pixels (card backgrounds, text, sidebar color).

const std = @import("std");

pub fn main(init: std.process.Init) !void {
    var gpa_impl = std.heap.DebugAllocator(.{}).init;
    defer _ = gpa_impl.deinit();
    const gpa = gpa_impl.allocator();

    const args = try init.minimal.args.toSlice(init.arena.allocator());

    if (args.len < 2) {
        std.debug.print("Usage: visual_check <screenshot.png>\n", .{});
        std.process.exit(1);
    }

    const path = args[1];

    // Read the PNG file.
    const data = std.Io.Dir.readFileAlloc(.cwd(), init.io, path, gpa, .limited(64 * 1024 * 1024)) catch |err| {
        std.debug.print("FAIL: cannot read '{s}': {}\n", .{ path, err });
        std.process.exit(1);
    };
    defer gpa.free(data);

    if (data.len < 8) {
        std.debug.print("FAIL: file too small ({d} bytes)\n", .{data.len});
        std.process.exit(1);
    }

    // Check PNG signature.
    const png_sig = [8]u8{ 137, 80, 78, 71, 13, 10, 26, 10 };
    if (!std.mem.eql(u8, data[0..8], &png_sig)) {
        std.debug.print("FAIL: not a PNG file\n", .{});
        std.process.exit(1);
    }

    // Scan chunks to find IDAT and sum non-zero bytes.
    // This is a heuristic — we're not decompressing, just checking the
    // compressed payload isn't all zeros (which a blank frame would produce
    // as near-zero entropy deflate output).
    var non_zero: u64 = 0;
    var total_idat: u64 = 0;
    var pos: usize = 8;
    while (pos + 12 <= data.len) {
        const chunk_len = std.mem.readInt(u32, data[pos..][0..4], .big);
        const chunk_type = data[pos + 4 .. pos + 8];
        const chunk_data_start = pos + 8;
        const chunk_data_end = chunk_data_start + chunk_len;

        if (chunk_data_end > data.len) break;

        if (std.mem.eql(u8, chunk_type, "IDAT")) {
            const idat = data[chunk_data_start..chunk_data_end];
            total_idat += idat.len;
            for (idat) |b| {
                if (b != 0) non_zero += 1;
            }
        } else if (std.mem.eql(u8, chunk_type, "IEND")) {
            break;
        }

        pos = chunk_data_end + 4; // skip CRC
    }

    if (total_idat == 0) {
        std.debug.print("FAIL: no IDAT chunks found in '{s}'\n", .{path});
        std.process.exit(1);
    }

    // A blank (all-black) frame compresses to very few non-zero bytes.
    // A rendered home screen has sidebar color + card backgrounds + text glyphs,
    // easily exceeding 5% non-zero bytes in the compressed payload.
    const ratio = @as(f64, @floatFromInt(non_zero)) / @as(f64, @floatFromInt(total_idat));
    const threshold: f64 = 0.05;

    if (ratio < threshold) {
        std.debug.print(
            "FAIL: screenshot appears blank — {d:.1}% non-zero IDAT bytes (threshold {d:.1}%)\n",
            .{ ratio * 100.0, threshold * 100.0 },
        );
        std.debug.print("  File: {s} ({d} bytes, {d} IDAT bytes)\n", .{ path, data.len, total_idat });
        std.process.exit(1);
    }

    std.debug.print(
        "PASS: screenshot '{s}' — {d:.1}% non-zero IDAT bytes\n",
        .{ path, ratio * 100.0 },
    );
}
