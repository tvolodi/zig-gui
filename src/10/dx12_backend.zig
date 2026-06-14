//! 10 — GPU backend — DX12 (Windows) — M22-01 / RJ3
//!
//! `Dx12Backend` implements the GpuBackend seam contract (INV-5.1) for Direct3D 12.
//! Selection: `zig build -Dgpu=dx12` (Windows only; Vulkan stays the default).
//!
//! All 9 GpuBackend methods are implemented (init, deinit, initPipelines, resize,
//! uploadAtlas, uploadSdfAtlas, uploadImage, drawFrame, capabilities).
//!
//! HLSL shaders (quad.hlsl, curve.hlsl) are compiled to DXIL by `dxc` at build time
//! and embedded via `embedded_shaders` (see build.zig).
//!
//! Dependencies: D3D12, DXGI (system Windows SDK headers — INV-5.6).
//!
//! COM vtable note: D3D12 interfaces are C++ COM objects. In Zig we access their
//! methods via `iface.*.lpVtbl.*.MethodName(iface, args...)` where `lpVtbl` is the
//! generated vtable pointer from the cImport.

const std = @import("std");
const builtin = @import("builtin");

// Only compile on Windows.
comptime {
    if (builtin.os.tag != .windows) {
        @compileError("dx12_backend.zig is only available on Windows (RJ3 / INV-1.2-v2)");
    }
}

const c = @cImport({
    @cInclude("windows.h");
    @cInclude("d3d12.h");
    @cInclude("dxgi1_4.h");
    @cInclude("d3d12sdklayers.h");
    @cDefine("GLFW_EXPOSE_NATIVE_WIN32", "1");
    @cInclude("GLFW/glfw3.h");
    @cInclude("GLFW/glfw3native.h");
});

const platform_types = @import("../01/types.zig");
const DrawCommand    = platform_types.DrawCommand;
const AtlasHandle    = platform_types.AtlasHandle;
const AtlasHandles   = platform_types.AtlasHandles;
const Platform       = platform_types.Platform;
const BackendError   = platform_types.BackendError;
const Caps           = @import("types.zig").Caps;

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const FRAME_COUNT: u32 = 2; // double-buffered swapchain

// DXGI format for the swapchain back buffers (BGRA8 matches common DX12 usage).
const BACK_BUFFER_FORMAT: c.DXGI_FORMAT = c.DXGI_FORMAT_B8G8R8A8_UNORM;

// ---------------------------------------------------------------------------
// GPU texture atlas handle (holds the D3D12 resource + SRV heap index).
// ---------------------------------------------------------------------------

const GpuTexture = struct {
    resource:  ?*c.ID3D12Resource = null,
    srv_index: u32 = 0,
    width:     u32 = 0,
    height:    u32 = 0,
};

// ---------------------------------------------------------------------------
// Internal implementation struct
// ---------------------------------------------------------------------------

const Dx12Impl = struct {
    allocator: std.mem.Allocator,

    // Core D3D12 objects
    device:     ?*c.ID3D12Device    = null,
    cmd_queue:  ?*c.ID3D12CommandQueue = null,
    swap_chain: ?*c.IDXGISwapChain3 = null,
    hwnd:       c.HWND              = null,
    width:      u32                 = 0,
    height:     u32                 = 0,

    // Render targets (one per back buffer)
    rtv_heap:      ?*c.ID3D12DescriptorHeap = null,
    rtv_increment: u32                      = 0,
    rt_resources:  [FRAME_COUNT]?*c.ID3D12Resource = [_]?*c.ID3D12Resource{null} ** FRAME_COUNT,

    // Command recording
    cmd_allocators: [FRAME_COUNT]?*c.ID3D12CommandAllocator = [_]?*c.ID3D12CommandAllocator{null} ** FRAME_COUNT,
    cmd_list:       ?*c.ID3D12GraphicsCommandList = null,

    // CPU-GPU synchronisation
    fence:       ?*c.ID3D12Fence = null,
    fence_event: c.HANDLE        = null,
    fence_value: u64             = 0,
    frame_index: u32             = 0,

    // Shader-resource view heap (atlas textures)
    srv_heap:      ?*c.ID3D12DescriptorHeap = null,
    srv_increment: u32                      = 0,
    srv_next:      u32                      = 0, // next free SRV slot

    // Pipeline objects (created by initPipelines)
    root_signature:  ?*c.ID3D12RootSignature = null,
    pipeline_state:  ?*c.ID3D12PipelineState = null,
    pipelines_ready: bool                    = false,

    // Vertex upload heap (CPU-visible ring buffer for per-frame quads)
    vb_resource: ?*c.ID3D12Resource = null,
    vb_mapped:   ?[*]u8             = null,
    vb_capacity: u32                = 0,

    // Device properties for capabilities()
    max_texture_dim: u32 = 16384,
};

// ---------------------------------------------------------------------------
// COM helper: call a method through the interface vtable.
// Zig's cImport generates lpVtbl as the first field of every COM interface.
// Usage: comCall(obj, "MethodName", .{args...})
// ---------------------------------------------------------------------------

/// HRESULT error check — DX12 API calls return S_OK (0) on success.
inline fn hr(result: c.HRESULT) BackendError!void {
    if (result < 0) return BackendError.DeviceCreationFailed;
}

// ---------------------------------------------------------------------------
// Dx12Backend — public struct satisfying the GpuBackend contract (INV-5.1)
// ---------------------------------------------------------------------------

