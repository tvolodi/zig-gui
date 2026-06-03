//! R43 — Image / icon rendering — ImageAtlas (CPU-side RGBA atlas).
//!
//! A simple shelf-packing 512×512 RGBA atlas.
//! ImageId 0 is reserved/invalid; allocated IDs start at 1.

const std = @import("std");

pub const ImageId = u16;

pub const ImageRect = struct {
    /// Normalized UV coordinates (0..1) of the image within the atlas.
    uv_x: f32,
    uv_y: f32,
    uv_w: f32,
    uv_h: f32,
    /// Original pixel dimensions.
    pixel_w: u32,
    pixel_h: u32,
};

pub const ImageAtlas = struct {
    /// RGBA8 bitmap. Length = ATLAS_SIZE * ATLAS_SIZE * 4.
    bitmap: []u8,
    width: u32,
    height: u32,
    /// Incremented on each mutation so callers can detect re-upload need.
    generation: u32,
    gpa: std.mem.Allocator,

    /// Images registered so far. Indexed by ImageId - 1 (id 0 is invalid).
    entries: std.ArrayListUnmanaged(ImageRect),

    /// Shelf packing cursor.
    cursor_x: u32,
    cursor_y: u32,
    row_h: u32,

    pub const ATLAS_SIZE: u32 = 512;

    pub fn init(gpa: std.mem.Allocator) error{OutOfMemory}!ImageAtlas {
        const bitmap = try gpa.alloc(u8, ATLAS_SIZE * ATLAS_SIZE * 4);
        @memset(bitmap, 0);
        return ImageAtlas{
            .bitmap = bitmap,
            .width = ATLAS_SIZE,
            .height = ATLAS_SIZE,
            .generation = 0,
            .gpa = gpa,
            .entries = .empty,
            .cursor_x = 0,
            .cursor_y = 0,
            .row_h = 0,
        };
    }

    pub fn deinit(self: *ImageAtlas) void {
        self.gpa.free(self.bitmap);
        self.entries.deinit(self.gpa);
    }

    /// Upload raw RGBA pixel data (packed, row-major, top-to-bottom).
    /// `pixels` must be `width * height * 4` bytes.
    pub fn addImage(
        self: *ImageAtlas,
        pixels: []const u8,
        img_w: u32,
        img_h: u32,
    ) error{ AtlasFull, OutOfMemory }!ImageId {
        // Move to next shelf row if image doesn't fit horizontally.
        if (self.cursor_x + img_w > self.width) {
            self.cursor_y += self.row_h;
            self.cursor_x = 0;
            self.row_h = 0;
        }
        // Check vertical fit.
        if (self.cursor_y + img_h > self.height) return error.AtlasFull;
        if (self.cursor_x + img_w > self.width) return error.AtlasFull;

        // Blit RGBA pixels into atlas.
        var row: u32 = 0;
        while (row < img_h) : (row += 1) {
            const src_start = row * img_w * 4;
            const dst_start = ((self.cursor_y + row) * self.width + self.cursor_x) * 4;
            const src_slice = pixels[src_start .. src_start + img_w * 4];
            const dst_slice = self.bitmap[dst_start .. dst_start + img_w * 4];
            @memcpy(dst_slice, src_slice);
        }

        const atlas_w_f = @as(f32, @floatFromInt(self.width));
        const atlas_h_f = @as(f32, @floatFromInt(self.height));
        const rect = ImageRect{
            .uv_x = @as(f32, @floatFromInt(self.cursor_x)) / atlas_w_f,
            .uv_y = @as(f32, @floatFromInt(self.cursor_y)) / atlas_h_f,
            .uv_w = @as(f32, @floatFromInt(img_w)) / atlas_w_f,
            .uv_h = @as(f32, @floatFromInt(img_h)) / atlas_h_f,
            .pixel_w = img_w,
            .pixel_h = img_h,
        };

        try self.entries.append(self.gpa, rect);
        const id: ImageId = @intCast(self.entries.items.len); // 1-based

        self.cursor_x += img_w;
        if (img_h > self.row_h) self.row_h = img_h;
        self.generation +%= 1;

        return id;
    }

    pub fn getRect(self: *const ImageAtlas, id: ImageId) ImageRect {
        if (id == 0 or id > self.entries.items.len) {
            return ImageRect{ .uv_x = 0, .uv_y = 0, .uv_w = 0, .uv_h = 0, .pixel_w = 0, .pixel_h = 0 };
        }
        return self.entries.items[id - 1];
    }
};
