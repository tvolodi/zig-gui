# R43 — M4-04: Image / icon rendering

> Roadmap item: M4-04  
> Depends on: module 09 (renderer/buildDrawList, GpuAtlas)  
> Read `00_constitution.md` before this file.

## Purpose

Allow RGBA images and single-color icons to be embedded in the UI and rendered as textured
quads. Images are stored in a separate `ImageAtlas` (an RGBA texture atlas distinct from the
glyph atlas). The draw-command vocabulary gains an `image_rect` command. Widget markup gains
an `<Image>` element kind and an `<Icon>` element kind (icon = image tinted with a color).

## What to build

### `ImageAtlas` — CPU-side RGBA atlas

Add `src/app/image_atlas.zig`:

```zig
pub const ImageId = u16;  // opaque handle; 0 is reserved (invalid)

pub const ImageRect = struct {
    /// Normalized UV coordinates of the image within the atlas (0..1).
    uv_x: f32,
    uv_y: f32,
    uv_w: f32,
    uv_h: f32,
    /// Original pixel dimensions of the image.
    pixel_w: u32,
    pixel_h: u32,
};

pub const ImageAtlas = struct {
    /// RGBA8 bitmap data. Width = height = ATLAS_SIZE (512 × 512 for v1).
    bitmap: []u8,           // owned; length = ATLAS_SIZE * ATLAS_SIZE * 4
    width:  u32,
    height: u32,
    /// Monotonically increasing counter; incremented on each mutation.
    /// Used to detect when the GPU atlas must be re-uploaded (mirrors GlyphAtlas.generation).
    generation: u32,
    gpa: std.mem.Allocator,

    /// Images registered so far. Indexed by ImageId - 1 (id 0 is invalid).
    entries: std.ArrayListUnmanaged(ImageRect),

    /// Simple shelf-packing cursor. x and y advance row by row.
    cursor_x: u32,
    cursor_y: u32,
    row_h:    u32,

    pub const ATLAS_SIZE: u32 = 512;

    pub fn init(gpa: std.mem.Allocator) error{OutOfMemory}!ImageAtlas

    pub fn deinit(self: *ImageAtlas) void

    /// Upload raw RGBA pixel data (packed, row-major, top-to-bottom) and return an ImageId.
    /// `pixels` must be `width * height * 4` bytes. Returns error.AtlasFull if it does not
    /// fit; returns error.OutOfMemory if the entries array cannot grow.
    pub fn addImage(
        self: *ImageAtlas,
        pixels: []const u8,
        width: u32,
        height: u32,
    ) error{ AtlasFull, OutOfMemory }!ImageId

    /// Look up an already-registered image's UV rect and dimensions.
    pub fn getRect(self: *const ImageAtlas, id: ImageId) ImageRect
};
```

Shelf packing is the simplest correct bin-packing algorithm: walk left-to-right, start a
new row when the current row is full. For v1 the 512×512 atlas is sufficient; atlas overflow
(`error.AtlasFull`) is a hard failure for v1 (no streaming or multiple pages).

### `GpuImageAtlas` — GPU upload wrapper

Mirror the `GpuAtlas` pattern from module 09 for the RGBA image atlas. Add to
`src/09/types.zig`:

```zig
pub const GpuImageAtlas = struct {
    image:      *anyopaque = undefined,  // VkImage
    image_view: *anyopaque = undefined,  // VkImageView
    sampler:    *anyopaque = undefined,  // VkSampler
    memory:     *anyopaque = undefined,  // VkDeviceMemory
    width:      u32 = 0,
    height:     u32 = 0,

    /// Upload the CPU ImageAtlas bitmap to a VK_FORMAT_R8G8B8A8_SRGB VkImage.
    /// Same upload pattern as GpuAtlas (staging buffer, layout transition, view+sampler).
    pub fn upload(
        gpa: std.mem.Allocator,
        device: *anyopaque,
        phys_device: *anyopaque,
        cmd_pool: *anyopaque,
        queue: *anyopaque,
        atlas: *const ImageAtlas,
    ) error{ OutOfMemory, GpuUploadFailed }!GpuImageAtlas

    pub fn deinit(self: *GpuImageAtlas, device: *anyopaque) void
};
```

