const std = @import("std");

// ---------------------------------------------------------------------------
// BackendKind — defined here (not imported from src/) so build.zig stays
// self-contained. Must stay in sync with src/01/types.zig:BackendKind.
// ---------------------------------------------------------------------------
const BackendKind = enum { vulkan, metal, dx12, webgpu };

const ImportAlias = struct {
    alias: []const u8,
    target: []const u8,
};

/// Describes one module the project exports.
const ModuleDesc = struct {
    name: []const u8,
    root: []const u8,
    deps: []const []const u8 = &.{},
    extra_imports: []const ImportAlias = &.{},
    needs_gpu: bool = false,
    needs_stb: bool = false,
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // -----------------------------------------------------------------------
    // GPU backend selection (-Dgpu=vulkan|metal|dx12|webgpu, default per target).
    // -----------------------------------------------------------------------
    const gpu_default: BackendKind = switch (target.result.os.tag) {
        .windows, .linux => .vulkan,
        .macos => .metal,
        .emscripten => .webgpu,
        else => .vulkan,
    };
    const gpu_selected = b.option(BackendKind, "gpu", "GPU backend (vulkan, metal, dx12, webgpu)") orelse gpu_default;

    // RJ0 AC4: Reject unsupported -Dgpu for the target at configure time.
    const supported = switch (target.result.os.tag) {
        .windows, .linux => gpu_selected == .vulkan,
        .macos => gpu_selected == .metal,
        .emscripten => gpu_selected == .webgpu,
        else => gpu_selected == .vulkan,
    };
    if (!supported) {
        @panic(b.fmt("backend '{s}' not supported for target {s}", .{
            @tagName(gpu_selected), @tagName(target.result.os.tag),
        }));
    }

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
    const vert_spv = compileShader(b, glslc_exe, "src/01/shaders/triangle.vert", "triangle.vert.spv");
    const frag_spv = compileShader(b, glslc_exe, "src/01/shaders/triangle.frag", "triangle.frag.spv");
    const quad_vert_spv = compileShader(b, glslc_exe, "src/09/shaders/quad.vert", "quad.vert.spv");
    const quad_frag_spv = compileShader(b, glslc_exe, "src/09/shaders/quad.frag", "quad.frag.spv");

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
    const shaders_mod = b.addModule("embedded_shaders", .{ .root_source_file = shaders_zig });

    // -----------------------------------------------------------------------
    // Descriptor table — every source module in the project.
    // -----------------------------------------------------------------------

    const modules = [_]ModuleDesc{
        .{ .name = "mod01_platform",      .root = "src/01/types.zig",          .needs_gpu = true },
        .{ .name = "mod02_text",          .root = "src/02/types.zig",          .needs_stb = true },
        .{ .name = "mod03_element_store", .root = "src/03/types.zig" },
        .{ .name = "mod04_layout_engine", .root = "src/04/types.zig",
            .deps = &.{"mod03_element_store"},
            .extra_imports = &.{
                ialias("../03/types.zig", "mod03_element_store"),
                ialias("../03_element_store/types.zig", "mod03_element_store"),
            } },
        .{ .name = "mod05_theme",         .root = "src/05/types.zig",
            .deps = &.{"mod03_element_store"},
            .extra_imports = &.{
                ialias("../03/types.zig", "mod03_element_store"),
                ialias("../03_element_store/types.zig", "mod03_element_store"),
            } },
        .{ .name = "mod06_markup",        .root = "src/06/types.zig",
            .deps = &.{ "mod03_element_store", "mod05_theme" },
            .extra_imports = &.{
                ialias("../03/types.zig", "mod03_element_store"),
                ialias("../05/types.zig", "mod05_theme"),
                ialias("../03_element_store/types.zig", "mod03_element_store"),
                ialias("../05_theme/types.zig",         "mod05_theme"),
            } },
        .{ .name = "mod07_components",    .root = "src/07/types.zig",
            .deps = &.{ "mod01_platform", "mod02_text", "mod03_element_store", "mod05_theme", "mod06_markup", "mod_font_family" },
            .extra_imports = &.{
                ialias("../01/types.zig", "mod01_platform"),
                ialias("../02/types.zig", "mod02_text"),
                ialias("../03/types.zig", "mod03_element_store"),
                ialias("../05/types.zig", "mod05_theme"),
                ialias("../06/types.zig", "mod06_markup"),
                ialias("../app/font_family.zig", "mod_font_family"),
                ialias("../03_element_store/types.zig", "mod03_element_store"),
                ialias("../05_theme/types.zig",         "mod05_theme"),
                ialias("../06_markup_style/types.zig",  "mod06_markup"),
                ialias("../02_text/types.zig",          "mod02_text"),
            } },
        .{ .name = "mod08_schema_forms",  .root = "src/08/types.zig",
            .deps = &.{ "mod03_element_store", "mod05_theme", "mod07_components" },
            .extra_imports = &.{
                ialias("../03/types.zig", "mod03_element_store"),
                ialias("../05/types.zig", "mod05_theme"),
                ialias("../07/types.zig", "mod07_components"),
                ialias("../03_element_store/types.zig", "mod03_element_store"),
                ialias("../05_theme/types.zig",         "mod05_theme"),
                ialias("../07_components/types.zig",    "mod07_components"),
            } },
        .{ .name = "mod09_renderer",      .root = "src/09/types.zig",
            .deps = &.{ "mod01_platform", "mod02_text", "mod03_element_store", "mod05_theme", "mod07_components", "mod_image_atlas", "mod_font_family" },
            .extra_imports = &.{
                ialias("../01/types.zig", "mod01_platform"),
                ialias("../02/types.zig", "mod02_text"),
                ialias("../03/types.zig", "mod03_element_store"),
                ialias("../05/types.zig", "mod05_theme"),
                ialias("../07/types.zig", "mod07_components"),
                ialias("../app/image_atlas.zig", "mod_image_atlas"),
                ialias("../app/font_family.zig", "mod_font_family"),
                ialias("../03_element_store/types.zig", "mod03_element_store"),
                ialias("../05_theme/types.zig",         "mod05_theme"),
                ialias("../07_components/types.zig",    "mod07_components"),
                ialias("../06_markup_style/types.zig",  "mod06_markup"),
                ialias("../01_platform/types.zig",      "mod01_platform"),
                ialias("../04_layout_engine/types.zig", "mod04_layout_engine"),
            } },
        .{ .name = "mod10_gpu_backend",   .root = "src/10/backend.zig",
            .deps = &.{ "mod01_platform", "mod02_text", "mod09_renderer" },
            .extra_imports = &.{
                ialias("../01/types.zig", "mod01_platform"),
                ialias("../02/types.zig", "mod02_text"),
                ialias("../09/types.zig", "mod09_renderer"),
            } },
        // App helper modules.
        .{ .name = "mod_font_family",     .root = "src/app/font_family.zig",   .deps = &.{"mod02_text"},
            .extra_imports = &.{ ialias("../02/types.zig", "mod02_text") } },
        .{ .name = "mod_image_atlas",     .root = "src/app/image_atlas.zig" },
        .{ .name = "mod_overlay",         .root = "src/app/overlay.zig",       .deps = &.{"mod01_platform"},
            .extra_imports = &.{ ialias("../01/types.zig", "mod01_platform") } },
        .{ .name = "mod_events",          .root = "src/app/events.zig",        .deps = &.{"mod01_platform"},
            .extra_imports = &.{ ialias("../01/types.zig", "mod01_platform") } },
        .{ .name = "mod_binding",         .root = "src/app/binding.zig",       .deps = &.{"mod07_components"},
            .extra_imports = &.{ ialias("../07/types.zig", "mod07_components") } },
        .{ .name = "mod_navigator",       .root = "src/app/navigator.zig",     .deps = &.{ "mod07_components", "mod05_theme", "mod_error_boundary" },
            .extra_imports = &.{
                ialias("../07/types.zig", "mod07_components"),
                ialias("../05/types.zig", "mod05_theme"),
                ialias("error_boundary.zig", "mod_error_boundary"),
            } },
        .{ .name = "mod_persistent_settings", .root = "src/app/persistent_settings.zig" },
        .{ .name = "mod_file_logger",     .root = "src/app/file_logger.zig" },
        .{ .name = "mod_logger",          .root = "src/app/logger.zig",        .deps = &.{"mod_file_logger"},
            .extra_imports = &.{ ialias("file_logger.zig", "mod_file_logger") } },
        .{ .name = "mod_budgeted_arena",  .root = "src/app/budgeted_arena.zig" },
        .{ .name = "mod_window_state",    .root = "src/app/window_state.zig",  .deps = &.{ "mod_persistent_settings", "mod01_platform" },
            .extra_imports = &.{
                ialias("../01/types.zig", "mod01_platform"),
                ialias("persistent_settings.zig", "mod_persistent_settings"),
            } },
        .{ .name = "mod_error_boundary",  .root = "src/app/error_boundary.zig",.deps = &.{ "mod07_components", "mod05_theme", "mod06_markup" },
            .extra_imports = &.{
                ialias("../07/types.zig", "mod07_components"),
                ialias("../05/types.zig", "mod05_theme"),
                ialias("../06/types.zig", "mod06_markup"),
            } },
        .{ .name = "mod_startup_error",   .root = "src/app/startup_error.zig" },
        .{ .name = "mod_tray",            .root = "src/app/tray.zig",          .deps = &.{"mod07_components"},
            .extra_imports = &.{ ialias("../07/types.zig", "mod07_components") } },
        // mod_app_impl.
        .{ .name = "mod_app_impl",        .root = "src/app/app.zig",           .deps = &.{
            "mod01_platform", "mod02_text", "mod03_element_store", "mod04_layout_engine",
            "mod05_theme", "mod06_markup", "mod07_components", "mod08_schema_forms",
            "mod09_renderer", "mod10_gpu_backend",
            "mod_overlay", "mod_binding", "mod_image_atlas", "mod_font_family",
            "mod_events", "mod_navigator", "mod_persistent_settings",
            "mod_file_logger", "mod_logger", "mod_budgeted_arena",
            "mod_window_state", "mod_error_boundary", "mod_startup_error", "mod_tray",
        },
            .extra_imports = &.{
                ialias("../01/types.zig", "mod01_platform"),
                ialias("../02/types.zig", "mod02_text"),
                ialias("../03/types.zig", "mod03_element_store"),
                ialias("../04/types.zig", "mod04_layout_engine"),
                ialias("../05/types.zig", "mod05_theme"),
                ialias("../06/types.zig", "mod06_markup"),
                ialias("../07/types.zig", "mod07_components"),
                ialias("../09/types.zig", "mod09_renderer"),
                // App-local helpers (used via @import("name.zig") in app.zig).
                ialias("events.zig", "mod_events"),
                ialias("binding.zig", "mod_binding"),
                ialias("overlay.zig", "mod_overlay"),
                ialias("image_atlas.zig", "mod_image_atlas"),
                ialias("font_family.zig", "mod_font_family"),
                ialias("navigator.zig", "mod_navigator"),
                ialias("persistent_settings.zig", "mod_persistent_settings"),
                ialias("file_logger.zig", "mod_file_logger"),
                ialias("logger.zig", "mod_logger"),
                ialias("budgeted_arena.zig", "mod_budgeted_arena"),
                ialias("window_state.zig", "mod_window_state"),
                ialias("error_boundary.zig", "mod_error_boundary"),
                ialias("startup_error.zig", "mod_startup_error"),
                ialias("tray.zig", "mod_tray"),
            } },
        // mod_app — public root module.
        .{ .name = "mod_app",             .root = "src/app/types.zig",         .deps = &.{
            "mod01_platform", "mod02_text", "mod03_element_store", "mod04_layout_engine",
            "mod05_theme", "mod06_markup", "mod07_components", "mod08_schema_forms",
            "mod09_renderer",
            "mod_app_impl", "mod_events", "mod_navigator", "mod_overlay", "mod_binding",
        },
            .extra_imports = &.{
                ialias("../01/types.zig", "mod01_platform"),
                ialias("../02/types.zig", "mod02_text"),
                ialias("../03/types.zig", "mod03_element_store"),
                ialias("../05/types.zig", "mod05_theme"),
                ialias("../06/types.zig", "mod06_markup"),
                ialias("../07/types.zig", "mod07_components"),
                ialias("app.zig", "mod_app_impl"),
                ialias("events.zig", "mod_events"),
                ialias("navigator.zig", "mod_navigator"),
                ialias("overlay.zig", "mod_overlay"),
                ialias("binding.zig", "mod_binding"),
            } },
    };

    // -----------------------------------------------------------------------
    // Build the module map: name -> *std.Build.Module
    // -----------------------------------------------------------------------

    var module_map = std.StringArrayHashMapUnmanaged(*std.Build.Module){};
    defer module_map.deinit(b.allocator);

    for (modules) |desc| {
        const mod = b.addModule(desc.name, .{
            .root_source_file = b.path(desc.root),
            .target = target,
            .optimize = optimize,
        });
        module_map.put(b.allocator, desc.name, mod) catch @panic("duplicate module name");
    }

    for (modules) |desc| {
        const mod = module_map.get(desc.name).?;
        for (desc.deps) |dep_name| {
            const dep_mod = module_map.get(dep_name) orelse
                @panic(b.fmt("module '{s}' -> dep '{s}' not found", .{ desc.name, dep_name }));
            mod.addImport(dep_name, dep_mod);
        }
        for (desc.extra_imports) |alias| {
            const target_mod = module_map.get(alias.target) orelse
                @panic(b.fmt("alias '{s}' -> '{s}' not found", .{ alias.alias, alias.target }));
            mod.addImport(alias.alias, target_mod);
        }
        if (desc.needs_gpu) addGpuLinks(mod, glfw_dep, vulkan_include, vulkan_lib, glfw_lib, target);
        if (desc.needs_stb) {
            mod.addIncludePath(b.path("deps"));
            mod.addCSourceFile(.{ .file = b.path("deps/stb_impl.c"), .flags = &.{} });
            mod.link_libc = true;
        }
    }

    // -- Special wiring not expressible in the table --

    module_map.get("mod01_platform").?.addImport("embedded_shaders", shaders_mod);
    const mws = module_map.get("mod_window_state").?;
    mws.addIncludePath(glfw_dep.path("include"));
    mws.addIncludePath(.{ .cwd_relative = vulkan_include });
    if (target.result.os.tag == .windows) {
        const tray = module_map.get("mod_tray").?;
        tray.linkSystemLibrary("gdi32", .{});
        tray.linkSystemLibrary("user32", .{});
        tray.linkSystemLibrary("shell32", .{});
    }

    // -----------------------------------------------------------------------
    // Build options: hot-reload passed to app layer; gpu backend to mod10.
    // -----------------------------------------------------------------------
    const hot_reload = b.option(bool, "hot-reload", "Enable .ui file watcher for live editing") orelse false;
    const build_options = b.addOptions();
    build_options.addOption(bool, "hot_reload", hot_reload);
    build_options.addOption(BackendKind, "gpu", gpu_selected);
    module_map.get("mod_app_impl").?.addImport("build_options", build_options.createModule());
    module_map.get("mod_app").?.addImport("build_options", build_options.createModule());
    module_map.get("mod10_gpu_backend").?.addImport("build_options", build_options.createModule());

    // -----------------------------------------------------------------------
    // String table codegen (M15-03 / RE2).
    // -----------------------------------------------------------------------
    const strings_codegen_mod = b.createModule(.{
        .root_source_file = b.path("src/tools/string_table_codegen.zig"),
        .target = b.resolveTargetQuery(.{}),
        .optimize = .Debug,
    });
    const strings_codegen_exe = b.addExecutable(.{ .name = "string_table_codegen", .root_module = strings_codegen_mod });
    const run_strings_codegen = b.addRunArtifact(strings_codegen_exe);
    run_strings_codegen.addArg(b.path("src/strings.en.txt").getPath(b));
    const strings_gen = run_strings_codegen.addOutputFileArg("strings.zig");
    const strings_mod = b.addModule("strings.zig", .{ .root_source_file = strings_gen });

    // ---- Module tests -----------------------------------------------------
    //
    // Note: GPU test modules (accept_01, unit_01, accept_09, accept_10) need
    // addGpuLinks applied directly because the linker must see Vulkan/GLFW
    // symbols even though the modules they import already link them.

    const accept_01 = createTest(b, target, optimize, &module_map, "01-smoke-test", "docs/specs/01.smoke_test.zig", &.{ia("types.zig", "mod01_platform")}, false, false);
    addGpuLinks(accept_01.root_module, glfw_dep, vulkan_include, vulkan_lib, glfw_lib, target);
    const unit_01   = createTest(b, target, optimize, &module_map, "01-unit-test", "src/01/01_test.zig", &.{ia("types.zig", "mod01_platform")}, false, false);
    addGpuLinks(unit_01.root_module, glfw_dep, vulkan_include, vulkan_lib, glfw_lib, target);
    const accept_02 = createTest(b, target, optimize, &module_map, "02-acceptance-test", "docs/specs/02.acceptance_test.zig", &.{ia("types.zig", "mod02_text")}, false, false);
    const unit_02   = createTest(b, target, optimize, &module_map, "02-unit-test", "src/02/02_test.zig", &.{ia("types.zig", "mod02_text")}, false, true);
    const accept_03 = createTest(b, target, optimize, &module_map, "03-acceptance-test", "docs/specs/03.acceptance_test.zig", &.{ia("types.zig", "mod03_element_store")}, false, false);
    const unit_03   = createTest(b, target, optimize, &module_map, "03-unit-test", "src/03/03_test.zig", &.{ia("types.zig", "mod03_element_store")}, false, false);
    const accept_04 = createTest(b, target, optimize, &module_map, "04-acceptance-test", "docs/specs/04.acceptance_test.zig", &.{
        ia("types.zig", "mod04_layout_engine"),
        ia("../03_element_store/types.zig", "mod03_element_store"),
    }, false, false);
    const unit_04   = createTest(b, target, optimize, &module_map, "04-unit-test", "src/04/04_test.zig", &.{
        ia("types.zig", "mod04_layout_engine"),
        ia("../03_element_store/types.zig", "mod03_element_store"),
    }, false, false);
    const accept_05 = createTest(b, target, optimize, &module_map, "05-acceptance-test", "docs/specs/05.acceptance_test.zig", &.{ia("types.zig", "mod05_theme")}, false, false);
    const unit_05   = createTest(b, target, optimize, &module_map, "05-unit-test", "src/05/05_test.zig", &.{
        ia("../05/types.zig", "mod05_theme"),
        ia("../03/types.zig", "mod03_element_store"),
    }, false, false);
    const accept_06 = createTest(b, target, optimize, &module_map, "06-acceptance-test", "docs/specs/06.acceptance_test.zig", &.{
        ia("types.zig", "mod06_markup"),
        ia("../03_element_store/types.zig", "mod03_element_store"),
        ia("../05_theme/types.zig", "mod05_theme"),
    }, false, false);
    const unit_06   = createTest(b, target, optimize, &module_map, "06-unit-test", "src/06/06_test.zig", &.{
        ia("../06/types.zig", "mod06_markup"),
        ia("../03/types.zig", "mod03_element_store"),
        ia("../05/types.zig", "mod05_theme"),
    }, false, false);
    const accept_07 = createTest(b, target, optimize, &module_map, "07-acceptance-test", "docs/specs/07.acceptance_test.zig", &.{
        ia("types.zig", "mod07_components"),
        ia("../03_element_store/types.zig", "mod03_element_store"),
        ia("../05_theme/types.zig", "mod05_theme"),
        ia("../06_markup_style/types.zig", "mod06_markup"),
        ia("../02_text/types.zig", "mod02_text"),
        ia("../app/font_family.zig", "mod_font_family"),
    }, false, false);
    const unit_07   = createTest(b, target, optimize, &module_map, "07-unit-test", "src/07/07_test.zig", &.{
        ia("types.zig", "mod07_components"),
        ia("../03/types.zig", "mod03_element_store"),
        ia("../05/types.zig", "mod05_theme"),
        ia("../06/types.zig", "mod06_markup"),
        ia("../app/font_family.zig", "mod_font_family"),
    }, false, true);
    const accept_08 = createTest(b, target, optimize, &module_map, "08-acceptance-test", "docs/specs/08.acceptance_test.zig", &.{
        ia("types.zig", "mod08_schema_forms"),
        ia("../07_components/types.zig", "mod07_components"),
        ia("../05_theme/types.zig", "mod05_theme"),
    }, false, false);
    const unit_08   = createTest(b, target, optimize, &module_map, "08-unit-test", "src/08/08_test.zig", &.{ia("types.zig", "mod08_schema_forms")}, false, false);
    const accept_09 = createTest(b, target, optimize, &module_map, "09-acceptance-test", "docs/specs/09.acceptance_test.zig", &.{
        ia("types.zig", "mod09_renderer"),
        ia("../03_element_store/types.zig", "mod03_element_store"),
        ia("../05_theme/types.zig", "mod05_theme"),
        ia("../07_components/types.zig", "mod07_components"),
        ia("../06_markup_style/types.zig", "mod06_markup"),
        ia("../01_platform/types.zig", "mod01_platform"),
        ia("../04_layout_engine/types.zig", "mod04_layout_engine"),
        ia("../app/font_family.zig", "mod_font_family"),
    }, false, false);
    addGpuLinks(accept_09.root_module, glfw_dep, vulkan_include, vulkan_lib, glfw_lib, target);
    const unit_09   = createTest(b, target, optimize, &module_map, "09-unit-test", "src/09/09_test.zig", &.{
        ia("types.zig", "mod09_renderer"),
        ia("../03/types.zig", "mod03_element_store"),
        ia("../05/types.zig", "mod05_theme"),
        ia("../07/types.zig", "mod07_components"),
        ia("../06/types.zig", "mod06_markup"),
        ia("layout_engine", "mod04_layout_engine"),
        ia("../app/image_atlas.zig", "mod_image_atlas"),
        ia("../app/font_family.zig", "mod_font_family"),
    }, false, true);
    const accept_10 = createTest(b, target, optimize, &module_map, "10-smoke-test", "docs/specs/10.smoke_test.zig", &.{
        ia("types.zig", "mod10_gpu_backend"),
        ia("../01/types.zig", "mod01_platform"),
        ia("../09/types.zig", "mod09_renderer"),
        ia("../02/types.zig", "mod02_text"),
    }, false, false);
    addGpuLinks(accept_10.root_module, glfw_dep, vulkan_include, vulkan_lib, glfw_lib, target);

    // App tests
    const app_test_           = createTest(b, target, optimize, &module_map, "app-test",           "src/app/app_test.zig",           &.{ ia("types.zig", "mod_app"), ia("../01/types.zig", "mod01_platform"), ia("events.zig", "mod_events") }, false, false);
    const events_test         = createTest(b, target, optimize, &module_map, "events-test",        "src/app/events_test.zig",        &.{ ia("types.zig", "mod_app"), ia("../01/types.zig", "mod01_platform"), ia("events.zig", "mod_events") }, false, false);
    const signal_test_        = createTest(b, target, optimize, &module_map, "signal-test",        "src/app/signal_test.zig",        &.{}, false, false);
    const anim_timeline_test_ = createTest(b, target, optimize, &module_map, "anim-timeline-test", "src/app/anim_timeline_test.zig", &.{}, false, false);
    const overlay_test        = createTest(b, target, optimize, &module_map, "overlay-test",       "src/app/overlay_test.zig",       &.{ ia("overlay.zig", "mod_overlay"), ia("../01/types.zig", "mod01_platform") }, false, false);
    const binding_test        = createTest(b, target, optimize, &module_map, "binding-test",       "src/app/binding_test.zig",       &.{ ia("../07/types.zig", "mod07_components"), ia("../05/types.zig", "mod05_theme"), ia("../06/types.zig", "mod06_markup"), ia("../03/types.zig", "mod03_element_store") }, false, true);
    const m7_widget_test      = createTest(b, target, optimize, &module_map, "m7-widget-test",     "src/07/m7_widget_test.zig",      &.{ ia("types.zig", "mod07_components"), ia("../03/types.zig", "mod03_element_store"), ia("../05/types.zig", "mod05_theme"), ia("../06/types.zig", "mod06_markup"), ia("../app/font_family.zig", "mod_font_family") }, false, true);
    const toast_test          = createTest(b, target, optimize, &module_map, "toast-test",         "src/app/toast_test.zig",         &.{ ia("../01/types.zig", "mod01_platform"), ia("../02/types.zig", "mod02_text"), ia("../05/types.zig", "mod05_theme"), ia("overlay.zig", "mod_overlay") }, false, true);
    const dialog_test         = createTest(b, target, optimize, &module_map, "dialog-test",        "src/app/dialog_test.zig",        &.{ ia("../01/types.zig", "mod01_platform"), ia("../07/types.zig", "mod07_components"), ia("../05/types.zig", "mod05_theme"), ia("../06/types.zig", "mod06_markup"), ia("overlay.zig", "mod_overlay"), ia("../app/font_family.zig", "mod_font_family") }, false, true);
    const date_util_test      = createTest(b, target, optimize, &module_map, "date-util-test",     "src/app/date_util_test.zig",     &.{ ia("../07/types.zig", "mod07_components"), ia("../03/types.zig", "mod03_element_store"), ia("../05/types.zig", "mod05_theme"), ia("../06/types.zig", "mod06_markup"), ia("../app/font_family.zig", "mod_font_family") }, false, true);
    const locale_test_        = createTest(b, target, optimize, &module_map, "locale-test",        "src/app/locale_test.zig",        &.{}, false, false);
    const context_menu_test   = createTest(b, target, optimize, &module_map, "context-menu-test",  "src/app/context_menu_test.zig",  &.{ ia("../01/types.zig", "mod01_platform"), ia("../02/types.zig", "mod02_text"), ia("../05/types.zig", "mod05_theme"), ia("overlay.zig", "mod_overlay"), ia("font_family.zig", "mod_font_family") }, false, true);
    const nav_test            = createTest(b, target, optimize, &module_map, "nav-test",           "src/app/navigator_test.zig",     &.{ ia("types.zig", "mod_app"), ia("../07/types.zig", "mod07_components"), ia("../05/types.zig", "mod05_theme") }, false, true);
    const tooltip_test        = createTest(b, target, optimize, &module_map, "tooltip-test",       "src/app/tooltip_test.zig",       &.{ ia("../01/types.zig", "mod01_platform"), ia("../02/types.zig", "mod02_text"), ia("../05/types.zig", "mod05_theme"), ia("../07/types.zig", "mod07_components"), ia("overlay.zig", "mod_overlay"), ia("font_family.zig", "mod_font_family") }, false, true);
    const app_state_test_     = createTest(b, target, optimize, &module_map, "app-state-test",     "src/app/app_state_test.zig",     &.{}, false, false);
    const settings_test_      = createTest(b, target, optimize, &module_map, "settings-test",      "src/app/persistent_settings_test.zig", &.{}, false, false);
    const multi_window_test_  = createTest(b, target, optimize, &module_map, "multi-window-test",  "src/app/multi_window_test.zig",  &.{ ia("../01/types.zig", "mod01_platform"), ia("../07/types.zig", "mod07_components"), ia("../05/types.zig", "mod05_theme"), ia("../06/types.zig", "mod06_markup"), ia("../03/types.zig", "mod03_element_store"), ia("../app/font_family.zig", "mod_font_family"), ia("overlay.zig", "mod_overlay"), ia("binding.zig", "mod_binding"), ia("events.zig", "mod_events"), ia("navigator.zig", "mod_navigator") }, false, true);
    const debug_overlay_test_ = createTest(b, target, optimize, &module_map, "debug-overlay-test", "src/app/debug_overlay_test.zig", &.{ ia("../01/types.zig", "mod01_platform"), ia("../02/types.zig", "mod02_text"), ia("../05/types.zig", "mod05_theme"), ia("../07/types.zig", "mod07_components") }, false, true);
    const scene_dump_test_    = createTest(b, target, optimize, &module_map, "scene-dump-test",    "src/07/debug_test.zig",           &.{ia("types.zig", "mod07_components")}, false, false);
    const perf_hud_test_      = createTest(b, target, optimize, &module_map, "perf-hud-test",      "src/app/perf_hud_test.zig",      &.{ ia("../01/types.zig", "mod01_platform"), ia("../02/types.zig", "mod02_text"), ia("../05/types.zig", "mod05_theme") }, false, true);
    const theme_swap_test_    = createTest(b, target, optimize, &module_map, "theme-swap-test",    "src/app/theme_swap_test.zig",    &.{ia("../05/types.zig", "mod05_theme")}, false, false);
    const font_scale_test_    = createTest(b, target, optimize, &module_map, "font-scale-test",    "src/app/font_scale_test.zig",    &.{ia("../05/types.zig", "mod05_theme")}, false, false);
    const high_contrast_test_ = createTest(b, target, optimize, &module_map, "high-contrast-test", "src/05/high_contrast_test.zig", &.{ ia("../05/types.zig", "mod05_theme"), ia("../03/types.zig", "mod03_element_store") }, false, false);

    // M10 hardening tests.
    const file_logger_test_    = createTest(b, target, optimize, &module_map, "file-logger-test",    "src/app/file_logger_test.zig",    &.{ ia("file_logger.zig", "mod_file_logger"), ia("app.zig", "mod_app_impl") }, false, false);
    const budget_arena_test_   = createTest(b, target, optimize, &module_map, "budget-arena-test",   "src/app/budgeted_arena_test.zig", &.{ ia("budgeted_arena.zig", "mod_budgeted_arena"), ia("app.zig", "mod_app_impl") }, false, false);
    const startup_error_test_  = createTest(b, target, optimize, &module_map, "startup-error-test",  "src/app/startup_error_test.zig",  &.{ia("startup_error.zig", "mod_startup_error")}, false, false);
    const window_state_test_   = createTest(b, target, optimize, &module_map, "window-state-test",   "src/app/window_state_test.zig",   &.{ ia("window_state.zig", "mod_window_state"), ia("persistent_settings.zig", "mod_persistent_settings"), ia("app.zig", "mod_app_impl") }, false, false);
    const error_boundary_test_ = createTest(b, target, optimize, &module_map, "error-boundary-test", "src/app/error_boundary_test.zig", &.{ ia("error_boundary.zig", "mod_error_boundary"), ia("../05/types.zig", "mod05_theme"), ia("../07/types.zig", "mod07_components"), ia("app.zig", "mod_app_impl") }, false, true);
    const m11_test_            = createTest(b, target, optimize, &module_map, "m11-test",            "src/app/m11_test.zig",            &.{ ia("../01/types.zig", "mod01_platform"), ia("../05/types.zig", "mod05_theme"), ia("../06/types.zig", "mod06_markup"), ia("../07/types.zig", "mod07_components"), ia("app.zig", "mod_app_impl") }, false, true);
    const m12_test_            = createTest(b, target, optimize, &module_map, "m12-test",            "src/app/m12_test.zig",            &.{ ia("../01/types.zig", "mod01_platform"), ia("../03/types.zig", "mod03_element_store"), ia("../04/types.zig", "mod04_layout_engine"), ia("../05/types.zig", "mod05_theme"), ia("../06/types.zig", "mod06_markup"), ia("../07/types.zig", "mod07_components"), ia("../09/types.zig", "mod09_renderer"), ia("app.zig", "mod_app_impl") }, false, true);
    const m16_test_            = createTest(b, target, optimize, &module_map, "m16-test",            "src/app/m16_test.zig",            &.{ ia("../01/types.zig", "mod01_platform"), ia("../05/types.zig", "mod05_theme"), ia("app.zig", "mod_app_impl") }, false, false);
    const m17_test_            = createTest(b, target, optimize, &module_map, "m17-test",            "src/app/m17_test.zig",            &.{ ia("../07/types.zig", "mod07_components"), ia("../03/types.zig", "mod03_element_store"), ia("../05/types.zig", "mod05_theme"), ia("../06/types.zig", "mod06_markup") }, false, true);
    const tray_test_           = createTest(b, target, optimize, &module_map, "tray-test",           "src/app/tray_test.zig",           &.{ ia("tray.zig", "mod_tray"), ia("app.zig", "mod_app_impl") }, false, true);

    // startup_error_test and tray_test need Win32 libs on Windows.
    if (target.result.os.tag == .windows) {
        startup_error_test_.root_module.linkSystemLibrary("user32", .{});
        tray_test_.root_module.linkSystemLibrary("gdi32", .{});
        tray_test_.root_module.linkSystemLibrary("user32", .{});
        tray_test_.root_module.linkSystemLibrary("shell32", .{});
    }

    // ---- Default step ------------------------------------------------

    b.default_step.dependOn(&accept_01.step);
    b.default_step.dependOn(&unit_01.step);
    b.default_step.dependOn(&signal_test_.step);
    b.default_step.dependOn(&anim_timeline_test_.step);
    b.default_step.dependOn(&overlay_test.step);
    b.default_step.dependOn(&binding_test.step);
    b.default_step.dependOn(&m7_widget_test.step);
    b.default_step.dependOn(&toast_test.step);
    b.default_step.dependOn(&dialog_test.step);
    b.default_step.dependOn(&date_util_test.step);
    b.default_step.dependOn(&locale_test_.step);
    b.default_step.dependOn(&context_menu_test.step);
    b.default_step.dependOn(&nav_test.step);
    b.default_step.dependOn(&tooltip_test.step);
    b.default_step.dependOn(&app_state_test_.step);
    b.default_step.dependOn(&settings_test_.step);
    b.default_step.dependOn(&multi_window_test_.step);
    b.default_step.dependOn(&debug_overlay_test_.step);
    b.default_step.dependOn(&scene_dump_test_.step);
    b.default_step.dependOn(&perf_hud_test_.step);
    b.default_step.dependOn(&theme_swap_test_.step);
    b.default_step.dependOn(&font_scale_test_.step);
    b.default_step.dependOn(&high_contrast_test_.step);
    b.default_step.dependOn(&file_logger_test_.step);
    b.default_step.dependOn(&budget_arena_test_.step);
    b.default_step.dependOn(&startup_error_test_.step);
    b.default_step.dependOn(&window_state_test_.step);
    b.default_step.dependOn(&error_boundary_test_.step);
    b.default_step.dependOn(&m11_test_.step);
    b.default_step.dependOn(&m17_test_.step);
    b.default_step.dependOn(&tray_test_.step);

    // ---- Named test steps --------------------------------------------

    const test_step = b.step("test", "Aggregate green-build gate: run every module test (constitution 7, SR-06)");
    inline for (.{
        accept_01, unit_01, accept_02, unit_02, accept_03, unit_03,
        accept_04, unit_04, accept_05, unit_05, accept_06, unit_06,
        accept_07, unit_07, accept_08, unit_08, accept_09, unit_09,
        accept_10,
        app_test_, events_test, signal_test_, anim_timeline_test_, overlay_test,
        binding_test, m7_widget_test, toast_test, dialog_test, date_util_test,
        locale_test_, context_menu_test, nav_test, tooltip_test,
        app_state_test_, settings_test_, multi_window_test_, debug_overlay_test_,
        scene_dump_test_, perf_hud_test_, theme_swap_test_, font_scale_test_,
        high_contrast_test_, file_logger_test_, budget_arena_test_,
        startup_error_test_, window_state_test_, error_boundary_test_,
        m11_test_, m12_test_, m16_test_, m17_test_, tray_test_,
    }) |t| {
        test_step.dependOn(&t.step);
    }

    _ = addTestStep(b, "test-01",          "Run module 01 smoke tests (needs GPU)", accept_01);
    _ = addTestStep(b, "test-01-unit",     "Run module 01 unit tests (GPU tests auto-skip)", unit_01);
    _ = addTestStep(b, "test-02",          "Run module 02 acceptance tests", accept_02);
    _ = addTestStep(b, "test-02-unit",     "Run module 02 unit tests", unit_02);
    _ = addTestStep(b, "test-03",          "Run module 03 acceptance tests", accept_03);
    _ = addTestStep(b, "test-03-unit",     "Run module 03 unit tests", unit_03);
    _ = addTestStep(b, "test-04",          "Run module 04 acceptance tests", accept_04);
    _ = addTestStep(b, "test-04-unit",     "Run module 04 unit tests", unit_04);
    _ = addTestStep(b, "test-05",          "Run module 05 acceptance tests", accept_05);
    _ = addTestStep(b, "test-05-unit",     "Run module 05 unit tests", unit_05);
    _ = addTestStep(b, "test-06",          "Run module 06 acceptance tests", accept_06);
    _ = addTestStep(b, "test-06-unit",     "Run module 06 unit tests", unit_06);
    _ = addTestStep(b, "test-07",          "Run module 07 acceptance tests", accept_07);
    _ = addTestStep(b, "test-07-unit",     "Run module 07 unit tests", unit_07);
    _ = addTestStep(b, "test-08",          "Run module 08 acceptance tests", accept_08);
    _ = addTestStep(b, "test-08-unit",     "Run module 08 unit tests", unit_08);
    _ = addTestStep(b, "test-09",          "Run module 09 tests (GPU tests skip if unavailable)", accept_09);
    _ = addTestStep(b, "test-09-unit",     "Run module 09 unit tests (pure CPU)", unit_09);
    _ = addTestStep(b, "test-10",          "Run module 10 GPU backend seam tests", accept_10);
    _ = addTestStep(b, "test-app",         "Run app layer unit tests (headless, no GPU)", app_test_);
    _ = addTestStep(b, "test-events",      "Run EventQueue unit tests (no GPU, no GLFW)", events_test);
    _ = addTestStep(b, "test-signal",      "Run Signal/Computed unit tests (pure, no GPU)", signal_test_);
    _ = addTestStep(b, "test-anim-timeline", "Run AnimTimeline unit tests (pure, no GPU)", anim_timeline_test_);
    _ = addTestStep(b, "test-overlay",     "Run OverlayLayer unit tests (no GPU, no GLFW)", overlay_test);
    _ = addTestStep(b, "test-binding",     "Run BindingSet unit tests (no GPU, no GLFW)", binding_test);
    _ = addTestStep(b, "test-m7-widget",   "Run Milestone 7 widget unit tests (R70-R79)", m7_widget_test);
    _ = addTestStep(b, "test-toast",       "Run ToastManager unit tests (R74, no GPU)", toast_test);
    _ = addTestStep(b, "test-dialog",      "Run DialogManager unit tests (R75, no GPU)", dialog_test);
    _ = addTestStep(b, "test-date-util",   "Run date utility unit tests (R78, pure)", date_util_test);
    _ = addTestStep(b, "test-locale",      "Run locale/date formatting unit tests (M15, pure)", locale_test_);
    _ = addTestStep(b, "test-context-menu","Run ContextMenuManager unit tests (R7D, no GPU)", context_menu_test);
    _ = addTestStep(b, "test-nav",         "Run Navigator unit tests (R80, headless)", nav_test);
    _ = addTestStep(b, "test-tooltip",     "Run TooltipManager unit tests (R7C, no GPU)", tooltip_test);
    _ = addTestStep(b, "test-app-state",   "Run AppState unit tests (R81, pure)", app_state_test_);
    _ = addTestStep(b, "test-settings",    "Run PersistentSettings unit tests (R82, file I/O)", settings_test_);
    _ = addTestStep(b, "test-multi-window","Run MultiWindowApp unit tests (R83, headless)", multi_window_test_);
    _ = addTestStep(b, "test-debug-overlay","Run DebugOverlay unit tests (R90, no GPU)", debug_overlay_test_);
    _ = addTestStep(b, "test-scene-dump",  "Run Scene dump unit tests (R91, no GPU)", scene_dump_test_);
    _ = addTestStep(b, "test-perf-hud",    "Run PerfHud unit tests (R92, no GPU)", perf_hud_test_);
    _ = addTestStep(b, "test-theme-swap",  "Run Theme live-swap unit tests (R93, pure)", theme_swap_test_);
    _ = addTestStep(b, "test-font-scale",  "Run font-scale unit tests (R94, pure)", font_scale_test_);
    _ = addTestStep(b, "test-high-contrast","Run high-contrast palette unit tests (R95, pure)", high_contrast_test_);
    _ = addTestStep(b, "test-file-logger", "Run FileLogger unit tests (RA2, file I/O)", file_logger_test_);
    _ = addTestStep(b, "test-budget-arena","Run BudgetedArena unit tests (RA1, pure)", budget_arena_test_);
    _ = addTestStep(b, "test-startup-error","Run startup_error unit tests (RA3)", startup_error_test_);
    _ = addTestStep(b, "test-window-state","Run WindowStateManager unit tests (RA4, headless)", window_state_test_);
    _ = addTestStep(b, "test-error-boundary","Run ErrorBoundary unit tests (RA0, headless)", error_boundary_test_);
    _ = addTestStep(b, "test-m11",         "Run M11 input completeness unit tests (RB0-RB5, headless)", m11_test_);
    _ = addTestStep(b, "test-m12",         "Run M12 layout extension tests (RC0-RC4, headless)", m12_test_);
    _ = addTestStep(b, "test-m16",         "Run M16 platform integration unit tests (RF1-RF4, headless)", m16_test_);
    _ = addTestStep(b, "test-m17",         "Run M17 accessibility unit tests (RG1, RG4, RG5, headless)", m17_test_);
    _ = addTestStep(b, "test-tray",        "Run Tray unit tests (RF0, headless)", tray_test_);

    // -------------------------------------------------------------------
    // R55 — Build-time markup codegen tool (ui_codegen).
    // -------------------------------------------------------------------
    {
        const codegen_mod = b.createModule(.{
            .root_source_file = b.path("src/tools/ui_codegen.zig"),
            .target = b.resolveTargetQuery(.{}),
            .optimize = .Debug,
        });
        codegen_mod.addImport("m06", module_map.get("mod06_markup").?);
        const codegen_exe = b.addExecutable(.{ .name = "ui_codegen", .root_module = codegen_mod });
        const ui_files = &[_][]const u8{"src/screens/example.ui"};
        const codegen_step = b.step("codegen", "Regenerate baked NodeDesc files from .ui markup");
        for (ui_files) |ui_path| {
            const out_path = b.fmt("{s}.zig", .{ui_path});
            const run = b.addRunArtifact(codegen_exe);
            run.addArg(b.path(ui_path).getPath(b));
            run.addArg(b.path(out_path).getPath(b));
            codegen_step.dependOn(&run.step);
        }
    }

    // -------------------------------------------------------------------
    // run-dev — launch with hot-reload enabled.
    // -------------------------------------------------------------------
    {
        const dev_options = b.addOptions();
        dev_options.addOption(bool, "hot_reload", true);
        const run_dev_mod = b.createModule(.{
            .root_source_file = b.path("src/app/main.zig"),
            .target = target,
            .optimize = optimize,
        });
        run_dev_mod.addOptions("build_options", dev_options);
        const run_dev_exe = b.addExecutable(.{ .name = "zig-gui-dev", .root_module = run_dev_mod });
        const run_dev_step = b.step("run-dev", "Run the app with hot-reload enabled");
        run_dev_step.dependOn(&b.addRunArtifact(run_dev_exe).step);
    }

    // -------------------------------------------------------------------
    // run-demo — Showcase Demo Application.
    // -------------------------------------------------------------------
    {
        const mod01 = module_map.get("mod01_platform").?;
        const mod02 = module_map.get("mod02_text").?;
        const mod03 = module_map.get("mod03_element_store").?;
        const mod05 = module_map.get("mod05_theme").?;
        const mod06 = module_map.get("mod06_markup").?;
        const mod07 = module_map.get("mod07_components").?;
        const mod08 = module_map.get("mod08_schema_forms").?;
        const mod_app = module_map.get("mod_app").?;
        const mod_nav = module_map.get("mod_navigator").?;
        const mod_ev = module_map.get("mod_events").?;

        const demo_mod = b.createModule(.{
            .root_source_file = b.path("src/demo/main.zig"),
            .target = target,
            .optimize = optimize,
        });
        demo_mod.addImport("app", mod_app);
        demo_mod.addImport("navigator.zig", mod_nav);
        demo_mod.addImport("../01/types.zig", mod01);
        demo_mod.addImport("../02/types.zig", mod02);
        demo_mod.addImport("../03/types.zig", mod03);
        demo_mod.addImport("../05/types.zig", mod05);
        demo_mod.addImport("../06/types.zig", mod06);
        demo_mod.addImport("../07/types.zig", mod07);
        demo_mod.addImport("../08/types.zig", mod08);
        demo_mod.addImport("events.zig", mod_ev);
        demo_mod.addImport("build_options", build_options.createModule());
        demo_mod.addImport("../strings.zig", strings_mod);
        addGpuLinks(demo_mod, glfw_dep, vulkan_include, vulkan_lib, glfw_lib, target);

        const demo_exe = b.addExecutable(.{ .name = "showcase", .root_module = demo_mod });
        demo_exe.step.dependOn(&run_strings_codegen.step);
        b.installArtifact(demo_exe);
        const run_demo_step = b.step("run-demo", "Run the zig-gui Showcase Demo Application");
        run_demo_step.dependOn(&b.addRunArtifact(demo_exe).step);

        // visual-check
        const screenshot_path = "testdata/screenshot_actual.png";
        const screenshot_cmd = b.addRunArtifact(demo_exe);
        screenshot_cmd.addArg("--screenshot-frames");
        screenshot_cmd.addArg("3");
        screenshot_cmd.addArg("--screenshot-out");
        screenshot_cmd.addArg(screenshot_path);
        const checker_mod = b.createModule(.{
            .root_source_file = b.path("src/tools/visual_check.zig"),
            .target = target,
            .optimize = optimize,
        });
        const checker_exe = b.addExecutable(.{ .name = "visual_check", .root_module = checker_mod });
        const run_checker = b.addRunArtifact(checker_exe);
        run_checker.addArg(screenshot_path);
        run_checker.step.dependOn(&screenshot_cmd.step);
        const visual_check_step = b.step("visual-check", "Render 3 demo frames, write a PNG, and verify it is not blank");
        visual_check_step.dependOn(&run_checker.step);

        // visual-baseline (RJ1 AC2): capture a reference screenshot to testdata/visual-baseline/baseline.png.
        // Run this BEFORE a refactor lands; then run visual-check after to diff.
        // The baseline directory must exist: `mkdir testdata\visual-baseline` on first use.
        const baseline_path = "testdata/visual-baseline/baseline.png";
        const baseline_cmd = b.addRunArtifact(demo_exe);
        baseline_cmd.addArg("--screenshot-frames");
        baseline_cmd.addArg("3");
        baseline_cmd.addArg("--screenshot-out");
        baseline_cmd.addArg(baseline_path);
        const visual_baseline_step = b.step("visual-baseline", "Capture reference baseline screenshot to testdata/visual-baseline/baseline.png (run before a refactor)");
        visual_baseline_step.dependOn(&baseline_cmd.step);

        // M19-05: App packaging.
        const package_mod = b.createModule(.{
            .root_source_file = b.path("src/tools/package.zig"),
            .target = target,
            .optimize = optimize,
        });
        const package_exe = b.addExecutable(.{ .name = "package", .root_module = package_mod });
        const run_package_cmd = b.addRunArtifact(package_exe);
        run_package_cmd.addArg("--binary-path");
        const showcase_binary_name = if (target.result.os.tag == .windows) "showcase.exe" else "showcase";
        run_package_cmd.addArg(b.fmt("zig-out/bin/{s}", .{showcase_binary_name}));
        run_package_cmd.addArg("--output");
        run_package_cmd.addArg("dist");
        run_package_cmd.addArg("--fonts-dir");
        run_package_cmd.addArg("testdata");
        const package_step = b.step("package", "Bundle binary + fonts + manifest into distributable archive");
        package_step.dependOn(&demo_exe.step);
        package_step.dependOn(&run_package_cmd.step);
    }

    // -------------------------------------------------------------------
    // generate-manifest — SHA256 manifest helper.
    // -------------------------------------------------------------------
    {
        const manifest_mod = b.createModule(.{
            .root_source_file = b.path("src/tools/generate_manifest.zig"),
            .target = target,
            .optimize = optimize,
        });
        const manifest_exe = b.addExecutable(.{ .name = "generate_manifest", .root_module = manifest_mod });
        const manifest_step = b.step("run-generate-manifest", "Generate update manifest for a package");
        manifest_step.dependOn(&b.addRunArtifact(manifest_exe).step);
    }
}