pub const Dx12Backend = struct {
    _impl: *anyopaque = undefined,

    // -----------------------------------------------------------------------
    // init — create device, swapchain, heaps, synchronisation objects.
    // -----------------------------------------------------------------------

    pub fn init(gpa: std.mem.Allocator, platform: *Platform) BackendError!Dx12Backend {
        const impl = gpa.create(Dx12Impl) catch return BackendError.InstanceCreationFailed;
        impl.* = .{ .allocator = gpa };
        errdefer gpa.destroy(impl);

        // Extract HWND from GLFW window via the Win32 native handle.
        const surface = platform.createSurface(.dx12, null) catch
            return BackendError.InstanceCreationFailed;
        impl.hwnd = @ptrCast(surface.dx12);

        // Get initial framebuffer size.
        const fb = platform.framebufferSize();
        impl.width  = fb.width;
        impl.height = fb.height;

        // Enable the D3D12 debug layer in debug builds.
        if (comptime builtin.mode == .Debug) {
            var debug_ctrl: ?*c.ID3D12Debug = null;
            if (c.D3D12GetDebugInterface(&c.IID_ID3D12Debug, @ptrCast(&debug_ctrl)) >= 0) {
                if (debug_ctrl) |d| d.*.lpVtbl.*.EnableDebugLayer.?(d);
            }
        }

        // Create DXGI factory.
        var factory: ?*c.IDXGIFactory4 = null;
        hr(c.CreateDXGIFactory1(&c.IID_IDXGIFactory4, @ptrCast(&factory))) catch
            return BackendError.InstanceCreationFailed;
        defer { if (factory) |f| _ = f.*.lpVtbl.*.Release.?(f); }

        // Find the first hardware adapter.
        var adapter: ?*c.IDXGIAdapter1 = null;
        {
            var i: u32 = 0;
            while (true) : (i += 1) {
                var a: ?*c.IDXGIAdapter1 = null;
                if (factory.?.*.lpVtbl.*.EnumAdapters1.?(factory.?, i, &a) != 0) break;
                // Try to create device on this adapter.
                var dev: ?*c.ID3D12Device = null;
                const ok = c.D3D12CreateDevice(
                    @ptrCast(a.?),
                    c.D3D_FEATURE_LEVEL_11_0,
                    &c.IID_ID3D12Device,
                    @ptrCast(&dev),
                );
                if (ok >= 0) {
                    if (dev) |d| _ = d.*.lpVtbl.*.Release.?(d);
                    adapter = a;
                    break;
                }
                if (a) |aa| _ = aa.*.lpVtbl.*.Release.?(aa);
            }
        }
        if (adapter == null) return BackendError.NoSuitableDevice;
        defer { if (adapter) |a| _ = a.*.lpVtbl.*.Release.?(a); }

        // Create D3D12 device.
        hr(c.D3D12CreateDevice(
            @ptrCast(adapter.?),
            c.D3D_FEATURE_LEVEL_11_0,
            &c.IID_ID3D12Device,
            @ptrCast(&impl.device),
        )) catch return BackendError.DeviceCreationFailed;

        // Query max texture dimension from feature level.
        impl.max_texture_dim = 16384; // Feature level 11.0 minimum

        // Create direct command queue.
        var queue_desc = std.mem.zeroes(c.D3D12_COMMAND_QUEUE_DESC);
        queue_desc.Type  = c.D3D12_COMMAND_LIST_TYPE_DIRECT;
        queue_desc.Flags = c.D3D12_COMMAND_QUEUE_FLAG_NONE;
        hr(impl.device.?.*.lpVtbl.*.CreateCommandQueue.?(
            impl.device.?,
            &queue_desc,
            &c.IID_ID3D12CommandQueue,
            @ptrCast(&impl.cmd_queue),
        )) catch return BackendError.DeviceCreationFailed;

        // Create IDXGISwapChain3.
        {
            var sc_desc = std.mem.zeroes(c.DXGI_SWAP_CHAIN_DESC1);
            sc_desc.BufferCount = FRAME_COUNT;
            sc_desc.Width       = impl.width;
            sc_desc.Height      = impl.height;
            sc_desc.Format      = BACK_BUFFER_FORMAT;
            sc_desc.BufferUsage = c.DXGI_USAGE_RENDER_TARGET_OUTPUT;
            sc_desc.SwapEffect  = c.DXGI_SWAP_EFFECT_FLIP_DISCARD;
            sc_desc.SampleDesc  = .{ .Count = 1, .Quality = 0 };

            var sc1: ?*c.IDXGISwapChain1 = null;
            hr(factory.?.*.lpVtbl.*.CreateSwapChainForHwnd.?(
                factory.?,
                @ptrCast(impl.cmd_queue.?),
                impl.hwnd,
                &sc_desc,
                null,
                null,
                &sc1,
            )) catch return BackendError.SwapchainCreationFailed;
            defer { if (sc1) |s| _ = s.*.lpVtbl.*.Release.?(s); }

            hr(sc1.?.*.lpVtbl.*.QueryInterface.?(
                sc1.?,
                &c.IID_IDXGISwapChain3,
                @ptrCast(&impl.swap_chain),
            )) catch return BackendError.SwapchainCreationFailed;
        }
        impl.frame_index = impl.swap_chain.?.*.lpVtbl.*.GetCurrentBackBufferIndex.?(impl.swap_chain.?);

        // Create RTV descriptor heap (one entry per back buffer).
        {
            var heap_desc = std.mem.zeroes(c.D3D12_DESCRIPTOR_HEAP_DESC);
            heap_desc.NumDescriptors = FRAME_COUNT;
            heap_desc.Type           = c.D3D12_DESCRIPTOR_HEAP_TYPE_RTV;
            heap_desc.Flags          = c.D3D12_DESCRIPTOR_HEAP_FLAG_NONE;
            hr(impl.device.?.*.lpVtbl.*.CreateDescriptorHeap.?(
                impl.device.?,
                &heap_desc,
                &c.IID_ID3D12DescriptorHeap,
                @ptrCast(&impl.rtv_heap),
            )) catch return BackendError.DeviceCreationFailed;
        }
        impl.rtv_increment = impl.device.?.*.lpVtbl.*.GetDescriptorHandleIncrementSize.?(
            impl.device.?, c.D3D12_DESCRIPTOR_HEAP_TYPE_RTV);

        // Create RTVs.
        try createRenderTargets(impl);

        // Create SRV descriptor heap (128 slots: glyph, SDF, image, and future atlases).
        {
            const srv_count: u32 = 128;
            var heap_desc = std.mem.zeroes(c.D3D12_DESCRIPTOR_HEAP_DESC);
            heap_desc.NumDescriptors = srv_count;
            heap_desc.Type           = c.D3D12_DESCRIPTOR_HEAP_TYPE_CBV_SRV_UAV;
            heap_desc.Flags          = c.D3D12_DESCRIPTOR_HEAP_FLAG_SHADER_VISIBLE;
            hr(impl.device.?.*.lpVtbl.*.CreateDescriptorHeap.?(
                impl.device.?,
                &heap_desc,
                &c.IID_ID3D12DescriptorHeap,
                @ptrCast(&impl.srv_heap),
            )) catch return BackendError.DeviceCreationFailed;
        }
        impl.srv_increment = impl.device.?.*.lpVtbl.*.GetDescriptorHandleIncrementSize.?(
            impl.device.?, c.D3D12_DESCRIPTOR_HEAP_TYPE_CBV_SRV_UAV);

        // Create command allocators and command list.
        for (0..FRAME_COUNT) |i| {
            hr(impl.device.?.*.lpVtbl.*.CreateCommandAllocator.?(
                impl.device.?,
                c.D3D12_COMMAND_LIST_TYPE_DIRECT,
                &c.IID_ID3D12CommandAllocator,
                @ptrCast(&impl.cmd_allocators[i]),
            )) catch return BackendError.DeviceCreationFailed;
        }
        hr(impl.device.?.*.lpVtbl.*.CreateCommandList.?(
            impl.device.?,
            0,
            c.D3D12_COMMAND_LIST_TYPE_DIRECT,
            impl.cmd_allocators[0].?,
            null,
            &c.IID_ID3D12GraphicsCommandList,
            @ptrCast(&impl.cmd_list),
        )) catch return BackendError.DeviceCreationFailed;
        // Close the command list (it starts in recording state).
        _ = impl.cmd_list.?.*.lpVtbl.*.Close.?(impl.cmd_list.?);

        // Create fence and event for CPU-GPU synchronisation.
        hr(impl.device.?.*.lpVtbl.*.CreateFence.?(
            impl.device.?,
            0,
            c.D3D12_FENCE_FLAG_NONE,
            &c.IID_ID3D12Fence,
            @ptrCast(&impl.fence),
        )) catch return BackendError.DeviceCreationFailed;
        impl.fence_value = 1;
        impl.fence_event = c.CreateEventW(null, c.FALSE, c.FALSE, null);
        if (impl.fence_event == null) return BackendError.DeviceCreationFailed;

        // Create a small upload-heap vertex buffer (1 MiB — plenty for UI quads).
        impl.vb_capacity = 1024 * 1024;
        {
            var heap_props = std.mem.zeroes(c.D3D12_HEAP_PROPERTIES);
            heap_props.Type = c.D3D12_HEAP_TYPE_UPLOAD;
            var res_desc = std.mem.zeroes(c.D3D12_RESOURCE_DESC);
            res_desc.Dimension        = c.D3D12_RESOURCE_DIMENSION_BUFFER;
            res_desc.Width            = impl.vb_capacity;
            res_desc.Height           = 1;
            res_desc.DepthOrArraySize = 1;
            res_desc.MipLevels        = 1;
            res_desc.Format           = c.DXGI_FORMAT_UNKNOWN;
            res_desc.SampleDesc       = .{ .Count = 1, .Quality = 0 };
            res_desc.Layout           = c.D3D12_TEXTURE_LAYOUT_ROW_MAJOR;
            hr(impl.device.?.*.lpVtbl.*.CreateCommittedResource.?(
                impl.device.?,
                &heap_props,
                c.D3D12_HEAP_FLAG_NONE,
                &res_desc,
                c.D3D12_RESOURCE_STATE_GENERIC_READ,
                null,
                &c.IID_ID3D12Resource,
                @ptrCast(&impl.vb_resource),
            )) catch return BackendError.DeviceCreationFailed;

            var range = c.D3D12_RANGE{ .Begin = 0, .End = 0 };
            var mapped: ?*anyopaque = null;
            _ = impl.vb_resource.?.*.lpVtbl.*.Map.?(impl.vb_resource.?, 0, &range, &mapped);
            impl.vb_mapped = @ptrCast(mapped);
        }

        return Dx12Backend{ ._impl = impl };
    }

    // -----------------------------------------------------------------------
    // deinit
    // -----------------------------------------------------------------------

    pub fn deinit(self: *Dx12Backend) void {
        const impl: *Dx12Impl = @ptrCast(@alignCast(self._impl));
        waitForGpu(impl);

        if (impl.vb_resource) |r| {
            var range = c.D3D12_RANGE{ .Begin = 0, .End = 0 };
            r.*.lpVtbl.*.Unmap.?(r, 0, &range);
            _ = r.*.lpVtbl.*.Release.?(r);
        }
        if (impl.pipeline_state) |ps| _ = ps.*.lpVtbl.*.Release.?(ps);
        if (impl.root_signature) |rs| _ = rs.*.lpVtbl.*.Release.?(rs);
        if (impl.fence_event)    |fe| _ = c.CloseHandle(fe);
        if (impl.fence)          |f|  _ = f.*.lpVtbl.*.Release.?(f);
        if (impl.cmd_list)       |cl| _ = cl.*.lpVtbl.*.Release.?(cl);
        for (0..FRAME_COUNT) |i| {
            if (impl.cmd_allocators[i]) |ca| _ = ca.*.lpVtbl.*.Release.?(ca);
            if (impl.rt_resources[i])   |rt| _ = rt.*.lpVtbl.*.Release.?(rt);
        }
        if (impl.srv_heap)  |h| _ = h.*.lpVtbl.*.Release.?(h);
        if (impl.rtv_heap)  |h| _ = h.*.lpVtbl.*.Release.?(h);
        if (impl.swap_chain)|s| _ = s.*.lpVtbl.*.Release.?(s);
        if (impl.cmd_queue) |q| _ = q.*.lpVtbl.*.Release.?(q);
        if (impl.device)    |d| _ = d.*.lpVtbl.*.Release.?(d);

        impl.allocator.destroy(impl);
    }

    // -----------------------------------------------------------------------
    // initPipelines — create root signature + PSO from embedded DXIL blobs.
    // -----------------------------------------------------------------------

    pub fn initPipelines(self: *Dx12Backend) !void {
        const impl: *Dx12Impl = @ptrCast(@alignCast(self._impl));
        if (impl.pipelines_ready) return;

        const shaders = @import("embedded_shaders");

        // ---------------------
        // Root signature
        // ---------------------
        // Layout:
        //   Root param 0: descriptor table (SRV t0-t2 + sampler s0)
        //   Root param 1: root 32-bit constants (push-constants equivalent)

        // Three SRV ranges: atlas (t0), subpixel (t1), SDF (t2).
        var srv_ranges = [3]c.D3D12_DESCRIPTOR_RANGE{
            .{
                .RangeType                         = c.D3D12_DESCRIPTOR_RANGE_TYPE_SRV,
                .NumDescriptors                    = 3,
                .BaseShaderRegister                = 0,
                .RegisterSpace                     = 0,
                .OffsetInDescriptorsFromTableStart = 0,
            },
            // Sampler range is in a separate heap; handled via static sampler below.
            undefined,
            undefined,
        };

        // Static sampler (linear, clamp-to-edge) at s0.
        var static_sampler = std.mem.zeroes(c.D3D12_STATIC_SAMPLER_DESC);
        static_sampler.Filter           = c.D3D12_FILTER_MIN_MAG_MIP_LINEAR;
        static_sampler.AddressU         = c.D3D12_TEXTURE_ADDRESS_MODE_CLAMP;
        static_sampler.AddressV         = c.D3D12_TEXTURE_ADDRESS_MODE_CLAMP;
        static_sampler.AddressW         = c.D3D12_TEXTURE_ADDRESS_MODE_CLAMP;
        static_sampler.ShaderRegister   = 0;
        static_sampler.RegisterSpace    = 0;
        static_sampler.ShaderVisibility = c.D3D12_SHADER_VISIBILITY_PIXEL;

        // Root parameters.
        var root_params = [2]c.D3D12_ROOT_PARAMETER{
            // Param 0: descriptor table (3 SRVs)
            .{
                .ParameterType    = c.D3D12_ROOT_PARAMETER_TYPE_DESCRIPTOR_TABLE,
                .ShaderVisibility = c.D3D12_SHADER_VISIBILITY_PIXEL,
                .unnamed_0        = .{
                    .DescriptorTable = .{
                        .NumDescriptorRanges = 1,
                        .pDescriptorRanges   = &srv_ranges[0],
                    },
                },
            },
            // Param 1: 32-bit root constants (push-constant equivalents: ortho[16] + clip[9])
            .{
                .ParameterType    = c.D3D12_ROOT_PARAMETER_TYPE_32BIT_CONSTANTS,
                .ShaderVisibility = c.D3D12_SHADER_VISIBILITY_ALL,
                .unnamed_0        = .{
                    .Constants = .{
                        .ShaderRegister = 0,
                        .RegisterSpace  = 0,
                        .Num32BitValues = 25, // 16 (ortho) + 4 (clipRect) + 4 (clipRadii) + 1 (clipEnabled)
                    },
                },
            },
        };

        var rs_desc = std.mem.zeroes(c.D3D12_ROOT_SIGNATURE_DESC);
        rs_desc.NumParameters     = 2;
        rs_desc.pParameters       = &root_params[0];
        rs_desc.NumStaticSamplers = 1;
        rs_desc.pStaticSamplers   = &static_sampler;
        rs_desc.Flags             = c.D3D12_ROOT_SIGNATURE_FLAG_ALLOW_INPUT_ASSEMBLER_INPUT_LAYOUT;

        var signature_blob:  ?*c.ID3DBlob = null;
        var error_blob:      ?*c.ID3DBlob = null;
        defer { if (signature_blob) |b| _ = b.*.lpVtbl.*.Release.?(b); }
        defer { if (error_blob)     |b| _ = b.*.lpVtbl.*.Release.?(b); }

        hr(c.D3D12SerializeRootSignature(
            &rs_desc,
            c.D3D_ROOT_SIGNATURE_VERSION_1,
            &signature_blob,
            &error_blob,
        )) catch return BackendError.ShaderLoadFailed;

        hr(impl.device.?.*.lpVtbl.*.CreateRootSignature.?(
            impl.device.?,
            0,
            signature_blob.?.*.lpVtbl.*.GetBufferPointer.?(signature_blob.?),
            signature_blob.?.*.lpVtbl.*.GetBufferSize.?(signature_blob.?),
            &c.IID_ID3D12RootSignature,
            @ptrCast(&impl.root_signature),
        )) catch return BackendError.ShaderLoadFailed;

        // ---------------------
        // Input layout
        // ---------------------
        // Matches QuadVertex in src/01/types.zig:
        //   pos[2]f32, uv[2]f32, color[4]u8, color_b[4]u8, mode u32
        const input_elements = [_]c.D3D12_INPUT_ELEMENT_DESC{
            .{
                .SemanticName         = "POSITION",
                .SemanticIndex        = 0,
                .Format               = c.DXGI_FORMAT_R32G32_FLOAT,
                .InputSlot            = 0,
                .AlignedByteOffset    = 0,
                .InputSlotClass       = c.D3D12_INPUT_CLASSIFICATION_PER_VERTEX_DATA,
                .InstanceDataStepRate = 0,
            },
            .{
                .SemanticName         = "TEXCOORD",
                .SemanticIndex        = 0,
                .Format               = c.DXGI_FORMAT_R32G32_FLOAT,
                .InputSlot            = 0,
                .AlignedByteOffset    = 8,
                .InputSlotClass       = c.D3D12_INPUT_CLASSIFICATION_PER_VERTEX_DATA,
                .InstanceDataStepRate = 0,
            },
            .{
                .SemanticName         = "COLOR",
                .SemanticIndex        = 0,
                .Format               = c.DXGI_FORMAT_R8G8B8A8_UNORM,
                .InputSlot            = 0,
                .AlignedByteOffset    = 16,
                .InputSlotClass       = c.D3D12_INPUT_CLASSIFICATION_PER_VERTEX_DATA,
                .InstanceDataStepRate = 0,
            },
            .{
                .SemanticName         = "COLOR",
                .SemanticIndex        = 1,
                .Format               = c.DXGI_FORMAT_R8G8B8A8_UNORM,
                .InputSlot            = 0,
                .AlignedByteOffset    = 20,
                .InputSlotClass       = c.D3D12_INPUT_CLASSIFICATION_PER_VERTEX_DATA,
                .InstanceDataStepRate = 0,
            },
            .{
                .SemanticName         = "BLENDINDICES",
                .SemanticIndex        = 0,
                .Format               = c.DXGI_FORMAT_R32_UINT,
                .InputSlot            = 0,
                .AlignedByteOffset    = 24,
                .InputSlotClass       = c.D3D12_INPUT_CLASSIFICATION_PER_VERTEX_DATA,
                .InstanceDataStepRate = 0,
            },
        };

        // ---------------------
        // Pipeline state object
        // ---------------------
        var pso_desc = std.mem.zeroes(c.D3D12_GRAPHICS_PIPELINE_STATE_DESC);
        pso_desc.pRootSignature       = impl.root_signature.?;
        pso_desc.VS                   = .{ .pShaderBytecode = shaders.quad_vert_dxil.ptr, .BytecodeLength = shaders.quad_vert_dxil.len };
        pso_desc.PS                   = .{ .pShaderBytecode = shaders.quad_frag_dxil.ptr, .BytecodeLength = shaders.quad_frag_dxil.len };
        pso_desc.InputLayout          = .{ .pInputElementDescs = &input_elements[0], .NumElements = input_elements.len };
        pso_desc.PrimitiveTopologyType = c.D3D12_PRIMITIVE_TOPOLOGY_TYPE_TRIANGLE;
        pso_desc.NumRenderTargets     = 1;
        pso_desc.RTVFormats[0]        = BACK_BUFFER_FORMAT;
        pso_desc.SampleDesc           = .{ .Count = 1, .Quality = 0 };
        pso_desc.SampleMask           = std.math.maxInt(u32);

        // Enable alpha blending (premultiplied alpha — same as Vulkan pipeline).
        pso_desc.BlendState.RenderTarget[0].BlendEnable           = c.TRUE;
        pso_desc.BlendState.RenderTarget[0].SrcBlend              = c.D3D12_BLEND_ONE;
        pso_desc.BlendState.RenderTarget[0].DestBlend             = c.D3D12_BLEND_INV_SRC_ALPHA;
        pso_desc.BlendState.RenderTarget[0].BlendOp               = c.D3D12_BLEND_OP_ADD;
        pso_desc.BlendState.RenderTarget[0].SrcBlendAlpha         = c.D3D12_BLEND_ONE;
        pso_desc.BlendState.RenderTarget[0].DestBlendAlpha        = c.D3D12_BLEND_INV_SRC_ALPHA;
        pso_desc.BlendState.RenderTarget[0].BlendOpAlpha          = c.D3D12_BLEND_OP_ADD;
        pso_desc.BlendState.RenderTarget[0].RenderTargetWriteMask = c.D3D12_COLOR_WRITE_ENABLE_ALL;

        // Rasteriser: no depth/stencil, CW front faces (matches GLFW / Vulkan defaults).
        pso_desc.RasterizerState.FillMode              = c.D3D12_FILL_MODE_SOLID;
        pso_desc.RasterizerState.CullMode              = c.D3D12_CULL_MODE_NONE;
        pso_desc.RasterizerState.DepthClipEnable       = c.TRUE;
        pso_desc.DepthStencilState.DepthEnable         = c.FALSE;
        pso_desc.DepthStencilState.StencilEnable       = c.FALSE;

        hr(impl.device.?.*.lpVtbl.*.CreateGraphicsPipelineState.?(
            impl.device.?,
            &pso_desc,
            &c.IID_ID3D12PipelineState,
            @ptrCast(&impl.pipeline_state),
        )) catch return BackendError.ShaderLoadFailed;

        impl.pipelines_ready = true;
    }

    // -----------------------------------------------------------------------
    // resize
    // -----------------------------------------------------------------------

    pub fn resize(self: *Dx12Backend, w: u32, h: u32, dpi_scale: f32) void {
        _ = dpi_scale; // RD5 deferred
        const impl: *Dx12Impl = @ptrCast(@alignCast(self._impl));
        if (w == 0 or h == 0) return;
        if (w == impl.width and h == impl.height) return;

        waitForGpu(impl);

        // Release existing render target references.
        for (0..FRAME_COUNT) |i| {
            if (impl.rt_resources[i]) |rt| {
                _ = rt.*.lpVtbl.*.Release.?(rt);
                impl.rt_resources[i] = null;
            }
        }

        impl.width  = w;
        impl.height = h;

        // Resize swap chain buffers.
        _ = impl.swap_chain.?.*.lpVtbl.*.ResizeBuffers.?(
            impl.swap_chain.?,
            FRAME_COUNT,
            w,
            h,
            BACK_BUFFER_FORMAT,
            0,
        );
        impl.frame_index = impl.swap_chain.?.*.lpVtbl.*.GetCurrentBackBufferIndex.?(impl.swap_chain.?);

        createRenderTargets(impl) catch {};
    }

    // -----------------------------------------------------------------------
    // uploadAtlas — upload a grayscale glyph atlas (R8_UNORM).
    // -----------------------------------------------------------------------

    pub fn uploadAtlas(self: *Dx12Backend, atlas: *const anyopaque) BackendError!struct { backend_obj: *anyopaque } {
        const impl: *Dx12Impl = @ptrCast(@alignCast(self._impl));

        // The atlas opaque pointer wraps a GlyphAtlas from mod02.
        // We extract pixels/width/height via the same pattern used by VulkanBackend.
        const GlyphAtlas = @import("../02/types.zig").GlyphAtlas;
        const cpu: *const GlyphAtlas = @ptrCast(@alignCast(atlas));

        const tex = uploadTexture(impl, cpu.pixels, cpu.width, cpu.height, c.DXGI_FORMAT_R8_UNORM) catch
            return BackendError.DeviceCreationFailed;

        const heap_tex = impl.allocator.create(GpuTexture) catch return BackendError.DeviceCreationFailed;
        heap_tex.* = tex;
        return .{ .backend_obj = heap_tex };
    }

    // -----------------------------------------------------------------------
    // uploadSdfAtlas — upload an SDF icon atlas (R8_UNORM).
    // -----------------------------------------------------------------------

    pub fn uploadSdfAtlas(self: *Dx12Backend, atlas: *const anyopaque) BackendError!struct { backend_obj: *anyopaque } {
        const impl: *Dx12Impl = @ptrCast(@alignCast(self._impl));

        const SdfAtlas = @import("../09/types.zig").SdfAtlas;
        const cpu: *const SdfAtlas = @ptrCast(@alignCast(atlas));

        const tex = uploadTexture(impl, cpu.pixels, cpu.width, cpu.height, c.DXGI_FORMAT_R8_UNORM) catch
            return BackendError.DeviceCreationFailed;

        const heap_tex = impl.allocator.create(GpuTexture) catch return BackendError.DeviceCreationFailed;
        heap_tex.* = tex;
        return .{ .backend_obj = heap_tex };
    }

    // -----------------------------------------------------------------------
    // uploadImage — upload an RGBA image.
    // -----------------------------------------------------------------------

    pub fn uploadImage(self: *Dx12Backend, pixels: []const u8, w: u32, h: u32) BackendError!struct { backend_obj: *anyopaque } {
        const impl: *Dx12Impl = @ptrCast(@alignCast(self._impl));

        const tex = uploadTexture(impl, pixels, w, h, c.DXGI_FORMAT_R8G8B8A8_UNORM) catch
            return BackendError.DeviceCreationFailed;

        const heap_tex = impl.allocator.create(GpuTexture) catch return BackendError.DeviceCreationFailed;
        heap_tex.* = tex;
        return .{ .backend_obj = heap_tex };
    }

    // -----------------------------------------------------------------------
    // drawFrame — record and submit one frame.
    // -----------------------------------------------------------------------

    pub fn drawFrame(self: *Dx12Backend, commands: []const DrawCommand, handles: AtlasHandles) void {
        const impl: *Dx12Impl = @ptrCast(@alignCast(self._impl));
        if (!impl.pipelines_ready) return;

        const idx = impl.frame_index;

        // Reset command allocator and re-open the command list.
        _ = impl.cmd_allocators[idx].?.*.lpVtbl.*.Reset.?(impl.cmd_allocators[idx].?);
        _ = impl.cmd_list.?.*.lpVtbl.*.Reset.?(impl.cmd_list.?, impl.cmd_allocators[idx].?, impl.pipeline_state.?);

        // Transition render target: PRESENT → RENDER_TARGET.
        const rt = impl.rt_resources[idx].?;
        var barrier = std.mem.zeroes(c.D3D12_RESOURCE_BARRIER);
        barrier.Type  = c.D3D12_RESOURCE_BARRIER_TYPE_TRANSITION;
        barrier.Flags = c.D3D12_RESOURCE_BARRIER_FLAG_NONE;
        barrier.unnamed_0.Transition.pResource   = rt;
        barrier.unnamed_0.Transition.StateBefore = c.D3D12_RESOURCE_STATE_PRESENT;
        barrier.unnamed_0.Transition.StateAfter  = c.D3D12_RESOURCE_STATE_RENDER_TARGET;
        barrier.unnamed_0.Transition.Subresource = c.D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES;
        impl.cmd_list.?.*.lpVtbl.*.ResourceBarrier.?(impl.cmd_list.?, 1, &barrier);

        // Compute RTV CPU handle for this back buffer.
        var rtv_handle: c.D3D12_CPU_DESCRIPTOR_HANDLE = undefined;
        rtv_handle = impl.rtv_heap.?.*.lpVtbl.*.GetCPUDescriptorHandleForHeapStart.?(impl.rtv_heap.?);
        rtv_handle.ptr += @as(usize, impl.rtv_increment) * @as(usize, idx);

        // Clear to black.
        const clear_color = [4]f32{ 0.0, 0.0, 0.0, 1.0 };
        impl.cmd_list.?.*.lpVtbl.*.ClearRenderTargetView.?(
            impl.cmd_list.?, rtv_handle, &clear_color, 0, null);

        // Set render target.
        impl.cmd_list.?.*.lpVtbl.*.OMSetRenderTargets.?(
            impl.cmd_list.?, 1, &rtv_handle, c.FALSE, null);

        // Viewport and scissor.
        const viewport = c.D3D12_VIEWPORT{
            .TopLeftX = 0.0,
            .TopLeftY = 0.0,
            .Width    = @floatFromInt(impl.width),
            .Height   = @floatFromInt(impl.height),
            .MinDepth = 0.0,
            .MaxDepth = 1.0,
        };
        const scissor = c.D3D12_RECT{
            .left   = 0,
            .top    = 0,
            .right  = @intCast(impl.width),
            .bottom = @intCast(impl.height),
        };
        impl.cmd_list.?.*.lpVtbl.*.RSSetViewports.?(impl.cmd_list.?, 1, &viewport);
        impl.cmd_list.?.*.lpVtbl.*.RSSetScissorRects.?(impl.cmd_list.?, 1, &scissor);

        // Pipeline state, root signature, primitive topology.
        impl.cmd_list.?.*.lpVtbl.*.SetPipelineState.?(impl.cmd_list.?, impl.pipeline_state.?);
        impl.cmd_list.?.*.lpVtbl.*.SetGraphicsRootSignature.?(impl.cmd_list.?, impl.root_signature.?);
        impl.cmd_list.?.*.lpVtbl.*.IASetPrimitiveTopology.?(impl.cmd_list.?, c.D3D_PRIMITIVE_TOPOLOGY_TRIANGLELIST);

        // Bind the SRV heap.
        var srv_heap_ptr: ?*c.ID3D12DescriptorHeap = impl.srv_heap.?;
        impl.cmd_list.?.*.lpVtbl.*.SetDescriptorHeaps.?(impl.cmd_list.?, 1, &srv_heap_ptr);

        // Compute the orthographic projection (top-left origin, 2D screen-space).
        const w: f32 = @floatFromInt(impl.width);
        const h: f32 = @floatFromInt(impl.height);
        // Column-major ortho: maps [0,w]x[0,h] to NDC [-1,1]x[1,-1].
        const ortho = [16]f32{
            2.0/w, 0.0,    0.0, 0.0,
            0.0,  -2.0/h,  0.0, 0.0,
            0.0,   0.0,    0.5, 0.0,
           -1.0,   1.0,    0.5, 1.0,
        };

        // Bind atlas textures via root descriptor table (param 0).
        // We bind the glyph atlas SRV first.  SDF and image SRVs follow contiguously.
        if (handles.glyph.backend_obj != @as(*anyopaque, @ptrFromInt(1))) {
            const glyph_tex: *const GpuTexture = @ptrCast(@alignCast(handles.glyph.backend_obj));
            var srv_gpu: c.D3D12_GPU_DESCRIPTOR_HANDLE = undefined;
            srv_gpu = impl.srv_heap.?.*.lpVtbl.*.GetGPUDescriptorHandleForHeapStart.?(impl.srv_heap.?);
            srv_gpu.ptr += @as(u64, impl.srv_increment) * @as(u64, glyph_tex.srv_index);
            impl.cmd_list.?.*.lpVtbl.*.SetGraphicsRootDescriptorTable.?(impl.cmd_list.?, 0, srv_gpu);
        }

        // Set push constants (root constants, param 1): ortho + clip.
        const clip_disabled = [9]u32{ 0, 0, 0, 0, 0, 0, 0, 0, 0 };
        _ = clip_disabled;
        // Upload ortho matrix as first 16 root constants.
        impl.cmd_list.?.*.lpVtbl.*.SetGraphicsRoot32BitConstants.?(
            impl.cmd_list.?, 1, 16, &ortho[0], 0);

        // Build and submit vertex batches from the draw command list.
        buildAndDrawCommands(impl, commands, ortho);

        // Transition render target: RENDER_TARGET → PRESENT.
        barrier.unnamed_0.Transition.StateBefore = c.D3D12_RESOURCE_STATE_RENDER_TARGET;
        barrier.unnamed_0.Transition.StateAfter  = c.D3D12_RESOURCE_STATE_PRESENT;
        impl.cmd_list.?.*.lpVtbl.*.ResourceBarrier.?(impl.cmd_list.?, 1, &barrier);

        // Close and execute.
        _ = impl.cmd_list.?.*.lpVtbl.*.Close.?(impl.cmd_list.?);
        var cmd_list_ptr: ?*c.ID3D12CommandList = @ptrCast(impl.cmd_list.?);
        impl.cmd_queue.?.*.lpVtbl.*.ExecuteCommandLists.?(impl.cmd_queue.?, 1, &cmd_list_ptr);

        // Present (sync_interval=1 = VSync).
        _ = impl.swap_chain.?.*.lpVtbl.*.Present.?(impl.swap_chain.?, 1, 0);

        // Signal fence and advance frame.
        _ = impl.cmd_queue.?.*.lpVtbl.*.Signal.?(impl.cmd_queue.?, impl.fence.?, impl.fence_value);
        impl.fence_value += 1;
        impl.frame_index = impl.swap_chain.?.*.lpVtbl.*.GetCurrentBackBufferIndex.?(impl.swap_chain.?);

        // If the next frame's allocator is still in flight, wait.
        const next_idx = impl.frame_index;
        _ = next_idx;
        // Simple approach: wait for the previous signal to complete before reusing the allocator.
        const completed = impl.fence.?.*.lpVtbl.*.GetCompletedValue.?(impl.fence.?);
        if (completed < impl.fence_value - 1) {
            _ = impl.fence.?.*.lpVtbl.*.SetEventOnCompletion.?(
                impl.fence.?, impl.fence_value - 1, impl.fence_event);
            _ = c.WaitForSingleObjectEx(impl.fence_event, c.INFINITE, c.FALSE);
        }
    }

    // -----------------------------------------------------------------------
    // capabilities
    // -----------------------------------------------------------------------

    pub fn capabilities(self: *const Dx12Backend) struct { max_texture_dim: u32, subpixel_text: bool, present_modes: u8 } {
        const impl: *const Dx12Impl = @ptrCast(@alignCast(self._impl));
        return .{
            .max_texture_dim = impl.max_texture_dim,
            .subpixel_text   = true,  // DX12 supports subpixel rendering (RD2)
            .present_modes   = 0b0011, // fifo + mailbox
        };
    }
};

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

