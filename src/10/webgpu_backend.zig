//! 10 — GPU backend — WebGPU (wgpu-native) — M23-01 / RJ4
//!
//! `WebGpuBackend` implements the GpuBackend seam contract (INV-5.1) for WebGPU.
//! Selection: `zig build -Dgpu=webgpu`
//!
//! On native Windows/Linux targets: uses wgpu-native (libwgpu_native) via the C API.
//! On WASM/Emscripten: the browser's built-in WebGPU is used instead.
//!
//! All 9 GpuBackend methods are implemented (init, deinit, initPipelines, resize,
//! uploadAtlas, uploadSdfAtlas, uploadImage, drawFrame, capabilities).
//!
//! WGSL shaders (quad.wgsl, curve.wgsl) are embedded at build time.
//!
//! Dependencies: wgpu-native (vendor/wgpu-native) — INV-5.6-v2, INV-2.1-v2.
//!
//! Note on capabilities: WebGPU does not support subpixel text rendering portably
//! (no framebuffer blending on individual RGB channels), so subpixel_text = false.
//! Shader mode 7 (subpixel_glyph) falls back to regular grayscale glyph rendering.

const std = @import("std");
const builtin = @import("builtin");

const c = @cImport({
    @cInclude("webgpu/webgpu.h");
});

const platform_types = @import("../01/types.zig");
const DrawCommand    = platform_types.DrawCommand;
const AtlasHandle    = platform_types.AtlasHandle;
const AtlasHandles   = platform_types.AtlasHandles;
const Platform       = platform_types.Platform;
const BackendError   = platform_types.BackendError;
const Caps           = @import("types.zig").Caps;

// ---------------------------------------------------------------------------
// GPU texture atlas handle (wgpu-native texture + view + sampler).
// ---------------------------------------------------------------------------

const WgpuTexture = struct {
    texture: c.WGPUTexture = null,
    view:    c.WGPUTextureView = null,
    sampler: c.WGPUSampler = null,
    width:   u32 = 0,
    height:  u32 = 0,
};

// ---------------------------------------------------------------------------
// Quad vertex layout — must match the WGSL VertexInput and QuadVertex in mod01.
// ---------------------------------------------------------------------------

const QuadVertex = extern struct {
    pos:     [2]f32,
    uv:      [2]f32,
    color:   u32,   // packed RGBA (R<<24 | G<<16 | B<<8 | A)
    color_b: u32,   // second gradient stop
    mode:    u32,
};

comptime {
    // 2*4 + 2*4 + 4 + 4 + 4 = 28
    std.debug.assert(@sizeOf(QuadVertex) == 28);
}

// ---------------------------------------------------------------------------
// Internal implementation state
// ---------------------------------------------------------------------------

const WgpuImpl = struct {
    allocator:     std.mem.Allocator,

    instance:      c.WGPUInstance      = null,
    adapter:       c.WGPUAdapter       = null,
    device:        c.WGPUDevice        = null,
    queue:         c.WGPUQueue         = null,
    wgpu_surface:  c.WGPUSurface       = null,
    swap_chain:    c.WGPUSwapChain     = null,

    pipeline:          c.WGPURenderPipeline   = null,
    bind_group_layout: c.WGPUBindGroupLayout  = null,
    pipeline_layout:   c.WGPUPipelineLayout   = null,
    pipelines_ready:   bool = false,

    // CPU-visible vertex staging buffer (1 MiB — plenty for UI quads).
    vertex_buffer:    c.WGPUBuffer = null,
    vertex_buf_size:  u64 = 0,

    width:  u32 = 0,
    height: u32 = 0,
    format: c.WGPUTextureFormat = c.WGPUTextureFormat_BGRA8Unorm,
};

// ---------------------------------------------------------------------------
// Adapter/device request state (callback pattern for synchronous wgpu-native).
// ---------------------------------------------------------------------------

const AdapterState = struct {
    adapter: c.WGPUAdapter = null,
    done:    bool = false,
};

fn adapterCallback(
    status: c.WGPURequestAdapterStatus,
    adapter: c.WGPUAdapter,
    _message: [*c]const u8,
    userdata: ?*anyopaque,
) callconv(.c) void {
    _ = _message;
    const state: *AdapterState = @ptrCast(@alignCast(userdata));
    if (status == c.WGPURequestAdapterStatus_Success) {
        state.adapter = adapter;
    }
    state.done = true;
}

const DeviceState = struct {
    device: c.WGPUDevice = null,
    done:   bool = false,
};

fn deviceCallback(
    status: c.WGPURequestDeviceStatus,
    device: c.WGPUDevice,
    _message: [*c]const u8,
    userdata: ?*anyopaque,
) callconv(.c) void {
    _ = _message;
    const state: *DeviceState = @ptrCast(@alignCast(userdata));
    if (status == c.WGPURequestDeviceStatus_Success) {
        state.device = device;
    }
    state.done = true;
}