// ---------------------------------------------------------------------------
// createTest — build a single test binary, wiring module imports.
// ---------------------------------------------------------------------------
fn createTest(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    module_map: *const std.StringArrayHashMapUnmanaged(*std.Build.Module),
    name: []const u8,
    root: []const u8,
    imports: []const ImportAlias,
    needs_gpu: bool,
    needs_stb: bool,
) *std.Build.Step.Compile {
    const mod = b.createModule(.{
        .root_source_file = b.path(root),
        .target = target,
        .optimize = optimize,
    });
    for (imports) |imp| {
        const tm = module_map.get(imp.target) orelse
            @panic(b.fmt("createTest '{s}': alias '{s}' target '{s}' not found", .{ name, imp.alias, imp.target }));
        mod.addImport(imp.alias, tm);
    }
    if (needs_stb) {
        mod.addIncludePath(b.path("deps"));
        mod.addCSourceFile(.{ .file = b.path("deps/stb_impl.c"), .flags = &.{} });
        mod.link_libc = true;
    }
    const test_exe = b.addTest(.{ .name = name, .root_module = mod });
    if (needs_gpu) {
        // GPU tests will link GLFW+Vulkan through their module deps.
    }
    return test_exe;
}

// ---------------------------------------------------------------------------
// addTestStep — create a named build step that runs a test binary.
// ---------------------------------------------------------------------------
fn addTestStep(
    b: *std.Build,
    name: []const u8,
    description: []const u8,
    test_compile: *std.Build.Step.Compile,
) *std.Build.Step {
    const run = b.addRunArtifact(test_compile);
    const step = b.step(name, description);
    step.dependOn(&run.step);
    return step;
}

