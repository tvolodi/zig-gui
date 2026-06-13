# RD3 — M13-04: Vector icons via SDF atlas

> Roadmap item: M13-04  
> Depends on: 09 (renderer), 07 (Icon widget)  
> Read `00_constitution.md` before this file.

## Purpose

Add a Signed Distance Field (SDF) atlas for rendering single-color icons from SVG path data.
Icons stored as SDF textures can be scaled to any size without re-rasterization and render
with smooth, anti-aliased edges. This replaces the current approach where icons are rendered
as Unicode codepoint glyphs from the text atlas, which have fixed rasterization size and
no built-in edge anti-aliasing.

The SDF atlas is pre-built at compile time from a fixed set of ~20 common icons (chevron,
check, cross, search, menu, plus, minus, arrow-up/down/left/right, home, user, settings,
info, warning, close, calendar, clock, star). This covers the icon needs of all existing
components (dropdown chevrons, modal close button, tooltip info icon, etc.).

## What to build

### `SdfAtlas` struct (module 09)

```zig
pub const SdfAtlas = struct {
    /// Packed SDF pixel data. width * height bytes, each 0–255 where 128 = edge.
    pixels: []const u8,
    width: u32,
    height: u32,
    /// Mapping from icon name to atlas UV region (Rect09, normalized 0–1).
    entries: std.StringHashMapUnmanaged(Rect09),

    pub fn init(allocator: std.mem.Allocator) !SdfAtlas { ... }
    pub fn deinit(self: *SdfAtlas) void { ... }
    /// Look up an icon by name. Returns the UV rect in the atlas texture (0–1 range)
    /// or null if the icon name is unknown.
    pub fn lookup(self: *const SdfAtlas, name: []const u8) ?Rect09 { ... }
};
```

The SDF atlas is a single-channel texture (`VK_FORMAT_R8_UNORM`) where each pixel stores
the signed distance to the nearest edge of the icon shape, normalized to 0–255:

- 0 (0.0) = deep inside the shape
- 128 (0.5) = exactly on the edge
- 255 (1.0) = deep outside the shape

This is the standard SDF encoding used by Valve (Signed Distance Field text), Mapbox
(SDF icons), and most GPU text renderers.

### Pre-built atlas generation

For v1, the SDF atlas is pre-generated offline and embedded as a static byte array.
A standalone Zig tool (`tools/generate_sdf_atlas.zig`) does the following:

1. Reads a set of SVG path strings (hardcoded for v1; ~20 icons).
2. For each icon, rasterizes the SVG path at a reference resolution (64×64 px) using
   a simple scanline rasterizer (no external SVG library needed — the paths are
   hardcoded as Zig path data, not parsed from `.svg` files at runtime).
3. Computes the SDF: for each pixel in the 64×64 grid, compute the Euclidean distance
   to the nearest edge of the rasterized shape. Signed positive inside, negative outside,
   remapped to 0–255.
4. Packs all 64×64 icons into a single atlas texture (e.g., 512×512 = up to 64 icons).
5. Outputs a Zig source file (`src/09/sdf_atlas_data.zig`) containing:
   - The packed pixel data as a `[]const u8` literal.
   - A map from icon name string to atlas UV rect.

This tool is run once (or when icons change) and the output is checked into the repository.
Runtime SVG parsing is explicitly NOT supported (see Non-goals).

### New draw command (module 01)

```zig
pub const SdfIconCmd = struct {
    dst: Rect09,    // screen-space destination rect
    uv: Rect09,     // UV region in the SDF atlas texture (0–1 normalized)
    color: Color09, // icon fill color
};

// DrawCommand gains:
sdf_icon: SdfIconCmd,
```

Each `sdf_icon` draw command renders one quad with mode 4 in the fragment shader.

### New shader mode 4: SDF icon (module 09 — `quad.frag`)