Format is `VK_FORMAT_R8G8B8A8_SRGB` (not `R8_UNORM` like the glyph atlas) so colors are
sRGB-corrected automatically by the hardware.

### `image_rect` draw command

Extend [09.types.zig](../specs/09.types.zig) `DrawCommand`:

```zig
pub const ImageCmd = struct {
    dst:   Rect,   // destination pixel rect on screen
    uv:    Rect,   // source rect in normalized image-atlas coordinates (0..1)
    tint:  Color,  // multiplied with the sampled RGBA; use white (255,255,255,255) for no tint
};

pub const DrawCommand = union(enum) {
    filled_rect:     FilledRect,
    border_rect:     BorderRect,
    glyph:           GlyphCmd,
    set_scissor:     ScissorRect,
    restore_scissor: void,
    image_rect:      ImageCmd,   // NEW
};
```

### Shader / pipeline changes

The quad fragment shader (`quad.frag`) gains a third mode:

- `mode == 2`: sample `image_sampler` (bound to descriptor binding 1) at `uv`, multiply
  RGBA by `color` (the tint). Output the resulting RGBA with alpha blending.

Add a second combined-image-sampler binding (binding 1) to the descriptor set layout in
`VulkanBackend`. Binding 0 remains the glyph atlas (R8_UNORM); binding 1 is the image atlas
(R8G8B8A8_SRGB). Both are bound per frame.

Update `VulkanBackend.drawFrame` signature:

```zig
pub fn drawFrame(
    self: *VulkanBackend,
    commands: []const DrawCommand,
    glyph_atlas: *const GpuAtlas,
    image_atlas: *const GpuImageAtlas,
) void
```

In `QuadVertex.mode`: `0` = filled, `1` = glyph (glyph atlas), `2` = image (image atlas).

### New widget kinds

Add to [07.types.zig](../specs/07.types.zig):

```zig
pub const WidgetKind = enum {
    text, button, input, card, row, column, dropdown,
    checkbox, scrollview,
    image,  // NEW: renders an ImageId in the element's layout rect
    icon,   // NEW: renders an ImageId with a tint color
};

pub fn tagToKind(tag: []const u8) ?WidgetKind {
    // ...existing cases...
    if (eql(u8, tag, "Image")) return .image;
    if (eql(u8, tag, "Icon"))  return .icon;
    return null;
}
```

### Image state storage in `Scene`

Extend [07.types.zig](../specs/07.types.zig):

```zig
pub const ImageState = struct {
    image_id: ImageId = 0,    // 0 = not set; element renders nothing
    tint:     Color   = .{ .r = 255, .g = 255, .b = 255, .a = 255 },
};

pub const Scene = struct {
    // ...existing fields...
    _image_state: std.ArrayListUnmanaged(ImageState) = .empty,

    pub fn imageStateOf(self: *Scene, idx: u32) *ImageState
    pub fn setImage(self: *Scene, idx: u32, id: ImageId) void
    pub fn setImageTint(self: *Scene, idx: u32, tint: Color) void
};
```

### Integration in `buildDrawList`

For each `image` or `icon` element, emit one `image_rect` command:

```zig
const state = scene.imageStateOf(idx);
if (state.image_id != 0) {
    const rect = scene.elements.layout[idx].computed;
    const uv   = image_atlas.getRect(state.image_id);
    try cmds.append(alloc, .{ .image_rect = .{
        .dst  = rect,
        .uv   = .{ .x = uv.uv_x, .y = uv.uv_y, .w = uv.uv_w, .h = uv.uv_h },
        .tint = state.tint,
    }});
}
```

`buildDrawList` gains an `image_atlas: *const ImageAtlas` parameter (for UV lookup):

```zig
pub fn buildDrawList(
    alloc: std.mem.Allocator,
    scene: *Scene,
    glyph_atlas: *GlyphAtlas,
    image_atlas: *const ImageAtlas,
    tokens: Tokens,
) error{OutOfMemory}![]DrawCommand
```

### `App` changes

Add `image_atlas: ImageAtlas` and `gpu_image_atlas: GpuImageAtlas` to `App`. Initialize
after the platform. Re-upload `gpu_image_atlas` when `image_atlas.generation` changes
(same pattern as `GpuAtlas` re-upload on glyph-atlas generation change).