// ---------------------------------------------------------------------------
// compileShader — run glslc to produce a .spv file.
// ---------------------------------------------------------------------------
fn compileShader(b: *std.Build, glslc: []const u8, src: []const u8, out: []const u8) std.Build.LazyPath {
    const cmd = b.addSystemCommand(&.{glslc});
    cmd.addFileArg(b.path(src));
    cmd.addArg("-o");
    return cmd.addOutputFileArg(out);
}

// ---------------------------------------------------------------------------
// addGpuLinks — apply Vulkan/GLFW linkage to a module.
// ---------------------------------------------------------------------------
fn addGpuLinks(
    m: *std.Build.Module,
    gd: *std.Build.Dependency,
    vi: []const u8,
    vl: []const u8,
    gl: *std.Build.Step.Compile,
    tgt: std.Build.ResolvedTarget,
) void {
    m.addIncludePath(gd.path("include"));
    m.addIncludePath(.{ .cwd_relative = vi });
    m.linkLibrary(gl);
    m.addLibraryPath(.{ .cwd_relative = vl });
    m.linkSystemLibrary("vulkan-1", .{});
    m.link_libc = true;
    if (tgt.result.os.tag == .windows) {
        m.linkSystemLibrary("gdi32", .{});
        m.linkSystemLibrary("user32", .{});
        m.linkSystemLibrary("shell32", .{});
    }
}

