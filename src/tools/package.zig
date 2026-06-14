const std = @import("std");
const builtin = @import("builtin");

const Io = std.Io;

const PackageOptions = struct {
    version: []const u8 = "",
    binary_path: []const u8 = "",
    output_dir: []const u8 = "",
    fonts_dir: []const u8 = "assets/fonts",
    include_manifest: bool = false,
};

fn parseArgs(args: []const []const u8) !PackageOptions {
    var opts = PackageOptions{};

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--version") and i + 1 < args.len) {
            opts.version = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--binary-path") and i + 1 < args.len) {
            opts.binary_path = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--output") and i + 1 < args.len) {
            opts.output_dir = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--fonts-dir") and i + 1 < args.len) {
            opts.fonts_dir = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--include-manifest")) {
            opts.include_manifest = true;
        }
    }

    if (opts.version.len == 0 or opts.output_dir.len == 0) {
        std.debug.print("Usage: package --version VERSION --output DIR [--binary-path PATH] [--fonts-dir DIR] [--include-manifest]\n", .{});
        return error.MissingArguments;
    }

    return opts;
}

fn sha256hex(data: []const u8) [64]u8 {
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hasher.update(data);
    var digest: [32]u8 = undefined;
    hasher.final(&digest);
    const hex_digits = "0123456789abcdef";
    var result: [64]u8 = undefined;
    for (digest, 0..) |byte, idx| {
        result[idx * 2] = hex_digits[byte >> 4];
        result[idx * 2 + 1] = hex_digits[byte & 0x0f];
    }
    return result;
}

// ---------------------------------------------------------------------------
// Little-endian write helpers
// ---------------------------------------------------------------------------

fn writeU16Le(buf: []u8, offset: usize, val: u16) void {
    buf[offset] = @intCast(val & 0xff);
    buf[offset + 1] = @intCast((val >> 8) & 0xff);
}

fn writeU32Le(buf: []u8, offset: usize, val: u32) void {
    buf[offset] = @intCast(val & 0xff);
    buf[offset + 1] = @intCast((val >> 8) & 0xff);
    buf[offset + 2] = @intCast((val >> 16) & 0xff);
    buf[offset + 3] = @intCast((val >> 24) & 0xff);
}

// ---------------------------------------------------------------------------
// ZIP writing (uncompressed Store method, pure Zig, no external deps)
// ---------------------------------------------------------------------------

const ZipEntry = struct {
    name: []const u8,
    data: []const u8,
    crc32: u32,
    local_header_offset: u32,
};