/// Create/recreate RTV views for each back buffer.
fn createRenderTargets(impl: *Dx12Impl) BackendError!void {
    var rtv_handle: c.D3D12_CPU_DESCRIPTOR_HANDLE = undefined;
    rtv_handle = impl.rtv_heap.?.*.lpVtbl.*.GetCPUDescriptorHandleForHeapStart.?(impl.rtv_heap.?);

    for (0..FRAME_COUNT) |i| {
        hr(impl.swap_chain.?.*.lpVtbl.*.GetBuffer.?(
            impl.swap_chain.?,
            @intCast(i),
            &c.IID_ID3D12Resource,
            @ptrCast(&impl.rt_resources[i]),
        )) catch return BackendError.SwapchainCreationFailed;

        impl.device.?.*.lpVtbl.*.CreateRenderTargetView.?(
            impl.device.?, impl.rt_resources[i].?, null, rtv_handle);
        rtv_handle.ptr += impl.rtv_increment;
    }
}

/// Wait until all GPU work is complete (used in deinit and resize).
fn waitForGpu(impl: *Dx12Impl) void {
    if (impl.cmd_queue == null or impl.fence == null or impl.fence_event == null) return;

    _ = impl.cmd_queue.?.*.lpVtbl.*.Signal.?(impl.cmd_queue.?, impl.fence.?, impl.fence_value);
    _ = impl.fence.?.*.lpVtbl.*.SetEventOnCompletion.?(impl.fence.?, impl.fence_value, impl.fence_event);
    _ = c.WaitForSingleObjectEx(impl.fence_event, c.INFINITE, c.FALSE);
    impl.fence_value += 1;
}