// ---------------------------------------------------------------------------
// buildGlfw — compile GLFW as a static library from source.
// ---------------------------------------------------------------------------
fn buildGlfw(
    b: *std.Build,
    dep: *std.Build.Dependency,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    vulkan_include: []const u8,
) *std.Build.Step.Compile {
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
    const lib = b.addLibrary(.{ .name = "glfw", .linkage = .static, .root_module = glfw_mod });
    glfw_mod.addIncludePath(dep.path("include"));
    glfw_mod.addIncludePath(dep.path("src"));
    glfw_mod.addIncludePath(.{ .cwd_relative = vulkan_include });

    const common = [_][]const u8{
        "src/context.c", "src/init.c", "src/input.c", "src/monitor.c",
        "src/platform.c", "src/vulkan.c", "src/window.c",
        "src/egl_context.c", "src/osmesa_context.c",
        "src/null_init.c", "src/null_joystick.c", "src/null_monitor.c", "src/null_window.c",
    };
    for (common) |src| glfw_mod.addCSourceFile(.{ .file = dep.path(src), .flags = platform_flags });

    switch (target.result.os.tag) {
        .windows => {
            glfw_mod.linkSystemLibrary("gdi32", .{});
            glfw_mod.linkSystemLibrary("user32", .{});
            glfw_mod.linkSystemLibrary("shell32", .{});
            const win = [_][]const u8{
                "src/win32_init.c", "src/win32_joystick.c", "src/win32_module.c",
                "src/win32_monitor.c", "src/win32_thread.c", "src/win32_time.c",
                "src/win32_window.c", "src/wgl_context.c",
            };
            for (win) |src| glfw_mod.addCSourceFile(.{ .file = dep.path(src), .flags = platform_flags });
        },
        .linux => {
            glfw_mod.linkSystemLibrary("X11", .{});
            const linux = [_][]const u8{
                "src/posix_module.c", "src/posix_poll.c", "src/posix_thread.c",
                "src/posix_time.c", "src/x11_init.c", "src/x11_monitor.c",
                "src/x11_window.c", "src/xkb_unicode.c", "src/glx_context.c",
                "src/linux_joystick.c",
            };
            for (linux) |src| glfw_mod.addCSourceFile(.{ .file = dep.path(src), .flags = platform_flags });
        },
        else => unreachable,
    }
    return lib;
}

// ---------------------------------------------------------------------------
// Convenience: ialias and ia create ImportAlias values.
// ---------------------------------------------------------------------------
fn ialias(alias: []const u8, target: []const u8) ImportAlias {
    return .{ .alias = alias, .target = target };
}

fn ia(alias: []const u8, target: []const u8) ImportAlias {
    return ialias(alias, target);
}
