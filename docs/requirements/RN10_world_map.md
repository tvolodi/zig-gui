# RN10 — World map / geographic visualization

> Status: `planned` — Milestone 27 extension.
> Blocking: TailAdmin Ecommerce demo screen (Screen 12, "Customers Demographic" widget).
> Read `docs/specs/00_constitution.md` before this file.
> Use project-relative paths only. Never use absolute Windows paths starting with `c:\`.

## 1. What to build

Add **simplified world map rendering** to `src/13/marks.zig`. A world map chart renders:
1. An ocean background (filled rect in a light blue-gray tone).
2. Simplified continent shapes as **filled polygons** using `FilledPathCmd` draw commands.
   Continent outline data is **hardcoded** as normalized (0–1) coordinate arrays.
3. **Dot markers** for data points (small filled circles at specific lat/lng positions).

The map is NOT interactive, NOT a true choropleth, and does NOT download any data. It uses
hardcoded simplified continent outlines sufficient to be visually recognizable.

## 2. Continent coordinate data

Continent coordinates are in **normalized map space**: x ∈ [0, 1] (longitude −180 to +180
mapped to 0 to 1), y ∈ [0, 1] (latitude +90 to −90 mapped to 0 to 1, i.e., north at top
with Y increasing downward).

Screen coordinates are computed as:
```
screen.x = plot_rect.x + norm_x * plot_rect.w
screen.y = plot_rect.y + norm_y * plot_rect.h
```

Hardcoded continent simplified polygons (normalized x, y):

```
North America: 14 points
  (0.05,0.12),(0.26,0.08),(0.32,0.14),(0.30,0.22),(0.26,0.28),(0.20,0.35),
  (0.15,0.42),(0.12,0.50),(0.10,0.42),(0.08,0.35),(0.06,0.28),(0.05,0.22),
  (0.04,0.16),(0.05,0.12)

South America: 10 points
  (0.22,0.50),(0.30,0.48),(0.32,0.55),(0.30,0.68),(0.25,0.78),(0.20,0.72),
  (0.17,0.62),(0.18,0.54),(0.20,0.50),(0.22,0.50)

Europe: 8 points
  (0.46,0.14),(0.52,0.12),(0.55,0.18),(0.54,0.24),(0.50,0.26),(0.46,0.24),
  (0.44,0.18),(0.46,0.14)

Africa: 12 points
  (0.48,0.28),(0.55,0.26),(0.58,0.32),(0.58,0.42),(0.55,0.55),(0.52,0.65),
  (0.49,0.68),(0.46,0.62),(0.44,0.50),(0.44,0.38),(0.46,0.30),(0.48,0.28)

Asia: 16 points
  (0.55,0.12),(0.72,0.08),(0.82,0.12),(0.88,0.20),(0.88,0.30),(0.82,0.36),
  (0.74,0.38),(0.68,0.42),(0.62,0.38),(0.58,0.32),(0.56,0.24),(0.54,0.18),
  (0.54,0.14),(0.55,0.12)

Australia: 8 points
  (0.75,0.58),(0.82,0.56),(0.86,0.60),(0.86,0.68),(0.82,0.72),(0.76,0.70),
  (0.73,0.64),(0.75,0.58)
```

## 3. Data point markers

A `MapMarker` is a single dot on the map:
```zig
pub const MapMarker = struct {
    /// Normalized x position [0, 1] (longitude −180→0 to +180→1).
    norm_x: f32,
    /// Normalized y position [0, 1] (latitude +90→0 to −90→1).
    norm_y: f32,
    /// Dot radius in pixels.
    radius: f32 = 4.0,
    /// Semantic color token.
    color_token: []const u8 = "accent",
};
```

## 4. Public API

In `src/13/marks.zig`, add:

```zig
pub const MapMarker = struct {
    norm_x: f32,
    norm_y: f32,
    radius: f32 = 4.0,
    color_token: []const u8 = "accent",
};

/// RN10 — Render a simplified world map into `out`.
/// Continent outlines are hardcoded normalized coordinates.
/// `markers`: optional data point dots to overlay on the map.
/// `ocean_token`: semantic color token for the background (e.g. "surface").
/// `land_token`: semantic color token for continent fills (e.g. "raised" or "axis").
pub fn renderWorldMap(
    markers: []const MapMarker,
    ocean_token: []const u8,
    land_token: []const u8,
    frame: *const ChartFrame,
    out: *std.ArrayListUnmanaged(DrawCmd),
    allocator: std.mem.Allocator,
) !void
```

Add `map` to `ChartKind` in `src/13/chart.zig`:
```zig
pub const ChartKind = enum { line, bar, area, scatter, pie, gauge, map };
```

Add map-specific fields to `Chart`:
```zig
/// RN10 — Map data point markers.
map_markers: []const MapMarker = &.{},
/// RN10 — Ocean background color token.
map_ocean_token: []const u8 = "surface",
/// RN10 — Land fill color token.
map_land_token: []const u8 = "axis",
```

Add the map case to `renderChart`:
```zig
.map => try renderWorldMap(chart.map_markers, chart.map_ocean_token, chart.map_land_token, frame, out, allocator),
```

Import `MapMarker` from marks.zig into chart.zig:
```zig
pub const MapMarker = marks_mod.MapMarker;
```

## 5. Acceptance criteria

- `zig build` exits 0.
- `Chart{ .kind = .map, ... }.render(frame, &cmds, alloc)` emits at least 7 draw commands
  (1 ocean background + 6 continent fills, possibly more for markers).
- The ocean background is the first command (`filled_rect` or `aa_filled_rect`).
- Adding 2 markers emits 2 additional arc commands for the dots.
- No existing tests are broken.

## 6. Non-goals

- No true choropleth (country-level coloring based on data values).
- No country border lines or accurate outlines.
- No zoom or pan interaction.
- No lat/lng label rendering.