// ---------------------------------------------------------------------------
// WebGpuBackend — public struct satisfying the GpuBackend contract (INV-5.1)
// ---------------------------------------------------------------------------

pub const WebGpuBackend = struct {
    _impl: *anyopaque = undefined,

    // -----------------------------------------------------------------------
    // init — create instance, request adapter + device, create surface + swapchain.
    // -----------------------------------------------------------------------

    pub fn init(gpa: std.mem.Allocator, platform: *Platform) BackendError!WebGpuBackend {
        const impl = gpa.create(WgpuImpl) catch return BackendError.InstanceCreationFailed;
        impl.* = .{ .allocator = gpa };
        errdefer gpa.destroy(impl);

        // 1. Create WGPUInstance.
        impl.instance = c.wgpuCreateInstance(null);
        if (impl.instance == null) return BackendError.InstanceCreationFailed;
        errdefer { c.wgpuInstanceRelease(impl.instance); impl.instance = null; }

        // 2. Create surface from the Platform window handle.
        // We call surface_webgpu_native directly (not via platform.createSurface) so that
        // wgpu-native symbols are only referenced in this file (compiled only on -Dgpu=webgpu).
        {
            const surface_native = @import("surface_webgpu_native.zig");
            const PlatformImpl = struct { window: *anyopaque };
            _ = PlatformImpl;
            // Extract the GLFW window pointer from Platform._impl.
            // Platform._impl is a *PlatformImpl with `window: *c.GLFWwindow` as the first field.
            const platform_impl_ptr: *anyopaque = platform._impl;
            // The GLFWwindow pointer is the first field of PlatformImpl.
            const window_ptr: **anyopaque = @ptrCast(@alignCast(platform_impl_ptr));
            const glfw_window: *anyopaque = window_ptr.*;
            const raw_surface = surface_native.createWebGpuNativeSurface(
                impl.instance,
                glfw_window,
            ) catch return BackendError.InstanceCreationFailed;
            impl.wgpu_surface = @ptrCast(raw_surface);
        }
        if (impl.wgpu_surface == null) return BackendError.InstanceCreationFailed;
        errdefer { c.wgpuSurfaceRelease(impl.wgpu_surface); impl.wgpu_surface = null; }

        // 3. Request adapter (synchronous via callback + spin).
        {
            var state = AdapterState{};
            const opts = std.mem.zeroes(c.WGPURequestAdapterOptions);
            c.wgpuInstanceRequestAdapter(impl.instance, &opts, adapterCallback, &state);
            // wgpu-native processes the request immediately in the callback on native.
            if (!state.done or state.adapter == null) return BackendError.NoSuitableDevice;
            impl.adapter = state.adapter;
        }
        errdefer { c.wgpuAdapterRelease(impl.adapter); impl.adapter = null; }

        // 4. Request device.
        {
            var state = DeviceState{};
            var dev_desc = std.mem.zeroes(c.WGPUDeviceDescriptor);
            dev_desc.defaultQueue.label = "default_queue";
            c.wgpuAdapterRequestDevice(impl.adapter, &dev_desc, deviceCallback, &state);
            if (!state.done or state.device == null) return BackendError.DeviceCreationFailed;
            impl.device = state.device;
        }
        errdefer { c.wgpuDeviceRelease(impl.device); impl.device = null; }

        // 5. Get queue.
        impl.queue = c.wgpuDeviceGetQueue(impl.device);
        if (impl.queue == null) return BackendError.DeviceCreationFailed;

        // 6. Get framebuffer size.
        const fb = platform.framebufferSize();
        impl.width  = fb.width;
        impl.height = fb.height;

        // 7. Create swapchain.
        {
            var sc_desc = std.mem.zeroes(c.WGPUSwapChainDescriptor);
            sc_desc.usage   = c.WGPUTextureUsage_RenderAttachment;
            sc_desc.format  = impl.format;
            sc_desc.width   = impl.width;
            sc_desc.height  = impl.height;
            sc_desc.presentMode = c.WGPUPresentMode_Fifo;
            impl.swap_chain = c.wgpuDeviceCreateSwapChain(impl.device, impl.wgpu_surface, &sc_desc);
        }
        if (impl.swap_chain == null) return BackendError.SwapchainCreationFailed;

        return WebGpuBackend{ ._impl = impl };
    }

    // -----------------------------------------------------------------------
    // deinit
    // -----------------------------------------------------------------------

    pub fn deinit(self: *WebGpuBackend) void {
        const impl: *WgpuImpl = @ptrCast(@alignCast(self._impl));

        if (impl.vertex_buffer)    |b| { c.wgpuBufferRelease(b); }
        if (impl.pipeline)         |p| { c.wgpuRenderPipelineRelease(p); }
        if (impl.bind_group_layout)|l| { c.wgpuBindGroupLayoutRelease(l); }
        if (impl.pipeline_layout)  |l| { c.wgpuPipelineLayoutRelease(l); }
        if (impl.swap_chain)       |s| { c.wgpuSwapChainRelease(s); }
        if (impl.queue)            |q| { c.wgpuQueueRelease(q); }
        if (impl.wgpu_surface)     |s| { c.wgpuSurfaceRelease(s); }
        if (impl.device)           |d| { c.wgpuDeviceRelease(d); }
        if (impl.adapter)          |a| { c.wgpuAdapterRelease(a); }
        if (impl.instance)         |i| { c.wgpuInstanceRelease(i); }

        impl.allocator.destroy(impl);
    }

    // -----------------------------------------------------------------------
    // initPipelines — load WGSL, create bind group layout + render pipeline.
    // -----------------------------------------------------------------------

    pub fn initPipelines(self: *WebGpuBackend) !void {
        const impl: *WgpuImpl = @ptrCast(@alignCast(self._impl));
        if (impl.pipelines_ready) return;

        // 1. Load and compile the WGSL shader.
        const wgsl_src: [:0]const u8 = @embedFile("shaders/quad.wgsl");

        var wgsl_desc = std.mem.zeroes(c.WGPUShaderModuleWGSLDescriptor);
        wgsl_desc.chain.sType = c.WGPUSType_ShaderModuleWGSLDescriptor;
        wgsl_desc.chain.next  = null;
        wgsl_desc.code = wgsl_src.ptr;

        var sm_desc = std.mem.zeroes(c.WGPUShaderModuleDescriptor);
        sm_desc.nextInChain = @ptrCast(&wgsl_desc.chain);
        sm_desc.label = "quad_wgsl";
        const shader_module = c.wgpuDeviceCreateShaderModule(impl.device, &sm_desc);
        if (shader_module == null) return BackendError.ShaderLoadFailed;
        defer c.wgpuShaderModuleRelease(shader_module);

        // 2. Bind group layout: binding 0 = texture, binding 1 = sampler.
        const bgl_entries = [2]c.WGPUBindGroupLayoutEntry{
            .{
                .nextInChain = null,
                .binding     = 0,
                .visibility  = c.WGPUShaderStage_Fragment,
                .buffer      = .{ .nextInChain = null, .type = 0, .hasDynamicOffset = 0, .minBindingSize = 0 },
                .sampler     = .{ .nextInChain = null, .type = 0 },
                .texture     = .{ .nextInChain = null, .sampleType = c.WGPUTextureSampleType_Float, .viewDimension = c.WGPUTextureViewDimension_2D, .multisampled = 0 },
                .storageTexture = .{ .nextInChain = null, .access = 0, .format = c.WGPUTextureFormat_Undefined, .viewDimension = c.WGPUTextureViewDimension_2D },
            },
            .{
                .nextInChain = null,
                .binding     = 1,
                .visibility  = c.WGPUShaderStage_Fragment,
                .buffer      = .{ .nextInChain = null, .type = 0, .hasDynamicOffset = 0, .minBindingSize = 0 },
                .sampler     = .{ .nextInChain = null, .type = c.WGPUSamplerBindingType_Filtering },
                .texture     = .{ .nextInChain = null, .sampleType = 0, .viewDimension = c.WGPUTextureViewDimension_2D, .multisampled = 0 },
                .storageTexture = .{ .nextInChain = null, .access = 0, .format = c.WGPUTextureFormat_Undefined, .viewDimension = c.WGPUTextureViewDimension_2D },
            },
        };

        var bgl_desc = std.mem.zeroes(c.WGPUBindGroupLayoutDescriptor);
        bgl_desc.label      = "quad_bgl";
        bgl_desc.entryCount = 2;
        bgl_desc.entries    = &bgl_entries[0];
        impl.bind_group_layout = c.wgpuDeviceCreateBindGroupLayout(impl.device, &bgl_desc);
        if (impl.bind_group_layout == null) return BackendError.ShaderLoadFailed;

        // 3. Pipeline layout.
        var pl_desc = std.mem.zeroes(c.WGPUPipelineLayoutDescriptor);
        pl_desc.label                = "quad_pl";
        pl_desc.bindGroupLayoutCount = 1;
        pl_desc.bindGroupLayouts     = &impl.bind_group_layout;
        impl.pipeline_layout = c.wgpuDeviceCreatePipelineLayout(impl.device, &pl_desc);
        if (impl.pipeline_layout == null) return BackendError.ShaderLoadFailed;

        // 4. Vertex buffer attributes (matching QuadVertex layout above).
        // Layout: pos(0) f32x2 @ 0, uv(1) f32x2 @ 8, color(2) u32 @ 16,
        //         color_b(3) u32 @ 20, mode(4) u32 @ 24
        const vb_attribs = [5]c.WGPUVertexAttribute{
            .{ .format = c.WGPUVertexFormat_Float32x2, .offset =  0, .shaderLocation = 0 },
            .{ .format = c.WGPUVertexFormat_Float32x2, .offset =  8, .shaderLocation = 1 },
            .{ .format = c.WGPUVertexFormat_Uint32,    .offset = 16, .shaderLocation = 2 },
            .{ .format = c.WGPUVertexFormat_Uint32,    .offset = 20, .shaderLocation = 3 },
            .{ .format = c.WGPUVertexFormat_Uint32,    .offset = 24, .shaderLocation = 4 },
        };

        const vb_layout = c.WGPUVertexBufferLayout{
            .arrayStride = @sizeOf(QuadVertex),
            .stepMode    = c.WGPUVertexStepMode_Vertex,
            .attributeCount = 5,
            .attributes  = &vb_attribs[0],
        };

        // 5. Blend state (premultiplied alpha — same as Vulkan/DX12 pipeline).
        const blend = c.WGPUBlendState{
            .color = .{ .operation = c.WGPUBlendOperation_Add, .srcFactor = c.WGPUBlendFactor_One, .dstFactor = c.WGPUBlendFactor_OneMinusSrcAlpha },
            .alpha = .{ .operation = c.WGPUBlendOperation_Add, .srcFactor = c.WGPUBlendFactor_One, .dstFactor = c.WGPUBlendFactor_OneMinusSrcAlpha },
        };

        const color_target = c.WGPUColorTargetState{
            .nextInChain = null,
            .format      = impl.format,
            .blend       = &blend,
            .writeMask   = 0xF, // all channels
        };

        const fragment_state = c.WGPUFragmentState{
            .nextInChain  = null,
            .module       = shader_module,
            .entryPoint   = "fs_main",
            .constantCount = 0,
            .constants    = null,
            .targetCount  = 1,
            .targets      = &color_target,
        };

        // 6. Render pipeline descriptor.
        const pipeline_desc = c.WGPURenderPipelineDescriptor{
            .nextInChain = null,
            .label       = "quad_pipeline",
            .layout      = impl.pipeline_layout,
            .vertex      = .{
                .nextInChain   = null,
                .module        = shader_module,
                .entryPoint    = "vs_main",
                .constantCount = 0,
                .constants     = null,
                .bufferCount   = 1,
                .buffers       = &vb_layout,
            },
            .primitive = .{
                .nextInChain   = null,
                .topology      = c.WGPUPrimitiveTopology_TriangleList,
                .stripIndexFormat = 0,
                .frontFace     = c.WGPUFrontFace_CCW,
                .cullMode      = c.WGPUCullMode_None,
            },
            .depthStencil = null,
            .multisample  = null,
            .fragment     = &fragment_state,
        };

        impl.pipeline = c.wgpuDeviceCreateRenderPipeline(impl.device, &pipeline_desc);
        if (impl.pipeline == null) return BackendError.ShaderLoadFailed;

        // 7. Create staging vertex buffer (1 MiB — ring buffer for per-frame quads).
        impl.vertex_buf_size = 1024 * 1024;
        var vb_desc = std.mem.zeroes(c.WGPUBufferDescriptor);
        vb_desc.label            = "quad_vb";
        vb_desc.usage            = c.WGPUBufferUsage_Vertex | c.WGPUBufferUsage_CopyDst;
        vb_desc.size             = impl.vertex_buf_size;
        vb_desc.mappedAtCreation = 0;
        impl.vertex_buffer = c.wgpuDeviceCreateBuffer(impl.device, &vb_desc);
        if (impl.vertex_buffer == null) return BackendError.ShaderLoadFailed;

        impl.pipelines_ready = true;
    }

    // -----------------------------------------------------------------------
    // resize — recreate swapchain at new dimensions.
    // -----------------------------------------------------------------------

    pub fn resize(self: *WebGpuBackend, w: u32, h: u32, dpi_scale: f32) void {
        _ = dpi_scale;
        const impl: *WgpuImpl = @ptrCast(@alignCast(self._impl));
        if (w == 0 or h == 0) return;
        if (w == impl.width and h == impl.height) return;

        impl.width  = w;
        impl.height = h;

        // Release old swap chain and create a new one.
        if (impl.swap_chain) |s| {
            c.wgpuSwapChainRelease(s);
            impl.swap_chain = null;
        }

        var sc_desc = std.mem.zeroes(c.WGPUSwapChainDescriptor);
        sc_desc.usage   = c.WGPUTextureUsage_RenderAttachment;
        sc_desc.format  = impl.format;
        sc_desc.width   = w;
        sc_desc.height  = h;
        sc_desc.presentMode = c.WGPUPresentMode_Fifo;
        impl.swap_chain = c.wgpuDeviceCreateSwapChain(impl.device, impl.wgpu_surface, &sc_desc);
    }

    // -----------------------------------------------------------------------
    // uploadAtlas — upload a grayscale glyph atlas (R8_Unorm).
    // -----------------------------------------------------------------------

    pub fn uploadAtlas(self: *WebGpuBackend, atlas: *const anyopaque) BackendError!struct { backend_obj: *anyopaque } {
        const impl: *WgpuImpl = @ptrCast(@alignCast(self._impl));
        const GlyphAtlas = @import("../02/types.zig").GlyphAtlas;
        const cpu: *const GlyphAtlas = @ptrCast(@alignCast(atlas));
        return uploadTexture(impl, cpu.pixels, cpu.width, cpu.height, c.WGPUTextureFormat_R8Unorm);
    }

    // -----------------------------------------------------------------------
    // uploadSdfAtlas — upload an SDF icon atlas (R8_Unorm).
    // -----------------------------------------------------------------------

    pub fn uploadSdfAtlas(self: *WebGpuBackend, atlas: *const anyopaque) BackendError!struct { backend_obj: *anyopaque } {
        const impl: *WgpuImpl = @ptrCast(@alignCast(self._impl));
        const SdfAtlas = @import("../09/types.zig").SdfAtlas;
        const cpu: *const SdfAtlas = @ptrCast(@alignCast(atlas));
        return uploadTexture(impl, cpu.pixels, cpu.width, cpu.height, c.WGPUTextureFormat_R8Unorm);
    }

    // -----------------------------------------------------------------------
    // uploadImage — upload an RGBA image (RGBA8Unorm).
    // -----------------------------------------------------------------------

    pub fn uploadImage(self: *WebGpuBackend, pixels: []const u8, w: u32, h: u32) BackendError!struct { backend_obj: *anyopaque } {
        const impl: *WgpuImpl = @ptrCast(@alignCast(self._impl));
        return uploadTexture(impl, pixels, w, h, c.WGPUTextureFormat_RGBA8Unorm);
    }

    // -----------------------------------------------------------------------
    // drawFrame — record and submit one frame.
    // -----------------------------------------------------------------------

    pub fn drawFrame(self: *WebGpuBackend, commands: []const DrawCommand, handles: AtlasHandles) void {
        const impl: *WgpuImpl = @ptrCast(@alignCast(self._impl));
        if (!impl.pipelines_ready) return;
        if (impl.swap_chain == null) return;

        // 1. Get current swapchain texture view.
        const target_view = c.wgpuSwapChainGetCurrentTextureView(impl.swap_chain);
        if (target_view == null) return;
        defer c.wgpuTextureViewRelease(target_view);

        // 2. Build per-draw bind group (using the glyph atlas as the bound texture).
        const glyph_tex: *const WgpuTexture = @ptrCast(@alignCast(handles.glyph.backend_obj));
        const bind_group = makeBindGroup(impl, glyph_tex) orelse return;
        defer c.wgpuBindGroupRelease(bind_group);

        // 3. Build vertex data.
        const w: f32 = @floatFromInt(impl.width);
        const h: f32 = @floatFromInt(impl.height);

        // Ortho projection: maps [0,w]x[0,h] to NDC [-1,1]x[1,-1].
        // We compute NDC in the CPU vertex data directly (same as DX12 path).
        // For simplicity we store pre-projected vertices in the staging buffer.

        // Temporary stack buffer for vertices (max 4096 quads = 24576 vertices).
        const MAX_VERTS = 24576;
        var vtx_buf: [MAX_VERTS]QuadVertex = undefined;
        var vert_count: u32 = 0;

        for (commands) |cmd| {
            switch (cmd) {
                .set_scissor, .restore_scissor,
                .clip_rounded_begin, .clip_rounded_end => {
                    // Scissor and clip are not yet wired for WebGPU in this pass (RJ4 scope).
                    // They are handled on the CPU side in future passes.
                    continue;
                },
                else => {
                    if (vert_count + 6 > MAX_VERTS) break; // overflow guard
                    const emitted = emitQuad(vtx_buf[vert_count..].ptr, cmd, w, h);
                    vert_count += emitted;
                },
            }
        }

        // 4. Upload vertex data to GPU buffer.
        if (vert_count > 0) {
            const byte_count = @as(u64, vert_count) * @sizeOf(QuadVertex);
            c.wgpuQueueWriteBuffer(
                impl.queue,
                impl.vertex_buffer,
                0,
                &vtx_buf[0],
                @intCast(byte_count),
            );
        }

        // 5. Create command encoder.
        var enc_desc = std.mem.zeroes(c.WGPUCommandEncoderDescriptor);
        enc_desc.label = "frame_encoder";
        const encoder = c.wgpuDeviceCreateCommandEncoder(impl.device, &enc_desc);
        defer c.wgpuCommandEncoderRelease(encoder);

        // 6. Begin render pass (clear to black).
        const color_attachment = c.WGPURenderPassColorAttachment{
            .nextInChain   = null,
            .view          = target_view,
            .resolveTarget = null,
            .loadOp        = c.WGPULoadOp_Clear,
            .storeOp       = c.WGPUStoreOp_Store,
            .clearValue    = .{ .r = 0.0, .g = 0.0, .b = 0.0, .a = 1.0 },
        };

        var rp_desc = std.mem.zeroes(c.WGPURenderPassDescriptor);
        rp_desc.label                  = "frame_pass";
        rp_desc.colorAttachmentCount   = 1;
        rp_desc.colorAttachments       = &color_attachment;
        rp_desc.depthStencilAttachment = null;

        const pass = c.wgpuCommandEncoderBeginRenderPass(encoder, &rp_desc);
        defer c.wgpuRenderPassEncoderRelease(pass);

        // 7. Draw.
        if (vert_count > 0) {
            c.wgpuRenderPassEncoderSetPipeline(pass, impl.pipeline);
            c.wgpuRenderPassEncoderSetBindGroup(pass, 0, bind_group, 0, null);
            c.wgpuRenderPassEncoderSetVertexBuffer(
                pass, 0, impl.vertex_buffer, 0,
                @as(u64, vert_count) * @sizeOf(QuadVertex),
            );
            c.wgpuRenderPassEncoderDraw(pass, vert_count, 1, 0, 0);
        }

        c.wgpuRenderPassEncoderEnd(pass);

        // 8. Submit.
        var cmd_buf_desc = std.mem.zeroes(c.WGPUCommandBufferDescriptor);
        cmd_buf_desc.label = "frame_cmd";
        const cmd_buf = c.wgpuCommandEncoderFinish(encoder, &cmd_buf_desc);
        defer c.wgpuCommandBufferRelease(cmd_buf);

        var submit_cmd_buf: c.WGPUCommandBuffer = cmd_buf;
        c.wgpuQueueSubmit(impl.queue, 1, &submit_cmd_buf);

        // 9. Present.
        c.wgpuSwapChainPresent(impl.swap_chain);
    }

    // -----------------------------------------------------------------------
    // capabilities
    // -----------------------------------------------------------------------

    pub fn capabilities(self: *const WebGpuBackend) struct { max_texture_dim: u32, subpixel_text: bool, present_modes: u8 } {
        _ = self;
        return .{
            .max_texture_dim = 8192,
            .subpixel_text   = false, // WebGPU does not support subpixel blending portably
            .present_modes   = 0b0001, // fifo only
        };
    }
};

