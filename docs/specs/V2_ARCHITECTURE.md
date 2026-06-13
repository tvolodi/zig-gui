# V2 — Architecture

> Companion to `V2_constitution_amendment.md`. Read `00_constitution.md` and the amendment
> first. This document describes *how* the five v2 features fit the existing architecture
> without disturbing its load-bearing decisions (INV-3.x, INV-2.3, INV-4.4). It is a design
> document only; per-feature behavior lives in the `RJ*`, `RK*`, `RL*`, `RM*` requirement
> files.

---

## 0. The one-sentence summary

v2 widens the framework at exactly three seams — **the GPU backend, the text pipeline, and
the style resolver** — and adds one new leaf vocabulary (**charts**), while leaving the
data-oriented core (element store, three trees, signal→dirty→scan, per-screen arena) and the
flat draw-command boundary completely untouched.

The architectural bet is that the v1 boundaries were drawn in the right places. Each v2
feature plugs into a boundary that already exists in v1 as either an explicit seam (INV-2.1
permitted a backend seam) or a single chokepoint function (`resolveClasses`,
`layoutParagraphEx`, `buildDrawList`). v2 is mostly "fill in the seam," not "re-cut the
architecture."

---

## 1. New build-order modules

v1 modules are 00–09 (`00_constitution.md` §7). v2 adds four, numbered to preserve the
"a module depends only on lower numbers" rule. They slot *after* 09 because each depends on
the renderer and/or text being in place:

```
10  gpu_backend     — GpuBackend seam; Vulkan/Metal/DX12/WebGPU implementations   (RJ0–RJ5)
11  text_shaping     — HarfBuzz shaping stage + Unicode bidi reordering            (RK0–RK3)
12  cascade          — build-time selector + specificity + inheritance resolver    (RL0–RL3)
13  charts           — chart-command vocabulary, scales/axes, chart components      (RM0–RM3)
```

Dependency directions (all point to lower numbers, INV §7 preserved):

- **10 gpu_backend** depends on 01 (Platform/surface), 09 (DrawCommand vocabulary, atlases).
  It *generalizes* the existing `VulkanBackend` rather than adding a peer.
- **11 text_shaping** depends on 02 (Font/GlyphAtlas), and is consumed by 04 (layout, line
  box widths) and 09 (glyph draw commands). It inserts a stage; it does not reorder modules.
- **12 cascade** depends on 05 (theme/tokens) and 06 (markup tree, `ComputedStyle`). It runs
  at build time only (INV-4.4) and emits the same `ComputedStyle` the renderer consumes.
- **13 charts** depends on 09 (draw commands) and 04 (layout for chart frames). It is a leaf:
  nothing depends on it.

---

## 2. Seam 1 — GPU backend (`gpu_backend`, modules 01/09/10)

### Current state (v1)
`VulkanBackend` (in `src/01/types.zig`) owns the device, swapchain, quad pipeline, and
`drawFrame(commands, atlas)`. `buildDrawList` (module 09) produces `[]const DrawCommand`;
`drawFrame` consumes it. INV-2.3 already isolates the renderer from widgets/layout/state.

### v2 change
Introduce a `GpuBackend` **interface** (Zig vtable or comptime-dispatched tagged union — RJ0
decides) capturing exactly what every backend must do:

```
GpuBackend:
  init(gpa, *Platform) !Self
  deinit()
  initPipelines() !void                 // quad + curve (RM0) pipelines
  resize(w, h, dpi_scale) void
  uploadAtlas(*const GlyphAtlas) !GpuAtlasHandle   // + SdfAtlas, ImageAtlas
  drawFrame(commands: []const DrawCommand, handles: AtlasHandles) void
  capabilities() Caps                   // present mode, max texture, subpixel support
```

`VulkanBackend` becomes the *reference implementation* of this interface (RJ1), proving the
seam is the contract, not Vulkan's shape. Metal (RJ2), DX12 (RJ3), and WebGPU (RJ4) are peer
implementations. The compile-time target selects exactly one (no runtime switch — INV-1.1
simplicity).

