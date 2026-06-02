const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

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
    // Module 07 — Components (Scene, instantiate, measurePass).
    // Imports: 02 (text/font/atlas), 03 (element store), 05 (theme), 06 (markup).
    // -----------------------------------------------------------------------
    const mod07 = b.addModule("components", .{
        .root_source_file = b.path("src/07/types.zig"),
        .target = target,
        .optimize = optimize,
    });
    // src/07/types.zig imports the other src/ re-export wrappers by relative path.
    // Wire them so the build system resolves C dependencies (stb_truetype for mod02).
    mod07.addImport("../02/types.zig", mod02);
    mod07.addImport("../03/types.zig", mod03);
    mod07.addImport("../05/types.zig", mod05);
    mod07.addImport("../06/types.zig", mod06);

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
    // Module 09 — Renderer (DrawCommand, buildDrawList, GpuAtlas, quad pipeline).
    // Imports: 01 (VulkanBackend/DrawCommand), 02 (GlyphAtlas), 03, 05, 07.
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

    // Acceptance test — docs/specs/09.acceptance_test.zig
    //   zig build test-09  → compile + run (pure CPU tests; GPU tests skip if no Vulkan)
    const accept09_mod = b.createModule(.{
        .root_source_file = b.path("docs/specs/09.acceptance_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    accept09_mod.addImport("types.zig", mod09);
    accept09_mod.addImport("../03_element_store/types.zig", mod03);
    accept09_mod.addImport("../05_theme/types.zig", mod05);
    accept09_mod.addImport("../07_components/types.zig", mod07);
    accept09_mod.addImport("../06_markup_style/types.zig", mod06);
    accept09_mod.addImport("../01_platform/types.zig", mod01);
    accept09_mod.addImport("../04_layout_engine/types.zig", mod04);
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
    unit09_mod.addIncludePath(b.path("deps"));
    unit09_mod.addCSourceFile(.{ .file = b.path("deps/stb_impl.c"), .flags = &.{} });
    unit09_mod.link_libc = true;
    const unit09_test = b.addTest(.{ .name = "09-unit-test", .root_module = unit09_mod });
    const run_unit09 = b.addRunArtifact(unit09_test);
    const unit09_test_step = b.step("test-09-unit", "Run module 09 unit tests (pure CPU)");
    unit09_test_step.dependOn(&run_unit09.step);
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