// ---------------------------------------------------------------------------
// Internal helper: create a bind group for the given texture.
// ---------------------------------------------------------------------------

fn makeBindGroup(impl: *WgpuImpl, tex: *const WgpuTexture) ?c.WGPUBindGroup {
    if (tex.view == null or tex.sampler == null) return null;

    const entries = [2]c.WGPUBindGroupEntry{
        .{
            .nextInChain = null,
            .binding     = 0,
            .buffer      = null,
            .offset      = 0,
            .size        = 0,
            .sampler     = null,
            .textureView = tex.view,
        },
        .{
            .nextInChain = null,
            .binding     = 1,
            .buffer      = null,
            .offset      = 0,
            .size        = 0,
            .sampler     = tex.sampler,
            .textureView = null,
        },
    };

    var bg_desc = std.mem.zeroes(c.WGPUBindGroupDescriptor);
    bg_desc.label      = "quad_bg";
    bg_desc.layout     = impl.bind_group_layout;
    bg_desc.entryCount = 2;
    bg_desc.entries    = &entries[0];

    return c.wgpuDeviceCreateBindGroup(impl.device, &bg_desc);
}

// ---------------------------------------------------------------------------
// Internal helper: upload a 2D texture to the GPU.
// ---------------------------------------------------------------------------

