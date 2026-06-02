//! 01 — Platform spike — types.zig (implementation)
//!
//! Contract (INV-5.1): public method signatures match docs/specs/01.types.zig exactly.
//! Internal field layout of Platform and VulkanBackend is implementation-defined.
//! Depends only on std, GLFW, and the Vulkan loader (INV-5.6).

const std = @import("std");
const builtin = @import("builtin");
const shaders = @import("embedded_shaders");

const c = @cImport({
    @cDefine("GLFW_INCLUDE_VULKAN", "1");
    @cInclude("GLFW/glfw3.h");
});

const enable_validation = (builtin.mode == .Debug);

// ---------------------------------------------------------------------------
// Public types — MUST match docs/specs/01.types.zig byte-for-byte (INV-5.1).
// ---------------------------------------------------------------------------

/// Pixel dimensions of the framebuffer / window. Distinct from module 03's layout `Size`.
pub const Extent2D = struct { width: u32, height: u32 };

/// Linear RGBA in 0..1. Used only for the spike's clear color.
pub const Color = struct { r: f32, g: f32, b: f32, a: f32 = 1.0 };

pub const WindowOptions = struct {
    title: [:0]const u8 = "spike",
    width: u32 = 960,
    height: u32 = 600,
};

pub const PlatformError = error{
    GlfwInitFailed,
    VulkanUnavailable,
    WindowCreationFailed,
    SurfaceCreationFailed,
};

pub const BackendError = error{
    NoSuitableDevice,
    InstanceCreationFailed,
    DeviceCreationFailed,
    SwapchainCreationFailed,
    ShaderLoadFailed,
};

// ---------------------------------------------------------------------------
// Internal implementation types (not part of the contract).
// ---------------------------------------------------------------------------

const PlatformImpl = struct {
    window: *c.GLFWwindow,
    allocator: std.mem.Allocator,
};

const VulkanImpl = struct {
    allocator: std.mem.Allocator,
    platform: *Platform,
    instance: c.VkInstance,
    debug_messenger: c.VkDebugUtilsMessengerEXT,
    surface: c.VkSurfaceKHR,
    physical_device: c.VkPhysicalDevice,
    device: c.VkDevice,
    graphics_queue: c.VkQueue,
    present_queue: c.VkQueue,
    graphics_family: u32,
    present_family: u32,
    swapchain: c.VkSwapchainKHR,
    swapchain_images: []c.VkImage,
    swapchain_image_views: []c.VkImageView,
    swapchain_format: c.VkFormat,
    swapchain_extent: c.VkExtent2D,
    render_pass: c.VkRenderPass,
    framebuffers: []c.VkFramebuffer,
    command_pool: c.VkCommandPool,
    command_buffer: c.VkCommandBuffer,
    image_available_sem: c.VkSemaphore,
    render_finished_sems: []c.VkSemaphore,
    in_flight_fence: c.VkFence,
    pipeline_layout: c.VkPipelineLayout,
    pipeline: c.VkPipeline,
    current_image_index: u32,
    validation_issue_count: u32,

    // Module 09 quad pipeline (null until initQuadPipeline is called).
    quad_pipeline_layout: c.VkPipelineLayout = null,
    quad_pipeline: c.VkPipeline = null,
    quad_desc_set_layout: c.VkDescriptorSetLayout = null,
    quad_desc_pool: c.VkDescriptorPool = null,
    quad_desc_set: c.VkDescriptorSet = null,
    quad_vertex_buf: c.VkBuffer = null,
    quad_vertex_mem: c.VkDeviceMemory = null,
    quad_pipeline_ready: bool = false,
    render_pass_active: bool = false,
};

// ---------------------------------------------------------------------------
// Module 09 — Draw command vocabulary (defined here so VulkanBackend can use them
// without an upward import; src/09/types.zig re-exports these).
// ---------------------------------------------------------------------------

pub const Rect09 = struct { x: f32 = 0, y: f32 = 0, w: f32 = 0, h: f32 = 0 };
pub const Color09 = struct { r: u8, g: u8, b: u8, a: u8 = 255 };

pub const FilledRect = struct {
    rect: Rect09,
    color: Color09,
    radius: f32 = 0,
};

pub const BorderRect = struct {
    rect: Rect09,
    color: Color09,
    width: f32,
    radius: f32 = 0,
};

pub const GlyphCmd = struct {
    dst: Rect09,
    uv: Rect09,
    color: Color09,
};

pub const DrawCommand = union(enum) {
    filled_rect: FilledRect,
    border_rect: BorderRect,
    glyph: GlyphCmd,
};

pub const QuadVertex = struct {
    pos: [2]f32,
    uv: [2]f32,
    color: [4]u8,
    mode: u32,
};

/// GPU-side glyph atlas handle. upload() lives in src/09/types.zig (needs module 02).
/// deinit() lives here alongside the Vulkan destroy calls.
pub const GpuAtlas = struct {
    image: ?*anyopaque = null,
    image_view: ?*anyopaque = null,
    sampler: ?*anyopaque = null,
    memory: ?*anyopaque = null,
    width: u32 = 0,
    height: u32 = 0,

    pub fn deinit(self: *GpuAtlas, device: *anyopaque) void {
        const dev: c.VkDevice = @ptrCast(device);
        if (self.sampler) |s| c.vkDestroySampler(dev, @ptrCast(s), null);
        if (self.image_view) |v| c.vkDestroyImageView(dev, @ptrCast(v), null);
        if (self.image) |img| c.vkDestroyImage(dev, @ptrCast(img), null);
        if (self.memory) |mem| c.vkFreeMemory(dev, @ptrCast(mem), null);
        self.* = .{};
    }
};

/// Upload a raw grayscale bitmap to a VK_FORMAT_R8_UNORM GPU image.
/// Called by src/09/types.zig GpuAtlas.upload.
pub fn vkUploadAtlas(
    device: *anyopaque,
    phys_device: *anyopaque,
    cmd_pool: *anyopaque,
    queue: *anyopaque,
    pixels: []const u8,
    atlas_w: u32,
    atlas_h: u32,
) error{GpuUploadFailed}!GpuAtlas {
    const dev: c.VkDevice = @ptrCast(device);
    const phys: c.VkPhysicalDevice = @ptrCast(phys_device);
    const pool: c.VkCommandPool = @ptrCast(cmd_pool);
    const q: c.VkQueue = @ptrCast(queue);
    const img_size: c.VkDeviceSize = @as(u64, atlas_w) * atlas_h;

    // Staging buffer
    var stg_buf: c.VkBuffer = undefined;
    var stg_buf_info = std.mem.zeroes(c.VkBufferCreateInfo);
    stg_buf_info.sType = c.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO;
    stg_buf_info.size = img_size;
    stg_buf_info.usage = c.VK_BUFFER_USAGE_TRANSFER_SRC_BIT;
    stg_buf_info.sharingMode = c.VK_SHARING_MODE_EXCLUSIVE;
    if (c.vkCreateBuffer(dev, &stg_buf_info, null, &stg_buf) != c.VK_SUCCESS)
        return error.GpuUploadFailed;
    defer c.vkDestroyBuffer(dev, stg_buf, null);

    var stg_req: c.VkMemoryRequirements = undefined;
    c.vkGetBufferMemoryRequirements(dev, stg_buf, &stg_req);
    const stg_type = findMemTypeLocal(phys, stg_req.memoryTypeBits,
        c.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | c.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT)
        orelse return error.GpuUploadFailed;

    var stg_ma = std.mem.zeroes(c.VkMemoryAllocateInfo);
    stg_ma.sType = c.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
    stg_ma.allocationSize = stg_req.size;
    stg_ma.memoryTypeIndex = stg_type;
    var stg_mem: c.VkDeviceMemory = undefined;
    if (c.vkAllocateMemory(dev, &stg_ma, null, &stg_mem) != c.VK_SUCCESS)
        return error.GpuUploadFailed;
    defer c.vkFreeMemory(dev, stg_mem, null);
    _ = c.vkBindBufferMemory(dev, stg_buf, stg_mem, 0);

    var mapped: ?*anyopaque = null;
    _ = c.vkMapMemory(dev, stg_mem, 0, img_size, 0, &mapped);
    @memcpy(@as([*]u8, @ptrCast(mapped.?))[0..pixels.len], pixels);
    c.vkUnmapMemory(dev, stg_mem);

    // Create image
    var ii = std.mem.zeroes(c.VkImageCreateInfo);
    ii.sType = c.VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO;
    ii.imageType = c.VK_IMAGE_TYPE_2D;
    ii.format = c.VK_FORMAT_R8_UNORM;
    ii.extent = .{ .width = atlas_w, .height = atlas_h, .depth = 1 };
    ii.mipLevels = 1;
    ii.arrayLayers = 1;
    ii.samples = c.VK_SAMPLE_COUNT_1_BIT;
    ii.tiling = c.VK_IMAGE_TILING_OPTIMAL;
    ii.usage = c.VK_IMAGE_USAGE_TRANSFER_DST_BIT | c.VK_IMAGE_USAGE_SAMPLED_BIT;
    ii.initialLayout = c.VK_IMAGE_LAYOUT_UNDEFINED;
    ii.sharingMode = c.VK_SHARING_MODE_EXCLUSIVE;
    var img: c.VkImage = undefined;
    if (c.vkCreateImage(dev, &ii, null, &img) != c.VK_SUCCESS)
        return error.GpuUploadFailed;
    errdefer c.vkDestroyImage(dev, img, null);

    var ir: c.VkMemoryRequirements = undefined;
    c.vkGetImageMemoryRequirements(dev, img, &ir);
    const img_type = findMemTypeLocal(phys, ir.memoryTypeBits,
        c.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT) orelse return error.GpuUploadFailed;

    var ima = std.mem.zeroes(c.VkMemoryAllocateInfo);
    ima.sType = c.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
    ima.allocationSize = ir.size;
    ima.memoryTypeIndex = img_type;
    var img_mem: c.VkDeviceMemory = undefined;
    if (c.vkAllocateMemory(dev, &ima, null, &img_mem) != c.VK_SUCCESS)
        return error.GpuUploadFailed;
    errdefer c.vkFreeMemory(dev, img_mem, null);
    _ = c.vkBindImageMemory(dev, img, img_mem, 0);

    // One-shot command buffer
    var cba = std.mem.zeroes(c.VkCommandBufferAllocateInfo);
    cba.sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO;
    cba.commandPool = pool;
    cba.level = c.VK_COMMAND_BUFFER_LEVEL_PRIMARY;
    cba.commandBufferCount = 1;
    var cb: c.VkCommandBuffer = undefined;
    if (c.vkAllocateCommandBuffers(dev, &cba, &cb) != c.VK_SUCCESS)
        return error.GpuUploadFailed;
    defer c.vkFreeCommandBuffers(dev, pool, 1, &cb);

    var bi = std.mem.zeroes(c.VkCommandBufferBeginInfo);
    bi.sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;
    bi.flags = c.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;
    _ = c.vkBeginCommandBuffer(cb, &bi);

    atlasTransition(cb, img, c.VK_IMAGE_LAYOUT_UNDEFINED, c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL);

    var cp = std.mem.zeroes(c.VkBufferImageCopy);
    cp.imageSubresource.aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT;
    cp.imageSubresource.layerCount = 1;
    cp.imageExtent = .{ .width = atlas_w, .height = atlas_h, .depth = 1 };
    c.vkCmdCopyBufferToImage(cb, stg_buf, img, c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &cp);

    atlasTransition(cb, img, c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, c.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL);

    _ = c.vkEndCommandBuffer(cb);
    var si = std.mem.zeroes(c.VkSubmitInfo);
    si.sType = c.VK_STRUCTURE_TYPE_SUBMIT_INFO;
    si.commandBufferCount = 1;
    si.pCommandBuffers = &cb;
    _ = c.vkQueueSubmit(q, 1, &si, null);
    _ = c.vkQueueWaitIdle(q);

    // Image view
    var ivi = std.mem.zeroes(c.VkImageViewCreateInfo);
    ivi.sType = c.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO;
    ivi.image = img;
    ivi.viewType = c.VK_IMAGE_VIEW_TYPE_2D;
    ivi.format = c.VK_FORMAT_R8_UNORM;
    ivi.subresourceRange.aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT;
    ivi.subresourceRange.levelCount = 1;
    ivi.subresourceRange.layerCount = 1;
    var iv: c.VkImageView = undefined;
    if (c.vkCreateImageView(dev, &ivi, null, &iv) != c.VK_SUCCESS)
        return error.GpuUploadFailed;
    errdefer c.vkDestroyImageView(dev, iv, null);

    // Sampler
    var spi = std.mem.zeroes(c.VkSamplerCreateInfo);
    spi.sType = c.VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO;
    spi.magFilter = c.VK_FILTER_LINEAR;
    spi.minFilter = c.VK_FILTER_LINEAR;
    spi.addressModeU = c.VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE;
    spi.addressModeV = c.VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE;
    spi.addressModeW = c.VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE;
    spi.borderColor = c.VK_BORDER_COLOR_INT_OPAQUE_BLACK;
    var samp: c.VkSampler = undefined;
    if (c.vkCreateSampler(dev, &spi, null, &samp) != c.VK_SUCCESS)
        return error.GpuUploadFailed;

    return GpuAtlas{
        .image = @ptrCast(img.?),
        .image_view = @ptrCast(iv.?),
        .sampler = @ptrCast(samp.?),
        .memory = @ptrCast(img_mem.?),
    };
}