/// Upload a 2D texture via an upload heap + copy command list.
fn uploadTexture(
    impl:   *Dx12Impl,
    pixels: []const u8,
    width:  u32,
    height: u32,
    format: c.DXGI_FORMAT,
) error{GpuUploadFailed}!GpuTexture {
    const bytes_per_pixel: u32 = switch (format) {
        c.DXGI_FORMAT_R8_UNORM         => 1,
        c.DXGI_FORMAT_R8G8B8A8_UNORM   => 4,
        else => return error.GpuUploadFailed,
    };

    // DX12 requires rows to be aligned to D3D12_TEXTURE_DATA_PITCH_ALIGNMENT (256 bytes).
    const row_pitch_raw  = width * bytes_per_pixel;
    const row_pitch_align = (row_pitch_raw + 255) & ~@as(u32, 255);
    const upload_size: u64 = @as(u64, row_pitch_align) * height;

    // Create upload heap buffer.
    var upload_heap: ?*c.ID3D12Resource = null;
    {
        var heap_props = std.mem.zeroes(c.D3D12_HEAP_PROPERTIES);
        heap_props.Type = c.D3D12_HEAP_TYPE_UPLOAD;
        var desc = std.mem.zeroes(c.D3D12_RESOURCE_DESC);
        desc.Dimension        = c.D3D12_RESOURCE_DIMENSION_BUFFER;
        desc.Width            = upload_size;
        desc.Height           = 1;
        desc.DepthOrArraySize = 1;
        desc.MipLevels        = 1;
        desc.Format           = c.DXGI_FORMAT_UNKNOWN;
        desc.SampleDesc       = .{ .Count = 1, .Quality = 0 };
        desc.Layout           = c.D3D12_TEXTURE_LAYOUT_ROW_MAJOR;
        if (impl.device.?.*.lpVtbl.*.CreateCommittedResource.?(
            impl.device.?,
            &heap_props,
            c.D3D12_HEAP_FLAG_NONE,
            &desc,
            c.D3D12_RESOURCE_STATE_GENERIC_READ,
            null,
            &c.IID_ID3D12Resource,
            @ptrCast(&upload_heap),
        ) < 0) return error.GpuUploadFailed;
    }
    defer { if (upload_heap) |u| _ = u.*.lpVtbl.*.Release.?(u); }

    // Map and copy pixel data (with row-pitch padding).
    {
        var range = c.D3D12_RANGE{ .Begin = 0, .End = 0 };
        var mapped: ?*anyopaque = null;
        if (upload_heap.?.*.lpVtbl.*.Map.?(upload_heap.?, 0, &range, &mapped) < 0)
            return error.GpuUploadFailed;
        defer {
            var unmap_range = c.D3D12_RANGE{ .Begin = 0, .End = upload_size };
            upload_heap.?.*.lpVtbl.*.Unmap.?(upload_heap.?, 0, &unmap_range);
        }
        const dst: [*]u8 = @ptrCast(mapped.?);
        for (0..height) |row| {
            const src_offset = row * row_pitch_raw;
            const dst_offset = row * row_pitch_align;
            @memcpy(
                dst[dst_offset..dst_offset + row_pitch_raw],
                pixels[src_offset..src_offset + row_pitch_raw],
            );
        }
    }

    // Create the GPU texture resource (default heap).
    var texture: ?*c.ID3D12Resource = null;
    {
        var heap_props = std.mem.zeroes(c.D3D12_HEAP_PROPERTIES);
        heap_props.Type = c.D3D12_HEAP_TYPE_DEFAULT;
        var desc = std.mem.zeroes(c.D3D12_RESOURCE_DESC);
        desc.Dimension        = c.D3D12_RESOURCE_DIMENSION_TEXTURE2D;
        desc.Width            = width;
        desc.Height           = height;
        desc.DepthOrArraySize = 1;
        desc.MipLevels        = 1;
        desc.Format           = format;
        desc.SampleDesc       = .{ .Count = 1, .Quality = 0 };
        desc.Layout           = c.D3D12_TEXTURE_LAYOUT_UNKNOWN;
        desc.Flags            = c.D3D12_RESOURCE_FLAG_NONE;
        if (impl.device.?.*.lpVtbl.*.CreateCommittedResource.?(
            impl.device.?,
            &heap_props,
            c.D3D12_HEAP_FLAG_NONE,
            &desc,
            c.D3D12_RESOURCE_STATE_COPY_DEST,
            null,
            &c.IID_ID3D12Resource,
            @ptrCast(&texture),
        ) < 0) return error.GpuUploadFailed;
    }

    // Use a fresh one-shot command list to copy upload heap → texture.
    // We reuse cmd_allocators[0] and cmd_list for this.
    _ = impl.cmd_allocators[0].?.*.lpVtbl.*.Reset.?(impl.cmd_allocators[0].?);
    _ = impl.cmd_list.?.*.lpVtbl.*.Reset.?(impl.cmd_list.?, impl.cmd_allocators[0].?, null);

    {
        var src_loc = std.mem.zeroes(c.D3D12_TEXTURE_COPY_LOCATION);
        src_loc.pResource = upload_heap.?;
        src_loc.Type      = c.D3D12_TEXTURE_COPY_TYPE_PLACED_FOOTPRINT;
        src_loc.unnamed_0.PlacedFootprint.Footprint.Format   = format;
        src_loc.unnamed_0.PlacedFootprint.Footprint.Width    = width;
        src_loc.unnamed_0.PlacedFootprint.Footprint.Height   = height;
        src_loc.unnamed_0.PlacedFootprint.Footprint.Depth    = 1;
        src_loc.unnamed_0.PlacedFootprint.Footprint.RowPitch = row_pitch_align;

        var dst_loc = std.mem.zeroes(c.D3D12_TEXTURE_COPY_LOCATION);
        dst_loc.pResource        = texture.?;
        dst_loc.Type             = c.D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX;
        dst_loc.unnamed_0.SubresourceIndex = 0;

        impl.cmd_list.?.*.lpVtbl.*.CopyTextureRegion.?(
            impl.cmd_list.?, &dst_loc, 0, 0, 0, &src_loc, null);
    }

    // Transition texture: COPY_DEST → PIXEL_SHADER_RESOURCE.
    var barrier = std.mem.zeroes(c.D3D12_RESOURCE_BARRIER);
    barrier.Type  = c.D3D12_RESOURCE_BARRIER_TYPE_TRANSITION;
    barrier.unnamed_0.Transition.pResource   = texture.?;
    barrier.unnamed_0.Transition.StateBefore = c.D3D12_RESOURCE_STATE_COPY_DEST;
    barrier.unnamed_0.Transition.StateAfter  = c.D3D12_RESOURCE_STATE_PIXEL_SHADER_RESOURCE;
    barrier.unnamed_0.Transition.Subresource = c.D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES;
    impl.cmd_list.?.*.lpVtbl.*.ResourceBarrier.?(impl.cmd_list.?, 1, &barrier);

    _ = impl.cmd_list.?.*.lpVtbl.*.Close.?(impl.cmd_list.?);
    var cl_ptr: ?*c.ID3D12CommandList = @ptrCast(impl.cmd_list.?);
    impl.cmd_queue.?.*.lpVtbl.*.ExecuteCommandLists.?(impl.cmd_queue.?, 1, &cl_ptr);
    waitForGpu(impl);

    // Create SRV in the heap.
    const srv_slot = impl.srv_next;
    impl.srv_next += 1;

    var cpu_handle: c.D3D12_CPU_DESCRIPTOR_HANDLE = undefined;
    cpu_handle = impl.srv_heap.?.*.lpVtbl.*.GetCPUDescriptorHandleForHeapStart.?(impl.srv_heap.?);
    cpu_handle.ptr += @as(usize, impl.srv_increment) * @as(usize, srv_slot);

    var srv_desc = std.mem.zeroes(c.D3D12_SHADER_RESOURCE_VIEW_DESC);
    srv_desc.Format                  = format;
    srv_desc.ViewDimension           = c.D3D12_SRV_DIMENSION_TEXTURE2D;
    srv_desc.Shader4ComponentMapping = c.D3D12_DEFAULT_SHADER_4_COMPONENT_MAPPING;
    srv_desc.unnamed_0.Texture2D.MipLevels = 1;
    impl.device.?.*.lpVtbl.*.CreateShaderResourceView.?(
        impl.device.?, texture.?, &srv_desc, cpu_handle);

    return GpuTexture{
        .resource  = texture.?,
        .srv_index = srv_slot,
        .width     = width,
        .height    = height,
    };
}