fn uploadTexture(
    impl:   *WgpuImpl,
    pixels: []const u8,
    width:  u32,
    height: u32,
    format: c.WGPUTextureFormat,
) BackendError!struct { backend_obj: *anyopaque } {
    const bytes_per_pixel: u32 = switch (format) {
        c.WGPUTextureFormat_R8Unorm    => 1,
        c.WGPUTextureFormat_RGBA8Unorm => 4,
        else => return BackendError.DeviceCreationFailed,
    };

    // Create GPU texture.
    var tex_desc = std.mem.zeroes(c.WGPUTextureDescriptor);
    tex_desc.label          = "atlas";
    tex_desc.usage          = c.WGPUTextureUsage_CopyDst | c.WGPUTextureUsage_TextureBinding;
    tex_desc.dimension      = c.WGPUTextureDimension_2D;
    tex_desc.size           = .{ .width = width, .height = height, .depthOrArrayLayers = 1 };
    tex_desc.format         = format;
    tex_desc.mipLevelCount  = 1;
    tex_desc.sampleCount    = 1;
    tex_desc.viewFormatCount = 0;
    tex_desc.viewFormats    = null;

    const texture = c.wgpuDeviceCreateTexture(impl.device, &tex_desc);
    if (texture == null) return BackendError.DeviceCreationFailed;
    errdefer c.wgpuTextureRelease(texture);

    // Upload pixel data.
    {
        const dst = c.WGPUImageCopyTexture{
            .nextInChain = null,
            .texture     = texture,
            .mipLevel    = 0,
            .origin      = .{ .x = 0, .y = 0, .z = 0 },
            .aspect      = c.WGPUTextureAspect_All,
        };
        const layout = c.WGPUTextureDataLayout{
            .nextInChain  = null,
            .offset       = 0,
            .bytesPerRow  = width * bytes_per_pixel,
            .rowsPerImage = height,
        };
        const size = c.WGPUExtent3D{ .width = width, .height = height, .depthOrArrayLayers = 1 };
        c.wgpuQueueWriteTexture(impl.queue, &dst, pixels.ptr, pixels.len, &layout, &size);
    }

    // Create texture view.
    var view_desc = std.mem.zeroes(c.WGPUTextureViewDescriptor);
    view_desc.label           = "atlas_view";
    view_desc.format          = format;
    view_desc.dimension       = c.WGPUTextureViewDimension_2D;
    view_desc.baseMipLevel    = 0;
    view_desc.mipLevelCount   = 1;
    view_desc.baseArrayLayer  = 0;
    view_desc.arrayLayerCount = 1;
    view_desc.aspect          = c.WGPUTextureAspect_All;

    const view = c.wgpuTextureCreateView(texture, &view_desc);
    if (view == null) return BackendError.DeviceCreationFailed;
    errdefer c.wgpuTextureViewRelease(view);

    // Create sampler (linear, clamp-to-edge).
    var samp_desc = std.mem.zeroes(c.WGPUSamplerDescriptor);
    samp_desc.label        = "atlas_sampler";
    samp_desc.addressModeU = c.WGPUAddressMode_ClampToEdge;
    samp_desc.addressModeV = c.WGPUAddressMode_ClampToEdge;
    samp_desc.addressModeW = c.WGPUAddressMode_ClampToEdge;
    samp_desc.magFilter    = c.WGPUFilterMode_Linear;
    samp_desc.minFilter    = c.WGPUFilterMode_Linear;
    samp_desc.mipmapFilter = c.WGPUMipmapFilterMode_Nearest;
    samp_desc.lodMinClamp  = 0.0;
    samp_desc.lodMaxClamp  = 1.0;
    samp_desc.maxAnisotropy = 1;

    const sampler = c.wgpuDeviceCreateSampler(impl.device, &samp_desc);
    if (sampler == null) return BackendError.DeviceCreationFailed;

    // Heap-allocate the WgpuTexture handle so we can return a *anyopaque.
    const heap_tex = impl.allocator.create(WgpuTexture) catch return BackendError.DeviceCreationFailed;
    heap_tex.* = .{
        .texture = texture,
        .view    = view,
        .sampler = sampler,
        .width   = width,
        .height  = height,
    };

    return .{ .backend_obj = heap_tex };
}