fn findMemTypeLocal(phys: c.VkPhysicalDevice, filter: u32, props: c.VkMemoryPropertyFlags) ?u32 {
    var mp: c.VkPhysicalDeviceMemoryProperties = undefined;
    c.vkGetPhysicalDeviceMemoryProperties(phys, &mp);
    var i: u32 = 0;
    while (i < mp.memoryTypeCount) : (i += 1) {
        if ((filter & (@as(u32, 1) << @intCast(i))) != 0 and
            (mp.memoryTypes[i].propertyFlags & props) == props) return i;
    }
    return null;
}

fn atlasTransition(cb: c.VkCommandBuffer, img: c.VkImage, old: c.VkImageLayout, new: c.VkImageLayout) void {
    var b = std.mem.zeroes(c.VkImageMemoryBarrier);
    b.sType = c.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER;
    b.oldLayout = old;
    b.newLayout = new;
    b.srcQueueFamilyIndex = c.VK_QUEUE_FAMILY_IGNORED;
    b.dstQueueFamilyIndex = c.VK_QUEUE_FAMILY_IGNORED;
    b.image = img;
    b.subresourceRange.aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT;
    b.subresourceRange.levelCount = 1;
    b.subresourceRange.layerCount = 1;
    var src_stage: c.VkPipelineStageFlags = undefined;
    var dst_stage: c.VkPipelineStageFlags = undefined;
    if (old == c.VK_IMAGE_LAYOUT_UNDEFINED) {
        b.srcAccessMask = 0;
        b.dstAccessMask = c.VK_ACCESS_TRANSFER_WRITE_BIT;
        src_stage = c.VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT;
        dst_stage = c.VK_PIPELINE_STAGE_TRANSFER_BIT;
    } else {
        b.srcAccessMask = c.VK_ACCESS_TRANSFER_WRITE_BIT;
        b.dstAccessMask = c.VK_ACCESS_SHADER_READ_BIT;
        src_stage = c.VK_PIPELINE_STAGE_TRANSFER_BIT;
        dst_stage = c.VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT;
    }
    c.vkCmdPipelineBarrier(cb, src_stage, dst_stage, 0, 0, null, 0, null, 1, &b);
}

// ---------------------------------------------------------------------------
// Vulkan validation debug callback.
// ---------------------------------------------------------------------------

fn debugCallback(
    message_severity: c.VkDebugUtilsMessageSeverityFlagBitsEXT,
    message_type: c.VkDebugUtilsMessageTypeFlagsEXT,
    p_callback_data: ?*const c.VkDebugUtilsMessengerCallbackDataEXT,
    p_user_data: ?*anyopaque,
) callconv(.c) c.VkBool32 {
    _ = message_type;
    if (message_severity >= c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT) {
        if (p_callback_data) |data| {
            std.debug.print("[VK validation] {s}\n", .{data.pMessage});
        }
        if (p_user_data) |ud| {
            const counter: *u32 = @ptrCast(@alignCast(ud));
            _ = @atomicRmw(u32, counter, .Add, 1, .monotonic);
        }
    }
    return c.VK_FALSE;
}

// ---------------------------------------------------------------------------
// Platform — GLFW-backed window + Vulkan surface + input (INV-2.2).
// ---------------------------------------------------------------------------

pub const Platform = struct {
    _impl: *anyopaque = undefined,

    pub fn init(gpa: std.mem.Allocator, opts: WindowOptions) PlatformError!Platform {
        if (c.glfwInit() == c.GLFW_FALSE) return PlatformError.GlfwInitFailed;
        errdefer c.glfwTerminate();

        if (c.glfwVulkanSupported() == c.GLFW_FALSE) return PlatformError.VulkanUnavailable;

        c.glfwWindowHint(c.GLFW_CLIENT_API, c.GLFW_NO_API);
        c.glfwWindowHint(c.GLFW_RESIZABLE, c.GLFW_TRUE);

        const window = c.glfwCreateWindow(
            @intCast(opts.width),
            @intCast(opts.height),
            opts.title.ptr,
            null,
            null,
        ) orelse return PlatformError.WindowCreationFailed;
        errdefer c.glfwDestroyWindow(window);

        const impl = gpa.create(PlatformImpl) catch return PlatformError.WindowCreationFailed;
        impl.* = .{ .window = window, .allocator = gpa };
        return Platform{ ._impl = impl };
    }

    pub fn deinit(self: *Platform) void {
        const impl: *PlatformImpl = @ptrCast(@alignCast(self._impl));
        c.glfwDestroyWindow(impl.window);
        c.glfwTerminate();
        impl.allocator.destroy(impl);
    }

    pub fn shouldClose(self: *Platform) bool {
        const impl: *PlatformImpl = @ptrCast(@alignCast(self._impl));
        return c.glfwWindowShouldClose(impl.window) != c.GLFW_FALSE;
    }

    pub fn pollEvents(self: *Platform) void {
        _ = self;
        c.glfwPollEvents();
    }

    pub fn framebufferSize(self: *Platform) Extent2D {
        const impl: *PlatformImpl = @ptrCast(@alignCast(self._impl));
        var w: c_int = 0;
        var h: c_int = 0;
        c.glfwGetFramebufferSize(impl.window, &w, &h);
        return .{ .width = @intCast(w), .height = @intCast(h) };
    }

    /// Vulkan instance extensions GLFW requires (returned as C strings).
    pub fn requiredInstanceExtensions(self: *Platform) []const [*:0]const u8 {
        _ = self;
        var count: u32 = 0;
        const ptr = c.glfwGetRequiredInstanceExtensions(&count);
        if (ptr == null or count == 0) return &.{};
        // [*c][*c]const u8 → [*]const [*:0]const u8 (same representation on all targets)
        return @as([*]const [*:0]const u8, @ptrCast(ptr))[0..count];
    }

    /// Create the window surface for an existing Vulkan instance.
    /// `instance` is VkInstance cast to *anyopaque; returned surface is VkSurfaceKHR cast
    /// to *anyopaque (both are pointer-sized handles on 64-bit — spec note 2).
    pub fn createSurface(self: *Platform, instance: *anyopaque) PlatformError!*anyopaque {
        const impl: *PlatformImpl = @ptrCast(@alignCast(self._impl));
        const vk_instance: c.VkInstance = @ptrCast(instance);
        var surface: c.VkSurfaceKHR = undefined;
        if (c.glfwCreateWindowSurface(vk_instance, impl.window, null, &surface) != c.VK_SUCCESS) {
            return PlatformError.SurfaceCreationFailed;
        }
        return @ptrCast(surface.?);
    }
};

// ---------------------------------------------------------------------------
// VulkanBackend — the only GPU backend (INV-2.1).
// ---------------------------------------------------------------------------

