const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // -----------------------------------------------------------------------
    // GPU backend selection (-Dgpu=vulkan|metal|dx12|webgpu, default per target).
    // -----------------------------------------------------------------------
    const gpu_backend_type = @import("./src/10/types.zig").BackendKind;
    const gpu_default: gpu_backend_type = switch (target.result.os.tag) {
        .windows, .linux => .vulkan,
        .macos => .metal,
        .emscripten => .webgpu,
        else => .vulkan,  // Default to Vulkan for unsupported targets (safe fallback)
    };
    const gpu_backend = b.option(
        gpu_backend_type,
        "gpu",
        "GPU backend (vulkan, metal, dx12, webgpu)",
    ) orelse gpu_default;

    // Create build_options module for comptime backend selection (module 10).
    const gpu_build_options = b.addOptions();
    gpu_build_options.addOption(gpu_backend_type, "gpu", gpu_backend);

    // -----------------------------------------------------------------------
    // Vulkan SDK paths (read from env; override with -Dvulkan_sdk=<path>).
    // -----------------------------------------------------------------------
    const vulkan_sdk = b.option(
        []const u8,
        "vulkan_sdk",
        "Path to Vulkan SDK root (defaults to $VULKAN_SDK)",
    ) orelse b.graph.environ_map.get("VULKAN_SDK") orelse
        @panic("Set -Dvulkan_sdk=<path> or export VULKAN_SDK=<path>");

    const vulkan_include = b.fmt("{s}\\Include", .{vulkan_sdk});
    const vulkan_lib = b.fmt("{s}\\Lib", .{vulkan_sdk});
    const glslc_exe = b.fmt("{s}\\Bin\\glslc.exe", .{vulkan_sdk});

    // -----------------------------------------------------------------------
    // GLFW — compiled from source (fetched via build.zig.zon).
    // -----------------------------------------------------------------------
    const glfw_dep = b.dependency("glfw", .{});
    const glfw_lib = buildGlfw(b, glfw_dep, target, optimize, vulkan_include);

    // -----------------------------------------------------------------------
    // Shaders — compiled to SPIR-V with glslc, then embedded via WriteFiles.
    // -----------------------------------------------------------------------
    const vert_cmd = b.addSystemCommand(&.{glslc_exe});
    vert_cmd.addFileArg(b.path("src/01/shaders/triangle.vert"));
    vert_cmd.addArg("-o");
    const vert_spv = vert_cmd.addOutputFileArg("triangle.vert.spv");

    const frag_cmd = b.addSystemCommand(&.{glslc_exe});
    frag_cmd.addFileArg(b.path("src/01/shaders/triangle.frag"));
    frag_cmd.addArg("-o");
    const frag_spv = frag_cmd.addOutputFileArg("triangle.frag.spv");

    // Module 09 quad shaders.
    const quad_vert_cmd = b.addSystemCommand(&.{glslc_exe});
    quad_vert_cmd.addFileArg(b.path("src/09/shaders/quad.vert"));
    quad_vert_cmd.addArg("-o");
    const quad_vert_spv = quad_vert_cmd.addOutputFileArg("quad.vert.spv");

    const quad_frag_cmd = b.addSystemCommand(&.{glslc_exe});
    quad_frag_cmd.addFileArg(b.path("src/09/shaders/quad.frag"));
    quad_frag_cmd.addArg("-o");
    const quad_frag_spv = quad_frag_cmd.addOutputFileArg("quad.frag.spv");

    // Bundle all .spv files into one WriteFiles directory.
    const wf = b.addWriteFiles();
    _ = wf.addCopyFile(vert_spv, "triangle.vert.spv");
    _ = wf.addCopyFile(frag_spv, "triangle.frag.spv");
    _ = wf.addCopyFile(quad_vert_spv, "quad.vert.spv");
    _ = wf.addCopyFile(quad_frag_spv, "quad.frag.spv");
    const shaders_zig = wf.add("embedded_shaders.zig",
        \\pub const vert_spv align(4) = @embedFile("triangle.vert.spv").*;
        \\pub const frag_spv align(4) = @embedFile("triangle.frag.spv").*;
        \\pub const quad_vert_spv align(4) = @embedFile("quad.vert.spv").*;
        \\pub const quad_frag_spv align(4) = @embedFile("quad.frag.spv").*;
        \\
    );

    const shaders_mod = b.addModule("embedded_shaders", .{
        .root_source_file = shaders_zig,
    });

    // -----------------------------------------------------------------------
    // Module 01 — the implementation (types.zig).
    // -----------------------------------------------------------------------
    const mod01 = b.addModule("types.zig", .{
        .root_source_file = b.path("src/01/types.zig"),
        .target = target,
        .optimize = optimize,
    });
    mod01.addImport("embedded_shaders", shaders_mod);
    mod01.addIncludePath(glfw_dep.path("include"));
    mod01.addIncludePath(.{ .cwd_relative = vulkan_include });
    mod01.linkLibrary(glfw_lib);
    mod01.addLibraryPath(.{ .cwd_relative = vulkan_lib });
    mod01.linkSystemLibrary("vulkan-1", .{});
    // Windows: GLFW needs gdi32/user32/shell32 (already linked inside glfw_lib,
    // but propagate them in case the linker needs them on the exe link line).
    if (target.result.os.tag == .windows) {
        mod01.linkSystemLibrary("gdi32", .{});
        mod01.linkSystemLibrary("user32", .{});
        mod01.linkSystemLibrary("shell32", .{});
    }

    // -----------------------------------------------------------------------
    // Smoke test — compiles from docs/specs/01.smoke_test.zig.
    //   zig build          → compile only (catches errors without GPU needed).
    //   zig build test-01  → compile + run (requires GPU + display).
    // -----------------------------------------------------------------------
    const smoke_mod = b.createModule(.{
        .root_source_file = b.path("docs/specs/01.smoke_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    smoke_mod.addImport("types.zig", mod01);
    const smoke = b.addTest(.{
        .name = "01-smoke-test",
        .root_module = smoke_mod,
    });

    // The default build step just compiles (no GPU required for CI).
    b.default_step.dependOn(&smoke.step);

    // Named step executes the tests on a GPU-capable machine.
    const run_smoke = b.addRunArtifact(smoke);
    const test_step = b.step("test-01", "Run module 01 smoke tests (needs GPU)");
    test_step.dependOn(&run_smoke.step);

    // -----------------------------------------------------------------------
    // Unit tests — src/01/01_test.zig
    //   zig build             → compile only (no GPU required for most tests)
    //   zig build test-01-unit → compile + run (GPU tests auto-skip if unavailable)
    // -----------------------------------------------------------------------
    const unit_mod = b.createModule(.{
        .root_source_file = b.path("src/01/01_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    unit_mod.addImport("types.zig", mod01);
    const unit_test = b.addTest(.{
        .name = "01-unit-test",
        .root_module = unit_mod,
    });

    // Compile is part of the default build step (catches errors without GPU).
    b.default_step.dependOn(&unit_test.step);

    const run_unit = b.addRunArtifact(unit_test);
    const unit_test_step = b.step("test-01-unit", "Run module 01 unit tests (GPU tests auto-skip)");
    unit_test_step.dependOn(&run_unit.step);

    // -----------------------------------------------------------------------
    // Module 02 — Text (stb_truetype-backed glyph rasterization).
    //
    // deps/stb_truetype.h is currently a declarations-only stub.
    // Replace it with the real header from https://github.com/nothings/stb
    // before implementing src/02/types.zig.  See deps/README.md.
    //
    // NOTE: `b.default_step` does NOT depend on accept02 here because
    // src/02/types.zig still carries @compileError stubs — adding it to the
    // default step would break `zig build` for all of module 01.  Once the
    // implementer fills in the stubs, add:
    //   b.default_step.dependOn(&accept02.step);
    // -----------------------------------------------------------------------
    const mod02 = b.addModule("text", .{
        .root_source_file = b.path("src/02/types.zig"),
        .target = target,
        .optimize = optimize,
    });
    mod02.addIncludePath(b.path("deps"));
    mod02.addCSourceFile(.{
        .file = b.path("deps/stb_impl.c"),
        .flags = &.{},
    });
    mod02.link_libc = true;

    // Acceptance test for module 02.
    //   zig build test-02  → compile + run (pure tests; font tests skip if no TTF present)
    const accept02_mod = b.createModule(.{
        .root_source_file = b.path("docs/specs/02.acceptance_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    accept02_mod.addImport("types.zig", mod02);
    const accept02 = b.addTest(.{
        .name = "02-acceptance-test",
        .root_module = accept02_mod,
    });
    const run_accept02 = b.addRunArtifact(accept02);
    const accept02_step = b.step("test-02", "Run module 02 acceptance tests");
    accept02_step.dependOn(&run_accept02.step);

    // -----------------------------------------------------------------------
    // Module 02 unit tests — src/02/02_test.zig
    //   zig build test-02-unit → compile + run (pure tests; no font, no GPU required)
    // -----------------------------------------------------------------------
    const unit02_mod = b.createModule(.{
        .root_source_file = b.path("src/02/02_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    unit02_mod.addImport("types.zig", mod02);
    const unit02_test = b.addTest(.{
        .name = "02-unit-test",
        .root_module = unit02_mod,
    });

    const run_unit02 = b.addRunArtifact(unit02_test);
    const unit02_test_step = b.step("test-02-unit", "Run module 02 unit tests (pure, no font, no GPU)");
    unit02_test_step.dependOn(&run_unit02.step);

    // -----------------------------------------------------------------------
    // Module 03 — Element store (pure Zig, no external deps).
    // -----------------------------------------------------------------------
    const mod03 = b.addModule("types.zig", .{
        .root_source_file = b.path("docs/specs/03.types.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Acceptance tests — docs/specs/03.acceptance_test.zig
    //   zig build test-03  → compile + run
    const accept03_mod = b.createModule(.{
        .root_source_file = b.path("docs/specs/03.acceptance_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    accept03_mod.addImport("types.zig", mod03);
    const accept03 = b.addTest(.{
        .name = "03-acceptance-test",
        .root_module = accept03_mod,
    });
    const run_accept03 = b.addRunArtifact(accept03);
    const accept03_step = b.step("test-03", "Run module 03 acceptance tests");
    accept03_step.dependOn(&run_accept03.step);

    // -----------------------------------------------------------------------
    // Module 04 — Layout engine (pure Zig, no external deps).
    // -----------------------------------------------------------------------
    const mod04 = b.addModule("layout", .{
        .root_source_file = b.path("docs/specs/04.types.zig"),
        .target = target,
        .optimize = optimize,
    });
    mod04.addImport("../03_element_store/types.zig", mod03);

    // Acceptance tests — docs/specs/04.acceptance_test.zig
    //   zig build test-04  → compile + run
    const accept04_mod = b.createModule(.{
        .root_source_file = b.path("docs/specs/04.acceptance_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    accept04_mod.addImport("types.zig", mod04);
    accept04_mod.addImport("../03_element_store/types.zig", mod03);
    const accept04 = b.addTest(.{
        .name = "04-acceptance-test",
        .root_module = accept04_mod,
    });
    const run_accept04 = b.addRunArtifact(accept04);
    const accept04_step = b.step("test-04", "Run module 04 acceptance tests");
    accept04_step.dependOn(&run_accept04.step);

    // -----------------------------------------------------------------------
    // Module 05 — Theme (pure Zig, no external deps).
    // -----------------------------------------------------------------------
    const mod05 = b.addModule("theme", .{
        .root_source_file = b.path("docs/specs/05.types.zig"),
        .target = target,
        .optimize = optimize,
    });
    mod05.addImport("../03_element_store/types.zig", mod03);

    // Acceptance tests — docs/specs/05.acceptance_test.zig
    //   zig build test-05  → compile + run
    const accept05_mod = b.createModule(.{
        .root_source_file = b.path("docs/specs/05.acceptance_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    accept05_mod.addImport("types.zig", mod05);
    const accept05 = b.addTest(.{
        .name = "05-acceptance-test",
        .root_module = accept05_mod,
    });
    const run_accept05 = b.addRunArtifact(accept05);
    const accept05_step = b.step("test-05", "Run module 05 acceptance tests");
    accept05_step.dependOn(&run_accept05.step);

    // -----------------------------------------------------------------------
    // Module 05 unit tests — src/05/05_test.zig
    //   zig build test-05-unit → compile + run
    // -----------------------------------------------------------------------
    const unit05_mod = b.createModule(.{
        .root_source_file = b.path("src/05/05_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    unit05_mod.addImport("../../docs/specs/05.types.zig", mod05);
    unit05_mod.addImport("../03_element_store/types.zig", mod03);
    const unit05_test = b.addTest(.{
        .name = "05-unit-test",
        .root_module = unit05_mod,
    });
    const run_unit05 = b.addRunArtifact(unit05_test);
    const unit05_test_step = b.step("test-05-unit", "Run module 05 unit tests");
    unit05_test_step.dependOn(&run_unit05.step);

    // Unit tests — src/03/03_test.zig
    //   zig build test-03-unit → compile + run
    const unit03_mod = b.createModule(.{
        .root_source_file = b.path("src/03/03_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    unit03_mod.addImport("types.zig", mod03);
    const unit03_test = b.addTest(.{
        .name = "03-unit-test",
        .root_module = unit03_mod,
    });
    const run_unit03 = b.addRunArtifact(unit03_test);
    const unit03_test_step = b.step("test-03-unit", "Run module 03 unit tests (pure, no GPU)");
    unit03_test_step.dependOn(&run_unit03.step);

    // -----------------------------------------------------------------------
    // Module 04 unit tests — src/04/04_test.zig
    //   zig build test-04-unit → compile + run
    // -----------------------------------------------------------------------
    const unit04_mod = b.createModule(.{
        .root_source_file = b.path("src/04/04_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    unit04_mod.addImport("types.zig", mod04);
    unit04_mod.addImport("../03_element_store/types.zig", mod03);
    const unit04_test = b.addTest(.{
        .name = "04-unit-test",
        .root_module = unit04_mod,
    });
    const run_unit04 = b.addRunArtifact(unit04_test);
    const unit04_test_step = b.step("test-04-unit", "Run module 04 unit tests");
    unit04_test_step.dependOn(&run_unit04.step);

    // -----------------------------------------------------------------------
    // Module 06 — Markup + style (pure Zig, no external deps).
    // -----------------------------------------------------------------------
    const mod06 = b.addModule("markup", .{
        .root_source_file = b.path("docs/specs/06.types.zig"),
        .target = target,
        .optimize = optimize,
    });
    mod06.addImport("../03_element_store/types.zig", mod03);
    mod06.addImport("../05_theme/types.zig", mod05);

    // Acceptance tests — docs/specs/06.acceptance_test.zig
    //   zig build test-06  → compile + run
    const accept06_mod = b.createModule(.{
        .root_source_file = b.path("docs/specs/06.acceptance_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    accept06_mod.addImport("types.zig", mod06);
    accept06_mod.addImport("../03_element_store/types.zig", mod03);
    accept06_mod.addImport("../05_theme/types.zig", mod05);
    const accept06 = b.addTest(.{
        .name = "06-acceptance-test",
        .root_module = accept06_mod,
    });
    const run_accept06 = b.addRunArtifact(accept06);
    const accept06_step = b.step("test-06", "Run module 06 acceptance tests");
    accept06_step.dependOn(&run_accept06.step);

    // -----------------------------------------------------------------------
    // Module 06 unit tests — src/06/06_test.zig
    //   zig build test-06-unit → compile + run
    // -----------------------------------------------------------------------
    const unit06_mod = b.createModule(.{
        .root_source_file = b.path("src/06/06_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    unit06_mod.addImport("../../docs/specs/06.types.zig", mod06);
    unit06_mod.addImport("../03_element_store/types.zig", mod03);
    unit06_mod.addImport("../../docs/specs/05.types.zig", mod05);
    const unit06_test = b.addTest(.{
        .name = "06-unit-test",
        .root_module = unit06_mod,
    });
    const run_unit06 = b.addRunArtifact(unit06_test);
    const unit06_test_step = b.step("test-06-unit", "Run module 06 unit tests");
    unit06_test_step.dependOn(&run_unit06.step);

    // -----------------------------------------------------------------------
    // font_family.zig — R60: three-slot font container (regular, bold, italic).
    // Defined here (before mod07) because mod07 imports it.
    // Depends on mod02 for text.Font.
    const mod_font_family = b.addModule("font_family.zig", .{
        .root_source_file = b.path("src/app/font_family.zig"),
        .target = target,
        .optimize = optimize,
    });
    mod_font_family.addImport("../02/types.zig", mod02);

    // -----------------------------------------------------------------------
    // Module 07 — Components (Scene, instantiate, measurePass).
    // Imports: 01 (platform/CursorShape), 02 (text/font/atlas), 03 (element store), 05 (theme), 06 (markup).
    // -----------------------------------------------------------------------
    const mod07 = b.addModule("components", .{
        .root_source_file = b.path("src/07/types.zig"),
        .target = target,
        .optimize = optimize,
    });
    // src/07/types.zig imports the other src/ re-export wrappers by relative path.
    // Wire them so the build system resolves C dependencies (stb_truetype for mod02).
    mod07.addImport("../01/types.zig", mod01); // M11 RB0: CursorShape re-export
    mod07.addImport("../02/types.zig", mod02);
    mod07.addImport("../03/types.zig", mod03);
    mod07.addImport("../05/types.zig", mod05);
    mod07.addImport("../06/types.zig", mod06);
    mod07.addImport("../app/font_family.zig", mod_font_family);

    // Acceptance test — docs/specs/07.acceptance_test.zig
    //   zig build test-07  → compile + run (pure tests + font test skips if no TTF)
    const accept07_mod = b.createModule(.{
        .root_source_file = b.path("docs/specs/07.acceptance_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    accept07_mod.addImport("types.zig", mod07);
    accept07_mod.addImport("../03_element_store/types.zig", mod03);
    accept07_mod.addImport("../05_theme/types.zig", mod05);
    accept07_mod.addImport("../06_markup_style/types.zig", mod06);
    accept07_mod.addImport("../02_text/types.zig", mod02);
    accept07_mod.addImport("../app/font_family.zig", mod_font_family);
    const accept07 = b.addTest(.{
        .name = "07-acceptance-test",
        .root_module = accept07_mod,
    });
    const run_accept07 = b.addRunArtifact(accept07);
    const accept07_step = b.step("test-07", "Run module 07 acceptance tests");
    accept07_step.dependOn(&run_accept07.step);

    // Unit tests — src/07/07_test.zig
    //   zig build test-07-unit → compile + run (pure, no font required)
    const unit07_mod = b.createModule(.{
        .root_source_file = b.path("src/07/07_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    unit07_mod.addImport("types.zig", mod07);
    unit07_mod.addImport("../03/types.zig", mod03);
    unit07_mod.addImport("../05/types.zig", mod05);
    unit07_mod.addImport("../06/types.zig", mod06);
    unit07_mod.addImport("../app/font_family.zig", mod_font_family);
    const unit07_test = b.addTest(.{
        .name = "07-unit-test",
        .root_module = unit07_mod,
    });
    const run_unit07 = b.addRunArtifact(unit07_test);
    const unit07_test_step = b.step("test-07-unit", "Run module 07 unit tests (pure, no font required)");
    unit07_test_step.dependOn(&run_unit07.step);

    // -----------------------------------------------------------------------
    // Module 08 — Schema forms (pure Zig, no external deps).
    // Imports: 03 (element store), 05 (theme), 07 (components/scene).
    // -----------------------------------------------------------------------
    const mod08 = b.addModule("schema_forms", .{
        .root_source_file = b.path("src/08/types.zig"),
        .target = target,
        .optimize = optimize,
    });
    mod08.addImport("../03/types.zig", mod03);
    mod08.addImport("../05/types.zig", mod05);
    mod08.addImport("../07/types.zig", mod07);

    // Acceptance tests — docs/specs/08.acceptance_test.zig
    //   zig build test-08  → compile + run
    const accept08_mod = b.createModule(.{
        .root_source_file = b.path("docs/specs/08.acceptance_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    accept08_mod.addImport("types.zig", mod08);
    accept08_mod.addImport("../07_components/types.zig", mod07);
    accept08_mod.addImport("../05_theme/types.zig", mod05);
    const accept08 = b.addTest(.{
        .name = "08-acceptance-test",
        .root_module = accept08_mod,
    });
    const run_accept08 = b.addRunArtifact(accept08);
    const accept08_step = b.step("test-08", "Run module 08 acceptance tests");
    accept08_step.dependOn(&run_accept08.step);

    const unit08_mod = b.createModule(.{
        .root_source_file = b.path("src/08/08_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    unit08_mod.addImport("types.zig", mod08);
    const unit08_test = b.addTest(.{ .name = "08-unit-test", .root_module = unit08_mod });
    const run_unit08 = b.addRunArtifact(unit08_test);
    const unit08_test_step = b.step("test-08-unit", "Run module 08 unit tests");
    unit08_test_step.dependOn(&run_unit08.step);

    // -----------------------------------------------------------------------
    // image_atlas.zig — standalone (no module deps beyond std).
    const mod_image_atlas = b.addModule("image_atlas.zig", .{
        .root_source_file = b.path("src/app/image_atlas.zig"),
        .target = target,
        .optimize = optimize,
    });

    // overlay.zig — depends on module 01 for DrawCommand.
    const mod_overlay = b.addModule("overlay.zig", .{
        .root_source_file = b.path("src/app/overlay.zig"),
        .target = target,
        .optimize = optimize,
    });
    mod_overlay.addImport("../01/types.zig", mod01);

    // Module 09 — Renderer (DrawCommand, buildDrawList, GpuAtlas, quad pipeline).
    // Imports: 01 (VulkanBackend/DrawCommand), 02 (GlyphAtlas), 03, 05, 07, image_atlas.
    // -----------------------------------------------------------------------
    const mod09 = b.addModule("renderer", .{
        .root_source_file = b.path("src/09/types.zig"),
        .target = target,
        .optimize = optimize,
    });
    mod09.addImport("../01/types.zig", mod01);
    mod09.addImport("../02/types.zig", mod02);
    mod09.addImport("../03/types.zig", mod03);
    mod09.addImport("../05/types.zig", mod05);
    mod09.addImport("../07/types.zig", mod07);
    mod09.addImport("../app/image_atlas.zig", mod_image_atlas);
    mod09.addImport("../app/font_family.zig", mod_font_family);

    // Acceptance test — docs/specs/09.acceptance_test.zig
    //   zig build test-09  → compile + run (pure CPU tests; GPU tests skip if no Vulkan)
    const accept09_mod = b.createModule(.{
        .root_source_file = b.path("docs/specs/09.acceptance_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    accept09_mod.addImport("types.zig", mod09);
    accept09_mod.addImport("../03/types.zig", mod03);
    accept09_mod.addImport("../05/types.zig", mod05);
    accept09_mod.addImport("../07/types.zig", mod07);
    accept09_mod.addImport("../06/types.zig", mod06);
    accept09_mod.addImport("../01/types.zig", mod01);
    accept09_mod.addImport("../04/types.zig", mod04);
    accept09_mod.addImport("../app/font_family.zig", mod_font_family);
    // Vulkan + GLFW needed for GPU tests (link through mod01's transitive deps).
    accept09_mod.addIncludePath(glfw_dep.path("include"));
    accept09_mod.addIncludePath(.{ .cwd_relative = vulkan_include });
    accept09_mod.linkLibrary(glfw_lib);
    accept09_mod.addLibraryPath(.{ .cwd_relative = vulkan_lib });
    accept09_mod.linkSystemLibrary("vulkan-1", .{});
    accept09_mod.link_libc = true;
    if (target.result.os.tag == .windows) {
        accept09_mod.linkSystemLibrary("gdi32", .{});
        accept09_mod.linkSystemLibrary("user32", .{});
        accept09_mod.linkSystemLibrary("shell32", .{});
    }
    const accept09 = b.addTest(.{
        .name = "09-acceptance-test",
        .root_module = accept09_mod,
    });
    const run_accept09 = b.addRunArtifact(accept09);
    const accept09_step = b.step("test-09", "Run module 09 acceptance tests (GPU tests skip if unavailable)");
    accept09_step.dependOn(&run_accept09.step);

    // Unit tests — src/09/09_test.zig
    //   zig build test-09-unit → compile + run (pure CPU, no GPU required)
    const unit09_mod = b.createModule(.{
        .root_source_file = b.path("src/09/09_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    unit09_mod.addImport("types.zig", mod09);
    unit09_mod.addImport("../03/types.zig", mod03);
    unit09_mod.addImport("../05/types.zig", mod05);
    unit09_mod.addImport("../07/types.zig", mod07);
    unit09_mod.addImport("../06/types.zig", mod06);
    unit09_mod.addImport("layout_engine", mod04);
    unit09_mod.addImport("../app/image_atlas.zig", mod_image_atlas);
    unit09_mod.addImport("../app/font_family.zig", mod_font_family);
    unit09_mod.addIncludePath(b.path("deps"));
    unit09_mod.addCSourceFile(.{ .file = b.path("deps/stb_impl.c"), .flags = &.{} });
    unit09_mod.link_libc = true;
    const unit09_test = b.addTest(.{ .name = "09-unit-test", .root_module = unit09_mod });
    const run_unit09 = b.addRunArtifact(unit09_test);
    const unit09_test_step = b.step("test-09-unit", "Run module 09 unit tests (pure CPU)");
    unit09_test_step.dependOn(&run_unit09.step);

    // -----------------------------------------------------------------------
    // Module 10 — GPU backend seam (RJ0).
    // Imports: 01 (Platform), 09 (DrawCommand, SdfAtlas), 02 (GlyphAtlas).
    // Defines: GpuBackend interface, comptime dispatch via -Dgpu build option.
    // -----------------------------------------------------------------------
    const mod10 = b.addModule("gpu_backend", .{
        .root_source_file = b.path("src/10/types.zig"),
        .target = target,
        .optimize = optimize,
    });
    mod10.addImport("../01/types.zig", mod01);
    mod10.addImport("../09/types.zig", mod09);
    mod10.addImport("../02/types.zig", mod02);

    // Acceptance test — docs/specs/10.acceptance_test.zig (or smoke test if acceptance test not yet written).
    //   zig build test-10  → compile + run (pure CPU tests; GPU tests skip if backend unavailable)
    const accept10_mod = b.createModule(.{
        .root_source_file = b.path("docs/specs/10.smoke_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    accept10_mod.addImport("types.zig", mod10);
    accept10_mod.addImport("../01/types.zig", mod01);
    accept10_mod.addImport("../09/types.zig", mod09);
    accept10_mod.addImport("../02/types.zig", mod02);
    // For GPU tests: Vulkan SDK paths.
    accept10_mod.addIncludePath(glfw_dep.path("include"));
    accept10_mod.addIncludePath(.{ .cwd_relative = vulkan_include });
    accept10_mod.linkLibrary(glfw_lib);
    accept10_mod.addLibraryPath(.{ .cwd_relative = vulkan_lib });
    accept10_mod.linkSystemLibrary("vulkan-1", .{});
    accept10_mod.link_libc = true;
    if (target.result.os.tag == .windows) {
        accept10_mod.linkSystemLibrary("gdi32", .{});
        accept10_mod.linkSystemLibrary("user32", .{});
        accept10_mod.linkSystemLibrary("shell32", .{});
    }
    const accept10 = b.addTest(.{
        .name = "10-smoke-test",
        .root_module = accept10_mod,
    });
    const run_accept10 = b.addRunArtifact(accept10);
    const accept10_step = b.step("test-10", "Run module 10 GPU backend seam tests (compiles with -Dgpu option)");
    accept10_step.dependOn(&run_accept10.step);

    // -----------------------------------------------------------------------
    // App layer (R10-R13) — src/app/
    // Depends on modules 01-09.
    //
    // Module identity rule: each .zig file gets ONE module object.  Sharing
    // the same module object across mod_app, test-app, and test-events ensures
    // Zig sees only one canonical identity for each file and avoids the
    // "file exists in modules X and Y" error.
    // -----------------------------------------------------------------------

    // events.zig — one module, shared everywhere.
    const mod_events = b.addModule("events.zig", .{
        .root_source_file = b.path("src/app/events.zig"),
        .target = target,
        .optimize = optimize,
    });
    mod_events.addImport("../01/types.zig", mod01);

    // navigator.zig — R80: Navigator, ScreenFn, NavEntry, PendingNav, ScreenEntry.
    // Does NOT import app.zig (to avoid circular build deps); app.zig imports it.
    const mod_navigator = b.addModule("navigator.zig", .{
        .root_source_file = b.path("src/app/navigator.zig"),
        .target = target,
        .optimize = optimize,
    });
    mod_navigator.addImport("../07/types.zig", mod07);
    mod_navigator.addImport("../05/types.zig", mod05);

    // -----------------------------------------------------------------------
    // M10 — Production hardening modules (RA0–RA4).
    // Each file is registered as exactly one named module (build-system rule).
    // -----------------------------------------------------------------------

    // persistent_settings.zig — R82, also used by RA4 window_state.zig.
    // Previously imported via relative path from types.zig; now a named module
    // so both app.zig and window_state.zig can share it safely.
    const mod_persistent_settings = b.addModule("persistent_settings.zig", .{
        .root_source_file = b.path("src/app/persistent_settings.zig"),
        .target = target,
        .optimize = optimize,
    });

    // RA2: file_logger.zig — no extra deps beyond std.
    const mod_file_logger = b.addModule("file_logger.zig", .{
        .root_source_file = b.path("src/app/file_logger.zig"),
        .target = target,
        .optimize = optimize,
    });

    // RA2: logger.zig — depends on file_logger.zig.
    const mod_logger = b.addModule("logger.zig", .{
        .root_source_file = b.path("src/app/logger.zig"),
        .target = target,
        .optimize = optimize,
    });
    mod_logger.addImport("file_logger.zig", mod_file_logger);

    // RA1: budgeted_arena.zig — no extra deps beyond std.
    const mod_budgeted_arena = b.addModule("budgeted_arena.zig", .{
        .root_source_file = b.path("src/app/budgeted_arena.zig"),
        .target = target,
        .optimize = optimize,
    });

    // RA4: window_state.zig — depends on persistent_settings.zig and mod01.
    // Needs GLFW includes for glfwGetWindowPos/Size/Attrib (same pattern as mod01).
    const mod_window_state = b.addModule("window_state.zig", .{
        .root_source_file = b.path("src/app/window_state.zig"),
        .target = target,
        .optimize = optimize,
    });
    mod_window_state.addImport("persistent_settings.zig", mod_persistent_settings);
    mod_window_state.addImport("../01/types.zig", mod01);
    mod_window_state.addIncludePath(glfw_dep.path("include"));
    mod_window_state.addIncludePath(.{ .cwd_relative = vulkan_include });

    // RA0: error_boundary.zig — imports mod07 (Scene), mod05 (Tokens), mod06 (NodeDesc).
    // Does NOT import navigator.zig to break the circular dep
    // (navigator.zig imports error_boundary.zig; error_boundary.zig redefines ScreenFn
    //  locally using the same signature as navigator.ScreenFn).
    const mod_error_boundary = b.addModule("error_boundary.zig", .{
        .root_source_file = b.path("src/app/error_boundary.zig"),
        .target = target,
        .optimize = optimize,
    });
    mod_error_boundary.addImport("../07/types.zig", mod07);
    mod_error_boundary.addImport("../05/types.zig", mod05);
    mod_error_boundary.addImport("../06/types.zig", mod06);

    // RA0: navigator.zig imports error_boundary.zig — add the dep now that mod_error_boundary exists.
    mod_navigator.addImport("error_boundary.zig", mod_error_boundary);

    // RA3: startup_error.zig — no extra deps beyond std and builtin (app.zig is passed generically).
    const mod_startup_error = b.addModule("startup_error.zig", .{
        .root_source_file = b.path("src/app/startup_error.zig"),
        .target = target,
        .optimize = optimize,
    });

    // binding.zig — one module, shared everywhere that imports it.
    // R83: multi_window.zig also imports binding.zig; registering it as a named
    // module ensures the build system sees only one canonical identity for the file.
    const mod_binding = b.addModule("binding.zig", .{
        .root_source_file = b.path("src/app/binding.zig"),
        .target = target,
        .optimize = optimize,
    });
    mod_binding.addImport("../07/types.zig", mod07);
    // binding.zig imports signal.zig via relative path — no extra wiring needed for it
    // since signal.zig only imports std.

    // tray.zig — RF0 system tray (M16-01). Depends on mod07 for CallbackFn.
    // Registered as a named module so tray_test.zig and app.zig share the same
    // module identity (build rule: each .zig file belongs to exactly one module).
    const mod_tray = b.addModule("tray.zig", .{
        .root_source_file = b.path("src/app/tray.zig"),
        .target = target,
        .optimize = optimize,
    });
    mod_tray.addImport("../07/types.zig", mod07);
    if (target.result.os.tag == .windows) {
        mod_tray.linkSystemLibrary("gdi32", .{});
        mod_tray.linkSystemLibrary("user32", .{});
        mod_tray.linkSystemLibrary("shell32", .{});
    }

    // app.zig — one module, shared everywhere.
    const mod_app_impl = b.addModule("app.zig", .{
        .root_source_file = b.path("src/app/app.zig"),
        .target = target,
        .optimize = optimize,
    });
    mod_app_impl.addImport("../01/types.zig", mod01);
    mod_app_impl.addImport("../02/types.zig", mod02);
    mod_app_impl.addImport("../03/types.zig", mod03);
    mod_app_impl.addImport("../04/types.zig", mod04);
    mod_app_impl.addImport("../05/types.zig", mod05);
    mod_app_impl.addImport("../06/types.zig", mod06);
    mod_app_impl.addImport("../07/types.zig", mod07);
    mod_app_impl.addImport("../08/types.zig", mod08);
    mod_app_impl.addImport("../09/types.zig", mod09);
    mod_app_impl.addImport("overlay.zig", mod_overlay);
    mod_app_impl.addImport("binding.zig", mod_binding);
    mod_app_impl.addImport("image_atlas.zig", mod_image_atlas);
    mod_app_impl.addImport("font_family.zig", mod_font_family);
    // NOTE: app.zig does NOT import types.zig (types.zig imports app.zig — no cycle).
    mod_app_impl.addImport("events.zig", mod_events);
    mod_app_impl.addImport("navigator.zig", mod_navigator);
    // M10: wire all new modules into app.zig so each file has exactly one module identity.
    mod_app_impl.addImport("persistent_settings.zig", mod_persistent_settings);
    mod_app_impl.addImport("file_logger.zig", mod_file_logger);
    mod_app_impl.addImport("logger.zig", mod_logger);
    mod_app_impl.addImport("budgeted_arena.zig", mod_budgeted_arena);
    mod_app_impl.addImport("window_state.zig", mod_window_state);
    mod_app_impl.addImport("error_boundary.zig", mod_error_boundary);
    mod_app_impl.addImport("startup_error.zig", mod_startup_error);
    mod_app_impl.addImport("tray.zig", mod_tray);

    // types.zig — the public root module.
    const mod_app = b.addModule("app", .{
        .root_source_file = b.path("src/app/types.zig"),
        .target = target,
        .optimize = optimize,
    });
    mod_app.addImport("../01/types.zig", mod01);
    mod_app.addImport("../02/types.zig", mod02);
    mod_app.addImport("../03/types.zig", mod03);
    mod_app.addImport("../04/types.zig", mod04);
    mod_app.addImport("../05/types.zig", mod05);
    mod_app.addImport("../06/types.zig", mod06);
    mod_app.addImport("../07/types.zig", mod07);
    mod_app.addImport("../08/types.zig", mod08);
    mod_app.addImport("../09/types.zig", mod09);
    mod_app.addImport("app.zig", mod_app_impl);
    mod_app.addImport("events.zig", mod_events);
    mod_app.addImport("navigator.zig", mod_navigator);
    // R83: multi_window.zig (imported by types.zig) uses overlay.zig, binding.zig,
    // events.zig, navigator.zig — wire them so the build system sees only one module
    // identity for each file (INV rule: files must belong to only one module).
    mod_app.addImport("overlay.zig", mod_overlay);
    mod_app.addImport("binding.zig", mod_binding);

    // -----------------------------------------------------------------------
    // test-app — headless unit tests (no GPU).
    //   zig build test-app → compile + run
    // -----------------------------------------------------------------------
    const app_test_mod = b.createModule(.{
        .root_source_file = b.path("src/app/app_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    app_test_mod.addImport("types.zig", mod_app);
    app_test_mod.addImport("../01/types.zig", mod01);
    app_test_mod.addImport("events.zig", mod_events);
    const app_test = b.addTest(.{ .name = "app-test", .root_module = app_test_mod });
    const run_app_test = b.addRunArtifact(app_test);
    const app_test_step = b.step("test-app", "Run app layer unit tests (headless, no GPU)");
    app_test_step.dependOn(&run_app_test.step);

    // -----------------------------------------------------------------------
    // test-events — EventQueue dedicated tests (no GPU, no GLFW).
    //   zig build test-events → compile + run
    // -----------------------------------------------------------------------
    const events_test_mod = b.createModule(.{
        .root_source_file = b.path("src/app/events_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    events_test_mod.addImport("types.zig", mod_app);
    events_test_mod.addImport("../01/types.zig", mod01);
    events_test_mod.addImport("events.zig", mod_events);
    const events_test = b.addTest(.{ .name = "events-test", .root_module = events_test_mod });
    const run_events_test = b.addRunArtifact(events_test);
    const events_test_step = b.step("test-events", "Run EventQueue unit tests (no GPU, no GLFW)");
    events_test_step.dependOn(&run_events_test.step);

    // -----------------------------------------------------------------------
    // test-signal — Signal(T) and Computed(T) unit tests (pure, no GPU).
    //   zig build             → compile only (compile check)
    //   zig build test-signal → compile + run
    // -----------------------------------------------------------------------
    const signal_test_mod = b.createModule(.{
        .root_source_file = b.path("src/app/signal_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    // signal.zig imports only std — no additional module wiring needed.
    const signal_test = b.addTest(.{ .name = "signal-test", .root_module = signal_test_mod });
    b.default_step.dependOn(&signal_test.step);
    const run_signal_test = b.addRunArtifact(signal_test);
    const signal_test_step = b.step("test-signal", "Run Signal/Computed unit tests (pure, no GPU)");
    signal_test_step.dependOn(&run_signal_test.step);

    // -----------------------------------------------------------------------
    // test-anim-timeline — AnimTimeline and easing unit tests (pure, no GPU).
    //   zig build                   → compile only (compile check)
    //   zig build test-anim-timeline → compile + run
    // -----------------------------------------------------------------------
    const anim_timeline_test_mod = b.createModule(.{
        .root_source_file = b.path("src/app/anim_timeline_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    // anim_timeline.zig imports only std — no additional module wiring needed.
    const anim_timeline_test = b.addTest(.{ .name = "anim-timeline-test", .root_module = anim_timeline_test_mod });
    b.default_step.dependOn(&anim_timeline_test.step);
    const run_anim_timeline_test = b.addRunArtifact(anim_timeline_test);
    const anim_timeline_test_step = b.step("test-anim-timeline", "Run AnimTimeline unit tests (pure, no GPU)");
    anim_timeline_test_step.dependOn(&run_anim_timeline_test.step);

    // -----------------------------------------------------------------------
    // test-overlay — OverlayLayer unit tests (no GPU, no GLFW).
    //   zig build               → compile only (compile check)
    //   zig build test-overlay  → compile + run
    // -----------------------------------------------------------------------
    const overlay_test_mod = b.createModule(.{
        .root_source_file = b.path("src/app/overlay_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    overlay_test_mod.addImport("overlay.zig", mod_overlay);
    overlay_test_mod.addImport("../01/types.zig", mod01);
    const overlay_test = b.addTest(.{ .name = "overlay-test", .root_module = overlay_test_mod });
    b.default_step.dependOn(&overlay_test.step);
    const run_overlay_test = b.addRunArtifact(overlay_test);
    const overlay_test_step = b.step("test-overlay", "Run OverlayLayer unit tests (no GPU, no GLFW)");
    overlay_test_step.dependOn(&run_overlay_test.step);

    // -----------------------------------------------------------------------
    // test-binding — BindingSet unit tests (no GPU, no GLFW).
    //   zig build              → compile only (compile check)
    //   zig build test-binding → compile + run
    // -----------------------------------------------------------------------
    const binding_test_mod = b.createModule(.{
        .root_source_file = b.path("src/app/binding_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    // binding.zig imports ../07/types.zig; wire mod07 so the build system resolves it.
    // mod07 transitively brings in mod02 (stb_truetype C code) — add them explicitly
    // to ensure the test binary links correctly.
    binding_test_mod.addImport("../07/types.zig", mod07);
    binding_test_mod.addImport("../../docs/specs/05.types.zig", mod05);
    binding_test_mod.addImport("../06/types.zig", mod06);
    binding_test_mod.addImport("../03/types.zig", mod03);
    binding_test_mod.addIncludePath(b.path("deps"));
    binding_test_mod.addCSourceFile(.{ .file = b.path("deps/stb_impl.c"), .flags = &.{} });
    binding_test_mod.link_libc = true;
    const binding_test = b.addTest(.{ .name = "binding-test", .root_module = binding_test_mod });
    b.default_step.dependOn(&binding_test.step);
    const run_binding_test = b.addRunArtifact(binding_test);
    const binding_test_step = b.step("test-binding", "Run BindingSet unit tests (no GPU, no GLFW)");
    binding_test_step.dependOn(&run_binding_test.step);

    // -----------------------------------------------------------------------
    // R55 — Build-time markup codegen tool (ui_codegen).
    //   zig build codegen → regenerate all .ui.zig files from .ui markup
    // -----------------------------------------------------------------------
    const codegen_mod = b.createModule(.{
        .root_source_file = b.path("src/tools/ui_codegen.zig"),
        .target = b.resolveTargetQuery(.{}),
        .optimize = .Debug,
    });
    codegen_mod.addImport("m06", mod06);
    const codegen_exe = b.addExecutable(.{
        .name = "ui_codegen",
        .root_module = codegen_mod,
    });

    // List of .ui files to process (explicit, no auto-discovery — INV-5.4).
    const ui_files = &[_][]const u8{
        "src/screens/example.ui",
    };

    const codegen_step = b.step("codegen", "Regenerate baked NodeDesc files from .ui markup");
    for (ui_files) |ui_path| {
        // Output: same path + ".zig" suffix (e.g. src/screens/example.ui.zig)
        const out_path = b.fmt("{s}.zig", .{ui_path});
        const run = b.addRunArtifact(codegen_exe);
        run.addArg(b.path(ui_path).getPath(b));
        run.addArg(b.path(out_path).getPath(b));
        codegen_step.dependOn(&run.step);
    }

    // -----------------------------------------------------------------------
    // M15-03 (RE2) — Build-time string table codegen (string_table_codegen).
    // Generates src/strings.zig from src/strings.en.txt at build time.
    // The generated file is a build artifact (not committed to the repo).
    // -----------------------------------------------------------------------
    const strings_codegen_mod = b.createModule(.{
        .root_source_file = b.path("src/tools/string_table_codegen.zig"),
        .target = b.resolveTargetQuery(.{}),
        .optimize = .Debug,
    });
    const strings_codegen_exe = b.addExecutable(.{
        .name = "string_table_codegen",
        .root_module = strings_codegen_mod,
    });

    const run_strings_codegen = b.addRunArtifact(strings_codegen_exe);
    run_strings_codegen.addArg(b.path("src/strings.en.txt").getPath(b));
    const strings_gen = run_strings_codegen.addOutputFileArg("strings.zig");

    const strings_mod = b.addModule("strings.zig", .{
        .root_source_file = strings_gen,
    });

    // -----------------------------------------------------------------------
    // R56 — hot-reload build option and run-dev step.
    //   zig build run-dev → build + run with hot-reload enabled
    // -----------------------------------------------------------------------
    const hot_reload = b.option(bool, "hot-reload", "Enable .ui file watcher for live editing") orelse false;
    const build_options = b.addOptions();
    build_options.addOption(bool, "hot_reload", hot_reload);

    // Add build_options to app module (so app.zig can read hot_reload at comptime).
    mod_app_impl.addImport("build_options", build_options.createModule());
    mod_app.addImport("build_options", build_options.createModule());

    // -----------------------------------------------------------------------
    // run-dev — build + run the app with hot-reload enabled.
    //   zig build run-dev → launch zig-gui-dev binary (hot_reload = true)
    //
    // NOTE: main.zig is a placeholder until module 09 renderer is wired up.
    //       The step is declared now so R56 acceptance criterion is satisfied.
    // -----------------------------------------------------------------------
    const dev_options = b.addOptions();
    dev_options.addOption(bool, "hot_reload", true);

    const run_dev_mod = b.createModule(.{
        .root_source_file = b.path("src/app/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    run_dev_mod.addOptions("build_options", dev_options);

    const run_dev_exe = b.addExecutable(.{
        .name = "zig-gui-dev",
        .root_module = run_dev_mod,
    });

    const run_dev_cmd = b.addRunArtifact(run_dev_exe);
    const run_dev_step = b.step("run-dev", "Run the app with hot-reload enabled");
    run_dev_step.dependOn(&run_dev_cmd.step);

    // -----------------------------------------------------------------------
    // test-m7-widget — Milestone 7 widget unit tests (R70-R79).
    //   zig build               → compile only (compile check)
    //   zig build test-m7-widget → compile + run
    // -----------------------------------------------------------------------
    const m7_widget_test_mod = b.createModule(.{
        .root_source_file = b.path("src/07/m7_widget_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    m7_widget_test_mod.addImport("types.zig", mod07);
    m7_widget_test_mod.addImport("../03/types.zig", mod03);
    m7_widget_test_mod.addImport("../05/types.zig", mod05);
    m7_widget_test_mod.addImport("../06/types.zig", mod06);
    m7_widget_test_mod.addImport("../app/font_family.zig", mod_font_family);
    m7_widget_test_mod.addIncludePath(b.path("deps"));
    m7_widget_test_mod.addCSourceFile(.{ .file = b.path("deps/stb_impl.c"), .flags = &.{} });
    m7_widget_test_mod.link_libc = true;
    const m7_widget_test = b.addTest(.{ .name = "m7-widget-test", .root_module = m7_widget_test_mod });
    b.default_step.dependOn(&m7_widget_test.step);
    const run_m7_widget_test = b.addRunArtifact(m7_widget_test);
    const m7_widget_test_step = b.step("test-m7-widget", "Run Milestone 7 widget unit tests (R70-R79)");
    m7_widget_test_step.dependOn(&run_m7_widget_test.step);

    // -----------------------------------------------------------------------
    // test-toast — ToastManager unit tests (R74, no GPU).
    //   zig build            → compile only
    //   zig build test-toast → compile + run
    // -----------------------------------------------------------------------
    const toast_test_mod = b.createModule(.{
        .root_source_file = b.path("src/app/toast_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    toast_test_mod.addImport("../01/types.zig", mod01);
    toast_test_mod.addImport("../02/types.zig", mod02);
    toast_test_mod.addImport("../05/types.zig", mod05);
    toast_test_mod.addImport("overlay.zig", mod_overlay);
    toast_test_mod.addIncludePath(b.path("deps"));
    toast_test_mod.addCSourceFile(.{ .file = b.path("deps/stb_impl.c"), .flags = &.{} });
    toast_test_mod.link_libc = true;
    const toast_test = b.addTest(.{ .name = "toast-test", .root_module = toast_test_mod });
    b.default_step.dependOn(&toast_test.step);
    const run_toast_test = b.addRunArtifact(toast_test);
    const toast_test_step = b.step("test-toast", "Run ToastManager unit tests (R74, no GPU)");
    toast_test_step.dependOn(&run_toast_test.step);

    // -----------------------------------------------------------------------
    // test-dialog — DialogManager unit tests (R75, no GPU).
    //   zig build             → compile only
    //   zig build test-dialog → compile + run
    // -----------------------------------------------------------------------
    const dialog_test_mod = b.createModule(.{
        .root_source_file = b.path("src/app/dialog_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    dialog_test_mod.addImport("../01/types.zig", mod01);
    dialog_test_mod.addImport("../07/types.zig", mod07);
    dialog_test_mod.addImport("../05/types.zig", mod05);
    dialog_test_mod.addImport("../06/types.zig", mod06);
    dialog_test_mod.addImport("overlay.zig", mod_overlay);
    dialog_test_mod.addImport("../app/font_family.zig", mod_font_family);
    dialog_test_mod.addIncludePath(b.path("deps"));
    dialog_test_mod.addCSourceFile(.{ .file = b.path("deps/stb_impl.c"), .flags = &.{} });
    dialog_test_mod.link_libc = true;
    const dialog_test = b.addTest(.{ .name = "dialog-test", .root_module = dialog_test_mod });
    b.default_step.dependOn(&dialog_test.step);
    const run_dialog_test = b.addRunArtifact(dialog_test);
    const dialog_test_step = b.step("test-dialog", "Run DialogManager unit tests (R75, no GPU)");
    dialog_test_step.dependOn(&run_dialog_test.step);

    // -----------------------------------------------------------------------
    // test-date-util — Date utility unit tests (R78, pure).
    //   zig build               → compile only
    //   zig build test-date-util → compile + run
    // -----------------------------------------------------------------------
    const date_util_test_mod = b.createModule(.{
        .root_source_file = b.path("src/app/date_util_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    date_util_test_mod.addImport("../07/types.zig", mod07);
    date_util_test_mod.addImport("../03/types.zig", mod03);
    date_util_test_mod.addImport("../05/types.zig", mod05);
    date_util_test_mod.addImport("../06/types.zig", mod06);
    date_util_test_mod.addImport("../app/font_family.zig", mod_font_family);
    date_util_test_mod.addIncludePath(b.path("deps"));
    date_util_test_mod.addCSourceFile(.{ .file = b.path("deps/stb_impl.c"), .flags = &.{} });
    date_util_test_mod.link_libc = true;
    const date_util_test = b.addTest(.{ .name = "date-util-test", .root_module = date_util_test_mod });
    b.default_step.dependOn(&date_util_test.step);
    const run_date_util_test = b.addRunArtifact(date_util_test);
    const date_util_test_step = b.step("test-date-util", "Run date utility unit tests (R78, pure)");
    date_util_test_step.dependOn(&run_date_util_test.step);

    // -----------------------------------------------------------------------
    // test-locale — Locale and date formatting unit tests (M15-01 + M15-02, pure).
    //   zig build             → compile only
    //   zig build test-locale → compile + run
    // -----------------------------------------------------------------------
    const locale_test_mod = b.createModule(.{
        .root_source_file = b.path("src/app/locale_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    const locale_test = b.addTest(.{ .name = "locale-test", .root_module = locale_test_mod });
    b.default_step.dependOn(&locale_test.step);
    const run_locale_test = b.addRunArtifact(locale_test);
    const locale_test_step = b.step("test-locale", "Run locale/date formatting unit tests (M15, pure)");
    locale_test_step.dependOn(&run_locale_test.step);

    // -----------------------------------------------------------------------
    // test-context-menu — ContextMenuManager unit tests (R7D, no GPU).
    //   zig build                  → compile only
    //   zig build test-context-menu → compile + run
    // -----------------------------------------------------------------------
    const context_menu_test_mod = b.createModule(.{
        .root_source_file = b.path("src/app/context_menu_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    context_menu_test_mod.addImport("../01/types.zig", mod01);
    context_menu_test_mod.addImport("../02/types.zig", mod02);
    context_menu_test_mod.addImport("../05/types.zig", mod05);
    context_menu_test_mod.addImport("overlay.zig", mod_overlay);
    context_menu_test_mod.addImport("font_family.zig", mod_font_family);
    context_menu_test_mod.addIncludePath(b.path("deps"));
    context_menu_test_mod.addCSourceFile(.{ .file = b.path("deps/stb_impl.c"), .flags = &.{} });
    context_menu_test_mod.link_libc = true;
    const context_menu_test = b.addTest(.{ .name = "context-menu-test", .root_module = context_menu_test_mod });
    b.default_step.dependOn(&context_menu_test.step);
    const run_context_menu_test = b.addRunArtifact(context_menu_test);
    const context_menu_test_step = b.step("test-context-menu", "Run ContextMenuManager unit tests (R7D, no GPU)");
    context_menu_test_step.dependOn(&run_context_menu_test.step);

    // -----------------------------------------------------------------------
    // test-nav — Navigator unit tests (R80, headless).
    //   zig build          → compile only
    //   zig build test-nav → compile + run
    // -----------------------------------------------------------------------
    const nav_test_mod = b.createModule(.{
        .root_source_file = b.path("src/app/navigator_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    nav_test_mod.addImport("types.zig", mod_app);
    nav_test_mod.addImport("../07/types.zig", mod07);
    nav_test_mod.addImport("../05/types.zig", mod05);
    nav_test_mod.addIncludePath(b.path("deps"));
    nav_test_mod.addCSourceFile(.{ .file = b.path("deps/stb_impl.c"), .flags = &.{} });
    nav_test_mod.link_libc = true;
    const nav_test = b.addTest(.{ .name = "nav-test", .root_module = nav_test_mod });
    b.default_step.dependOn(&nav_test.step);
    const run_nav_test = b.addRunArtifact(nav_test);
    const nav_test_step = b.step("test-nav", "Run Navigator unit tests (R80, headless)");
    nav_test_step.dependOn(&run_nav_test.step);

    // -----------------------------------------------------------------------
    // test-tooltip — TooltipManager unit tests (R7C, no GPU).
    //   zig build              → compile only
    //   zig build test-tooltip → compile + run
    // -----------------------------------------------------------------------
    const tooltip_test_mod = b.createModule(.{
        .root_source_file = b.path("src/app/tooltip_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    tooltip_test_mod.addImport("../01/types.zig", mod01);
    tooltip_test_mod.addImport("../02/types.zig", mod02);
    tooltip_test_mod.addImport("../05/types.zig", mod05);
    tooltip_test_mod.addImport("../07/types.zig", mod07);
    tooltip_test_mod.addImport("overlay.zig", mod_overlay);
    tooltip_test_mod.addImport("font_family.zig", mod_font_family);
    tooltip_test_mod.addIncludePath(b.path("deps"));
    tooltip_test_mod.addCSourceFile(.{ .file = b.path("deps/stb_impl.c"), .flags = &.{} });
    tooltip_test_mod.link_libc = true;
    const tooltip_test = b.addTest(.{ .name = "tooltip-test", .root_module = tooltip_test_mod });
    b.default_step.dependOn(&tooltip_test.step);
    const run_tooltip_test = b.addRunArtifact(tooltip_test);
    const tooltip_test_step = b.step("test-tooltip", "Run TooltipManager unit tests (R7C, no GPU)");
    tooltip_test_step.dependOn(&run_tooltip_test.step);

    // -----------------------------------------------------------------------
    // test-app-state — AppState(T) unit tests (R81, pure, no GPU).
    //   zig build               → compile only (compile check)
    //   zig build test-app-state → compile + run
    // -----------------------------------------------------------------------
    const app_state_test_mod = b.createModule(.{
        .root_source_file = b.path("src/app/app_state_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    // app_state_test.zig imports signal.zig and app_state.zig by relative path.
    // No external modules needed — both files import only std.
    const app_state_test = b.addTest(.{ .name = "app-state-test", .root_module = app_state_test_mod });
    b.default_step.dependOn(&app_state_test.step);
    const run_app_state_test = b.addRunArtifact(app_state_test);
    const app_state_test_step = b.step("test-app-state", "Run AppState unit tests (R81, pure)");
    app_state_test_step.dependOn(&run_app_state_test.step);

    // -----------------------------------------------------------------------
    // test-settings — PersistentSettings unit tests (R82, file I/O).
    //   zig build               → compile only (compile check)
    //   zig build test-settings → compile + run
    // -----------------------------------------------------------------------
    const settings_test_mod = b.createModule(.{
        .root_source_file = b.path("src/app/persistent_settings_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    const settings_test = b.addTest(.{ .name = "settings-test", .root_module = settings_test_mod });
    b.default_step.dependOn(&settings_test.step);
    const run_settings_test = b.addRunArtifact(settings_test);
    const settings_test_step = b.step("test-settings", "Run PersistentSettings unit tests (R82, file I/O)");
    settings_test_step.dependOn(&run_settings_test.step);

    // -----------------------------------------------------------------------
    // test-multi-window — MultiWindowApp unit tests (R83, headless — no GPU).
    //   zig build                  → compile only (compile check)
    //   zig build test-multi-window → compile + run
    // -----------------------------------------------------------------------
    const multi_window_test_mod = b.createModule(.{
        .root_source_file = b.path("src/app/multi_window_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    // multi_window_test.zig imports:
    //   multi_window.zig → overlay.zig, binding.zig, events.zig, navigator.zig, mod05, mod07
    //   ../01/types.zig  → for is_shared field check
    //   ../07/types.zig  → for Scene (mod07 brings in mod02/stb_truetype)
    //   ../05/types.zig  → for Tokens/Palette
    multi_window_test_mod.addImport("../01/types.zig", mod01);
    multi_window_test_mod.addImport("../07/types.zig", mod07);
    multi_window_test_mod.addImport("../05/types.zig", mod05);
    multi_window_test_mod.addImport("../06/types.zig", mod06);
    multi_window_test_mod.addImport("../03/types.zig", mod03);
    multi_window_test_mod.addImport("../app/font_family.zig", mod_font_family);
    multi_window_test_mod.addImport("overlay.zig", mod_overlay);
    multi_window_test_mod.addImport("binding.zig", mod_binding);
    multi_window_test_mod.addImport("events.zig", mod_events);
    multi_window_test_mod.addImport("navigator.zig", mod_navigator);
    multi_window_test_mod.addIncludePath(b.path("deps"));
    multi_window_test_mod.addCSourceFile(.{ .file = b.path("deps/stb_impl.c"), .flags = &.{} });
    multi_window_test_mod.link_libc = true;
    const multi_window_test = b.addTest(.{ .name = "multi-window-test", .root_module = multi_window_test_mod });
    b.default_step.dependOn(&multi_window_test.step);
    const run_multi_window_test = b.addRunArtifact(multi_window_test);
    const multi_window_test_step = b.step("test-multi-window", "Run MultiWindowApp unit tests (R83, headless)");
    multi_window_test_step.dependOn(&run_multi_window_test.step);

    // -----------------------------------------------------------------------
    // test-debug-overlay — DebugOverlay unit tests (R90, no GPU).
    //   zig build                    → compile only
    //   zig build test-debug-overlay → compile + run
    // -----------------------------------------------------------------------
    const debug_overlay_test_mod = b.createModule(.{
        .root_source_file = b.path("src/app/debug_overlay_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    debug_overlay_test_mod.addImport("../01/types.zig", mod01);
    debug_overlay_test_mod.addImport("../02/types.zig", mod02);
    debug_overlay_test_mod.addImport("../05/types.zig", mod05);
    debug_overlay_test_mod.addImport("../07/types.zig", mod07);
    debug_overlay_test_mod.addIncludePath(b.path("deps"));
    debug_overlay_test_mod.addCSourceFile(.{ .file = b.path("deps/stb_impl.c"), .flags = &.{} });
    debug_overlay_test_mod.link_libc = true;
    const debug_overlay_test = b.addTest(.{ .name = "debug-overlay-test", .root_module = debug_overlay_test_mod });
    b.default_step.dependOn(&debug_overlay_test.step);
    const run_debug_overlay_test = b.addRunArtifact(debug_overlay_test);
    const debug_overlay_test_step = b.step("test-debug-overlay", "Run DebugOverlay unit tests (R90, no GPU)");
    debug_overlay_test_step.dependOn(&run_debug_overlay_test.step);

    // -----------------------------------------------------------------------
    // test-scene-dump — Scene dump unit tests (R91, no GPU).
    //   zig build              → compile only
    //   zig build test-scene-dump → compile + run
    // -----------------------------------------------------------------------
    const scene_dump_test_mod = b.createModule(.{
        .root_source_file = b.path("src/07/debug_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    scene_dump_test_mod.addImport("types.zig", mod07);
    const scene_dump_test = b.addTest(.{ .name = "scene-dump-test", .root_module = scene_dump_test_mod });
    b.default_step.dependOn(&scene_dump_test.step);
    const run_scene_dump_test = b.addRunArtifact(scene_dump_test);
    const scene_dump_test_step = b.step("test-scene-dump", "Run Scene dump unit tests (R91, no GPU)");
    scene_dump_test_step.dependOn(&run_scene_dump_test.step);

    // -----------------------------------------------------------------------
    // test-perf-hud — PerfHud unit tests (R92, no GPU).
    //   zig build            → compile only
    //   zig build test-perf-hud → compile + run
    // -----------------------------------------------------------------------
    const perf_hud_test_mod = b.createModule(.{
        .root_source_file = b.path("src/app/perf_hud_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    perf_hud_test_mod.addImport("../01/types.zig", mod01);
    perf_hud_test_mod.addImport("../02/types.zig", mod02);
    perf_hud_test_mod.addImport("../05/types.zig", mod05);
    perf_hud_test_mod.addIncludePath(b.path("deps"));
    perf_hud_test_mod.addCSourceFile(.{ .file = b.path("deps/stb_impl.c"), .flags = &.{} });
    perf_hud_test_mod.link_libc = true;
    const perf_hud_test = b.addTest(.{ .name = "perf-hud-test", .root_module = perf_hud_test_mod });
    b.default_step.dependOn(&perf_hud_test.step);
    const run_perf_hud_test = b.addRunArtifact(perf_hud_test);
    const perf_hud_test_step = b.step("test-perf-hud", "Run PerfHud unit tests (R92, no GPU)");
    perf_hud_test_step.dependOn(&run_perf_hud_test.step);

    // -----------------------------------------------------------------------
    // test-theme-swap — Theme live-swap unit tests (R93, pure Zig).
    //   zig build              → compile only
    //   zig build test-theme-swap → compile + run
    // -----------------------------------------------------------------------
    const theme_swap_test_mod = b.createModule(.{
        .root_source_file = b.path("src/app/theme_swap_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    theme_swap_test_mod.addImport("../05/types.zig", mod05);
    const theme_swap_test = b.addTest(.{ .name = "theme-swap-test", .root_module = theme_swap_test_mod });
    b.default_step.dependOn(&theme_swap_test.step);
    const run_theme_swap_test = b.addRunArtifact(theme_swap_test);
    const theme_swap_test_step = b.step("test-theme-swap", "Run Theme live-swap unit tests (R93, pure)");
    theme_swap_test_step.dependOn(&run_theme_swap_test.step);

    // -----------------------------------------------------------------------
    // test-font-scale — Font-scale unit tests (R94, pure Zig).
    //   zig build              → compile only
    //   zig build test-font-scale → compile + run
    // -----------------------------------------------------------------------
    const font_scale_test_mod = b.createModule(.{
        .root_source_file = b.path("src/app/font_scale_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    font_scale_test_mod.addImport("../05/types.zig", mod05);
    const font_scale_test = b.addTest(.{ .name = "font-scale-test", .root_module = font_scale_test_mod });
    b.default_step.dependOn(&font_scale_test.step);
    const run_font_scale_test = b.addRunArtifact(font_scale_test);
    const font_scale_test_step = b.step("test-font-scale", "Run font-scale unit tests (R94, pure)");
    font_scale_test_step.dependOn(&run_font_scale_test.step);

    // -----------------------------------------------------------------------
    // test-high-contrast — High-contrast palette unit tests (R95, pure Zig).
    //   zig build                  → compile only
    //   zig build test-high-contrast → compile + run
    // -----------------------------------------------------------------------
    const high_contrast_test_mod = b.createModule(.{
        .root_source_file = b.path("src/05/high_contrast_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    high_contrast_test_mod.addImport("../../docs/specs/05.types.zig", mod05);
    high_contrast_test_mod.addImport("../03_element_store/types.zig", mod03);
    const high_contrast_test = b.addTest(.{ .name = "high-contrast-test", .root_module = high_contrast_test_mod });
    b.default_step.dependOn(&high_contrast_test.step);
    const run_high_contrast_test = b.addRunArtifact(high_contrast_test);
    const high_contrast_test_step = b.step("test-high-contrast", "Run high-contrast palette unit tests (R95, pure)");
    high_contrast_test_step.dependOn(&run_high_contrast_test.step);

    // -----------------------------------------------------------------------
    // M10 unit tests
    // -----------------------------------------------------------------------

    // test-file-logger — FileLogger unit tests (RA2, file I/O).
    //   zig build                → compile only
    //   zig build test-file-logger → compile + run
    const file_logger_test_mod = b.createModule(.{
        .root_source_file = b.path("src/app/file_logger_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    file_logger_test_mod.addImport("file_logger.zig", mod_file_logger);
    file_logger_test_mod.addImport("app.zig", mod_app_impl);
    const file_logger_test = b.addTest(.{ .name = "file-logger-test", .root_module = file_logger_test_mod });
    b.default_step.dependOn(&file_logger_test.step);
    const run_file_logger_test = b.addRunArtifact(file_logger_test);
    const file_logger_test_step = b.step("test-file-logger", "Run FileLogger unit tests (RA2, file I/O)");
    file_logger_test_step.dependOn(&run_file_logger_test.step);

    // test-budget-arena — BudgetedArena unit tests (RA1, pure).
    //   zig build                 → compile only
    //   zig build test-budget-arena → compile + run
    const budget_arena_test_mod = b.createModule(.{
        .root_source_file = b.path("src/app/budgeted_arena_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    budget_arena_test_mod.addImport("budgeted_arena.zig", mod_budgeted_arena);
    budget_arena_test_mod.addImport("app.zig", mod_app_impl);
    const budget_arena_test = b.addTest(.{ .name = "budget-arena-test", .root_module = budget_arena_test_mod });
    b.default_step.dependOn(&budget_arena_test.step);
    const run_budget_arena_test = b.addRunArtifact(budget_arena_test);
    const budget_arena_test_step = b.step("test-budget-arena", "Run BudgetedArena unit tests (RA1, pure)");
    budget_arena_test_step.dependOn(&run_budget_arena_test.step);

    // test-startup-error — startup_error unit tests (RA3, platform detection).
    //   zig build                  → compile only
    //   zig build test-startup-error → compile + run
    const startup_error_test_mod = b.createModule(.{
        .root_source_file = b.path("src/app/startup_error_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    startup_error_test_mod.addImport("startup_error.zig", mod_startup_error);
    // Windows: user32 needed for MessageBoxW (already linked transitively via GLFW in
    // the main app, but the test binary is standalone).
    if (target.result.os.tag == .windows) {
        startup_error_test_mod.linkSystemLibrary("user32", .{});
    }
    const startup_error_test = b.addTest(.{ .name = "startup-error-test", .root_module = startup_error_test_mod });
    b.default_step.dependOn(&startup_error_test.step);
    const run_startup_error_test = b.addRunArtifact(startup_error_test);
    const startup_error_test_step = b.step("test-startup-error", "Run startup_error unit tests (RA3)");
    startup_error_test_step.dependOn(&run_startup_error_test.step);

    // test-window-state — WindowStateManager unit tests (RA4, headless).
    //   zig build                → compile only
    //   zig build test-window-state → compile + run
    const window_state_test_mod = b.createModule(.{
        .root_source_file = b.path("src/app/window_state_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    window_state_test_mod.addImport("window_state.zig", mod_window_state);
    window_state_test_mod.addImport("persistent_settings.zig", mod_persistent_settings);
    window_state_test_mod.addImport("app.zig", mod_app_impl);
    const window_state_test = b.addTest(.{ .name = "window-state-test", .root_module = window_state_test_mod });
    b.default_step.dependOn(&window_state_test.step);
    const run_window_state_test = b.addRunArtifact(window_state_test);
    const window_state_test_step = b.step("test-window-state", "Run WindowStateManager unit tests (RA4, headless)");
    window_state_test_step.dependOn(&run_window_state_test.step);

    // test-error-boundary — ErrorBoundary unit tests (RA0, headless).
    //   zig build                  → compile only
    //   zig build test-error-boundary → compile + run
    const error_boundary_test_mod = b.createModule(.{
        .root_source_file = b.path("src/app/error_boundary_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    error_boundary_test_mod.addImport("error_boundary.zig", mod_error_boundary);
    error_boundary_test_mod.addImport("../05/types.zig", mod05);
    error_boundary_test_mod.addImport("../07/types.zig", mod07);
    error_boundary_test_mod.addImport("app.zig", mod_app_impl);
    error_boundary_test_mod.addIncludePath(b.path("deps"));
    error_boundary_test_mod.addCSourceFile(.{ .file = b.path("deps/stb_impl.c"), .flags = &.{} });
    error_boundary_test_mod.link_libc = true;
    const error_boundary_test = b.addTest(.{ .name = "error-boundary-test", .root_module = error_boundary_test_mod });
    b.default_step.dependOn(&error_boundary_test.step);
    const run_error_boundary_test = b.addRunArtifact(error_boundary_test);
    const error_boundary_test_step = b.step("test-error-boundary", "Run ErrorBoundary unit tests (RA0, headless)");
    error_boundary_test_step.dependOn(&run_error_boundary_test.step);

    // test-m11 — M11 input completeness unit tests (RB0–RB5, headless).
    //   zig build           → compile only
    //   zig build test-m11  → compile + run
    const m11_test_mod = b.createModule(.{
        .root_source_file = b.path("src/app/m11_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    m11_test_mod.addImport("../01/types.zig", mod01);
    m11_test_mod.addImport("../05/types.zig", mod05);
    m11_test_mod.addImport("../06/types.zig", mod06);
    m11_test_mod.addImport("../07/types.zig", mod07);
    m11_test_mod.addImport("app.zig", mod_app_impl);
    m11_test_mod.addIncludePath(b.path("deps"));
    m11_test_mod.addCSourceFile(.{ .file = b.path("deps/stb_impl.c"), .flags = &.{} });
    m11_test_mod.link_libc = true;
    const m11_test = b.addTest(.{ .name = "m11-test", .root_module = m11_test_mod });
    b.default_step.dependOn(&m11_test.step);
    const run_m11_test = b.addRunArtifact(m11_test);
    const m11_test_step = b.step("test-m11", "Run M11 input completeness unit tests (RB0–RB5, headless)");
    m11_test_step.dependOn(&run_m11_test.step);

    // -----------------------------------------------------------------------
    // test-m12 — M12 layout extensions acceptance tests (RC0–RC4).
    //   zig build test-m12 → run M12 tests headless
    // -----------------------------------------------------------------------
    const m12_test_mod = b.createModule(.{
        .root_source_file = b.path("src/app/m12_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    m12_test_mod.addImport("../01/types.zig", mod01);
    m12_test_mod.addImport("../03/types.zig", mod03);
    m12_test_mod.addImport("../04/types.zig", mod04);
    m12_test_mod.addImport("../05/types.zig", mod05);
    m12_test_mod.addImport("../06/types.zig", mod06);
    m12_test_mod.addImport("../07/types.zig", mod07);
    m12_test_mod.addImport("../09/types.zig", mod09);
    m12_test_mod.addImport("app.zig", mod_app_impl);
    m12_test_mod.addIncludePath(b.path("deps"));
    m12_test_mod.addCSourceFile(.{ .file = b.path("deps/stb_impl.c"), .flags = &.{} });
    m12_test_mod.link_libc = true;
    const m12_test = b.addTest(.{ .name = "m12-test", .root_module = m12_test_mod });
    const run_m12_test = b.addRunArtifact(m12_test);
    const m12_test_step = b.step("test-m12", "Run M12 layout extension tests (RC0–RC4, headless)");
    m12_test_step.dependOn(&run_m12_test.step);

    // -----------------------------------------------------------------------
    // test-m16 — M16 platform integration unit tests (RF1–RF4, headless).
    //   zig build          → compile only
    //   zig build test-m16 → compile + run
    // -----------------------------------------------------------------------
    const m16_test_mod = b.createModule(.{
        .root_source_file = b.path("src/app/m16_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    m16_test_mod.addImport("../01/types.zig", mod01);
    m16_test_mod.addImport("../05/types.zig", mod05);
    m16_test_mod.addImport("app.zig", mod_app_impl);
    const m16_test = b.addTest(.{ .name = "m16-test", .root_module = m16_test_mod });
    b.default_step.dependOn(&m16_test.step);
    const run_m16_test = b.addRunArtifact(m16_test);
    const m16_test_step = b.step("test-m16", "Run M16 platform integration unit tests (RF1–RF4, headless)");
    m16_test_step.dependOn(&run_m16_test.step);

    // -----------------------------------------------------------------------
    // test-m17 — M17 accessibility unit tests (RG1, RG4, RG5, headless).
    //   zig build          → compile only
    //   zig build test-m17 → compile + run
    // -----------------------------------------------------------------------
    const m17_test_mod = b.createModule(.{
        .root_source_file = b.path("src/app/m17_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    m17_test_mod.addImport("../07/types.zig", mod07);
    m17_test_mod.addImport("../03/types.zig", mod03);
    m17_test_mod.addImport("../05/types.zig", mod05);
    m17_test_mod.addImport("../06/types.zig", mod06);
    // stb_truetype needed by mod06 (indirectly for resolveClasses)
    m17_test_mod.addIncludePath(b.path("deps"));
    m17_test_mod.addCSourceFile(.{ .file = b.path("deps/stb_impl.c"), .flags = &.{} });
    m17_test_mod.link_libc = true;
    const m17_test = b.addTest(.{ .name = "m17-test", .root_module = m17_test_mod });
    b.default_step.dependOn(&m17_test.step);
    const run_m17_test = b.addRunArtifact(m17_test);
    const m17_test_step = b.step("test-m17", "Run M17 accessibility unit tests (RG1, RG4, RG5, headless)");
    m17_test_step.dependOn(&run_m17_test.step);

    // -----------------------------------------------------------------------
    // test-tray — Tray unit tests (RF0, headless — no GPU, no real tray icon).
    //   zig build           → compile only
    //   zig build test-tray → compile + run
    // -----------------------------------------------------------------------
    const tray_test_mod = b.createModule(.{
        .root_source_file = b.path("src/app/tray_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    // tray.zig is registered as mod_tray (named module) so the build system sees
    // only one canonical identity for src/app/tray.zig across app.zig and the test.
    tray_test_mod.addImport("tray.zig", mod_tray);
    tray_test_mod.addImport("app.zig", mod_app_impl);
    // app.zig brings in stb_truetype (via mod02) and Win32 libs transitively;
    // re-add them explicitly here so the standalone test binary links correctly.
    tray_test_mod.addIncludePath(b.path("deps"));
    tray_test_mod.addCSourceFile(.{ .file = b.path("deps/stb_impl.c"), .flags = &.{} });
    tray_test_mod.link_libc = true;
    if (target.result.os.tag == .windows) {
        tray_test_mod.linkSystemLibrary("gdi32", .{});
        tray_test_mod.linkSystemLibrary("user32", .{});
        tray_test_mod.linkSystemLibrary("shell32", .{});
    }
    const tray_test = b.addTest(.{ .name = "tray-test", .root_module = tray_test_mod });
    b.default_step.dependOn(&tray_test.step);
    const run_tray_test = b.addRunArtifact(tray_test);
    const tray_test_step = b.step("test-tray", "Run Tray unit tests (RF0, headless — no GPU, no tray icon shown)");
    tray_test_step.dependOn(&run_tray_test.step);

    // -----------------------------------------------------------------------
    // run-demo — Showcase Demo Application (DEMO_APP.md).
    //   zig build run-demo → build + run the showcase app
    // -----------------------------------------------------------------------
    const demo_mod = b.createModule(.{
        .root_source_file = b.path("src/demo/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    demo_mod.addImport("app", mod_app);
    demo_mod.addImport("navigator.zig", mod_navigator);
    demo_mod.addImport("../01/types.zig", mod01);
    demo_mod.addImport("../02/types.zig", mod02);
    demo_mod.addImport("../03/types.zig", mod03);
    demo_mod.addImport("../05/types.zig", mod05);
    demo_mod.addImport("../06/types.zig", mod06);
    demo_mod.addImport("../07/types.zig", mod07);
    demo_mod.addImport("../08/types.zig", mod08);
    demo_mod.addImport("events.zig", mod_events);
    demo_mod.addImport("build_options", build_options.createModule());
    demo_mod.addImport("../strings.zig", strings_mod);
    // C/GPU dependencies are inherited transitively via mod_app → mod02/mod09.
    // Do NOT re-add stb_impl.c here — mod02 already owns it; adding it twice
    // causes duplicate-symbol linker errors.
    demo_mod.addIncludePath(glfw_dep.path("include"));
    demo_mod.addIncludePath(.{ .cwd_relative = vulkan_include });
    demo_mod.linkLibrary(glfw_lib);
    demo_mod.addLibraryPath(.{ .cwd_relative = vulkan_lib });
    demo_mod.linkSystemLibrary("vulkan-1", .{});
    if (target.result.os.tag == .windows) {
        demo_mod.linkSystemLibrary("gdi32", .{});
        demo_mod.linkSystemLibrary("user32", .{});
        demo_mod.linkSystemLibrary("shell32", .{});
    }

    const demo_exe = b.addExecutable(.{
        .name = "showcase",
        .root_module = demo_mod,
    });
    // Ensure the string table is generated before the demo binary compiles.
    demo_exe.step.dependOn(&run_strings_codegen.step);
    b.installArtifact(demo_exe);
    const run_demo_cmd = b.addRunArtifact(demo_exe);
    const run_demo_step = b.step("run-demo", "Run the zig-gui Showcase Demo Application");
    run_demo_step.dependOn(&run_demo_cmd.step);

    // -----------------------------------------------------------------------
    // M19-05: App installer / packaging
    //   zig build package -- --version 1.0.1
    //
    // Creates a distributable archive (.zip on Windows, .tar.gz on Linux)
    // containing the binary, fonts, and optional manifest.
    // -----------------------------------------------------------------------
    const package_mod = b.createModule(.{
        .root_source_file = b.path("src/tools/package.zig"),
        .target = target,
        .optimize = optimize,
    });
    const package_exe = b.addExecutable(.{
        .name = "package",
        .root_module = package_mod,
    });
    const run_package_cmd = b.addRunArtifact(package_exe);
    // Pass through all arguments from the build command
    run_package_cmd.addArg("--binary-path");
    // Use the installed binary path (add .exe on Windows)
    const showcase_binary_name = if (target.result.os.tag == .windows) "showcase.exe" else "showcase";
    const showcase_path = b.fmt("zig-out/bin/{s}", .{showcase_binary_name});
    run_package_cmd.addArg(showcase_path);
    run_package_cmd.addArg("--output");
    run_package_cmd.addArg("dist");
    run_package_cmd.addArg("--fonts-dir");
    run_package_cmd.addArg("testdata");

    const package_step = b.step("package", "Bundle binary + fonts + manifest into distributable archive");
    package_step.dependOn(&demo_exe.step); // Ensure binary is built first
    package_step.dependOn(&run_package_cmd.step);

    // -----------------------------------------------------------------------
    // generate-manifest — helper tool for creating update manifests
    //   zig build run-generate-manifest -- path/to/app.zip https://example.com/app.zip
    //
    // Computes SHA256 of a binary and outputs manifest.json
    // -----------------------------------------------------------------------
    const manifest_mod = b.createModule(.{
        .root_source_file = b.path("src/tools/generate_manifest.zig"),
        .target = target,
        .optimize = optimize,
    });
    const manifest_exe = b.addExecutable(.{
        .name = "generate_manifest",
        .root_module = manifest_mod,
    });
    const run_manifest_cmd = b.addRunArtifact(manifest_exe);

    const manifest_step = b.step("run-generate-manifest", "Generate update manifest for a package");
    manifest_step.dependOn(&run_manifest_cmd.step);

    // -----------------------------------------------------------------------
    // visual-check — render 3 frames, write PNG, verify it is not blank.
    //   zig build visual-check
    //
    // Requires a display (GLFW opens a real window). The window is visible
    // briefly, then the process exits after 3 frames.
    // -----------------------------------------------------------------------
    const screenshot_path = "testdata/screenshot_actual.png";

    // Step 1: run the demo in screenshot mode.
    const screenshot_cmd = b.addRunArtifact(demo_exe);
    screenshot_cmd.addArg("--screenshot-frames");
    screenshot_cmd.addArg("3");
    screenshot_cmd.addArg("--screenshot-out");
    screenshot_cmd.addArg(screenshot_path);

    // Step 2: build and run the visual checker.
    const checker_mod = b.createModule(.{
        .root_source_file = b.path("src/tools/visual_check.zig"),
        .target = target,
        .optimize = optimize,
    });
    const checker_exe = b.addExecutable(.{
        .name = "visual_check",
        .root_module = checker_mod,
    });
    const run_checker = b.addRunArtifact(checker_exe);
    run_checker.addArg(screenshot_path);
    run_checker.step.dependOn(&screenshot_cmd.step);

    const visual_check_step = b.step("visual-check",
        "Render 3 demo frames, write a PNG, and verify it is not blank");
    visual_check_step.dependOn(&run_checker.step);
}

// ---------------------------------------------------------------------------
// Helper: build GLFW as a static library from source.
// ---------------------------------------------------------------------------
fn buildGlfw(
    b: *std.Build,
    dep: *std.Build.Dependency,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    vulkan_include: []const u8,
) *std.Build.Step.Compile {
    // Determine platform define — needed for all GLFW C files (including common ones).
    const platform_flags: []const []const u8 = switch (target.result.os.tag) {
        .windows => &[_][]const u8{"-D_GLFW_WIN32=1"},
        .linux => &[_][]const u8{"-D_GLFW_X11=1"},
        else => @panic("Unsupported OS for GLFW"),
    };

    const glfw_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    const lib = b.addLibrary(.{
        .name = "glfw",
        .linkage = .static,
        .root_module = glfw_mod,
    });
    glfw_mod.addIncludePath(dep.path("include"));
    glfw_mod.addIncludePath(dep.path("src")); // internal.h etc.
    glfw_mod.addIncludePath(.{ .cwd_relative = vulkan_include });

    const common_sources = [_][]const u8{
        "src/context.c",
        "src/init.c",
        "src/input.c",
        "src/monitor.c",
        "src/platform.c",
        "src/vulkan.c",
        "src/window.c",
        "src/egl_context.c",
        "src/osmesa_context.c",
        "src/null_init.c",
        "src/null_joystick.c",
        "src/null_monitor.c",
        "src/null_window.c",
    };
    for (common_sources) |src| {
        glfw_mod.addCSourceFile(.{ .file = dep.path(src), .flags = platform_flags });
    }

    switch (target.result.os.tag) {
        .windows => {
            glfw_mod.linkSystemLibrary("gdi32", .{});
            glfw_mod.linkSystemLibrary("user32", .{});
            glfw_mod.linkSystemLibrary("shell32", .{});
            const win32_sources = [_][]const u8{
                "src/win32_init.c",
                "src/win32_joystick.c",
                "src/win32_module.c",
                "src/win32_monitor.c",
                "src/win32_thread.c",
                "src/win32_time.c",
                "src/win32_window.c",
                "src/wgl_context.c",
            };
            for (win32_sources) |src| {
                glfw_mod.addCSourceFile(.{ .file = dep.path(src), .flags = platform_flags });
            }
        },
        .linux => {
            glfw_mod.linkSystemLibrary("X11", .{});
            const linux_sources = [_][]const u8{
                "src/posix_module.c",
                "src/posix_poll.c",
                "src/posix_thread.c",
                "src/posix_time.c",
                "src/x11_init.c",
                "src/x11_monitor.c",
                "src/x11_window.c",
                "src/xkb_unicode.c",
                "src/glx_context.c",
                "src/linux_joystick.c",
            };
            for (linux_sources) |src| {
                glfw_mod.addCSourceFile(.{ .file = dep.path(src), .flags = platform_flags });
            }
        },
        else => unreachable, // already panicked above
    }

    return lib;
}