### Behavioral contract

| Situation | Behavior |
|---|---|
| `image_id == 0` (not set) | No draw command emitted; element is invisible |
| `tint == white` | Image drawn with original colors |
| `tint` with alpha < 255 | Image blended with alpha |
| Icon element | Same as image but tint color is typically the theme text color |
| ImageAtlas full | `addImage` returns `error.AtlasFull`; existing images unaffected |
| `image_atlas.generation` changes | `gpu_image_atlas` re-uploaded on next frame |

### Module location

```
src/app/image_atlas.zig      — ImageAtlas, ImageId, ImageRect
src/09/types.zig             — GpuImageAtlas, ImageCmd, image_rect in DrawCommand,
                               buildDrawList signature update
src/01/types.zig             — VulkanBackend.drawFrame signature update, descriptor binding 1,
                               quad.frag mode 2
src/09/shaders/quad.frag     — mode == 2 image sampling branch
src/app/types.zig            — ImageState, Scene._image_state
docs/specs/07.types.zig      — WidgetKind.image/icon, tagToKind, ImageState
docs/specs/09.types.zig      — GpuImageAtlas, ImageCmd, buildDrawList signature
docs/requirements/R43_image_icon_rendering.md
```

## Public API

New (`image_atlas.zig`):

```zig
pub const ImageId = u16;
pub const ImageRect = struct { uv_x, uv_y, uv_w, uv_h: f32; pixel_w, pixel_h: u32 }
pub const ImageAtlas = struct { ... pub fn init, deinit, addImage, getRect }
```

New in module 09:

```zig
pub const GpuImageAtlas = struct { pub fn upload, deinit }
pub const ImageCmd = struct { dst: Rect, uv: Rect, tint: Color }
// DrawCommand gains .image_rect tag
// buildDrawList gains image_atlas parameter
```

New in module 07:

```zig
pub const ImageState = struct { image_id: ImageId, tint: Color }
pub fn imageStateOf(self: *Scene, idx: u32) *ImageState
pub fn setImage(self: *Scene, idx: u32, id: ImageId) void
pub fn setImageTint(self: *Scene, idx: u32, tint: Color) void
// WidgetKind gains .image and .icon
```

## Non-goals (DO NOT implement — INV-5.4)

- **No SVG rendering** — only pre-rasterized RGBA bitmaps.
- **No animated images (GIF/APNG)** — static bitmaps only.
- **No image scaling quality** — nearest or bilinear is GPU default; no Lanczos or mipmap.
- **No image loading from disk** — `addImage` accepts raw RGBA pixels; file I/O is the
  caller's responsibility. No `stb_image` dependency (INV-5.6 — no new deps).
- **No multiple atlas pages** — one 512×512 RGBA atlas only. `error.AtlasFull` is a hard
  stop for v1.
- **No nine-patch / sliced images** — images fill the entire `dst` rect.
- **No image cropping in markup** — object-fit / overflow crop is post-v1.
- **No icon font / ligature rendering** — icons are pre-rasterized RGBA bitmaps.

## Acceptance criteria

1. `zig build test-09-unit` passes. New CPU-only tests:
   - `ImageAtlas.addImage` on a blank atlas returns a non-zero `ImageId`.
   - `ImageAtlas.getRect` returns UV coordinates that cover the correct subregion.
   - Adding two images side-by-side produces non-overlapping UV rects.
   - Filling the atlas (adding more pixels than `ATLAS_SIZE²`) returns `error.AtlasFull`.
   - `buildDrawList` on a scene with an image element emits one `image_rect` command with
     correct UV and tint values.
   - An image element with `image_id == 0` emits no `image_rect` command.

2. GPU integration test (skip if no Vulkan):
   - `GpuImageAtlas.upload` succeeds on a real device.
   - `drawFrame` with an `image_rect` command completes without Vulkan validation errors.
   - A 32×32 white RGBA image with a red tint renders as a red quad.

3. `setImage` and `setImageTint` mark the element dirty.

4. No memory leaks: `ImageAtlas.deinit` and `GpuImageAtlas.deinit` free all resources.

5. Checklist fully ticked.

## Open questions

None. The 512×512 RGBA atlas covers v1 icon sets. Larger or streaming atlases are post-v1.