pub const VulkanBackend = struct {
    _impl: *anyopaque = undefined,

    pub fn init(gpa: std.mem.Allocator, platform: *Platform) BackendError!VulkanBackend {
        const impl = gpa.create(VulkanImpl) catch return BackendError.InstanceCreationFailed;
        impl.* = .{
            .allocator = gpa,
            .platform = platform,
            .instance = null,
            .debug_messenger = null,
            .surface = null,
            .physical_device = null,
            .device = null,
            .graphics_queue = null,
            .present_queue = null,
            .graphics_family = 0,
            .present_family = 0,
            .swapchain = null,
            .swapchain_images = &.{},
            .swapchain_image_views = &.{},
            .swapchain_format = 0,
            .swapchain_extent = .{ .width = 0, .height = 0 },
            .render_pass = null,
            .framebuffers = &.{},
            .command_pool = null,
            .command_buffer = null,
            .image_available_sem = null,
            .render_finished_sems = &.{},
            .in_flight_fence = null,
            .pipeline_layout = null,
            .pipeline = null,
            .current_image_index = 0,
            .validation_issue_count = 0,
            .render_pass_active = false,
        };

        errdefer gpa.destroy(impl);

        impl.instance = vkCreateInstance(gpa, platform) catch return BackendError.InstanceCreationFailed;
        errdefer c.vkDestroyInstance(impl.instance, null);

        if (enable_validation) {
            impl.debug_messenger = vkCreateDebugMessenger(impl.instance, &impl.validation_issue_count) catch
                return BackendError.InstanceCreationFailed;
        }
        errdefer if (enable_validation) vkDestroyDebugMessenger(impl.instance, impl.debug_messenger);

        const surface_opaque = platform.createSurface(@ptrCast(impl.instance.?)) catch
            return BackendError.InstanceCreationFailed;
        impl.surface = @ptrCast(surface_opaque);
        errdefer c.vkDestroySurfaceKHR(impl.instance, impl.surface, null);

        const pd = vkSelectPhysicalDevice(gpa, impl.instance, impl.surface) catch
            return BackendError.NoSuitableDevice;
        impl.physical_device = pd.physical_device;
        impl.graphics_family = pd.graphics_family;
        impl.present_family = pd.present_family;

        vkCreateLogicalDevice(impl) catch return BackendError.DeviceCreationFailed;
        errdefer c.vkDestroyDevice(impl.device, null);

        vkCreateSwapchain(impl) catch return BackendError.SwapchainCreationFailed;
        errdefer vkDestroySwapchainResources(impl);

        vkCreateRenderPass(impl) catch return BackendError.DeviceCreationFailed;
        errdefer c.vkDestroyRenderPass(impl.device, impl.render_pass, null);

        vkCreateFramebuffers(impl) catch return BackendError.SwapchainCreationFailed;
        errdefer vkDestroyFramebuffers(impl);

        vkCreateCommandPool(impl) catch return BackendError.DeviceCreationFailed;
        errdefer c.vkDestroyCommandPool(impl.device, impl.command_pool, null);

        vkCreateSyncObjects(impl) catch return BackendError.DeviceCreationFailed;
        errdefer vkDestroySyncObjects(impl);

        vkCreatePipeline(impl) catch return BackendError.ShaderLoadFailed;

        return VulkanBackend{ ._impl = impl };
    }

    pub fn deinit(self: *VulkanBackend) void {
        const impl: *VulkanImpl = @ptrCast(@alignCast(self._impl));
        _ = c.vkDeviceWaitIdle(impl.device);
        c.vkDestroyPipeline(impl.device, impl.pipeline, null);
        c.vkDestroyPipelineLayout(impl.device, impl.pipeline_layout, null);
        vkDestroySyncObjects(impl);
        c.vkDestroyCommandPool(impl.device, impl.command_pool, null);
        vkDestroyFramebuffers(impl);
        c.vkDestroyRenderPass(impl.device, impl.render_pass, null);
        vkDestroySwapchainResources(impl);
        c.vkDestroyDevice(impl.device, null);
        c.vkDestroySurfaceKHR(impl.instance, impl.surface, null);
        if (enable_validation) vkDestroyDebugMessenger(impl.instance, impl.debug_messenger);
        c.vkDestroyInstance(impl.instance, null);
        impl.allocator.destroy(impl);
    }

    pub fn beginFrame(self: *VulkanBackend) bool {
        const impl: *VulkanImpl = @ptrCast(@alignCast(self._impl));
        _ = c.vkWaitForFences(impl.device, 1, &impl.in_flight_fence, c.VK_TRUE, std.math.maxInt(u64));
        const result = c.vkAcquireNextImageKHR(
            impl.device,
            impl.swapchain,
            std.math.maxInt(u64),
            impl.image_available_sem,
            null,
            &impl.current_image_index,
        );
        if (result == c.VK_ERROR_OUT_OF_DATE_KHR) {
            vkRecreateSwapchain(impl) catch {};
            return false;
        }
        _ = c.vkResetFences(impl.device, 1, &impl.in_flight_fence);
        _ = c.vkResetCommandBuffer(impl.command_buffer, 0);
        var begin_info = std.mem.zeroes(c.VkCommandBufferBeginInfo);
        begin_info.sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;
        _ = c.vkBeginCommandBuffer(impl.command_buffer, &begin_info);
        return true;
    }

    pub fn clear(self: *VulkanBackend, color: Color) void {
        const impl: *VulkanImpl = @ptrCast(@alignCast(self._impl));
        var clear_color: c.VkClearColorValue = undefined;
        clear_color.float32 = [4]f32{ color.r, color.g, color.b, color.a };
        var clear_value: c.VkClearValue = undefined;
        clear_value.color = clear_color;
        var rp_begin = std.mem.zeroes(c.VkRenderPassBeginInfo);
        rp_begin.sType = c.VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO;
        rp_begin.renderPass = impl.render_pass;
        rp_begin.framebuffer = impl.framebuffers[impl.current_image_index];
        rp_begin.renderArea = .{ .offset = .{ .x = 0, .y = 0 }, .extent = impl.swapchain_extent };
        rp_begin.clearValueCount = 1;
        rp_begin.pClearValues = &clear_value;
        c.vkCmdBeginRenderPass(impl.command_buffer, &rp_begin, c.VK_SUBPASS_CONTENTS_INLINE);
        impl.render_pass_active = true;
    }

    pub fn drawTriangle(self: *VulkanBackend) void {
        const impl: *VulkanImpl = @ptrCast(@alignCast(self._impl));
        c.vkCmdBindPipeline(impl.command_buffer, c.VK_PIPELINE_BIND_POINT_GRAPHICS, impl.pipeline);
        const viewport = c.VkViewport{
            .x = 0.0,
            .y = 0.0,
            .width = @as(f32, @floatFromInt(impl.swapchain_extent.width)),
            .height = @as(f32, @floatFromInt(impl.swapchain_extent.height)),
            .minDepth = 0.0,
            .maxDepth = 1.0,
        };
        c.vkCmdSetViewport(impl.command_buffer, 0, 1, &viewport);
        const scissor = c.VkRect2D{
            .offset = .{ .x = 0, .y = 0 },
            .extent = impl.swapchain_extent,
        };
        c.vkCmdSetScissor(impl.command_buffer, 0, 1, &scissor);
        c.vkCmdDraw(impl.command_buffer, 3, 1, 0, 0);
    }

    pub fn endFrame(self: *VulkanBackend) void {
        const impl: *VulkanImpl = @ptrCast(@alignCast(self._impl));
        if (impl.render_pass_active) {
            c.vkCmdEndRenderPass(impl.command_buffer);
            impl.render_pass_active = false;
        }
        _ = c.vkEndCommandBuffer(impl.command_buffer);
        const wait_stage: c.VkPipelineStageFlags = c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
        var submit_info = std.mem.zeroes(c.VkSubmitInfo);
        submit_info.sType = c.VK_STRUCTURE_TYPE_SUBMIT_INFO;
        submit_info.waitSemaphoreCount = 1;
        submit_info.pWaitSemaphores = &impl.image_available_sem;
        submit_info.pWaitDstStageMask = &wait_stage;
        submit_info.commandBufferCount = 1;
        submit_info.pCommandBuffers = &impl.command_buffer;
        submit_info.signalSemaphoreCount = 1;
        submit_info.pSignalSemaphores = &impl.render_finished_sems[impl.current_image_index];
        _ = c.vkQueueSubmit(impl.graphics_queue, 1, &submit_info, impl.in_flight_fence);
        var present_info = std.mem.zeroes(c.VkPresentInfoKHR);
        present_info.sType = c.VK_STRUCTURE_TYPE_PRESENT_INFO_KHR;
        present_info.waitSemaphoreCount = 1;
        present_info.pWaitSemaphores = &impl.render_finished_sems[impl.current_image_index];
        present_info.swapchainCount = 1;
        present_info.pSwapchains = &impl.swapchain;
        present_info.pImageIndices = &impl.current_image_index;
        const present_result = c.vkQueuePresentKHR(impl.present_queue, &present_info);
        if (present_result == c.VK_ERROR_OUT_OF_DATE_KHR or present_result == c.VK_SUBOPTIMAL_KHR) {
            vkRecreateSwapchain(impl) catch {};
        }
    }

    pub fn onResize(self: *VulkanBackend, size: Extent2D) void {
        _ = size;
        const impl: *VulkanImpl = @ptrCast(@alignCast(self._impl));
        vkRecreateSwapchain(impl) catch {};
    }

    pub fn swapchainImageCount(self: *VulkanBackend) u32 {
        const impl: *VulkanImpl = @ptrCast(@alignCast(self._impl));
        return @intCast(impl.swapchain_images.len);
    }

    pub fn validationIssueCount(self: *VulkanBackend) u32 {
        const impl: *VulkanImpl = @ptrCast(@alignCast(self._impl));
        return @atomicLoad(u32, &impl.validation_issue_count, .acquire);
    }

    /// Expose raw Vulkan handles as *anyopaque for module 09 GpuAtlas upload.
    /// Returns error.Unavailable if backend was not fully initialised (handles safety).
    pub fn _impl_vulkan(self: *VulkanBackend) error{Unavailable}!struct {
        device: *anyopaque,
        phys_device: *anyopaque,
        cmd_pool: *anyopaque,
        graphics_queue: *anyopaque,
    } {
        const impl: *VulkanImpl = @ptrCast(@alignCast(self._impl));
        if (impl.device == null or impl.physical_device == null or
            impl.command_pool == null or impl.graphics_queue == null)
            return error.Unavailable;
        return .{
            .device = @ptrCast(impl.device.?),
            .phys_device = @ptrCast(impl.physical_device.?),
            .cmd_pool = @ptrCast(impl.command_pool.?),
            .graphics_queue = @ptrCast(impl.graphics_queue.?),
        };
    }

    // -----------------------------------------------------------------------
    // Module 09 extensions — quad pipeline (added alongside the triangle pipeline)
    // -----------------------------------------------------------------------

    pub fn initQuadPipeline(self: *VulkanBackend, gpa: std.mem.Allocator) !void {
        const impl: *VulkanImpl = @ptrCast(@alignCast(self._impl));
        try vkInitQuadPipeline(impl, gpa);
    }

    pub fn deinitQuadPipeline(self: *VulkanBackend) void {
        const impl: *VulkanImpl = @ptrCast(@alignCast(self._impl));
        vkDeinitQuadPipeline(impl);
    }

    /// `atlas` is *const GpuAtlas or any struct with the same leading fields
    /// (image, image_view, sampler, memory as ?*anyopaque). Any *T coerces to *const anyopaque.
    pub fn drawFrame(self: *VulkanBackend, commands: []const DrawCommand, atlas: *const anyopaque) void {
        const impl: *VulkanImpl = @ptrCast(@alignCast(self._impl));
        const h: *const GpuAtlas = @ptrCast(@alignCast(atlas));
        vkDrawFrame(impl, commands, h);
    }
};