fn createZipPackage(
    allocator: std.mem.Allocator,
    io: Io,
    opts: PackageOptions,
    binary_data: []const u8,
    font_files: []const FontFile,
    manifest_data: ?[]const u8,
) !void {
    const cwd = Io.Dir.cwd();
    const output_filename = try std.fmt.allocPrint(
        allocator,
        "{s}/app-{s}.zip",
        .{ opts.output_dir, opts.version },
    );
    defer allocator.free(output_filename);

    std.debug.print("Creating ZIP package: {s}\n", .{output_filename});

    var entries = std.ArrayList(ZipEntry).empty;
    defer entries.deinit(allocator);

    // Binary entry (may be absent if no binary path given)
    if (binary_data.len > 0) {
        const bin_name = if (builtin.os.tag == .windows) "app.exe" else "app";
        try entries.append(allocator, .{
            .name = bin_name,
            .data = binary_data,
            .crc32 = std.hash.Crc32.hash(binary_data),
            .local_header_offset = 0,
        });
    }

    // Font entries
    for (font_files) |ff| {
        try entries.append(allocator, .{
            .name = ff.archive_name,
            .data = ff.data,
            .crc32 = std.hash.Crc32.hash(ff.data),
            .local_header_offset = 0,
        });
    }

    // Manifest entry
    if (manifest_data) |md| {
        try entries.append(allocator, .{
            .name = "manifest.json",
            .data = md,
            .crc32 = std.hash.Crc32.hash(md),
            .local_header_offset = 0,
        });
    }

    var zip_buf = std.ArrayList(u8).empty;
    defer zip_buf.deinit(allocator);

    // Write local file headers + data, track offsets
    for (entries.items) |*entry| {
        entry.local_header_offset = @intCast(zip_buf.items.len);

        const fname_len: u16 = @intCast(entry.name.len);
        const data_len: u32 = @intCast(entry.data.len);

        // Local file header (30 bytes + filename)
        var lhdr: [30]u8 = [_]u8{0} ** 30;
        lhdr[0] = 'P'; lhdr[1] = 'K'; lhdr[2] = 0x03; lhdr[3] = 0x04;
        writeU16Le(&lhdr, 4, 20);    // version needed
        writeU16Le(&lhdr, 6, 0);     // general purpose bit flag
        writeU16Le(&lhdr, 8, 0);     // compression method (Store)
        writeU16Le(&lhdr, 10, 0);    // last mod time
        writeU16Le(&lhdr, 12, 0);    // last mod date
        writeU32Le(&lhdr, 14, entry.crc32);
        writeU32Le(&lhdr, 18, data_len); // compressed size
        writeU32Le(&lhdr, 22, data_len); // uncompressed size
        writeU16Le(&lhdr, 26, fname_len);
        writeU16Le(&lhdr, 28, 0);    // extra field length

        try zip_buf.appendSlice(allocator, &lhdr);
        try zip_buf.appendSlice(allocator, entry.name);
        try zip_buf.appendSlice(allocator, entry.data);
    }

    // Central directory start offset
    const cd_offset: u32 = @intCast(zip_buf.items.len);

    // Central directory entries
    for (entries.items) |entry| {
        const fname_len: u16 = @intCast(entry.name.len);
        const data_len: u32 = @intCast(entry.data.len);

        var cdhdr: [46]u8 = [_]u8{0} ** 46;
        cdhdr[0] = 'P'; cdhdr[1] = 'K'; cdhdr[2] = 0x01; cdhdr[3] = 0x02;
        writeU16Le(&cdhdr, 4, 20);   // version made by
        writeU16Le(&cdhdr, 6, 20);   // version needed
        writeU16Le(&cdhdr, 8, 0);    // general purpose bit flag
        writeU16Le(&cdhdr, 10, 0);   // compression method (Store)
        writeU16Le(&cdhdr, 12, 0);   // last mod time
        writeU16Le(&cdhdr, 14, 0);   // last mod date
        writeU32Le(&cdhdr, 16, entry.crc32);
        writeU32Le(&cdhdr, 20, data_len); // compressed size
        writeU32Le(&cdhdr, 24, data_len); // uncompressed size
        writeU16Le(&cdhdr, 28, fname_len);
        writeU16Le(&cdhdr, 30, 0);   // extra field length
        writeU16Le(&cdhdr, 32, 0);   // file comment length
        writeU16Le(&cdhdr, 34, 0);   // disk number start
        writeU16Le(&cdhdr, 36, 0);   // internal file attributes
        // external file attributes: executable flag on Unix
        const ext_attrs: u32 = if (builtin.os.tag == .windows) 0 else 0x81A40000;
        writeU32Le(&cdhdr, 38, ext_attrs);
        writeU32Le(&cdhdr, 42, entry.local_header_offset);

        try zip_buf.appendSlice(allocator, &cdhdr);
        try zip_buf.appendSlice(allocator, entry.name);
    }

    const cd_size: u32 = @intCast(zip_buf.items.len - cd_offset);
    const entry_count: u16 = @intCast(entries.items.len);

    // End of central directory (22 bytes)
    var eocd: [22]u8 = [_]u8{0} ** 22;
    eocd[0] = 'P'; eocd[1] = 'K'; eocd[2] = 0x05; eocd[3] = 0x06;
    writeU16Le(&eocd, 4, 0);             // disk number
    writeU16Le(&eocd, 6, 0);             // disk with start of central dir
    writeU16Le(&eocd, 8, entry_count);   // entries on this disk
    writeU16Le(&eocd, 10, entry_count);  // total entries
    writeU32Le(&eocd, 12, cd_size);      // size of central directory
    writeU32Le(&eocd, 16, cd_offset);    // offset of central directory
    writeU16Le(&eocd, 20, 0);            // comment length

    try zip_buf.appendSlice(allocator, &eocd);

    // Write to output file
    const out_file = try Io.Dir.createFile(cwd, io, output_filename, .{});
    defer out_file.close(io);
    try out_file.writeStreamingAll(io, zip_buf.items);

    std.debug.print("Package created: {s} ({d} bytes)\n", .{ output_filename, zip_buf.items.len });
}