The shaders are the only per-backend asset that multiplies: SPIR-V (Vulkan), MSL/`.metallib`
(Metal), DXIL (DX12), WGSL (WebGPU). Because all four implement the *same* fragment "modes"
(rect, glyph, image, AA-circle, SDF-icon, and the new curve mode), the shader logic is
translated once per language and kept in lockstep by a shared mode table (RJ0 §"shader
mode parity"). A backend may not add a private mode (INV-2.1-v2).

### Why this is safe
The renderer boundary (INV-2.3) already guarantees nothing upstream knows about Vulkan. The
seam makes that guarantee structural instead of incidental. Atlas upload and the draw-command
list are the only data crossing the seam, and both are backend-agnostic by construction.

### Platform surface layer (RJ5)
GLFW already abstracts windowing for Win/Linux and supports Cocoa for macOS. The
`Platform.createSurface(instance)` call (v1) generalizes to `createSurface(backend_kind)`
returning a `VkSurfaceKHR`, `CAMetalLayer`, `HWND`/`IDXGISwapChain`, or canvas handle. Web is
the exception: it has no GLFW; RJ5 defines a thin Emscripten/`<canvas>` surface shim behind
the same `Platform` API. Per-OS code is confined here and in module 10 (INV-1.2-v2).

---

## 3. Seam 2 — text shaping (`text_shaping`, module 11)

### Current state (v1)
`layoutParagraphEx` (module 02) maps a UTF-8 run + font to positioned glyphs using kerning
and basic line breaking. `FontVariant {regular, bold, italic}`, `GlyphAtlas` keyed by
`GlyphKey`, fallback via `stbtt_FindGlyphIndex`. No contextual shaping, no bidi (RE3 added an
RTL *layout-direction* flag but not character-level reordering).

### v2 change
Insert a **shaping stage** between line breaking and glyph rasterization. The text pipeline
becomes:

```
UTF-8 run
  → itemize (split by script + bidi level + font)     [new, RK1]
  → bidi reorder runs to visual order (UBA)            [new, RK1]
  → shape each run via HarfBuzz → glyph IDs + offsets  [new, RK0]
  → rasterize glyph IDs into GlyphAtlas (unchanged keying, now by glyph id not codepoint)
  → position into line boxes (existing line-box logic, fed shaped advances)
```

The output type the rest of the system sees — positioned glyphs feeding `GlyphCmd` draw
commands — is **unchanged**. Shaping changes *how* advances and glyph ids are computed, not
*what* layout and the renderer receive. This keeps INV-2.3 and the atlas model intact.

`GlyphKey` migrates from "(codepoint, size, variant)" to "(glyph_id, size, variant,
font_id)" because shaping selects glyphs by font-internal id, not codepoint (RK0 §atlas).
CJK pushes atlas volume up; RK2 specifies atlas growth/eviction since the v1 fixed atlas
assumed a small Latin+Cyrillic glyph set.

### Editing, caret, selection (RK3)
Shaping breaks the v1 assumption that one codepoint = one advance = one caret stop. Caret
positions become **cluster** boundaries (HarfBuzz cluster values); hit-testing maps pixel x
→ cluster → byte offset. Text input (R32), textarea (R63), and selection (R62) consume a new
`ShapedLine` query API instead of per-codepoint advances. This is the deepest-reaching v2
change into existing widgets and is called out as the primary regression risk.

### Bidi and RE3
RE3's `direction: rtl` flag stays as the *paragraph base direction* input to the UBA. RK1
replaces RE3's coordinate-mirroring shortcut with real per-run level resolution. Mixed
LTR/RTL ("call me at +1 555" inside an Arabic sentence) works after RK1; it does not in v1.

---

## 4. Seam 3 — style cascade (`cascade`, module 12)

### Current state (v1)
`resolveClasses(classes, tokens) Resolved` (module 06) maps a flat, order-independent class
string to a `ComputedStyle` patch. No selectors, no specificity, no inheritance (INV-4.2).
Markup is baked at build time (INV-4.4); pseudo-states (R40) are token overrides applied by
the renderer.

### v2 change
Add a **build-time cascade resolver** that runs over the parsed markup tree plus a set of
rule blocks (a `.style` file, or `<style>` blocks). For each element it computes the winning
declarations by:

1. Matching selectors (type, class, id, descendant ` `, child `>`) against the element's
   position in the baked tree.
2. Ordering matches by specificity (id > class/attr > type), then source order.
3. Applying the fixed inheritance set (color, font-family, font-size, line-height,
   direction, text-align) from parent computed values where a property is unset.
4. Folding the result, plus any utility classes (which sit at a defined specificity tier),
   into the **same `ComputedStyle`** the renderer already consumes.

Because this happens at **build-time codegen** (INV-4.4), the production binary still contains
no parser and no cascade engine — only baked `ComputedStyle` literals. At runtime, signals
flipping a class (R52 conditional, pseudo-states) still work because each reachable variant's
`ComputedStyle` is pre-resolved, exactly as pseudo-states are today (R40). RL1 specifies the
finite set of dynamic variants that must be pre-baked.