// ---------------------------------------------------------------------------
// Vulkan helpers — instance creation.
// ---------------------------------------------------------------------------

fn vkCreateInstance(gpa: std.mem.Allocator, platform: *Platform) !c.VkInstance {
    // Collect required extensions from GLFW + debug messenger (debug only).
    const glfw_exts = platform.requiredInstanceExtensions();

    var ext_names: std.ArrayListUnmanaged([*:0]const u8) = .empty;
    defer ext_names.deinit(gpa);
    try ext_names.appendSlice(gpa, glfw_exts);
    if (enable_validation) {
        try ext_names.append(gpa, "VK_EXT_debug_utils");
    }

    var layer_names: std.ArrayListUnmanaged([*:0]const u8) = .empty;
    defer layer_names.deinit(gpa);
    if (enable_validation) {
        try layer_names.append(gpa, "VK_LAYER_KHRONOS_validation");
    }

    var app_info = std.mem.zeroes(c.VkApplicationInfo);
    app_info.sType = c.VK_STRUCTURE_TYPE_APPLICATION_INFO;
    app_info.pApplicationName = "zig-gui-spike";
    app_info.applicationVersion = c.VK_MAKE_VERSION(0, 1, 0);
    app_info.pEngineName = "zig-gui";
    app_info.engineVersion = c.VK_MAKE_VERSION(0, 1, 0);
    app_info.apiVersion = c.VK_API_VERSION_1_0;

    var create_info = std.mem.zeroes(c.VkInstanceCreateInfo);
    create_info.sType = c.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO;
    create_info.pApplicationInfo = &app_info;
    create_info.enabledExtensionCount = @intCast(ext_names.items.len);
    create_info.ppEnabledExtensionNames = ext_names.items.ptr;
    create_info.enabledLayerCount = @intCast(layer_names.items.len);
    create_info.ppEnabledLayerNames = layer_names.items.ptr;

    // Attach debug messenger create info to instance create so early init messages
    // are captured (before the real messenger is set up).
    var dbg_ci = debugMessengerCreateInfo(null);
    if (enable_validation) {
        create_info.pNext = &dbg_ci;
    }

    var instance: c.VkInstance = undefined;
    if (c.vkCreateInstance(&create_info, null, &instance) != c.VK_SUCCESS) {
        return error.InstanceCreationFailed;
    }
    return instance;
}

// ---------------------------------------------------------------------------
// Debug messenger.
// ---------------------------------------------------------------------------

fn debugMessengerCreateInfo(counter: ?*u32) c.VkDebugUtilsMessengerCreateInfoEXT {
    var info = std.mem.zeroes(c.VkDebugUtilsMessengerCreateInfoEXT);
    info.sType = c.VK_STRUCTURE_TYPE_DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT;
    info.messageSeverity = c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_VERBOSE_BIT_EXT |
        c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT |
        c.VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT;
    info.messageType = c.VK_DEBUG_UTILS_MESSAGE_TYPE_GENERAL_BIT_EXT |
        c.VK_DEBUG_UTILS_MESSAGE_TYPE_VALIDATION_BIT_EXT |
        c.VK_DEBUG_UTILS_MESSAGE_TYPE_PERFORMANCE_BIT_EXT;
    info.pfnUserCallback = debugCallback;
    info.pUserData = counter;
    return info;
}

fn vkCreateDebugMessenger(instance: c.VkInstance, counter: *u32) !c.VkDebugUtilsMessengerEXT {
    const create_fn: c.PFN_vkCreateDebugUtilsMessengerEXT = @ptrCast(
        c.vkGetInstanceProcAddr(instance, "vkCreateDebugUtilsMessengerEXT"),
    );
    if (create_fn == null) return error.InstanceCreationFailed;

    var info = debugMessengerCreateInfo(counter);
    var messenger: c.VkDebugUtilsMessengerEXT = undefined;
    if (create_fn.?(instance, &info, null, &messenger) != c.VK_SUCCESS) {
        return error.InstanceCreationFailed;
    }
    return messenger;
}

fn vkDestroyDebugMessenger(instance: c.VkInstance, messenger: c.VkDebugUtilsMessengerEXT) void {
    const destroy_fn: c.PFN_vkDestroyDebugUtilsMessengerEXT = @ptrCast(
        c.vkGetInstanceProcAddr(instance, "vkDestroyDebugUtilsMessengerEXT"),
    );
    if (destroy_fn) |f| f(instance, messenger, null);
}

// ---------------------------------------------------------------------------
// Physical device selection.
// ---------------------------------------------------------------------------

const PhysicalDeviceResult = struct {
    physical_device: c.VkPhysicalDevice,
    graphics_family: u32,
    present_family: u32,
};

fn vkSelectPhysicalDevice(
    gpa: std.mem.Allocator,
    instance: c.VkInstance,
    surface: c.VkSurfaceKHR,
) !PhysicalDeviceResult {
    var count: u32 = 0;
    _ = c.vkEnumeratePhysicalDevices(instance, &count, null);
    if (count == 0) return error.NoSuitableDevice;

    const devices = try gpa.alloc(c.VkPhysicalDevice, count);
    defer gpa.free(devices);
    _ = c.vkEnumeratePhysicalDevices(instance, &count, devices.ptr);

    for (devices) |pd| {
        if (try isDeviceSuitable(gpa, pd, surface)) |result| return result;
    }
    return error.NoSuitableDevice;
}

fn isDeviceSuitable(
    gpa: std.mem.Allocator,
    pd: c.VkPhysicalDevice,
    surface: c.VkSurfaceKHR,
) !?PhysicalDeviceResult {
    // Check swapchain extension support.
    var ext_count: u32 = 0;
    _ = c.vkEnumerateDeviceExtensionProperties(pd, null, &ext_count, null);
    const exts = try gpa.alloc(c.VkExtensionProperties, ext_count);
    defer gpa.free(exts);
    _ = c.vkEnumerateDeviceExtensionProperties(pd, null, &ext_count, exts.ptr);

    var has_swapchain = false;
    for (exts) |ext| {
        const name = std.mem.sliceTo(&ext.extensionName, 0);
        if (std.mem.eql(u8, name, "VK_KHR_swapchain")) {
            has_swapchain = true;
            break;
        }
    }
    if (!has_swapchain) return null;

    // Find graphics + present queue families.
    var qf_count: u32 = 0;
    c.vkGetPhysicalDeviceQueueFamilyProperties(pd, &qf_count, null);
    const qfs = try gpa.alloc(c.VkQueueFamilyProperties, qf_count);
    defer gpa.free(qfs);
    c.vkGetPhysicalDeviceQueueFamilyProperties(pd, &qf_count, qfs.ptr);

    var graphics_family: ?u32 = null;
    var present_family: ?u32 = null;

    for (qfs, 0..) |qf, i| {
        const idx: u32 = @intCast(i);
        if (qf.queueFlags & c.VK_QUEUE_GRAPHICS_BIT != 0) graphics_family = idx;

        var present_support: c.VkBool32 = c.VK_FALSE;
        _ = c.vkGetPhysicalDeviceSurfaceSupportKHR(pd, idx, surface, &present_support);
        if (present_support == c.VK_TRUE) present_family = idx;

        if (graphics_family != null and present_family != null) break;
    }

    const gf = graphics_family orelse return null;
    const pf = present_family orelse return null;

    // Check that the surface has at least one format and one present mode.
    var fmt_count: u32 = 0;
    _ = c.vkGetPhysicalDeviceSurfaceFormatsKHR(pd, surface, &fmt_count, null);
    var pm_count: u32 = 0;
    _ = c.vkGetPhysicalDeviceSurfacePresentModesKHR(pd, surface, &pm_count, null);
    if (fmt_count == 0 or pm_count == 0) return null;

    return PhysicalDeviceResult{
        .physical_device = pd,
        .graphics_family = gf,
        .present_family = pf,
    };
}

// ---------------------------------------------------------------------------
// Logical device + queues.
// ---------------------------------------------------------------------------