// ---------------------------------------------------------------------------
// TAR writing (POSIX ustar format, uncompressed, pure Zig)
// ---------------------------------------------------------------------------

fn writeTarHeader(buf: *[512]u8, name: []const u8, size: usize, is_executable: bool) void {
    @memset(buf, 0);

    // Filename (bytes 0–99)
    const name_len = @min(name.len, 99);
    @memcpy(buf[0..name_len], name[0..name_len]);

    // File mode (bytes 100–107)
    const mode: []const u8 = if (is_executable) "0000755\x00" else "0000644\x00";
    @memcpy(buf[100..108], mode);

    // uid (bytes 108–115)
    @memcpy(buf[108..116], "0000000\x00");

    // gid (bytes 116–123)
    @memcpy(buf[116..124], "0000000\x00");

    // File size in octal (bytes 124–135)
    _ = std.fmt.bufPrint(buf[124..136], "{o:0>11}\x00", .{size}) catch {};

    // mtime (bytes 136–147) — zero
    @memcpy(buf[136..148], "00000000000\x00");

    // Checksum placeholder — 8 spaces (bytes 148–155)
    @memset(buf[148..156], ' ');

    // Type flag (byte 156) — '0' = regular file
    buf[156] = '0';

    // ustar magic (bytes 257–262)
    @memcpy(buf[257..262], "ustar");

    // version (bytes 263–264)
    @memcpy(buf[263..265], "00");

    // uname (bytes 265–296)
    @memcpy(buf[265..269], "root");

    // gname (bytes 297–328)
    @memcpy(buf[297..301], "root");

    // Compute checksum (sum of all bytes, checksum field already = 8 spaces)
    var checksum: u32 = 0;
    for (buf) |byte| checksum += byte;

    // Write checksum as 6-digit octal + null + space (bytes 148–155)
    _ = std.fmt.bufPrint(buf[148..155], "{o:0>6}\x00", .{checksum}) catch {};
    buf[155] = ' ';
}

fn appendTarFile(allocator: std.mem.Allocator, buf: *std.ArrayList(u8), name: []const u8, data: []const u8, executable: bool) !void {
    var header: [512]u8 = undefined;
    writeTarHeader(&header, name, data.len, executable);
    try buf.appendSlice(allocator, &header);
    try buf.appendSlice(allocator, data);
    // Pad to 512-byte boundary
    const remainder = data.len % 512;
    if (remainder != 0) {
        const padding = 512 - remainder;
        const zeros = [_]u8{0} ** 512;
        try buf.appendSlice(allocator, zeros[0..padding]);
    }
}

fn createTarPackage(
    allocator: std.mem.Allocator,
    io: Io,
    opts: PackageOptions,
    binary_data: []const u8,
    font_files: []const FontFile,
    manifest_data: ?[]const u8,
) !void {
    const cwd = Io.Dir.cwd();
    const output_filename = try std.fmt.allocPrint(
        allocator,
        "{s}/app-{s}.tar",
        .{ opts.output_dir, opts.version },
    );
    defer allocator.free(output_filename);

    std.debug.print("Creating TAR package: {s}\n", .{output_filename});

    var tar_buf = std.ArrayList(u8).empty;
    defer tar_buf.deinit(allocator);

    // Binary
    if (binary_data.len > 0) {
        const bin_name = if (builtin.os.tag == .windows) "app.exe" else "app";
        try appendTarFile(allocator, &tar_buf, bin_name, binary_data, true);
    }

    // Font files
    for (font_files) |ff| {
        try appendTarFile(allocator, &tar_buf, ff.archive_name, ff.data, false);
    }

    // Manifest
    if (manifest_data) |md| {
        try appendTarFile(allocator, &tar_buf, "manifest.json", md, false);
    }

    // End of archive: two 512-byte zero blocks
    const zeros = [_]u8{0} ** 1024;
    try tar_buf.appendSlice(allocator, &zeros);

    const out_file = try Io.Dir.createFile(cwd, io, output_filename, .{});
    defer out_file.close(io);
    try out_file.writeStreamingAll(io, tar_buf.items);

    std.debug.print("Package created: {s} ({d} bytes)\n", .{ output_filename, tar_buf.items.len });
}

// ---------------------------------------------------------------------------
// Font file collection
// ---------------------------------------------------------------------------

const FontFile = struct {
    archive_name: []const u8, // e.g. "fonts/regular.ttf"
    data: []const u8,
};