```glsl
if (fragMode == 4u) {
    float dist = texture(sdfTexture, fragUV).r;  // 0.0 = inside, 0.5 = edge, 1.0 = outside
    float smoothing = 0.5 / min(dstWidthPx, dstHeightPx); // adaptive smoothing
    float alpha_val = 1.0 - smoothstep(0.5 - smoothing, 0.5 + smoothing, dist);
    outColor = vec4(fragColor.rgb, fragColor.a * alpha_val);
}
```

The `smoothing` factor is computed from the destination rect size in pixels so that
anti-aliasing adapts to the rendered size: a 16×16 icon gets a ~0.5 px feather, while
a 64×64 icon gets a ~0.125 px feather.

The SDF atlas texture is bound at `binding = 2` in the descriptor set:
```glsl
layout(binding = 2) uniform sampler2D sdfTexture;
```

### Descriptor set change

The quad pipeline descriptor set layout gains a third image sampler (`binding = 2`).
Total bindings after RD3: `binding = 0` (glyph atlas), `binding = 1` (subpixel atlas),
`binding = 2` (SDF atlas).

The SDF texture has its own sampler with `VK_FILTER_LINEAR` for smooth interpolation
at non-integer scales.

### Icon widget integration (module 07)

The existing `Icon` widget kind (from M7) currently renders as a Unicode codepoint glyph.
A new field is added:

```zig
// On the Icon component:
icon_name: ?[]const u8 = null,  // e.g. "chevron-down", "check", "search"
```

When `icon_name` is set, the renderer looks up the name in `SdfAtlas.lookup()` and emits
an `sdf_icon` draw command instead of a `glyph` draw command. When `icon_name` is null,
the existing Unicode-codepoint path is used (backward compatibility).

### Renderer changes (module 09 — `buildDrawList`)

In `buildDrawList`, when visiting an `Icon` widget:

1. If `icon.icon_name != null`:
   - Look up `sdf_atlas.lookup(icon.icon_name.?)`.
   - If found, emit `DrawCommand{ .sdf_icon = SdfIconCmd{ .dst = ..., .uv = entry, .color = ... } }`.
   - If not found, fall back to the Unicode glyph path (silently degrade — do not crash).
2. If `icon.icon_name == null`:
   - Emit the existing `glyph` path (unchanged behavior for Unicode icons).

### GPU upload (module 09)

A new function `GpuSdfAtlas` mirrors `GpuAtlas` for the SDF texture:

```zig
pub const GpuSdfAtlas = struct {
    image: ?*anyopaque, image_view: ?*anyopaque, sampler: ?*anyopaque,
    memory: ?*anyopaque, width: u32, height: u32,

    pub fn upload(gpa, device, phys_device, cmd_pool, queue, atlas: *const SdfAtlas) !GpuSdfAtlas { ... }
    pub fn deinit(self: *GpuSdfAtlas, device: *anyopaque) void { ... }
};
```