fn vkCreateLogicalDevice(impl: *VulkanImpl) !void {
    const priority: f32 = 1.0;

    var queue_infos: [2]c.VkDeviceQueueCreateInfo = undefined;
    var queue_count: u32 = 1;

    queue_infos[0] = std.mem.zeroes(c.VkDeviceQueueCreateInfo);
    queue_infos[0].sType = c.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO;
    queue_infos[0].queueFamilyIndex = impl.graphics_family;
    queue_infos[0].queueCount = 1;
    queue_infos[0].pQueuePriorities = &priority;

    if (impl.present_family != impl.graphics_family) {
        queue_infos[1] = std.mem.zeroes(c.VkDeviceQueueCreateInfo);
        queue_infos[1].sType = c.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO;
        queue_infos[1].queueFamilyIndex = impl.present_family;
        queue_infos[1].queueCount = 1;
        queue_infos[1].pQueuePriorities = &priority;
        queue_count = 2;
    }

    const device_exts = [_][*:0]const u8{"VK_KHR_swapchain"};
    const features = std.mem.zeroes(c.VkPhysicalDeviceFeatures);

    var device_ci = std.mem.zeroes(c.VkDeviceCreateInfo);
    device_ci.sType = c.VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO;
    device_ci.queueCreateInfoCount = queue_count;
    device_ci.pQueueCreateInfos = &queue_infos;
    device_ci.enabledExtensionCount = 1;
    device_ci.ppEnabledExtensionNames = &device_exts;
    device_ci.pEnabledFeatures = &features;

    if (c.vkCreateDevice(impl.physical_device, &device_ci, null, &impl.device) != c.VK_SUCCESS) {
        return error.DeviceCreationFailed;
    }
    c.vkGetDeviceQueue(impl.device, impl.graphics_family, 0, &impl.graphics_queue);
    c.vkGetDeviceQueue(impl.device, impl.present_family, 0, &impl.present_queue);
}

// ---------------------------------------------------------------------------
// Swapchain creation.
// ---------------------------------------------------------------------------

fn vkCreateSwapchain(impl: *VulkanImpl) !void {
    var caps = std.mem.zeroes(c.VkSurfaceCapabilitiesKHR);
    _ = c.vkGetPhysicalDeviceSurfaceCapabilitiesKHR(impl.physical_device, impl.surface, &caps);

    const format = chooseSwapFormat(impl);
    const present_mode = chooseSwapPresentMode(impl);
    const extent = chooseSwapExtent(impl, &caps);

    var image_count: u32 = caps.minImageCount + 1;
    if (caps.maxImageCount > 0 and image_count > caps.maxImageCount) {
        image_count = caps.maxImageCount;
    }

    var sci = std.mem.zeroes(c.VkSwapchainCreateInfoKHR);
    sci.sType = c.VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR;
    sci.surface = impl.surface;
    sci.minImageCount = image_count;
    sci.imageFormat = format.format;
    sci.imageColorSpace = format.colorSpace;
    sci.imageExtent = extent;
    sci.imageArrayLayers = 1;
    sci.imageUsage = c.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT;

    const indices = [2]u32{ impl.graphics_family, impl.present_family };
    if (impl.graphics_family != impl.present_family) {
        sci.imageSharingMode = c.VK_SHARING_MODE_CONCURRENT;
        sci.queueFamilyIndexCount = 2;
        sci.pQueueFamilyIndices = &indices;
    } else {
        sci.imageSharingMode = c.VK_SHARING_MODE_EXCLUSIVE;
    }

    sci.preTransform = caps.currentTransform;
    sci.compositeAlpha = c.VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR;
    sci.presentMode = present_mode;
    sci.clipped = c.VK_TRUE;

    if (c.vkCreateSwapchainKHR(impl.device, &sci, null, &impl.swapchain) != c.VK_SUCCESS) {
        return error.SwapchainCreationFailed;
    }
    impl.swapchain_format = format.format;
    impl.swapchain_extent = extent;

    // Retrieve images.
    var img_count: u32 = 0;
    _ = c.vkGetSwapchainImagesKHR(impl.device, impl.swapchain, &img_count, null);
    impl.swapchain_images = try impl.allocator.alloc(c.VkImage, img_count);
    _ = c.vkGetSwapchainImagesKHR(impl.device, impl.swapchain, &img_count, impl.swapchain_images.ptr);

    // Create image views.
    try vkCreateImageViews(impl);
}

fn chooseSwapFormat(impl: *VulkanImpl) c.VkSurfaceFormatKHR {
    var count: u32 = 0;
    _ = c.vkGetPhysicalDeviceSurfaceFormatsKHR(impl.physical_device, impl.surface, &count, null);
    var buf: [16]c.VkSurfaceFormatKHR = undefined;
    var actual: u32 = @min(count, 16);
    _ = c.vkGetPhysicalDeviceSurfaceFormatsKHR(impl.physical_device, impl.surface, &actual, &buf);
    for (buf[0..actual]) |fmt| {
        if (fmt.format == c.VK_FORMAT_B8G8R8A8_SRGB and
            fmt.colorSpace == c.VK_COLOR_SPACE_SRGB_NONLINEAR_KHR)
        {
            return fmt;
        }
    }
    return buf[0];
}

fn chooseSwapPresentMode(impl: *VulkanImpl) c.VkPresentModeKHR {
    var count: u32 = 0;
    _ = c.vkGetPhysicalDeviceSurfacePresentModesKHR(impl.physical_device, impl.surface, &count, null);
    var buf: [8]c.VkPresentModeKHR = undefined;
    var actual: u32 = @min(count, 8);
    _ = c.vkGetPhysicalDeviceSurfacePresentModesKHR(impl.physical_device, impl.surface, &actual, &buf);
    for (buf[0..actual]) |pm| {
        if (pm == c.VK_PRESENT_MODE_MAILBOX_KHR) return pm;
    }
    return c.VK_PRESENT_MODE_FIFO_KHR;
}

fn chooseSwapExtent(impl: *VulkanImpl, caps: *const c.VkSurfaceCapabilitiesKHR) c.VkExtent2D {
    if (caps.currentExtent.width != std.math.maxInt(u32)) {
        return caps.currentExtent;
    }
    const fb = impl.platform.framebufferSize();
    return .{
        .width = std.math.clamp(fb.width, caps.minImageExtent.width, caps.maxImageExtent.width),
        .height = std.math.clamp(fb.height, caps.minImageExtent.height, caps.maxImageExtent.height),
    };
}

fn vkCreateImageViews(impl: *VulkanImpl) !void {
    impl.swapchain_image_views = try impl.allocator.alloc(c.VkImageView, impl.swapchain_images.len);
    for (impl.swapchain_images, 0..) |image, i| {
        var ivi = std.mem.zeroes(c.VkImageViewCreateInfo);
        ivi.sType = c.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO;
        ivi.image = image;
        ivi.viewType = c.VK_IMAGE_VIEW_TYPE_2D;
        ivi.format = impl.swapchain_format;
        ivi.components.r = c.VK_COMPONENT_SWIZZLE_IDENTITY;
        ivi.components.g = c.VK_COMPONENT_SWIZZLE_IDENTITY;
        ivi.components.b = c.VK_COMPONENT_SWIZZLE_IDENTITY;
        ivi.components.a = c.VK_COMPONENT_SWIZZLE_IDENTITY;
        ivi.subresourceRange.aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT;
        ivi.subresourceRange.baseMipLevel = 0;
        ivi.subresourceRange.levelCount = 1;
        ivi.subresourceRange.baseArrayLayer = 0;
        ivi.subresourceRange.layerCount = 1;
        if (c.vkCreateImageView(impl.device, &ivi, null, &impl.swapchain_image_views[i]) != c.VK_SUCCESS) {
            // Clean up views created so far.
            for (impl.swapchain_image_views[0..i]) |v| c.vkDestroyImageView(impl.device, v, null);
            impl.allocator.free(impl.swapchain_image_views);
            return error.SwapchainCreationFailed;
        }
    }
}

// ---------------------------------------------------------------------------
// Render pass.
// ---------------------------------------------------------------------------

fn vkCreateRenderPass(impl: *VulkanImpl) !void {
    var color_att = std.mem.zeroes(c.VkAttachmentDescription);
    color_att.format = impl.swapchain_format;
    color_att.samples = c.VK_SAMPLE_COUNT_1_BIT;
    color_att.loadOp = c.VK_ATTACHMENT_LOAD_OP_CLEAR;
    color_att.storeOp = c.VK_ATTACHMENT_STORE_OP_STORE;
    color_att.stencilLoadOp = c.VK_ATTACHMENT_LOAD_OP_DONT_CARE;
    color_att.stencilStoreOp = c.VK_ATTACHMENT_STORE_OP_DONT_CARE;
    color_att.initialLayout = c.VK_IMAGE_LAYOUT_UNDEFINED;
    color_att.finalLayout = c.VK_IMAGE_LAYOUT_PRESENT_SRC_KHR;

    const color_ref = c.VkAttachmentReference{
        .attachment = 0,
        .layout = c.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
    };

    var subpass = std.mem.zeroes(c.VkSubpassDescription);
    subpass.pipelineBindPoint = c.VK_PIPELINE_BIND_POINT_GRAPHICS;
    subpass.colorAttachmentCount = 1;
    subpass.pColorAttachments = &color_ref;

    var dep = std.mem.zeroes(c.VkSubpassDependency);
    dep.srcSubpass = c.VK_SUBPASS_EXTERNAL;
    dep.dstSubpass = 0;
    dep.srcStageMask = c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
    dep.srcAccessMask = 0;
    dep.dstStageMask = c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
    dep.dstAccessMask = c.VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT;

    var rp_info = std.mem.zeroes(c.VkRenderPassCreateInfo);
    rp_info.sType = c.VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO;
    rp_info.attachmentCount = 1;
    rp_info.pAttachments = &color_att;
    rp_info.subpassCount = 1;
    rp_info.pSubpasses = &subpass;
    rp_info.dependencyCount = 1;
    rp_info.pDependencies = &dep;

    if (c.vkCreateRenderPass(impl.device, &rp_info, null, &impl.render_pass) != c.VK_SUCCESS) {
        return error.DeviceCreationFailed;
    }
}

// ---------------------------------------------------------------------------
// Framebuffers.
// ---------------------------------------------------------------------------