fn collectFonts(allocator: std.mem.Allocator, io: Io, fonts_dir: []const u8) ![]FontFile {
    const cwd = Io.Dir.cwd();
    var list = std.ArrayList(FontFile).empty;
    errdefer list.deinit(allocator);

    var dir = Io.Dir.openDir(cwd, io, fonts_dir, .{ .iterate = true }) catch |err| {
        if (err == error.FileNotFound or err == error.NotDir) {
            std.debug.print("  (fonts dir '{s}' not found — skipping fonts)\n", .{fonts_dir});
            return list.toOwnedSlice(allocator);
        }
        return err;
    };
    defer dir.close(io);

    var it = dir.iterate();
    while (try it.next(io)) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.name, ".ttf") and
            !std.mem.endsWith(u8, entry.name, ".TTF")) continue;

        const full_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ fonts_dir, entry.name });
        defer allocator.free(full_path);

        const data = try Io.Dir.readFileAlloc(cwd, io, full_path, allocator, .limited(64 * 1024 * 1024));
        const archive_name = try std.fmt.allocPrint(allocator, "fonts/{s}", .{entry.name});

        try list.append(allocator, .{ .archive_name = archive_name, .data = data });
    }

    return list.toOwnedSlice(allocator);
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const io = init.io;
    const cwd = Io.Dir.cwd();

    const args = try init.minimal.args.toSlice(init.arena.allocator());
    const opts = try parseArgs(args);

    // Ensure output directory exists
    Io.Dir.createDirPath(cwd, io, opts.output_dir) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };

    // Read binary (optional — warn if missing but continue)
    var binary_data: []const u8 = &[_]u8{};
    var binary_size: usize = 0;
    var binary_owned = false;
    if (opts.binary_path.len > 0) {
        if (Io.Dir.readFileAlloc(cwd, io, opts.binary_path, allocator, .limited(512 * 1024 * 1024))) |data| {
            binary_data = data;
            binary_size = data.len;
            binary_owned = true;
        } else |err| {
            std.debug.print("Warning: could not read binary '{s}': {s}\n", .{ opts.binary_path, @errorName(err) });
        }
    }
    defer if (binary_owned) allocator.free(binary_data);

    // Compute SHA256
    var sha256_hex: [64]u8 = [_]u8{'0'} ** 64;
    if (binary_size > 0) sha256_hex = sha256hex(binary_data);

    std.debug.print("Packaging app version {s}...\n", .{opts.version});
    std.debug.print("  Binary: {d} bytes\n", .{binary_size});
    std.debug.print("  SHA256: {s}\n", .{&sha256_hex});

    // Collect fonts
    const font_files = try collectFonts(allocator, io, opts.fonts_dir);
    defer {
        for (font_files) |ff| {
            allocator.free(ff.data);
            allocator.free(ff.archive_name);
        }
        allocator.free(font_files);
    }

    var fonts_total: usize = 0;
    for (font_files) |ff| fonts_total += ff.data.len;
    std.debug.print("  Fonts: {d} files, {d} bytes\n", .{ font_files.len, fonts_total });

    // Optional manifest JSON
    var manifest_data: ?[]u8 = null;
    defer if (manifest_data) |md| allocator.free(md);

    if (opts.include_manifest) {
        const ext = if (builtin.os.tag == .windows) "zip" else "tar";
        const download_url = try std.fmt.allocPrint(
            allocator,
            "https://example.com/app-{s}.{s}",
            .{ opts.version, ext },
        );
        defer allocator.free(download_url);

        manifest_data = try std.fmt.allocPrint(
            allocator,
            \\{{
            \\  "version": "{s}",
            \\  "download_url": "{s}",
            \\  "checksum_sha256": "{s}",
            \\  "release_notes": ""
            \\}}
            \\
        ,
            .{ opts.version, download_url, &sha256_hex },
        );
    }

    // Create archive
    if (builtin.os.tag == .windows) {
        try createZipPackage(allocator, io, opts, binary_data, font_files, manifest_data);
    } else {
        try createTarPackage(allocator, io, opts, binary_data, font_files, manifest_data);
    }

    const total = binary_size + fonts_total + (if (manifest_data) |md| md.len else 0);
    std.debug.print("  Total packaged: {d} bytes\n", .{total});
    std.debug.print("Packaging complete.\n", .{});
}