The upload uses `vkUploadAtlas` with `VK_FORMAT_R8_UNORM` (same as the glyph atlas) and a
`VK_FILTER_LINEAR` sampler (different from the glyph atlas's `VK_FILTER_NEAREST`).

### App wiring (src/app/app.zig)

```zig
// AppInner gains:
sdf_atlas: SdfAtlas,
gpu_sdf_atlas: ?GpuSdfAtlas = null,
```

`SdfAtlas.init(allocator)` is called at app startup. The GPU-side upload happens after
the Vulkan device is ready. `gpu_sdf_atlas` is bound to the quad pipeline descriptor set
alongside the glyph atlas.

## Module location

```
tools/generate_sdf_atlas.zig  — offline SDF atlas generation tool (run once, output checked in)
src/09/sdf_atlas_data.zig     — generated: packed pixel data + name→UV map
src/01/types.zig              — SdfIconCmd struct, .sdf_icon DrawCommand variant
src/09/types.zig              — SdfAtlas struct + lookup(), GpuSdfAtlas + upload(), buildDrawList emits sdf_icon
src/09/shaders/quad.vert      — pass through fragUV for binding=2
src/09/shaders/quad.frag      — mode 4: SDF icon with smoothstep
src/07/types.zig              — icon_name field on Icon widget
src/app/app.zig               — SdfAtlas + GpuSdfAtlas init/deinit, bind to descriptor set
docs/specs/09.types.zig       — spec mirror
docs/requirements/RD3_vector_icons_sdf.md
```

## Public API changes

```zig
// Module 01
pub const SdfIconCmd = struct { dst: Rect09, uv: Rect09, color: Color09 };
// DrawCommand gains: sdf_icon: SdfIconCmd,

// Module 09
pub const SdfAtlas = struct { ... pub fn lookup(name: []const u8) ?Rect09 ... };
pub const GpuSdfAtlas = struct { ... pub fn upload(...) !GpuSdfAtlas ... };

// Module 07 Icon widget gains:
icon_name: ?[]const u8 = null,
```

## Behavioral contract

| Situation | Behavior |
|---|---|
| Icon: `icon_name = "chevron-down"` | Looked up in SdfAtlas; if found, rendered as SDF icon with smooth edges at any size |
| Icon: `icon_name = "nonexistent"` | Fallback to Unicode codepoint glyph (or renders nothing if no codepoint set) |
| Icon: `icon_name = null` | Existing Unicode codepoint path used — no SDF lookup |
| SDF icon rendered at 4× its atlas resolution | Smooth upscaling via linear texture filtering + SDF edge smoothing |
| SDF icon rendered at 0.5× its atlas resolution | Still smooth; SDF smoothing adapts to the smaller pixel footprint |
| Icon color changes (e.g., hover state) | SdfIconCmd.color updated; re-render uses new color — no atlas change needed |
| SDF atlas not yet uploaded to GPU | Icons fall back to Unicode glyphs; app does not crash |

## Non-goals (DO NOT implement — INV-5.4)

- **No runtime SVG parsing** — SVG path data is processed offline by `generate_sdf_atlas.zig`.
  The runtime never parses SVG.
- **No multi-color icons** — icons are single-color (the `color` field on `SdfIconCmd`).
  Multi-color icons would require a separate atlas layer per color or an RGBA atlas.
- **No icon animation** — no morphing, rotation, or animated icon states.
- **No user-provided icons at runtime** — the icon set is fixed at compile time.
- **No more than ~64 icons in the atlas** — the atlas is 512×512 with 64×64 cells, giving
  a maximum of 64 icons. v1 ships with ~20.
- **No variable-width icons** — all SDF icons share the same cell size (64×64). Non-square
  icons are padded to fit.
- **No SDF text rendering** — SDF is for icons only. Text uses the glyph atlas (grayscale
  or subpixel).
- **No distance-field generation at runtime** — the SDF atlas is pre-computed offline.

## Acceptance criteria

1. `zig build` passes; `tools/generate_sdf_atlas.zig` compiles and produces valid output
   when invoked standalone.

2. Unit tests in `src/09/09_test.zig` cover:
   - `SdfAtlas.lookup("check")` returns a valid UV rect.
   - `SdfAtlas.lookup("nonexistent")` returns null.
   - `buildDrawList` emits `.sdf_icon` (not `.glyph`) when Icon has `icon_name` set and
     the name is found in the atlas.
   - `buildDrawList` falls back to `.glyph` when `icon_name` is set but not found.

3. Unit tests in `src/07/07_test.zig` cover:
   - Icon widget with `icon_name = "chevron-down"` stores the name correctly.
   - Icon widget with `icon_name = null` has no change in behavior.

4. Visual: demo app screen shows an icon row with at least 5 SDF icons (chevron, check,
   cross, search, menu) at 16×16, 24×24, and 48×48 sizes. All sizes render clear edges
   without blur or stair-stepping.

5. Visual: hover a SDF icon (color change via pseudo-state) — the icon re-renders in the
   new color with no texture reload.

6. No regression: existing Unicode-codepoint icons render identically to before.