### Why a cascade at all (vs. staying flat)
The flat model cannot express "every button inside a `.toolbar` is compact" or a shared
component theme without repeating utility classes on every node. The bounded cascade adds
descendant reach and inheritance — the two things real component libraries need — while
explicitly refusing the unbounded parts of CSS (`@media`, arbitrary combinators,
`!important` wars). RL3 guarantees utility-only screens (all of v1's demo app) keep working
unchanged: with no rule blocks present, the cascade is identity over the existing resolver.

---

## 5. New leaf vocabulary — charts (`charts`, module 13)

### Current state (v1)
The draw-command list (INV-2.3) has rect, glyph, image, AA-circle, SDF-icon. No way to draw a
line strip, a filled area under a curve, or an arc. Charts are listed as a separate concern
needing "a chart-command vocabulary alongside `DrawCommand`."

### v2 change
Two layers:

1. **GPU curve primitives (RM0).** Add a small set of draw commands — `polyline`
   (stroked, with width + join), `filled_path` (triangulated polygon for areas/wedges), and
   `arc` — plus one new fragment **mode** in every backend's shaders (parity per RJ0). These
   are general primitives, not chart-specific; they live in the shared vocabulary so all four
   backends render them identically. This is the only place charts touch the renderer.
2. **Chart components (RM1–RM3).** A `chart` module that, given data + a chart spec, computes
   scales (linear/log/band/time → pixel), axes, ticks, and gridlines (RM1), emits the curve
   primitives for line/bar/area/scatter/pie marks (RM2), and wires hover/tooltip/legend
   through the *existing* event + overlay + signal systems (RM3) — no new interaction
   mechanism (INV-3.3 preserved).

Charts are deliberately a **leaf**: they consume layout (a chart occupies a normal layout
rect), the draw-command list, signals, and overlays. Nothing in the core depends on charts;
removing module 13 leaves a working framework. Data binding uses the existing `Signal`/
`Value` machinery, so a chart re-renders on data change via the normal dirty scan.

---

## 6. What explicitly does NOT change

| Subsystem | v2 status |
|---|---|
| Element store (SoA, generational handles, arena) — modules 03 | Untouched |
| Three trees (Widget → Element → RenderObject) — INV-3.4 | Untouched |
| Reactivity (Signal → dirty bitset → linear scan) — INV-3.3 | Untouched; charts & cascade-driven restyles flow through it |
| Layout engine (Taffy port) — module 04 | Consumes shaped advances (11); no structural change |
| Four-layer token model — module 05, INV-4.3 | Cascade resolves *into* it |
| Draw-command boundary — INV-2.3 | Reaffirmed; now the multi-backend contract |
| Build-time codegen, no runtime parser — INV-4.4 | Extended to the cascade resolver |

If a v2 task finds itself wanting to change a row in this table, that is the signal to STOP
and surface a conflict (`00_constitution.md` §7), not to proceed.

---

## 7. Sequencing and risk

Recommended order, by dependency and risk:

1. **Module 10 (backend seam), RJ0 + RJ1 first.** Refactoring `VulkanBackend` behind the seam
   with *zero behavior change* is the safest possible first step and de-risks every backend
   after it. Land RJ0/RJ1 before writing a second backend.
2. **Module 11 (shaping).** Highest regression risk because it reaches into text editing
   widgets (RK3). Do it on its own, with the v1 visual-regression suite as the guard.
3. **Module 12 (cascade).** Build-time only; lowest runtime risk. RL3's compatibility proof
   (utility-only screens unchanged) is the gate.
4. **Module 13 (charts).** Leaf; can be built any time after RM0's curve primitives land in
   the backends (so it depends on the backend seam being complete enough to add a shader
   mode in each target).

Backends beyond Vulkan (RJ2–RJ4) can proceed in parallel once the seam (RJ0/RJ1) is proven,
since each is independent and selected at build time.

---

## 8. Open decisions deferred to requirements

These are real choices left to the individual requirement files rather than pre-decided here:

- `GpuBackend` dispatch: vtable vs. comptime tagged union — **RJ0**.
- WebGPU implementation: Dawn vs. wgpu-native — **RJ4** (also recorded in the amendment §2).
- Bidi: SheenBidi C lib vs. pure-Zig UBA port — **RK1** (also amendment §2).
- Atlas growth strategy for CJK volume — **RK2**.
- Exact pre-baked dynamic-variant set for the cascade — **RL1**.
- Curve tessellation: CPU pre-tessellation vs. GPU — **RM0**.