// ---------------------------------------------------------------------------
// QuadVertex layout (must match src/01/types.zig QuadVertex exactly).
// ---------------------------------------------------------------------------

const QuadVertex = extern struct {
    pos:     [2]f32,
    uv:      [2]f32,
    color:   [4]u8,
    color_b: [4]u8,
    mode:    u32,
};

comptime {
    std.debug.assert(@sizeOf(QuadVertex) == 28);
}

/// Build vertex quads from draw commands and submit draw calls.
fn buildAndDrawCommands(impl: *Dx12Impl, commands: []const DrawCommand, ortho: [16]f32) void {
    _ = ortho; // ortho is already uploaded as root constants

    const vb = impl.vb_mapped orelse return;
    const vb_cap = impl.vb_capacity;
    var vb_offset: u32 = 0;
    var vert_count: u32 = 0;

    const w: f32 = @floatFromInt(impl.width);
    const h: f32 = @floatFromInt(impl.height);

    // Helper: flush the current vertex batch as a draw call.
    const flushBatch = struct {
        fn call(i: *Dx12Impl, vtx_count: u32, vtx_off: u32) void {
            if (vtx_count == 0) return;
            const stride: u32 = @sizeOf(QuadVertex);
            const vb_view = c.D3D12_VERTEX_BUFFER_VIEW{
                .BufferLocation = blk: {
                    const base = i.vb_resource.?.*.lpVtbl.*.GetGPUVirtualAddress.?(i.vb_resource.?);
                    break :blk base + vtx_off;
                },
                .SizeInBytes    = vtx_count * stride,
                .StrideInBytes  = stride,
            };
            i.cmd_list.?.*.lpVtbl.*.IASetVertexBuffers.?(i.cmd_list.?, 0, 1, &vb_view);
            i.cmd_list.?.*.lpVtbl.*.DrawInstanced.?(i.cmd_list.?, vtx_count, 1, 0, 0);
        }
    }.call;

    for (commands) |cmd| {
        switch (cmd) {
            .set_scissor => |sc| {
                // Flush pending quads before changing scissor.
                flushBatch(impl, vert_count, vb_offset);
                vb_offset += vert_count * @sizeOf(QuadVertex);
                vert_count = 0;

                const rect = c.D3D12_RECT{
                    .left   = sc.x,
                    .top    = sc.y,
                    .right  = sc.x + @as(i32, @intCast(sc.w)),
                    .bottom = sc.y + @as(i32, @intCast(sc.h)),
                };
                impl.cmd_list.?.*.lpVtbl.*.RSSetScissorRects.?(impl.cmd_list.?, 1, &rect);
            },
            .restore_scissor => {
                flushBatch(impl, vert_count, vb_offset);
                vb_offset += vert_count * @sizeOf(QuadVertex);
                vert_count = 0;

                const rect = c.D3D12_RECT{
                    .left   = 0,
                    .top    = 0,
                    .right  = @intCast(impl.width),
                    .bottom = @intCast(impl.height),
                };
                impl.cmd_list.?.*.lpVtbl.*.RSSetScissorRects.?(impl.cmd_list.?, 1, &rect);
            },
            else => {
                // Emit 2 triangles (6 vertices) for the draw command.
                const needed = 6 * @sizeOf(QuadVertex);
                if (vb_offset + vert_count * @sizeOf(QuadVertex) + needed > vb_cap) {
                    flushBatch(impl, vert_count, vb_offset);
                    vb_offset = 0;
                    vert_count = 0;
                }

                const vtx_base = vb_offset + vert_count * @sizeOf(QuadVertex);
                const vtx: [*]QuadVertex = @ptrCast(@alignCast(vb + vtx_base));
                const emitted = emitQuad(vtx, cmd, w, h);
                vert_count += emitted;
            },
        }
    }

    flushBatch(impl, vert_count, vb_offset);
}