fn vkCreateFramebuffers(impl: *VulkanImpl) !void {
    impl.framebuffers = try impl.allocator.alloc(c.VkFramebuffer, impl.swapchain_image_views.len);
    for (impl.swapchain_image_views, 0..) |iv, i| {
        var fb_info = std.mem.zeroes(c.VkFramebufferCreateInfo);
        fb_info.sType = c.VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO;
        fb_info.renderPass = impl.render_pass;
        fb_info.attachmentCount = 1;
        fb_info.pAttachments = &iv;
        fb_info.width = impl.swapchain_extent.width;
        fb_info.height = impl.swapchain_extent.height;
        fb_info.layers = 1;
        if (c.vkCreateFramebuffer(impl.device, &fb_info, null, &impl.framebuffers[i]) != c.VK_SUCCESS) {
            for (impl.framebuffers[0..i]) |fb| c.vkDestroyFramebuffer(impl.device, fb, null);
            impl.allocator.free(impl.framebuffers);
            return error.SwapchainCreationFailed;
        }
    }
}

// ---------------------------------------------------------------------------
// Command pool + buffer.
// ---------------------------------------------------------------------------

fn vkCreateCommandPool(impl: *VulkanImpl) !void {
    var pool_info = std.mem.zeroes(c.VkCommandPoolCreateInfo);
    pool_info.sType = c.VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO;
    pool_info.flags = c.VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT;
    pool_info.queueFamilyIndex = impl.graphics_family;
    if (c.vkCreateCommandPool(impl.device, &pool_info, null, &impl.command_pool) != c.VK_SUCCESS) {
        return error.DeviceCreationFailed;
    }

    var alloc_info = std.mem.zeroes(c.VkCommandBufferAllocateInfo);
    alloc_info.sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO;
    alloc_info.commandPool = impl.command_pool;
    alloc_info.level = c.VK_COMMAND_BUFFER_LEVEL_PRIMARY;
    alloc_info.commandBufferCount = 1;
    if (c.vkAllocateCommandBuffers(impl.device, &alloc_info, &impl.command_buffer) != c.VK_SUCCESS) {
        return error.DeviceCreationFailed;
    }
}

// ---------------------------------------------------------------------------
// Sync objects.
// ---------------------------------------------------------------------------

fn vkCreateSyncObjects(impl: *VulkanImpl) !void {
    var sem_info = std.mem.zeroes(c.VkSemaphoreCreateInfo);
    sem_info.sType = c.VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO;

    var fence_info = std.mem.zeroes(c.VkFenceCreateInfo);
    fence_info.sType = c.VK_STRUCTURE_TYPE_FENCE_CREATE_INFO;
    fence_info.flags = c.VK_FENCE_CREATE_SIGNALED_BIT;

    if (c.vkCreateSemaphore(impl.device, &sem_info, null, &impl.image_available_sem) != c.VK_SUCCESS)
        return error.DeviceCreationFailed;
    errdefer c.vkDestroySemaphore(impl.device, impl.image_available_sem, null);

    const count = impl.swapchain_images.len;
    impl.render_finished_sems = try impl.allocator.alloc(c.VkSemaphore, count);
    var created: usize = 0;
    errdefer {
        for (impl.render_finished_sems[0..created]) |sem| c.vkDestroySemaphore(impl.device, sem, null);
        impl.allocator.free(impl.render_finished_sems);
        impl.render_finished_sems = &.{};
    }
    for (impl.render_finished_sems) |*sem| {
        if (c.vkCreateSemaphore(impl.device, &sem_info, null, sem) != c.VK_SUCCESS)
            return error.DeviceCreationFailed;
        created += 1;
    }

    if (c.vkCreateFence(impl.device, &fence_info, null, &impl.in_flight_fence) != c.VK_SUCCESS) {
        return error.DeviceCreationFailed;
    }
}

fn vkDestroySyncObjects(impl: *VulkanImpl) void {
    c.vkDestroySemaphore(impl.device, impl.image_available_sem, null);
    for (impl.render_finished_sems) |sem| c.vkDestroySemaphore(impl.device, sem, null);
    impl.allocator.free(impl.render_finished_sems);
    impl.render_finished_sems = &.{};
    c.vkDestroyFence(impl.device, impl.in_flight_fence, null);
}

// ---------------------------------------------------------------------------
// Graphics pipeline (triangle spike — throwaway per spec non-goals).
// ---------------------------------------------------------------------------

fn vkCreatePipeline(impl: *VulkanImpl) !void {
    // Shader modules.
    const vert_module = try createShaderModule(impl.device, &shaders.vert_spv);
    defer c.vkDestroyShaderModule(impl.device, vert_module, null);
    const frag_module = try createShaderModule(impl.device, &shaders.frag_spv);
    defer c.vkDestroyShaderModule(impl.device, frag_module, null);

    var vert_stage = std.mem.zeroes(c.VkPipelineShaderStageCreateInfo);
    vert_stage.sType = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
    vert_stage.stage = c.VK_SHADER_STAGE_VERTEX_BIT;
    vert_stage.module = vert_module;
    vert_stage.pName = "main";

    var frag_stage = std.mem.zeroes(c.VkPipelineShaderStageCreateInfo);
    frag_stage.sType = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
    frag_stage.stage = c.VK_SHADER_STAGE_FRAGMENT_BIT;
    frag_stage.module = frag_module;
    frag_stage.pName = "main";

    const shader_stages = [2]c.VkPipelineShaderStageCreateInfo{ vert_stage, frag_stage };

    // No vertex input (positions hardcoded in shader).
    var vertex_input = std.mem.zeroes(c.VkPipelineVertexInputStateCreateInfo);
    vertex_input.sType = c.VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO;

    var input_assembly = std.mem.zeroes(c.VkPipelineInputAssemblyStateCreateInfo);
    input_assembly.sType = c.VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO;
    input_assembly.topology = c.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST;
    input_assembly.primitiveRestartEnable = c.VK_FALSE;

    // Dynamic viewport + scissor (no pipeline rebuild on resize).
    var viewport_state = std.mem.zeroes(c.VkPipelineViewportStateCreateInfo);
    viewport_state.sType = c.VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO;
    viewport_state.viewportCount = 1;
    viewport_state.scissorCount = 1;

    var rasterizer = std.mem.zeroes(c.VkPipelineRasterizationStateCreateInfo);
    rasterizer.sType = c.VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO;
    rasterizer.polygonMode = c.VK_POLYGON_MODE_FILL;
    rasterizer.cullMode = c.VK_CULL_MODE_BACK_BIT;
    rasterizer.frontFace = c.VK_FRONT_FACE_CLOCKWISE;
    rasterizer.lineWidth = 1.0;

    var multisampling = std.mem.zeroes(c.VkPipelineMultisampleStateCreateInfo);
    multisampling.sType = c.VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO;
    multisampling.rasterizationSamples = c.VK_SAMPLE_COUNT_1_BIT;

    var blend_att = std.mem.zeroes(c.VkPipelineColorBlendAttachmentState);
    blend_att.colorWriteMask = c.VK_COLOR_COMPONENT_R_BIT | c.VK_COLOR_COMPONENT_G_BIT |
        c.VK_COLOR_COMPONENT_B_BIT | c.VK_COLOR_COMPONENT_A_BIT;
    blend_att.blendEnable = c.VK_FALSE;

    var blend_state = std.mem.zeroes(c.VkPipelineColorBlendStateCreateInfo);
    blend_state.sType = c.VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO;
    blend_state.logicOpEnable = c.VK_FALSE;
    blend_state.attachmentCount = 1;
    blend_state.pAttachments = &blend_att;

    const dynamic_states = [2]c.VkDynamicState{
        c.VK_DYNAMIC_STATE_VIEWPORT,
        c.VK_DYNAMIC_STATE_SCISSOR,
    };
    var dynamic_state = std.mem.zeroes(c.VkPipelineDynamicStateCreateInfo);
    dynamic_state.sType = c.VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO;
    dynamic_state.dynamicStateCount = dynamic_states.len;
    dynamic_state.pDynamicStates = &dynamic_states;

    // Pipeline layout (no descriptors for spike).
    var layout_info = std.mem.zeroes(c.VkPipelineLayoutCreateInfo);
    layout_info.sType = c.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO;
    if (c.vkCreatePipelineLayout(impl.device, &layout_info, null, &impl.pipeline_layout) != c.VK_SUCCESS) {
        return error.ShaderLoadFailed;
    }
    errdefer c.vkDestroyPipelineLayout(impl.device, impl.pipeline_layout, null);

    var gfx_ci = std.mem.zeroes(c.VkGraphicsPipelineCreateInfo);
    gfx_ci.sType = c.VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO;
    gfx_ci.stageCount = 2;
    gfx_ci.pStages = &shader_stages;
    gfx_ci.pVertexInputState = &vertex_input;
    gfx_ci.pInputAssemblyState = &input_assembly;
    gfx_ci.pViewportState = &viewport_state;
    gfx_ci.pRasterizationState = &rasterizer;
    gfx_ci.pMultisampleState = &multisampling;
    gfx_ci.pColorBlendState = &blend_state;
    gfx_ci.pDynamicState = &dynamic_state;
    gfx_ci.layout = impl.pipeline_layout;
    gfx_ci.renderPass = impl.render_pass;
    gfx_ci.subpass = 0;

    if (c.vkCreateGraphicsPipelines(impl.device, null, 1, &gfx_ci, null, &impl.pipeline) != c.VK_SUCCESS) {
        return error.ShaderLoadFailed;
    }
}

fn createShaderModule(device: c.VkDevice, code: []align(4) const u8) !c.VkShaderModule {
    var info = std.mem.zeroes(c.VkShaderModuleCreateInfo);
    info.sType = c.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO;
    info.codeSize = code.len;
    // Vulkan requires u32-aligned SPIR-V. Alignment is guaranteed by the type.
    info.pCode = @ptrCast(code.ptr);
    var module: c.VkShaderModule = undefined;
    if (c.vkCreateShaderModule(device, &info, null, &module) != c.VK_SUCCESS) {
        return error.ShaderLoadFailed;
    }
    return module;
}

// ---------------------------------------------------------------------------
// Swapchain teardown helpers (used in deinit and recreation).
// ---------------------------------------------------------------------------

fn vkDestroySwapchainResources(impl: *VulkanImpl) void {
    for (impl.swapchain_image_views) |iv| c.vkDestroyImageView(impl.device, iv, null);
    impl.allocator.free(impl.swapchain_image_views);
    impl.allocator.free(impl.swapchain_images);
    c.vkDestroySwapchainKHR(impl.device, impl.swapchain, null);
}