// ---------------------------------------------------------------------------
// Quad vertex emission (matches DX12 / Vulkan pattern).
// ---------------------------------------------------------------------------

/// Pack a Color09 (r,g,b,a u8) into a u32 RGBA big-endian.
inline fn packColor(r: u8, g: u8, b: u8, a: u8) u32 {
    return (@as(u32, r) << 24) | (@as(u32, g) << 16) | (@as(u32, b) << 8) | @as(u32, a);
}

/// Convert a pixel coordinate to NDC x coordinate.
inline fn toNdcX(px: f32, w: f32) f32 { return (px / w) * 2.0 - 1.0; }

/// Convert a pixel coordinate to NDC y coordinate (y-flip: top=+1, bottom=-1).
inline fn toNdcY(py: f32, h: f32) f32 { return 1.0 - (py / h) * 2.0; }

/// Emit 6 vertices for one DrawCommand (2 triangles). Returns the number emitted.
fn emitQuad(vtx: [*]QuadVertex, cmd: DrawCommand, win_w: f32, win_h: f32) u32 {
    var px0: f32 = 0; var py0: f32 = 0;
    var px1: f32 = 0; var py1: f32 = 0;
    var tu0: f32 = 0; var tv0: f32 = 0;
    var tu1: f32 = 1; var tv1: f32 = 1;
    var color: u32 = packColor(255, 255, 255, 255);
    var color_b: u32 = packColor(255, 255, 255, 255);
    var mode: u32 = 0;

    switch (cmd) {
        .filled_rect => |r| {
            px0 = r.rect.x; py0 = r.rect.y;
            px1 = r.rect.x + r.rect.w; py1 = r.rect.y + r.rect.h;
            color = packColor(r.color.r, r.color.g, r.color.b, r.color.a);
            mode = 0;
        },
        .border_rect => |r| {
            px0 = r.rect.x; py0 = r.rect.y;
            px1 = r.rect.x + r.rect.w; py1 = r.rect.y + r.rect.h;
            color = packColor(r.color.r, r.color.g, r.color.b, r.color.a);
            mode = 2;
        },
        .glyph => |g| {
            px0 = g.dst.x; py0 = g.dst.y;
            px1 = g.dst.x + g.dst.w; py1 = g.dst.y + g.dst.h;
            tu0 = g.uv.x; tv0 = g.uv.y; tu1 = g.uv.x + g.uv.w; tv1 = g.uv.y + g.uv.h;
            color = packColor(g.color.r, g.color.g, g.color.b, g.color.a);
            mode = g.mode;
        },
        .image_rect => |r| {
            px0 = r.dst.x; py0 = r.dst.y;
            px1 = r.dst.x + r.dst.w; py1 = r.dst.y + r.dst.h;
            tu0 = r.uv.x; tv0 = r.uv.y; tu1 = r.uv.x + r.uv.w; tv1 = r.uv.y + r.uv.h;
            color = packColor(r.tint.r, r.tint.g, r.tint.b, r.tint.a);
            mode = 3;
        },
        .gradient_rect => |r| {
            px0 = r.rect.x; py0 = r.rect.y;
            px1 = r.rect.x + r.rect.w; py1 = r.rect.y + r.rect.h;
            color   = packColor(r.color_a.r, r.color_a.g, r.color_a.b, r.color_a.a);
            color_b = packColor(r.color_b.r, r.color_b.g, r.color_b.b, r.color_b.a);
            switch (r.direction) {
                .right        => { tu0 = 0.0; tv0 = 0.0; tu1 = 1.0; tv1 = 0.0; },
                .bottom       => { tu0 = 0.0; tv0 = 0.0; tu1 = 0.0; tv1 = 1.0; },
                .bottom_right => { tu0 = 0.0; tv0 = 0.0; tu1 = 1.0; tv1 = 1.0; },
            }
            mode = 5;
        },
        .aa_filled_rect => |r| {
            px0 = r.rect.x; py0 = r.rect.y;
            px1 = r.rect.x + r.rect.w; py1 = r.rect.y + r.rect.h;
            color = packColor(r.color.r, r.color.g, r.color.b, r.color.a);
            mode = 0;
        },
        .aa_filled_circle => |r| {
            px0 = r.center_x - r.radius; py0 = r.center_y - r.radius;
            px1 = r.center_x + r.radius; py1 = r.center_y + r.radius;
            tu0 = 0.0; tv0 = 0.0; tu1 = 1.0; tv1 = 1.0;
            color = packColor(r.color.r, r.color.g, r.color.b, r.color.a);
            mode = 6;
        },
        .sdf_icon => |r| {
            px0 = r.dst.x; py0 = r.dst.y;
            px1 = r.dst.x + r.dst.w; py1 = r.dst.y + r.dst.h;
            tu0 = r.uv.x; tv0 = r.uv.y; tu1 = r.uv.x + r.uv.w; tv1 = r.uv.y + r.uv.h;
            color = packColor(r.color.r, r.color.g, r.color.b, r.color.a);
            mode = 4;
        },
        else => return 0,
    }

    // Convert pixel coords to NDC.
    const x0 = toNdcX(px0, win_w); const y0 = toNdcY(py0, win_h);
    const x1 = toNdcX(px1, win_w); const y1 = toNdcY(py1, win_h);

    // Two triangles (CCW winding, NDC y-flipped):
    // Triangle 1: TL, TR, BL
    // Triangle 2: TR, BR, BL
    vtx[0] = .{ .pos = .{x0, y0}, .uv = .{tu0, tv0}, .color = color, .color_b = color_b, .mode = mode };
    vtx[1] = .{ .pos = .{x1, y0}, .uv = .{tu1, tv0}, .color = color, .color_b = color_b, .mode = mode };
    vtx[2] = .{ .pos = .{x0, y1}, .uv = .{tu0, tv1}, .color = color, .color_b = color_b, .mode = mode };
    vtx[3] = .{ .pos = .{x1, y0}, .uv = .{tu1, tv0}, .color = color, .color_b = color_b, .mode = mode };
    vtx[4] = .{ .pos = .{x1, y1}, .uv = .{tu1, tv1}, .color = color, .color_b = color_b, .mode = mode };
    vtx[5] = .{ .pos = .{x0, y1}, .uv = .{tu0, tv1}, .color = color, .color_b = color_b, .mode = mode };
    return 6;
}