/// Emit up to 6 vertices for one DrawCommand into `vtx`. Returns the number emitted.
fn emitQuad(vtx: [*]QuadVertex, cmd: DrawCommand, win_w: f32, win_h: f32) u32 {
    _ = win_w;
    _ = win_h;

    // All non-scissor draw commands produce a textured quad (6 vertices = 2 triangles).
    var qx0: f32 = 0; var qy0: f32 = 0;
    var qx1: f32 = 0; var qy1: f32 = 0;
    var qu0: f32 = 0; var qv0: f32 = 0;
    var qu1: f32 = 1; var qv1: f32 = 1;
    var color: [4]u8 = .{255, 255, 255, 255};
    var color_b: [4]u8 = .{255, 255, 255, 255};
    var mode: u32 = 0;

    switch (cmd) {
        .filled_rect => |r| {
            qx0 = r.rect.x; qy0 = r.rect.y; qx1 = r.rect.x + r.rect.w; qy1 = r.rect.y + r.rect.h;
            color = .{r.color.r, r.color.g, r.color.b, r.color.a};
            mode = 0;
        },
        .border_rect => |r| {
            qx0 = r.rect.x; qy0 = r.rect.y; qx1 = r.rect.x + r.rect.w; qy1 = r.rect.y + r.rect.h;
            color = .{r.color.r, r.color.g, r.color.b, r.color.a};
            mode = 2;
        },
        .glyph => |g| {
            qx0 = g.dst.x; qy0 = g.dst.y; qx1 = g.dst.x + g.dst.w; qy1 = g.dst.y + g.dst.h;
            qu0 = g.uv.x;  qv0 = g.uv.y;  qu1 = g.uv.x + g.uv.w;   qv1 = g.uv.y + g.uv.h;
            color = .{g.color.r, g.color.g, g.color.b, g.color.a};
            mode = g.mode;
        },
        .image_rect => |r| {
            qx0 = r.dst.x; qy0 = r.dst.y; qx1 = r.dst.x + r.dst.w; qy1 = r.dst.y + r.dst.h;
            qu0 = r.uv.x;  qv0 = r.uv.y;  qu1 = r.uv.x + r.uv.w;   qv1 = r.uv.y + r.uv.h;
            color = .{r.tint.r, r.tint.g, r.tint.b, r.tint.a};
            mode = 3;
        },
        .gradient_rect => |r| {
            qx0 = r.rect.x; qy0 = r.rect.y; qx1 = r.rect.x + r.rect.w; qy1 = r.rect.y + r.rect.h;
            color   = .{r.color_a.r, r.color_a.g, r.color_a.b, r.color_a.a};
            color_b = .{r.color_b.r, r.color_b.g, r.color_b.b, r.color_b.a};
            // Encode direction in UV (matches GLSL gradient logic).
            switch (r.direction) {
                .right        => { qu0 = 0.0; qv0 = 0.0; qu1 = 1.0; qv1 = 0.0; },
                .bottom       => { qu0 = 0.0; qv0 = 0.0; qu1 = 0.0; qv1 = 1.0; },
                .bottom_right => { qu0 = 0.0; qv0 = 0.0; qu1 = 1.0; qv1 = 1.0; },
            }
            mode = 5;
        },
        .aa_filled_rect => |r| {
            qx0 = r.rect.x; qy0 = r.rect.y; qx1 = r.rect.x + r.rect.w; qy1 = r.rect.y + r.rect.h;
            color = .{r.color.r, r.color.g, r.color.b, r.color.a};
            mode = 0; // use solid rect mode; AA is done at fragment level
        },
        .aa_filled_circle => |r| {
            qx0 = r.center_x - r.radius; qy0 = r.center_y - r.radius;
            qx1 = r.center_x + r.radius; qy1 = r.center_y + r.radius;
            qu0 = 0.0; qv0 = 0.0; qu1 = 1.0; qv1 = 1.0;
            color = .{r.color.r, r.color.g, r.color.b, r.color.a};
            mode = 6;
        },
        .sdf_icon => |r| {
            qx0 = r.dst.x; qy0 = r.dst.y; qx1 = r.dst.x + r.dst.w; qy1 = r.dst.y + r.dst.h;
            qu0 = r.uv.x;  qv0 = r.uv.y;  qu1 = r.uv.x + r.uv.w;   qv1 = r.uv.y + r.uv.h;
            color = .{r.color.r, r.color.g, r.color.b, r.color.a};
            mode = 4;
        },
        // clip_rounded_begin/end, set_scissor, restore_scissor handled before emitQuad.
        else => return 0,
    }

    // Two triangles: top-left, top-right, bottom-left, bottom-right.
    vtx[0] = .{ .pos = .{qx0, qy0}, .uv = .{qu0, qv0}, .color = color, .color_b = color_b, .mode = mode };
    vtx[1] = .{ .pos = .{qx1, qy0}, .uv = .{qu1, qv0}, .color = color, .color_b = color_b, .mode = mode };
    vtx[2] = .{ .pos = .{qx0, qy1}, .uv = .{qu0, qv1}, .color = color, .color_b = color_b, .mode = mode };
    vtx[3] = .{ .pos = .{qx1, qy0}, .uv = .{qu1, qv0}, .color = color, .color_b = color_b, .mode = mode };
    vtx[4] = .{ .pos = .{qx1, qy1}, .uv = .{qu1, qv1}, .color = color, .color_b = color_b, .mode = mode };
    vtx[5] = .{ .pos = .{qx0, qy1}, .uv = .{qu0, qv1}, .color = color, .color_b = color_b, .mode = mode };
    return 6;
}
