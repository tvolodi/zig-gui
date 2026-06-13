# RD2 — M13-03: Subpixel glyph rendering

> Roadmap item: M13-03  
> Depends on: 02 (glyph atlas), 09 (renderer)  
> Read `00_constitution.md` before this file.

## Purpose

Render glyphs using RGB subpixel anti-aliasing for sharper text at small font sizes (12–14 px).
On LCD displays, each pixel is composed of three vertically-aligned subpixels (red, green,
blue). Standard grayscale anti-aliasing treats the pixel as a single unit, effectively
discarding two-thirds of the horizontal resolution. Subpixel rendering uses each color channel
independently, tripling the effective horizontal resolution of glyph edges.

Without subpixel rendering, small UI text (labels, button text, table cells) appears blurry
compared to native OS-rendered text on the same display.

## What to build

### Subpixel atlas in module 02

The glyph atlas (`GlyphAtlas`) currently rasterizes each glyph at native resolution using
`stbtt_GetCodepointBitmap`, producing a single-channel (grayscale) bitmap packed into the
atlas's red channel.

For subpixel rendering, each glyph is rasterized at **3x horizontal resolution**:

1. `stbtt_GetCodepointBitmap` is called with a scale that produces 3x the requested pixel
   width. The resulting grayscale bitmap is 3x wider than the normal glyph bitmap.
2. For each group of 3 adjacent horizontal pixels in the wide bitmap, the values are
   compressed into one RGB pixel:
   - `R = pixel[3*i + 0]` (left subpixel coverage)
   - `G = pixel[3*i + 1]` (center subpixel coverage)
   - `B = pixel[3*i + 2]` (right subpixel coverage)
3. The resulting RGB bitmap has the same width as the standard glyph but stores subpixel
   coverage in the three color channels.

New function on `GlyphAtlas` (module 02):

```zig
/// Rasterize a glyph at 3× horizontal resolution and pack into RGB channels.
/// Returns a slice of `width * 3 * height` bytes (to be packed into `width * height * 3` RGB).
pub fn rasterizeSubpixel(
    self: *GlyphAtlas,
    glyph_index: u32,
    font_size_px: f32,
) SubpixelBitmap { ... }
```

`SubpixelBitmap` is a struct:
```zig
pub const SubpixelBitmap = struct {
    width: u32,
    height: u32,
    /// RGBRGBRGB... packed bytes. width * height * 3 bytes.
    rgb: []const u8,
};
```

The subpixel atlas region is packed separately from the grayscale atlas. A new field on
`GlyphAtlas` tracks the subpixel atlas dimensions and pixel data.

### Activation gate

Subpixel rendering is only applied when ALL of these conditions are true:
- `AppOptions.subpixel_text == true` (default: `false` — off by default for safety).
- The glyph's requested font size is in the range 12–14 px (inclusive).
- The display is known to use RGB subpixel layout (assumed for all standard LCD monitors).

Larger text (15+ px) uses standard grayscale anti-aliasing because subpixel rendering
provides diminishing returns at larger sizes and can introduce color fringing.

### New shader mode 3: subpixel glyph (module 09 — `quad.frag`)

```glsl
if (fragMode == 3u) {
    // Subpixel glyph: texture RGB channels hold independent subpixel coverage.
    vec3 coverage = texture(atlasTexture, fragUV).rgb;
    outColor = vec4(fragColor.rgb * coverage, fragColor.a);
}
```

The atlas texture format changes from `VK_FORMAT_R8_UNORM` to `VK_FORMAT_R8G8B8A8_UNORM`
for the subpixel region, OR a separate atlas texture is used for subpixel data. For v1,
the simplest approach is to use a **separate region** within the existing atlas texture
but with the texture format upgraded to `VK_FORMAT_R8G8B8A8_UNORM` globally. The grayscale
glyphs continue to work because the shader reads only `.r` for mode 1, and the RGBA texture
provides that channel identically.

Actually, upgrading the entire atlas to RGBA wastes memory. Better approach for v1:
use a **separate atlas** (`subpixel_atlas`) for subpixel glyphs. The fragment shader
binds a second texture sampler at `binding = 1` for subpixel data.

```glsl
layout(binding = 0) uniform sampler2D atlasTexture;       // grayscale (mode 1)
layout(binding = 1) uniform sampler2D subpixelTexture;    // RGB subpixel (mode 3)
```

### Draw command changes (module 01)

No new draw command variant is needed. The existing `GlyphCmd` is reused. The glyph's
`uv` field points into either the grayscale atlas or the subpixel atlas depending on
whether subpixel rendering is active for that glyph. The `mode` on the quad vertex is
set to 3 instead of 1 for subpixel glyphs.

A new field on the scene or renderer tracks whether the subpixel atlas is populated:

```zig
// On GpuAtlas (module 01/09):
subpixel_atlas: ?GpuAtlas = null,
subpixel_atlas_ready: bool = false,
```

### Renderer changes (module 09 — `buildDrawList`)

In `buildDrawList`, when emitting a glyph command:

1. Check `AppOptions.subpixel_text` and the glyph's font size.
2. If subpixel is active for this glyph:
   - Look up the glyph in the subpixel atlas.
   - If the glyph is not yet in the subpixel atlas, rasterize it via
     `GlyphAtlas.rasterizeSubpixel` and pack it (lazy population, same as the grayscale
     atlas).
   - Emit the glyph quad with mode 3, UV pointing into the subpixel atlas region.
3. Otherwise, use mode 1 as before.

### AppOptions (module 01 or app)

```zig
// On AppOptions:
subpixel_text: bool = false,
```

### Vulkan descriptor set changes

The quad pipeline's descriptor set layout gains a second image sampler binding (binding = 1)
for the subpixel texture. This is bound only when `subpixel_atlas_ready` is true. If no
subpixel atlas exists, the binding points to a 1x1 black texture (harmless).

## Module location

```
src/02/types.zig         — SubpixelBitmap struct, GlyphAtlas.rasterizeSubpixel(), subpixel packing
src/01/types.zig         — subpixel_atlas field on GpuAtlas, subpixel_text on AppOptions, QuadVertex mode 3
src/09/types.zig         — subpixel atlas upload, buildDrawList subpixel glyph emission, second texture binding
src/09/shaders/quad.vert — pass through fragUV for subpixel texture binding
src/09/shaders/quad.frag — mode 3: subpixel glyph (RGB coverage)
src/app/app.zig          — subpixel_text option on AppOptions, wire subpixel atlas init/deinit
docs/specs/09.types.zig  — spec mirror
docs/requirements/RD2_subpixel_glyph_rendering.md
```

## Public API changes

```zig
// Module 02
pub const SubpixelBitmap = struct { width: u32, height: u32, rgb: []const u8 };
// GlyphAtlas gains: pub fn rasterizeSubpixel(...) SubpixelBitmap

// Module 01 — GpuAtlas gains:
subpixel_atlas: ?*anyopaque = null,      // VkImage for subpixel atlas
subpixel_atlas_view: ?*anyopaque = null,  // VkImageView
subpixel_atlas_sampler: ?*anyopaque = null,
subpixel_atlas_ready: bool = false,

// AppOptions gains:
subpixel_text: bool = false,
```

## Behavioral contract

| Situation | Behavior |
|---|---|
| `subpixel_text = false` (default) | All glyphs use mode 1 (grayscale anti-aliasing), unchanged |
| `subpixel_text = true`, font size 12 px | Glyphs rasterized at 3× horizontal resolution, packed into RGB atlas, rendered with mode 3 |
| `subpixel_text = true`, font size 14 px | Same as 12 px |
| `subpixel_text = true`, font size 16 px | Glyph uses mode 1 (grayscale), even with subpixel enabled — outside 12–14 px range |
| `subpixel_text = true`, font size 10 px | Glyph uses mode 1 — below the 12 px minimum |
| Glyph not yet in subpixel atlas | Lazy-rasterized on first use (same pattern as grayscale atlas) |
| Subpixel glyph at non-integer position | Color fringing may occur — this is acceptable for v1; position snapping is a non-goal |

## Non-goals (DO NOT implement — INV-5.4)

- **No ClearType tuning per display** — no per-monitor subpixel configuration.
- **No BGR, V-RGB, or other subpixel layouts** — only RGB horizontal subpixel layout is
  supported. Non-RGB layouts render with grayscale fallback.
- **No subpixel rendering for fonts > 16 px.**
- **No subpixel rendering for fonts < 12 px.**
- **No subpixel position snapping** — glyph positions are not rounded to subpixel boundaries;
  the atlas stores 3× horizontal data but the glyph quad may be placed at a fractional pixel.
- **No subpixel vertical** — only horizontal subpixel rendering (matching LCD pixel geometry).
  Vertical subpixel (e.g., rotated displays) is a non-goal.
- **No hardware gamma correction** — the shader does not apply per-channel gamma before
  blending. Standard sRGB framebuffer handles gamma.
- **No user override of the 12–14 px range.**
- **No per-glyph subpixel toggle** — subpixel is all-or-nothing per font size.

## Acceptance criteria

1. `zig build` passes; subpixel SPIR-V shader compiles; `zig build test-02` passes with
   the new `rasterizeSubpixel` function returning correct dimensions.

2. Unit tests in `src/02/02_test.zig` cover:
   - `rasterizeSubpixel` for ASCII 'A' at 12 px returns a bitmap with `width * 3` bytes per row compressed into `width * 3` RGB bytes.
   - The grayscale atlas rasterization is unchanged (no regression).

3. Unit tests in `src/09/09_test.zig` cover:
   - `buildDrawList` emits mode-3 quad vertices for a 12 px glyph when `subpixel_text = true`.
   - `buildDrawList` emits mode-1 quad vertices for a 12 px glyph when `subpixel_text = false`.
   - `buildDrawList` emits mode-1 for a 20 px glyph regardless of `subpixel_text`.

4. Visual (manual, on an LCD display): demo app with `subpixel_text = true` shows noticeably
   sharper text at 12 px and 14 px compared to `subpixel_text = false`. No color fringing
   visible at normal viewing distance.

5. No regression: text with `subpixel_text = false` renders identically to before.