fn vkDestroyFramebuffers(impl: *VulkanImpl) void {
    for (impl.framebuffers) |fb| c.vkDestroyFramebuffer(impl.device, fb, null);
    impl.allocator.free(impl.framebuffers);
}

fn vkRecreateSwapchain(impl: *VulkanImpl) !void {
    _ = c.vkDeviceWaitIdle(impl.device);
    vkDestroyFramebuffers(impl);
    vkDestroySwapchainResources(impl);
    try vkCreateSwapchain(impl);
    try vkCreateFramebuffers(impl);
    // If the swapchain image count changed, recreate render_finished_sems.
    if (impl.render_finished_sems.len != impl.swapchain_images.len) {
        for (impl.render_finished_sems) |sem| c.vkDestroySemaphore(impl.device, sem, null);
        impl.allocator.free(impl.render_finished_sems);
        impl.render_finished_sems = &.{};
        var sem_info = std.mem.zeroes(c.VkSemaphoreCreateInfo);
        sem_info.sType = c.VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO;
        impl.render_finished_sems = try impl.allocator.alloc(c.VkSemaphore, impl.swapchain_images.len);
        for (impl.render_finished_sems, 0..) |*sem, i| {
            if (c.vkCreateSemaphore(impl.device, &sem_info, null, sem) != c.VK_SUCCESS) {
                for (impl.render_finished_sems[0..i]) |s| c.vkDestroySemaphore(impl.device, s, null);
                impl.allocator.free(impl.render_finished_sems);
                impl.render_finished_sems = &.{};
                return error.DeviceCreationFailed;
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Module 09 quad pipeline helpers
// ---------------------------------------------------------------------------

const MAX_QUADS: u32 = 65536;
const VERTS_PER_QUAD: u32 = 6; // two triangles, no index buffer

fn findMemoryType(impl: *VulkanImpl, type_filter: u32, props: c.VkMemoryPropertyFlags) !u32 {
    var mem_props: c.VkPhysicalDeviceMemoryProperties = undefined;
    c.vkGetPhysicalDeviceMemoryProperties(impl.physical_device, &mem_props);
    var i: u32 = 0;
    while (i < mem_props.memoryTypeCount) : (i += 1) {
        if ((type_filter & (@as(u32, 1) << @intCast(i))) != 0 and
            (mem_props.memoryTypes[i].propertyFlags & props) == props)
        {
            return i;
        }
    }
    return error.NoSuitableMemoryType;
}

fn vkInitQuadPipeline(impl: *VulkanImpl, gpa: std.mem.Allocator) !void {
    _ = gpa;

    // --- Descriptor set layout: binding 0 = combined image sampler ---
    var ds_binding = std.mem.zeroes(c.VkDescriptorSetLayoutBinding);
    ds_binding.binding = 0;
    ds_binding.descriptorType = c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER;
    ds_binding.descriptorCount = 1;
    ds_binding.stageFlags = c.VK_SHADER_STAGE_FRAGMENT_BIT;

    var dsl_info = std.mem.zeroes(c.VkDescriptorSetLayoutCreateInfo);
    dsl_info.sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO;
    dsl_info.bindingCount = 1;
    dsl_info.pBindings = &ds_binding;
    if (c.vkCreateDescriptorSetLayout(impl.device, &dsl_info, null, &impl.quad_desc_set_layout) != c.VK_SUCCESS)
        return error.ShaderLoadFailed;

    // --- Descriptor pool ---
    var pool_size = std.mem.zeroes(c.VkDescriptorPoolSize);
    pool_size.type = c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER;
    pool_size.descriptorCount = 1;
    var pool_info = std.mem.zeroes(c.VkDescriptorPoolCreateInfo);
    pool_info.sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO;
    pool_info.maxSets = 1;
    pool_info.poolSizeCount = 1;
    pool_info.pPoolSizes = &pool_size;
    if (c.vkCreateDescriptorPool(impl.device, &pool_info, null, &impl.quad_desc_pool) != c.VK_SUCCESS)
        return error.ShaderLoadFailed;

    // --- Descriptor set ---
    var ds_alloc = std.mem.zeroes(c.VkDescriptorSetAllocateInfo);
    ds_alloc.sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO;
    ds_alloc.descriptorPool = impl.quad_desc_pool;
    ds_alloc.descriptorSetCount = 1;
    ds_alloc.pSetLayouts = &impl.quad_desc_set_layout;
    if (c.vkAllocateDescriptorSets(impl.device, &ds_alloc, &impl.quad_desc_set) != c.VK_SUCCESS)
        return error.ShaderLoadFailed;

    // --- Push constants: mat4 ortho (16 floats = 64 bytes) ---
    var push_range = std.mem.zeroes(c.VkPushConstantRange);
    push_range.stageFlags = c.VK_SHADER_STAGE_VERTEX_BIT;
    push_range.offset = 0;
    push_range.size = 64;

    var pl_info = std.mem.zeroes(c.VkPipelineLayoutCreateInfo);
    pl_info.sType = c.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO;
    pl_info.setLayoutCount = 1;
    pl_info.pSetLayouts = &impl.quad_desc_set_layout;
    pl_info.pushConstantRangeCount = 1;
    pl_info.pPushConstantRanges = &push_range;
    if (c.vkCreatePipelineLayout(impl.device, &pl_info, null, &impl.quad_pipeline_layout) != c.VK_SUCCESS)
        return error.ShaderLoadFailed;

    // --- Shaders ---
    const vert_module = try createShaderModule(impl.device, &shaders.quad_vert_spv);
    defer c.vkDestroyShaderModule(impl.device, vert_module, null);
    const frag_module = try createShaderModule(impl.device, &shaders.quad_frag_spv);
    defer c.vkDestroyShaderModule(impl.device, frag_module, null);

    var vert_stage = std.mem.zeroes(c.VkPipelineShaderStageCreateInfo);
    vert_stage.sType = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
    vert_stage.stage = c.VK_SHADER_STAGE_VERTEX_BIT;
    vert_stage.module = vert_module;
    vert_stage.pName = "main";

    var frag_stage = std.mem.zeroes(c.VkPipelineShaderStageCreateInfo);
    frag_stage.sType = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
    frag_stage.stage = c.VK_SHADER_STAGE_FRAGMENT_BIT;
    frag_stage.module = frag_module;
    frag_stage.pName = "main";

    const shader_stages = [2]c.VkPipelineShaderStageCreateInfo{ vert_stage, frag_stage };

    // --- Vertex input: QuadVertex ---
    var vib = std.mem.zeroes(c.VkVertexInputBindingDescription);
    vib.binding = 0;
    vib.stride = @sizeOf(QuadVertex);
    vib.inputRate = c.VK_VERTEX_INPUT_RATE_VERTEX;

    var attr_descs: [4]c.VkVertexInputAttributeDescription = undefined;
    attr_descs[0] = .{ .location = 0, .binding = 0, .format = c.VK_FORMAT_R32G32_SFLOAT,
        .offset = @offsetOf(QuadVertex, "pos") };
    attr_descs[1] = .{ .location = 1, .binding = 0, .format = c.VK_FORMAT_R32G32_SFLOAT,
        .offset = @offsetOf(QuadVertex, "uv") };
    attr_descs[2] = .{ .location = 2, .binding = 0, .format = c.VK_FORMAT_R8G8B8A8_UNORM,
        .offset = @offsetOf(QuadVertex, "color") };
    attr_descs[3] = .{ .location = 3, .binding = 0, .format = c.VK_FORMAT_R32_UINT,
        .offset = @offsetOf(QuadVertex, "mode") };

    var vi = std.mem.zeroes(c.VkPipelineVertexInputStateCreateInfo);
    vi.sType = c.VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO;
    vi.vertexBindingDescriptionCount = 1;
    vi.pVertexBindingDescriptions = &vib;
    vi.vertexAttributeDescriptionCount = 4;
    vi.pVertexAttributeDescriptions = &attr_descs;

    var ia = std.mem.zeroes(c.VkPipelineInputAssemblyStateCreateInfo);
    ia.sType = c.VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO;
    ia.topology = c.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST;

    var vp_state = std.mem.zeroes(c.VkPipelineViewportStateCreateInfo);
    vp_state.sType = c.VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO;
    vp_state.viewportCount = 1;
    vp_state.scissorCount = 1;

    var rast = std.mem.zeroes(c.VkPipelineRasterizationStateCreateInfo);
    rast.sType = c.VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO;
    rast.polygonMode = c.VK_POLYGON_MODE_FILL;
    rast.cullMode = c.VK_CULL_MODE_NONE;
    rast.frontFace = c.VK_FRONT_FACE_CLOCKWISE;
    rast.lineWidth = 1.0;

    var ms = std.mem.zeroes(c.VkPipelineMultisampleStateCreateInfo);
    ms.sType = c.VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO;
    ms.rasterizationSamples = c.VK_SAMPLE_COUNT_1_BIT;

    var blend_attach = std.mem.zeroes(c.VkPipelineColorBlendAttachmentState);
    blend_attach.blendEnable = c.VK_TRUE;
    blend_attach.srcColorBlendFactor = c.VK_BLEND_FACTOR_SRC_ALPHA;
    blend_attach.dstColorBlendFactor = c.VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA;
    blend_attach.colorBlendOp = c.VK_BLEND_OP_ADD;
    blend_attach.srcAlphaBlendFactor = c.VK_BLEND_FACTOR_ONE;
    blend_attach.dstAlphaBlendFactor = c.VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA;
    blend_attach.alphaBlendOp = c.VK_BLEND_OP_ADD;
    blend_attach.colorWriteMask = c.VK_COLOR_COMPONENT_R_BIT | c.VK_COLOR_COMPONENT_G_BIT |
        c.VK_COLOR_COMPONENT_B_BIT | c.VK_COLOR_COMPONENT_A_BIT;

    var blend = std.mem.zeroes(c.VkPipelineColorBlendStateCreateInfo);
    blend.sType = c.VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO;
    blend.attachmentCount = 1;
    blend.pAttachments = &blend_attach;

    const dyn_states = [2]c.VkDynamicState{ c.VK_DYNAMIC_STATE_VIEWPORT, c.VK_DYNAMIC_STATE_SCISSOR };
    var dyn = std.mem.zeroes(c.VkPipelineDynamicStateCreateInfo);
    dyn.sType = c.VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO;
    dyn.dynamicStateCount = 2;
    dyn.pDynamicStates = &dyn_states;

    var gp_info = std.mem.zeroes(c.VkGraphicsPipelineCreateInfo);
    gp_info.sType = c.VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO;
    gp_info.stageCount = 2;
    gp_info.pStages = &shader_stages;
    gp_info.pVertexInputState = &vi;
    gp_info.pInputAssemblyState = &ia;
    gp_info.pViewportState = &vp_state;
    gp_info.pRasterizationState = &rast;
    gp_info.pMultisampleState = &ms;
    gp_info.pColorBlendState = &blend;
    gp_info.pDynamicState = &dyn;
    gp_info.layout = impl.quad_pipeline_layout;
    gp_info.renderPass = impl.render_pass;
    gp_info.subpass = 0;

    if (c.vkCreateGraphicsPipelines(impl.device, null, 1, &gp_info, null, &impl.quad_pipeline) != c.VK_SUCCESS)
        return error.ShaderLoadFailed;

    // --- Host-visible vertex buffer for per-frame geometry ---
    const buf_size: c.VkDeviceSize = @as(u64, MAX_QUADS) * VERTS_PER_QUAD * @sizeOf(QuadVertex);
    var buf_info = std.mem.zeroes(c.VkBufferCreateInfo);
    buf_info.sType = c.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO;
    buf_info.size = buf_size;
    buf_info.usage = c.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT;
    buf_info.sharingMode = c.VK_SHARING_MODE_EXCLUSIVE;
    if (c.vkCreateBuffer(impl.device, &buf_info, null, &impl.quad_vertex_buf) != c.VK_SUCCESS)
        return error.ShaderLoadFailed;

    var mem_req: c.VkMemoryRequirements = undefined;
    c.vkGetBufferMemoryRequirements(impl.device, impl.quad_vertex_buf, &mem_req);
    const mem_type = try findMemoryType(impl, mem_req.memoryTypeBits,
        c.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | c.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT);

    var ma_info = std.mem.zeroes(c.VkMemoryAllocateInfo);
    ma_info.sType = c.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
    ma_info.allocationSize = mem_req.size;
    ma_info.memoryTypeIndex = mem_type;
    if (c.vkAllocateMemory(impl.device, &ma_info, null, &impl.quad_vertex_mem) != c.VK_SUCCESS)
        return error.ShaderLoadFailed;
    _ = c.vkBindBufferMemory(impl.device, impl.quad_vertex_buf, impl.quad_vertex_mem, 0);

    impl.quad_pipeline_ready = true;
}

fn vkDeinitQuadPipeline(impl: *VulkanImpl) void {
    if (!impl.quad_pipeline_ready) return;
    _ = c.vkDeviceWaitIdle(impl.device);
    c.vkDestroyBuffer(impl.device, impl.quad_vertex_buf, null);
    c.vkFreeMemory(impl.device, impl.quad_vertex_mem, null);
    c.vkDestroyPipeline(impl.device, impl.quad_pipeline, null);
    c.vkDestroyPipelineLayout(impl.device, impl.quad_pipeline_layout, null);
    c.vkDestroyDescriptorPool(impl.device, impl.quad_desc_pool, null);
    c.vkDestroyDescriptorSetLayout(impl.device, impl.quad_desc_set_layout, null);
    impl.quad_pipeline_ready = false;
    impl.quad_pipeline = null;
    impl.quad_pipeline_layout = null;
    impl.quad_desc_pool = null;
    impl.quad_desc_set_layout = null;
    impl.quad_desc_set = null;
    impl.quad_vertex_buf = null;
    impl.quad_vertex_mem = null;
}

fn vkDrawFrame(impl: *VulkanImpl, commands: []const DrawCommand, atlas: *const GpuAtlas) void {
    if (!impl.quad_pipeline_ready) return;

    // Begin render pass if clear() was not called before drawFrame().
    if (!impl.render_pass_active) {
        var clear_color: c.VkClearColorValue = undefined;
        clear_color.float32 = [4]f32{ 0, 0, 0, 0 };
        var clear_value: c.VkClearValue = undefined;
        clear_value.color = clear_color;
        var rp_begin = std.mem.zeroes(c.VkRenderPassBeginInfo);
        rp_begin.sType = c.VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO;
        rp_begin.renderPass = impl.render_pass;
        rp_begin.framebuffer = impl.framebuffers[impl.current_image_index];
        rp_begin.renderArea = .{ .offset = .{ .x = 0, .y = 0 }, .extent = impl.swapchain_extent };
        rp_begin.clearValueCount = 1;
        rp_begin.pClearValues = &clear_value;
        c.vkCmdBeginRenderPass(impl.command_buffer, &rp_begin, c.VK_SUBPASS_CONTENTS_INLINE);
        impl.render_pass_active = true;
    }

    // Update descriptor set to point at the current atlas image/sampler.
    if (atlas.image_view != null and atlas.sampler != null) {
        var img_info = std.mem.zeroes(c.VkDescriptorImageInfo);
        img_info.imageLayout = c.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
        img_info.imageView = @ptrCast(atlas.image_view.?);
        img_info.sampler = @ptrCast(atlas.sampler.?);
        var write = std.mem.zeroes(c.VkWriteDescriptorSet);
        write.sType = c.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
        write.dstSet = impl.quad_desc_set;
        write.dstBinding = 0;
        write.descriptorCount = 1;
        write.descriptorType = c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER;
        write.pImageInfo = &img_info;
        c.vkUpdateDescriptorSets(impl.device, 1, &write, 0, null);
    }

    // Build vertex data: expand each DrawCommand into 6 vertices.
    const max_verts = MAX_QUADS * VERTS_PER_QUAD;
    var mapped: ?*anyopaque = null;
    const buf_size: c.VkDeviceSize = @as(u64, max_verts) * @sizeOf(QuadVertex);
    _ = c.vkMapMemory(impl.device, impl.quad_vertex_mem, 0, buf_size, 0, &mapped);
    const verts: [*]QuadVertex = @ptrCast(@alignCast(mapped.?));

    var vert_count: u32 = 0;
    const W = @as(f32, @floatFromInt(impl.swapchain_extent.width));
    const H = @as(f32, @floatFromInt(impl.swapchain_extent.height));

    for (commands) |cmd| {
        if (vert_count + VERTS_PER_QUAD > max_verts) {
            std.debug.print("[renderer] MAX_QUADS ({}) exceeded, truncating\n", .{MAX_QUADS});
            break;
        }
        switch (cmd) {
            .filled_rect => |r| emitQuad(verts, &vert_count, r.rect, .{}, r.color, 0),
            .border_rect => |br| emitQuad(verts, &vert_count, br.rect, .{}, br.color, 0),
            .glyph => |g| emitQuad(verts, &vert_count, g.dst, g.uv, g.color, 1),
        }
    }
    c.vkUnmapMemory(impl.device, impl.quad_vertex_mem);

    if (vert_count == 0) return; // render pass still active; endFrame will close it

    const cb = impl.command_buffer;
    c.vkCmdBindPipeline(cb, c.VK_PIPELINE_BIND_POINT_GRAPHICS, impl.quad_pipeline);

    const viewport = c.VkViewport{ .x = 0, .y = 0, .width = W, .height = H,
        .minDepth = 0, .maxDepth = 1 };
    c.vkCmdSetViewport(cb, 0, 1, &viewport);
    const scissor = c.VkRect2D{ .offset = .{ .x = 0, .y = 0 }, .extent = impl.swapchain_extent };
    c.vkCmdSetScissor(cb, 0, 1, &scissor);

    // Orthographic projection: pixel coords to NDC. Column-major.
    const ortho = [16]f32{
        2.0 / W, 0,       0, 0,
        0,       2.0 / H, 0, 0,
        0,       0,       1, 0,
        -1,      -1,      0, 1,
    };
    c.vkCmdPushConstants(cb, impl.quad_pipeline_layout, c.VK_SHADER_STAGE_VERTEX_BIT, 0, 64, &ortho);
    c.vkCmdBindDescriptorSets(cb, c.VK_PIPELINE_BIND_POINT_GRAPHICS,
        impl.quad_pipeline_layout, 0, 1, &impl.quad_desc_set, 0, null);

    const vb_offset: c.VkDeviceSize = 0;
    c.vkCmdBindVertexBuffers(cb, 0, 1, &impl.quad_vertex_buf, &vb_offset);
    c.vkCmdDraw(cb, vert_count, 1, 0, 0);
}

fn emitQuad(
    verts: [*]QuadVertex,
    count: *u32,
    rect: Rect09,
    uv: Rect09,
    color: Color09,
    mode: u32,
) void {
    const px0 = rect.x;             const py0 = rect.y;
    const px1 = rect.x + rect.w;    const py1 = rect.y + rect.h;
    const ux0 = uv.x;               const vy0 = uv.y;
    const ux1 = uv.x + uv.w;        const vy1 = uv.y + uv.h;
    const col = [4]u8{ color.r, color.g, color.b, color.a };
    verts[count.*] = .{ .pos = .{ px0, py0 }, .uv = .{ ux0, vy0 }, .color = col, .mode = mode }; count.* += 1;
    verts[count.*] = .{ .pos = .{ px1, py0 }, .uv = .{ ux1, vy0 }, .color = col, .mode = mode }; count.* += 1;
    verts[count.*] = .{ .pos = .{ px0, py1 }, .uv = .{ ux0, vy1 }, .color = col, .mode = mode }; count.* += 1;
    verts[count.*] = .{ .pos = .{ px1, py0 }, .uv = .{ ux1, vy0 }, .color = col, .mode = mode }; count.* += 1;
    verts[count.*] = .{ .pos = .{ px1, py1 }, .uv = .{ ux1, vy1 }, .color = col, .mode = mode }; count.* += 1;
    verts[count.*] = .{ .pos = .{ px0, py1 }, .uv = .{ ux0, vy1 }, .color = col, .mode = mode }; count.* += 1;
}
