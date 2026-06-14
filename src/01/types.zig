//! 01 — Platform spike — types.zig (implementation)
//!
//! Contract (INV-5.1): public method signatures match docs/specs/01.types.zig exactly.
//! Internal field layout of Platform and VulkanBackend is implementation-defined.
//! Depends only on std, GLFW, and the Vulkan loader (INV-5.6).

const std = @import("std");
const builtin = @import("builtin");
const shaders = @import("embedded_shaders");
const surface_vulkan = @import("surface_vulkan.zig");

const c = @cImport({
    @cDefine("GLFW_INCLUDE_VULKAN", "1");
    @cInclude("GLFW/glfw3.h");
    if (builtin.os.tag == .windows) {
        @cDefine("GLFW_EXPOSE_NATIVE_WIN32", "1");
        @cInclude("GLFW/glfw3native.h");
        @cInclude("windows.h");
        @cInclude("commdlg.h");
        @cInclude("shellapi.h");
        @cInclude("winreg.h");
    }
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

pub const BackendKind = enum { vulkan, metal, dx12, webgpu };

pub const Surface = union(BackendKind) {
    vulkan: *anyopaque,   // VkSurfaceKHR
    metal: *anyopaque,    // CAMetalLayer (deferred to RJ2)
    dx12: *anyopaque,     // HWND + IDXGISwapChain (deferred to RJ3)
    webgpu: *anyopaque,   // WGPUSurface or canvas (deferred to RJ4)
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

// ---------------------------------------------------------------------------
// Input event vocabulary (R11) — defined here (module 01) so module 09 and
// the app layer can re-export without an upward import (same pattern as DrawCommand).
// ---------------------------------------------------------------------------

pub const MouseButton = enum { left, right, middle };
pub const InputAction = enum { press, release };
pub const Key = enum {
    enter,
    escape,
    tab,
    backspace,
    delete,
    left,
    right,
    up,
    down,
    home,
    end,
    page_up,
    page_down,
    left_shift,
    right_shift,
    left_ctrl,
    right_ctrl,
    left_alt,
    right_alt,
    f1,
    f2,
    f3,
    f4,
    f5,
    f6,
    f7,
    f8,
    f9,
    f10,
    f11,
    f12,
    // Printable keys needed for text editing and clipboard shortcuts (R32, R33, R34)
    space,
    a,
    c,
    v,
    x,
    z,
    other,
};
pub const Modifiers = packed struct {
    shift: bool = false,
    ctrl: bool = false,
    alt: bool = false,
    super: bool = false,
};
pub const InputEvent = union(enum) {
    mouse_move: struct { x: f32, y: f32 },
    mouse_button: struct { button: MouseButton, action: InputAction, x: f32, y: f32 },
    /// RB3 — Synthesized by dispatchEvents; never pushed directly by GLFW callbacks.
    mouse_button_double: struct { button: MouseButton, x: f32, y: f32 },
    scroll: struct { dx: f32, dy: f32 },
    /// RB5 — Synthesized from trackpad fractional scroll input.
    gesture_swipe: struct { dx: f32, dy: f32 },
    /// RB5 — Synthesized when |dy| > PINCH_THRESHOLD with dx==0. scale_delta > 1 = zoom in.
    gesture_pinch: struct { scale_delta: f32 },
    key: struct { key: Key, action: InputAction, mods: Modifiers },
    char: struct { codepoint: u21 },
};

/// RB5 — Scale factor applied to trackpad swipe deltas to match scroll-wheel step sizes.
pub const SWIPE_SCALE: f32 = 20;
/// RB5 — |dy| threshold above which a scroll event is treated as a pinch gesture.
pub const PINCH_THRESHOLD: f32 = 5.0;
/// RB5 — Scaling factor mapping dy to pinch scale_delta (5% per unit).
pub const PINCH_SCALE: f32 = 0.05;

/// RB0 — OS cursor shapes available via glfwCreateStandardCursor.
pub const CursorShape = enum {
    arrow,       // GLFW_ARROW_CURSOR
    text_beam,   // GLFW_IBEAM_CURSOR
    crosshair,   // GLFW_CROSSHAIR_CURSOR
    hand,        // GLFW_POINTING_HAND_CURSOR
    resize_ew,   // GLFW_RESIZE_EW_CURSOR   (horizontal resize)
    resize_ns,   // GLFW_RESIZE_NS_CURSOR   (vertical resize)
    resize_all,  // GLFW_RESIZE_ALL_CURSOR  (move/drag)
    not_allowed, // GLFW_NOT_ALLOWED_CURSOR
};

/// Function pointer type for pushing an InputEvent into a queue (R11).
/// The app layer provides this; module 01 stores it in GlfwCallbackContext.
pub const PushEventFn = *const fn (queue: *anyopaque, event: InputEvent) void;

/// Packed context for all GLFW window user-pointer callbacks.
/// glfwSetWindowUserPointer is called exactly once per window and always points here.
pub const GlfwCallbackContext = struct {
    /// EventQueue opaque pointer — set by Platform.setEventQueue.
    event_queue: ?*anyopaque = null,
    /// Function called to push an InputEvent into the queue.
    push_fn: ?PushEventFn = null,
    /// Framebuffer resize callback — set by Platform.setFramebufferSizeCallback.
    resize_cb: ?*const fn (user_data: *anyopaque, size: Extent2D) void = null,
    resize_ud: ?*anyopaque = null,
};

const PlatformImpl = struct {
    window: *c.GLFWwindow,
    allocator: std.mem.Allocator,
    /// Packed callback context — glfwSetWindowUserPointer points here (R11 + R12).
    callback_ctx: GlfwCallbackContext = .{},
    /// RB0 — Cursor cache. Indexed by CursorShape ordinal. null = not yet created.
    cursor_cache: [8]?*c.GLFWcursor = [_]?*c.GLFWcursor{null} ** 8,
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
    device_properties: c.VkPhysicalDeviceProperties = .{},

    /// Present mode selected at init (R13). Reused on swapchain recreation — never re-queried.
    present_mode: c.VkPresentModeKHR = c.VK_PRESENT_MODE_FIFO_KHR,

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

    // M13-03 RD2 — Subpixel atlas GPU handles (RGBA8 texture at binding=1).
    subpixel_atlas_image: c.VkImage = null,
    subpixel_atlas_view: c.VkImageView = null,
    subpixel_atlas_sampler: c.VkSampler = null,
    subpixel_atlas_mem: c.VkDeviceMemory = null,
    /// 1x1 RGBA8 black dummy used for binding=1 when no subpixel atlas is active.
    dummy_subpixel_image: c.VkImage = null,
    dummy_subpixel_view: c.VkImageView = null,
    dummy_subpixel_sampler: c.VkSampler = null,
    dummy_subpixel_mem: c.VkDeviceMemory = null,

    // M13-04 RD3 — SDF icon atlas GPU handles (R8_UNORM texture at binding=2).
    sdf_atlas_image: c.VkImage = null,
    sdf_atlas_view: c.VkImageView = null,
    sdf_atlas_sampler: c.VkSampler = null,
    sdf_atlas_mem: c.VkDeviceMemory = null,
    /// 1x1 R8 black dummy used for binding=2 when no SDF atlas is active.
    dummy_sdf_image: c.VkImage = null,
    dummy_sdf_view: c.VkImageView = null,
    dummy_sdf_sampler: c.VkSampler = null,
    dummy_sdf_mem: c.VkDeviceMemory = null,
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
    /// M13-03 RD2 — shader mode: 1 = grayscale atlas, 3 = subpixel atlas.
    mode: u32 = 1,
};

/// Integer pixel rect used for scissor (R42). Origin top-left, exclusive right/bottom.
pub const ScissorRect = struct {
    x: i32,
    y: i32,
    w: u32,
    h: u32,
};

/// Image/icon draw command (R43).
pub const ImageCmd = struct {
    dst: Rect09,
    uv: Rect09,
    tint: Color09,
};

/// M13-01 RD0 — Gradient direction for gradient_rect draw commands.
pub const GradientDirection = enum(u32) {
    right = 0,
    bottom = 1,
    bottom_right = 2,
};

/// M13-01 RD0 — Two-stop linear gradient fill.
pub const GradientRect = struct {
    rect: Rect09,
    color_a: Color09, // left/top color
    color_b: Color09, // right/bottom color
    direction: GradientDirection,
};

/// M13-05 RD4 — Anti-aliased filled circle draw command.
pub const CircleCmd = struct {
    center_x: f32,
    center_y: f32,
    radius: f32,
    color: Color09,
};

/// M13-04 RD3 — SDF icon draw command.
/// Renders an icon from the SDF atlas at binding=2 using shader mode 4.
pub const SdfIconCmd = struct {
    dst: Rect09,    // screen-space destination rect
    uv: Rect09,     // UV region in the SDF atlas texture (0-1 normalized)
    color: Color09, // icon fill color
};

/// M13-02 RD1 — Rounded content clipping parameters.
/// Screen-space pixel rect + four corner radii (tl, tr, br, bl).
pub const ClipRounded = struct {
    rect: Rect09,
    radius_tl: f32,
    radius_tr: f32,
    radius_br: f32,
    radius_bl: f32,
};

pub const DrawCommand = union(enum) {
    filled_rect: FilledRect,
    border_rect: BorderRect,
    glyph: GlyphCmd,
    set_scissor: ScissorRect, // R42
    restore_scissor: void, // R42
    image_rect: ImageCmd, // R43
    gradient_rect: GradientRect, // M13-01 RD0
    aa_filled_rect: FilledRect, // M13-05 RD4 — anti-aliased filled rect (mode 5)
    aa_filled_circle: CircleCmd, // M13-05 RD4 — anti-aliased filled circle (mode 6)
    clip_rounded_begin: ClipRounded, // M13-02 RD1
    clip_rounded_end: void, // M13-02 RD1
    sdf_icon: SdfIconCmd, // M13-04 RD3
};

/// Opaque handle to a GPU texture atlas (used by GpuBackend.drawFrame).
/// Defined here (mod01) so VulkanBackend and mod10 share the same nominal type
/// without a circular dependency (mod10 re-exports these from mod01).
pub const AtlasHandle = struct { backend_obj: *anyopaque };

/// Three atlas handles passed to drawFrame: glyph, SDF icon, and image atlases.
pub const AtlasHandles = struct {
    glyph: AtlasHandle,
    sdf: AtlasHandle,
    image: AtlasHandle,
};

pub const QuadVertex = extern struct {
    pos: [2]f32,
    uv: [2]f32,
    color: [4]u8,
    color_b: [4]u8, // M13-01 RD0 — second gradient stop color
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

/// M13-04 RD3 — GPU-side SDF icon atlas handle.
pub const GpuSdfAtlas = struct {
    image: ?*anyopaque = null,
    image_view: ?*anyopaque = null,
    sampler: ?*anyopaque = null,
    memory: ?*anyopaque = null,
    width: u32 = 0,
    height: u32 = 0,

    pub fn deinit(self: *GpuSdfAtlas, device: *anyopaque) void {
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
    const stg_type = findMemTypeLocal(phys, stg_req.memoryTypeBits, c.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | c.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT) orelse return error.GpuUploadFailed;

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
    const img_type = findMemTypeLocal(phys, ir.memoryTypeBits, c.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT) orelse return error.GpuUploadFailed;

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
// RF3 — OS color-scheme detection (M16-04).
// ---------------------------------------------------------------------------

/// The OS-reported user preference for light or dark UI.
pub const ColorScheme = enum {
    light,
    dark,
    /// The OS preference could not be determined; use the app default.
    unknown,
};

// ---------------------------------------------------------------------------
// RF1/RF2 — Native file dialogs (M16-02, M16-03).
// ---------------------------------------------------------------------------

/// A single file-type filter entry for the file dialog.
/// Example: .{ .name = "PNG images", .pattern = "*.png" }
pub const FileDialogFilter = struct {
    name: []const u8,    // human-readable label shown in the filter dropdown
    pattern: []const u8, // glob pattern, e.g. "*.png" or "*.zig"
};

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
        // RB0: Destroy cached cursors before destroying the window.
        for (&impl.cursor_cache) |*slot| {
            if (slot.*) |cur| {
                c.glfwDestroyCursor(cur);
                slot.* = null;
            }
        }
        c.glfwDestroyWindow(impl.window);
        c.glfwTerminate();
        impl.allocator.destroy(impl);
    }

    /// RB0 — Change the OS cursor displayed over the GLFW window.
    /// Cursor objects are created on first use and cached for the window's lifetime.
    pub fn setCursor(self: *Platform, shape: CursorShape) void {
        const impl: *PlatformImpl = @ptrCast(@alignCast(self._impl));
        const idx = @intFromEnum(shape);
        if (impl.cursor_cache[idx] == null) {
            const cursor_shape: c_int = switch (shape) {
                .arrow       => c.GLFW_ARROW_CURSOR,
                .text_beam   => c.GLFW_IBEAM_CURSOR,
                .crosshair   => c.GLFW_CROSSHAIR_CURSOR,
                .hand        => c.GLFW_POINTING_HAND_CURSOR,
                .resize_ew   => c.GLFW_RESIZE_EW_CURSOR,
                .resize_ns   => c.GLFW_RESIZE_NS_CURSOR,
                .resize_all  => c.GLFW_RESIZE_ALL_CURSOR,
                .not_allowed => c.GLFW_NOT_ALLOWED_CURSOR,
            };
            impl.cursor_cache[idx] = c.glfwCreateStandardCursor(cursor_shape);
        }
        c.glfwSetCursor(impl.window, impl.cursor_cache[idx]);
    }

    pub fn shouldClose(self: *Platform) bool {
        const impl: *PlatformImpl = @ptrCast(@alignCast(self._impl));
        return c.glfwWindowShouldClose(impl.window) != c.GLFW_FALSE;
    }

    pub fn pollEvents(self: *Platform) void {
        _ = self;
        c.glfwPollEvents();
    }

    /// Block the calling thread until the OS delivers at least one windowing or
    /// input event, then return. Wraps glfwWaitEvents.
    /// Call only from the main thread (GLFW requirement).
    pub fn waitEvents(self: *Platform) void {
        _ = self;
        c.glfwWaitEvents();
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

    /// Create a platform surface for the specified backend (RJ5).
    /// `instance` is backend-specific (VkInstance for Vulkan, null for deferred backends).
    /// Returns a union(BackendKind) tagged with the surface handle.
    /// Dispatch per backend is handled by the surface layer files (RJ2 extraction):
    ///   src/01/surface_vulkan.zig — VkSurfaceKHR creation
    ///   src/01/surface_macos.zig  — CAMetalLayer (RJ2, not yet implemented)
    ///   src/01/surface_win32.zig  — HWND/DXGI   (RJ3, not yet implemented)
    ///   src/01/surface_web.zig    — <canvas>     (RJ4, not yet implemented)
    pub fn createSurface(self: *Platform, backend: BackendKind, instance: ?*anyopaque) PlatformError!Surface {
        return switch (backend) {
            .vulkan => {
                const impl: *PlatformImpl = @ptrCast(@alignCast(self._impl));
                const handle = try surface_vulkan.createVulkanSurface(@ptrCast(impl.window), instance);
                return Surface{ .vulkan = handle };
            },
            .metal  => return error.SurfaceCreationFailed, // Deferred to RJ2 (surface_macos.zig)
            .dx12   => return error.SurfaceCreationFailed, // Deferred to RJ3 (surface_win32.zig)
            .webgpu => return error.SurfaceCreationFailed, // Deferred to RJ4 (surface_web.zig)
        };
    }

    // -----------------------------------------------------------------------
    // R11 / R12 — event queue + framebuffer resize callback (added here)
    // -----------------------------------------------------------------------

    /// Register the event queue that GLFW callbacks will push into (R11).
    /// `queue` is an opaque pointer to EventQueue; `push_fn` is called to push events.
    /// Installs cursor-pos, mouse-button, scroll, key, and char callbacks.
    /// Uses glfwSetWindowUserPointer — shares the packed context with setFramebufferSizeCallback.
    pub fn setEventQueue(self: *Platform, queue: *anyopaque, push_fn: PushEventFn) void {
        const impl: *PlatformImpl = @ptrCast(@alignCast(self._impl));
        impl.callback_ctx.event_queue = queue;
        impl.callback_ctx.push_fn = push_fn;
        // Point the window user-pointer to the packed context (shared with resize callback).
        c.glfwSetWindowUserPointer(impl.window, &impl.callback_ctx);

        // Install all five input callbacks.
        _ = c.glfwSetCursorPosCallback(impl.window, glfwCursorPosCallback);
        _ = c.glfwSetMouseButtonCallback(impl.window, glfwMouseButtonCallback);
        _ = c.glfwSetScrollCallback(impl.window, glfwScrollCallback);
        _ = c.glfwSetKeyCallback(impl.window, glfwKeyCallback);
        _ = c.glfwSetCharCallback(impl.window, glfwCharCallback);
    }

    /// Return the current cursor position in screen pixels (top-left origin) (R11).
    pub fn cursorPos(self: *Platform) struct { x: f32, y: f32 } {
        const impl: *PlatformImpl = @ptrCast(@alignCast(self._impl));
        var xpos: f64 = 0;
        var ypos: f64 = 0;
        c.glfwGetCursorPos(impl.window, &xpos, &ypos);
        return .{ .x = @floatCast(xpos), .y = @floatCast(ypos) };
    }

    /// Install a framebuffer-resize callback (R12).
    /// `user_data` is stored in the packed GlfwCallbackContext alongside the event queue.
    /// glfwSetWindowUserPointer must already have been set by setEventQueue, or will be
    /// set here if not yet done.
    pub fn setFramebufferSizeCallback(
        self: *Platform,
        user_data: *anyopaque,
        callback: *const fn (user_data: *anyopaque, size: Extent2D) void,
    ) void {
        const impl: *PlatformImpl = @ptrCast(@alignCast(self._impl));
        impl.callback_ctx.resize_cb = callback;
        impl.callback_ctx.resize_ud = user_data;
        // Ensure the window user-pointer points to our context (idempotent if already set).
        c.glfwSetWindowUserPointer(impl.window, &impl.callback_ctx);
        _ = c.glfwSetFramebufferSizeCallback(impl.window, glfwFramebufferSizeCallback);
    }

    /// Set the system clipboard to the given text (R36).
    /// Text is null-terminated and copied via GLFW; ownership remains with the caller.
    pub fn setClipboard(self: *Platform, text: []const u8) void {
        const impl: *PlatformImpl = @ptrCast(@alignCast(self._impl));
        // Heap-allocate a null-terminated copy (C6: no stack buffer limit).
        const z_str = impl.allocator.dupeZ(u8, text) catch return;
        defer impl.allocator.free(z_str);
        c.glfwSetClipboardString(impl.window, z_str.ptr);
    }

    /// Get the current system clipboard content as a UTF-8 string (R36).
    /// Returns an allocated string (caller owns, must free), or null if empty/non-UTF-8.
    pub fn getClipboard(self: *Platform, allocator: std.mem.Allocator) ?[]u8 {
        const impl: *PlatformImpl = @ptrCast(@alignCast(self._impl));
        const c_str = c.glfwGetClipboardString(impl.window) orelse return null;
        const len = std.mem.len(c_str);
        if (len == 0) return null;
        const result = allocator.alloc(u8, len) catch return null;
        @memcpy(result, c_str[0..len]);
        // C7: validate UTF-8; return null for non-UTF-8 content.
        if (!std.unicode.utf8ValidateSlice(result)) {
            allocator.free(result);
            return null;
        }
        return result;
    }

    /// RD5: Query the primary monitor's content scale factor.
    /// Returns 1.0 when no monitor is connected (headless / CI).
    /// The app uses this value to multiply all logical px values so the UI
    /// renders at the correct physical pixel density on HiDPI displays.
    pub fn contentScale(self: *Platform) f32 {
        _ = self;
        const monitor = c.glfwGetPrimaryMonitor();
        if (monitor == null) return 1.0;
        var scale_x: f32 = 1.0;
        var scale_y: f32 = 1.0;
        c.glfwGetMonitorContentScale(monitor, &scale_x, &scale_y);
        return @max(scale_x, scale_y);
    }

    // -----------------------------------------------------------------------
    // RF3 — OS color-scheme detection (M16-04).
    // -----------------------------------------------------------------------

    /// Read the OS current color-scheme preference.
    /// Call this once at startup before the first frame.
    /// Returns .light, .dark, or .unknown.
    /// Does NOT register a system listener — call again to refresh if needed.
    pub fn getColorScheme(self: *const Platform) ColorScheme {
        _ = self;
        if (comptime builtin.os.tag == .windows) {
            // Registry path:
            //   HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize
            //   Value name: AppsUseLightTheme (REG_DWORD)
            //   0 = dark mode, 1 = light mode, absent = unknown
            // Win32 predefined HKEY constants (e.g. HKEY_CURRENT_USER = 0x80000001) are
            // magic unaligned pointer values. Zig's @ptrFromInt rejects them because the
            // target HKEY type has alignment > 1. Work around by calling the registry
            // functions via extern declarations that accept *anyopaque for the hkey param.
            const RegOpenFn = *const fn (*anyopaque, [*:0]const u16, c.DWORD, c.REGSAM, *c.HKEY) callconv(.c) c.LONG;
            const RegQueryFn = *const fn (c.HKEY, [*:0]const u16, ?*c.DWORD, ?*c.DWORD, ?*c.BYTE, ?*c.DWORD) callconv(.c) c.LONG;
            const regOpen: RegOpenFn = @ptrCast(&c.RegOpenKeyExW);
            const regQuery: RegQueryFn = @ptrCast(&c.RegQueryValueExW);
            // HKCU = 0x80000001 as a *anyopaque — alignment 1, valid for this cast.
            const hkcu: *anyopaque = @ptrFromInt(0x80000001);
            var hkey: c.HKEY = undefined;
            const key_path = std.unicode.utf8ToUtf16LeStringLiteral("SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize");
            if (regOpen(hkcu, key_path, 0, c.KEY_READ, &hkey) != 0) {
                return .unknown;
            }
            defer _ = c.RegCloseKey(hkey);

            var data: c.DWORD = 0;
            var data_size: c.DWORD = @sizeOf(c.DWORD);
            var reg_type: c.DWORD = 0;
            const value_name = std.unicode.utf8ToUtf16LeStringLiteral("AppsUseLightTheme");
            const query_result = regQuery(
                hkey,
                value_name,
                null,
                &reg_type,
                @ptrCast(&data),
                &data_size,
            );
            if (query_result != 0) return .unknown;
            return if (data == 0) .dark else .light;
        } else {
            // Linux: check environment variables.
            const gtk_theme = std.posix.getenv("GTK_THEME") orelse "";
            if (std.mem.endsWith(u8, gtk_theme, ":dark")) return .dark;
            if (std.mem.endsWith(u8, gtk_theme, ":light")) return .light;

            // KDE hint via COLORFGBG: dark bg is "15;default;0" (ends with ";0")
            const colorfgbg = std.posix.getenv("COLORFGBG") orelse "";
            if (std.mem.endsWith(u8, colorfgbg, ";0")) return .dark;

            return .unknown;
        }
    }

    // -----------------------------------------------------------------------
    // RF1 — Native file-open dialog (M16-02).
    // -----------------------------------------------------------------------

    /// Display the native file-open dialog.
    ///
    /// `filters`    — slice of FileDialogFilter entries (may be empty for "all files").
    /// `allocator`  — used to allocate the returned path string.
    ///
    /// Returns an allocator-owned UTF-8 path string, or null if:
    ///   - the user cancelled,
    ///   - no file was selected,
    ///   - or (Linux stub) the platform does not support native dialogs yet.
    ///
    /// Caller must free the returned slice with `allocator.free(path)`.
    /// Blocking: does not return until the dialog is dismissed.
    pub fn showOpenDialog(
        self: *Platform,
        filters: []const FileDialogFilter,
        allocator: std.mem.Allocator,
    ) ?[]u8 {
        if (comptime builtin.os.tag == .windows) {
            return showOpenDialogWin32(self, filters, allocator);
        } else {
            @compileLog("showOpenDialog: GTK not yet approved (INV-5.6) — returns null on Linux");
            return null;
        }
    }

    // -----------------------------------------------------------------------
    // RF2 — Native file-save dialog (M16-03).
    // -----------------------------------------------------------------------

    /// Display the native file-save dialog.
    ///
    /// `default_name` — initial filename pre-filled in the filename field (may be empty).
    /// `filters`      — slice of FileDialogFilter entries (may be empty for "all files").
    /// `allocator`    — used to allocate the returned path string.
    ///
    /// Returns an allocator-owned UTF-8 path string, or null if:
    ///   - the user cancelled,
    ///   - or (Linux stub) the platform does not support native dialogs yet.
    ///
    /// Caller must free the returned slice with `allocator.free(path)`.
    /// Blocking: does not return until the dialog is dismissed.
    pub fn showSaveDialog(
        self: *Platform,
        default_name: []const u8,
        filters: []const FileDialogFilter,
        allocator: std.mem.Allocator,
    ) ?[]u8 {
        if (comptime builtin.os.tag == .windows) {
            return showSaveDialogWin32(self, default_name, filters, allocator);
        } else {
            return null;
        }
    }

    // -----------------------------------------------------------------------
    // RF4 — MIME clipboard (M16-05).
    // -----------------------------------------------------------------------

    /// Write data of a specific MIME type to the system clipboard.
    ///
    /// `mime_type` — MIME type string, e.g. "text/plain", "text/html", "image/png".
    /// `data`      — raw bytes to place on the clipboard.
    ///
    /// On Windows, MIME types are mapped to Win32 clipboard formats:
    ///   "text/plain"       → CF_UNICODETEXT (data is interpreted as UTF-8, converted to UTF-16)
    ///   "text/html"        → registered custom format "HTML Format"
    ///   any other MIME     → RegisterClipboardFormatA(mime_type) → custom format
    ///
    /// On Linux (GLFW): only "text/plain" is supported; all other types are no-ops.
    pub fn setClipboardMime(
        self: *Platform,
        mime_type: []const u8,
        data: []const u8,
    ) void {
        if (comptime builtin.os.tag == .windows) {
            setClipboardMimeWin32(self, mime_type, data);
        } else {
            if (std.mem.eql(u8, mime_type, "text/plain")) {
                self.setClipboard(data);
            }
            // All other MIME types: no-op on Linux.
        }
    }

    /// Read data of a specific MIME type from the system clipboard.
    ///
    /// `mime_type`  — MIME type string to request, e.g. "text/html".
    /// `buf`        — caller-supplied buffer to receive the data.
    ///
    /// Returns a slice of `buf` containing the clipboard data, or null if:
    ///   - the clipboard does not contain data of the requested MIME type,
    ///   - the data is larger than `buf`,
    ///   - or (Linux) the requested MIME type is not "text/plain".
    pub fn getClipboardMime(
        self: *Platform,
        mime_type: []const u8,
        buf: []u8,
    ) ?[]const u8 {
        if (builtin.os.tag == .windows) {
            return getClipboardMimeWin32(self, mime_type, buf);
        } else {
            const impl: *PlatformImpl = @ptrCast(@alignCast(self._impl));
            if (std.mem.eql(u8, mime_type, "text/plain")) {
                const raw = c.glfwGetClipboardString(impl.window) orelse return null;
                const len = std.mem.len(raw);
                if (len > buf.len) return null;
                @memcpy(buf[0..len], raw[0..len]);
                return buf[0..len];
            }
            return null;
        }
    }
};

// ---------------------------------------------------------------------------
// ---------------------------------------------------------------------------
// RF1 Win32 — showOpenDialog implementation
// ---------------------------------------------------------------------------

fn buildWideFilterString(filters: []const FileDialogFilter, buf: []u16) usize {
    var pos: usize = 0;
    for (filters) |f| {
        // name\0
        const name_wide_len = std.unicode.calcUtf16LeLen(f.name) catch f.name.len;
        if (pos + name_wide_len + 1 > buf.len) break;
        const name_written = std.unicode.utf8ToUtf16Le(buf[pos..], f.name) catch 0;
        pos += name_written;
        buf[pos] = 0;
        pos += 1;
        // pattern\0
        const pat_wide_len = std.unicode.calcUtf16LeLen(f.pattern) catch f.pattern.len;
        if (pos + pat_wide_len + 1 > buf.len) break;
        const pat_written = std.unicode.utf8ToUtf16Le(buf[pos..], f.pattern) catch 0;
        pos += pat_written;
        buf[pos] = 0;
        pos += 1;
    }
    // Terminating null (double-null at end).
    if (pos < buf.len) {
        buf[pos] = 0;
        pos += 1;
    }
    return pos;
}

fn wideToUtf8Alloc(wide: [*:0]const u16, allocator: std.mem.Allocator) ?[]u8 {
    if (builtin.os.tag != .windows) return null;
    const wide_len = std.mem.len(wide);
    if (wide_len == 0) return null;
    // Calculate required UTF-8 buffer length via WideCharToMultiByte.
    const needed = c.WideCharToMultiByte(c.CP_UTF8, 0, wide, @intCast(wide_len), null, 0, null, null);
    if (needed <= 0) return null;
    const buf = allocator.alloc(u8, @intCast(needed)) catch return null;
    const written = c.WideCharToMultiByte(c.CP_UTF8, 0, wide, @intCast(wide_len), buf.ptr, needed, null, null);
    if (written <= 0) {
        allocator.free(buf);
        return null;
    }
    return buf[0..@intCast(written)];
}

fn utf8ToWide(src: []const u8, out: []u16) usize {
    if (src.len == 0) return 0;
    if (builtin.os.tag != .windows) return 0;
    const written = c.MultiByteToWideChar(c.CP_UTF8, 0, src.ptr, @intCast(src.len), out.ptr, @intCast(out.len));
    if (written <= 0) return 0;
    return @intCast(written);
}

fn showOpenDialogWin32(
    self: *Platform,
    filters: []const FileDialogFilter,
    allocator: std.mem.Allocator,
) ?[]u8 {
    const impl: *PlatformImpl = @ptrCast(@alignCast(self._impl));
    const hwnd = c.glfwGetWin32Window(impl.window);

    // Build filter string: "Name\0*.ext\0\0"
    var filter_buf: [4096]u16 = undefined;
    const filter_len = buildWideFilterString(filters, &filter_buf);
    const filter_ptr: ?[*:0]const u16 = if (filter_len > 0) @ptrCast(filter_buf[0..filter_len].ptr) else null;

    var file_buf: [c.MAX_PATH + 1]u16 = undefined;
    @memset(&file_buf, 0);

    var ofn = std.mem.zeroes(c.OPENFILENAMEW);
    ofn.lStructSize = @sizeOf(c.OPENFILENAMEW);
    ofn.hwndOwner = hwnd;
    ofn.lpstrFilter = filter_ptr;
    ofn.lpstrFile = @ptrCast(&file_buf);
    ofn.nMaxFile = c.MAX_PATH;
    ofn.Flags = c.OFN_FILEMUSTEXIST | c.OFN_PATHMUSTEXIST;

    if (c.GetOpenFileNameW(&ofn) == 0) return null;

    return wideToUtf8Alloc(@ptrCast(&file_buf), allocator);
}

fn showSaveDialogWin32(
    self: *Platform,
    default_name: []const u8,
    filters: []const FileDialogFilter,
    allocator: std.mem.Allocator,
) ?[]u8 {
    const impl: *PlatformImpl = @ptrCast(@alignCast(self._impl));
    const hwnd = c.glfwGetWin32Window(impl.window);

    // Build filter string.
    var filter_buf: [4096]u16 = undefined;
    const filter_len = buildWideFilterString(filters, &filter_buf);
    const filter_ptr: ?[*:0]const u16 = if (filter_len > 0) @ptrCast(filter_buf[0..filter_len].ptr) else null;

    // Pre-fill szFile with default_name converted to wide chars.
    var file_buf: [c.MAX_PATH + 1]u16 = undefined;
    @memset(&file_buf, 0);
    if (default_name.len > 0) {
        _ = utf8ToWide(default_name, &file_buf);
    }

    var ofn = std.mem.zeroes(c.OPENFILENAMEW);
    ofn.lStructSize = @sizeOf(c.OPENFILENAMEW);
    ofn.hwndOwner = hwnd;
    ofn.lpstrFilter = filter_ptr;
    ofn.lpstrFile = @ptrCast(&file_buf);
    ofn.nMaxFile = c.MAX_PATH;
    ofn.Flags = c.OFN_OVERWRITEPROMPT; // no OFN_FILEMUSTEXIST — save target may not exist

    if (c.GetSaveFileNameW(&ofn) == 0) return null;

    return wideToUtf8Alloc(@ptrCast(&file_buf), allocator);
}

// ---------------------------------------------------------------------------
// RF4 Win32 — MIME clipboard implementation
// ---------------------------------------------------------------------------

fn mimeToClipboardFormat(mime_type: []const u8) c.UINT {
    if (std.mem.eql(u8, mime_type, "text/plain")) return c.CF_UNICODETEXT;
    if (std.mem.eql(u8, mime_type, "text/html")) {
        return c.RegisterClipboardFormatA("HTML Format");
    }
    // For all other MIME types: register a custom Win32 format by the MIME string.
    // RegisterClipboardFormatA is idempotent — returns the same UINT for the same string.
    var cbuf: [256]u8 = undefined;
    const len = @min(mime_type.len, cbuf.len - 1);
    @memcpy(cbuf[0..len], mime_type[0..len]);
    cbuf[len] = 0;
    return c.RegisterClipboardFormatA(&cbuf[0]);
}

fn setClipboardMimeWin32(
    self: *Platform,
    mime_type: []const u8,
    data: []const u8,
) void {
    // "text/plain" delegates to the existing R36 setClipboard (UTF-8 → CF_UNICODETEXT).
    if (std.mem.eql(u8, mime_type, "text/plain")) {
        self.setClipboard(data);
        return;
    }
    const fmt = mimeToClipboardFormat(mime_type);
    if (fmt == 0) return;

    if (c.OpenClipboard(null) == 0) return;
    defer _ = c.CloseClipboard();
    _ = c.EmptyClipboard();

    const hMem = c.GlobalAlloc(c.GMEM_MOVEABLE, data.len);
    if (hMem == null) return;

    const ptr = c.GlobalLock(hMem);
    if (ptr == null) {
        _ = c.GlobalFree(hMem);
        return;
    }
    @memcpy(@as([*]u8, @ptrCast(ptr))[0..data.len], data);
    _ = c.GlobalUnlock(hMem);
    _ = c.SetClipboardData(fmt, hMem);
    // Clipboard takes ownership of hMem on success; do not free.
}

fn getClipboardMimeWin32(
    self: *Platform,
    mime_type: []const u8,
    buf: []u8,
) ?[]const u8 {
    // "text/plain": use existing getClipboard logic via CF_UNICODETEXT.
    if (std.mem.eql(u8, mime_type, "text/plain")) {
        // Re-use glfwGetClipboardString for the plain-text fast path.
        const impl: *PlatformImpl = @ptrCast(@alignCast(self._impl));
        const raw = c.glfwGetClipboardString(impl.window) orelse return null;
        const len = std.mem.len(raw);
        if (len > buf.len) return null;
        @memcpy(buf[0..len], raw[0..len]);
        return buf[0..len];
    }
    const fmt = mimeToClipboardFormat(mime_type);
    if (fmt == 0) return null;

    if (c.OpenClipboard(null) == 0) return null;
    defer _ = c.CloseClipboard();

    const hMem = c.GetClipboardData(fmt);
    if (hMem == null) return null;

    const ptr = c.GlobalLock(hMem);
    if (ptr == null) return null;
    defer _ = c.GlobalUnlock(hMem);

    const data_len = c.GlobalSize(hMem);
    if (data_len == 0 or data_len > buf.len) return null;

    @memcpy(buf[0..data_len], @as([*]const u8, @ptrCast(ptr))[0..data_len]);
    return buf[0..data_len];
}

// GLFW input callbacks (R11) — C calling convention required.
// ---------------------------------------------------------------------------

/// Convert a GLFW key code to our Key enum.
fn glfwKeyToKey(glfw_key: c_int) Key {
    return switch (glfw_key) {
        c.GLFW_KEY_ENTER, c.GLFW_KEY_KP_ENTER => .enter,
        c.GLFW_KEY_ESCAPE => .escape,
        c.GLFW_KEY_TAB => .tab,
        c.GLFW_KEY_BACKSPACE => .backspace,
        c.GLFW_KEY_DELETE => .delete,
        c.GLFW_KEY_LEFT => .left,
        c.GLFW_KEY_RIGHT => .right,
        c.GLFW_KEY_UP => .up,
        c.GLFW_KEY_DOWN => .down,
        c.GLFW_KEY_HOME => .home,
        c.GLFW_KEY_END => .end,
        c.GLFW_KEY_PAGE_UP => .page_up,
        c.GLFW_KEY_PAGE_DOWN => .page_down,
        c.GLFW_KEY_LEFT_SHIFT => .left_shift,
        c.GLFW_KEY_RIGHT_SHIFT => .right_shift,
        c.GLFW_KEY_LEFT_CONTROL => .left_ctrl,
        c.GLFW_KEY_RIGHT_CONTROL => .right_ctrl,
        c.GLFW_KEY_LEFT_ALT => .left_alt,
        c.GLFW_KEY_RIGHT_ALT => .right_alt,
        c.GLFW_KEY_F1 => .f1,
        c.GLFW_KEY_F2 => .f2,
        c.GLFW_KEY_F3 => .f3,
        c.GLFW_KEY_F4 => .f4,
        c.GLFW_KEY_F5 => .f5,
        c.GLFW_KEY_F6 => .f6,
        c.GLFW_KEY_F7 => .f7,
        c.GLFW_KEY_F8 => .f8,
        c.GLFW_KEY_F9 => .f9,
        c.GLFW_KEY_F10 => .f10,
        c.GLFW_KEY_F11 => .f11,
        c.GLFW_KEY_F12 => .f12,
        c.GLFW_KEY_SPACE => .space,
        c.GLFW_KEY_A => .a,
        c.GLFW_KEY_C => .c,
        c.GLFW_KEY_V => .v,
        c.GLFW_KEY_X => .x,
        c.GLFW_KEY_Z => .z,
        else => .other,
    };
}

fn glfwMods(mods: c_int) Modifiers {
    return .{
        .shift = (mods & c.GLFW_MOD_SHIFT) != 0,
        .ctrl = (mods & c.GLFW_MOD_CONTROL) != 0,
        .alt = (mods & c.GLFW_MOD_ALT) != 0,
        .super = (mods & c.GLFW_MOD_SUPER) != 0,
    };
}

fn glfwCursorPosCallback(
    window: ?*c.GLFWwindow,
    xpos: f64,
    ypos: f64,
) callconv(.c) void {
    const ctx: *GlfwCallbackContext = @ptrCast(@alignCast(
        c.glfwGetWindowUserPointer(window) orelse return,
    ));
    const q = ctx.event_queue orelse return;
    const push = ctx.push_fn orelse return;
    push(q, InputEvent{ .mouse_move = .{
        .x = @floatCast(xpos),
        .y = @floatCast(ypos),
    } });
}

fn glfwMouseButtonCallback(
    window: ?*c.GLFWwindow,
    button: c_int,
    action: c_int,
    _mods: c_int,
) callconv(.c) void {
    _ = _mods;
    const ctx: *GlfwCallbackContext = @ptrCast(@alignCast(
        c.glfwGetWindowUserPointer(window) orelse return,
    ));
    const q = ctx.event_queue orelse return;
    const push = ctx.push_fn orelse return;

    const btn: MouseButton = switch (button) {
        c.GLFW_MOUSE_BUTTON_LEFT => .left,
        c.GLFW_MOUSE_BUTTON_RIGHT => .right,
        c.GLFW_MOUSE_BUTTON_MIDDLE => .middle,
        else => return,
    };
    const act: InputAction = if (action == c.GLFW_PRESS) .press else .release;

    var xpos: f64 = 0;
    var ypos: f64 = 0;
    c.glfwGetCursorPos(window, &xpos, &ypos);

    push(q, InputEvent{ .mouse_button = .{
        .button = btn,
        .action = act,
        .x = @floatCast(xpos),
        .y = @floatCast(ypos),
    } });
}

fn glfwScrollCallback(
    window: ?*c.GLFWwindow,
    xoffset: f64,
    yoffset: f64,
) callconv(.c) void {
    const ctx: *GlfwCallbackContext = @ptrCast(@alignCast(
        c.glfwGetWindowUserPointer(window) orelse return,
    ));
    const q = ctx.event_queue orelse return;
    const push = ctx.push_fn orelse return;
    const dx: f32 = @floatCast(xoffset);
    const dy: f32 = @floatCast(yoffset);

    // RB5: Heuristic pinch detection — large |dy| with dx==0 and non-integer dy.
    // Check pinch before swipe so that large fractional-dy events map to pinch, not swipe.
    if (dx == 0 and @abs(dy) > PINCH_THRESHOLD) {
        const scale_delta: f32 = 1.0 + dy * PINCH_SCALE;
        push(q, InputEvent{ .gesture_pinch = .{ .scale_delta = scale_delta } });
        return;
    }

    // RB5: Swipe heuristic — fractional values or simultaneous x+y movement = trackpad swipe.
    const is_swipe = (dx != 0 and dy != 0)
        or (@floor(dy) != dy)
        or (@floor(dx) != dx);

    if (is_swipe) {
        push(q, InputEvent{ .gesture_swipe = .{ .dx = dx * SWIPE_SCALE, .dy = dy * SWIPE_SCALE } });
    } else {
        push(q, InputEvent{ .scroll = .{ .dx = dx, .dy = dy } });
    }
}

fn glfwKeyCallback(
    window: ?*c.GLFWwindow,
    key: c_int,
    _scancode: c_int,
    action: c_int,
    mods: c_int,
) callconv(.c) void {
    _ = _scancode;
    if (action == c.GLFW_REPEAT) {
        // Allow repeat only for text-editing keys (backspace, delete, arrows, home, end).
        switch (key) {
            c.GLFW_KEY_BACKSPACE, c.GLFW_KEY_DELETE, c.GLFW_KEY_LEFT, c.GLFW_KEY_RIGHT, c.GLFW_KEY_HOME, c.GLFW_KEY_END => {}, // fall through
            else => return,
        }
    }
    const ctx: *GlfwCallbackContext = @ptrCast(@alignCast(
        c.glfwGetWindowUserPointer(window) orelse return,
    ));
    const q = ctx.event_queue orelse return;
    const push = ctx.push_fn orelse return;
    const act: InputAction = if (action == c.GLFW_PRESS) .press else .release;
    push(q, InputEvent{ .key = .{
        .key = glfwKeyToKey(key),
        .action = act,
        .mods = glfwMods(mods),
    } });
}

fn glfwCharCallback(
    window: ?*c.GLFWwindow,
    codepoint: c_uint,
) callconv(.c) void {
    const ctx: *GlfwCallbackContext = @ptrCast(@alignCast(
        c.glfwGetWindowUserPointer(window) orelse return,
    ));
    const q = ctx.event_queue orelse return;
    const push = ctx.push_fn orelse return;
    push(q, InputEvent{ .char = .{ .codepoint = @intCast(codepoint) } });
}

fn glfwFramebufferSizeCallback(
    window: ?*c.GLFWwindow,
    width: c_int,
    height: c_int,
) callconv(.c) void {
    const ctx: *GlfwCallbackContext = @ptrCast(@alignCast(
        c.glfwGetWindowUserPointer(window) orelse return,
    ));
    const cb = ctx.resize_cb orelse return;
    const ud = ctx.resize_ud orelse return;
    cb(ud, Extent2D{
        .width = @intCast(@max(0, width)),
        .height = @intCast(@max(0, height)),
    });
}

// ---------------------------------------------------------------------------
// VulkanBackend — the only GPU backend (INV-2.1).
// ---------------------------------------------------------------------------

pub const VulkanBackend = struct {
    _impl: *anyopaque = undefined,

    /// R83 — true when this backend was created by initShared and does NOT own
    /// the VkDevice, VkPhysicalDevice, VkCommandPool, or VkQueue.
    /// deinit() skips device destruction when this flag is set.
    is_shared: bool = false,

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

        const surface_result = platform.createSurface(.vulkan, @ptrCast(impl.instance.?)) catch
            return BackendError.InstanceCreationFailed;
        impl.surface = @ptrCast(surface_result.vulkan);
        errdefer c.vkDestroySurfaceKHR(impl.instance, impl.surface, null);

        const pd = vkSelectPhysicalDevice(gpa, impl.instance, impl.surface) catch
            return BackendError.NoSuitableDevice;
        impl.physical_device = pd.physical_device;
        impl.graphics_family = pd.graphics_family;
        impl.present_family = pd.present_family;

        // Populate device properties for capabilities() method (RJ1).
        c.vkGetPhysicalDeviceProperties(impl.physical_device, &impl.device_properties);

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
        if (self.is_shared) {
            // R83: shared backend — only destroy surface-owned resources, NOT the device.
            // The primary backend that owns the device is responsible for destroying it.
            _ = c.vkDeviceWaitIdle(impl.device);
            c.vkDestroyPipeline(impl.device, impl.pipeline, null);
            c.vkDestroyPipelineLayout(impl.device, impl.pipeline_layout, null);
            vkDestroySyncObjects(impl);
            vkDestroyFramebuffers(impl);
            c.vkDestroyRenderPass(impl.device, impl.render_pass, null);
            vkDestroySwapchainResources(impl);
            // Do NOT destroy command pool, device, debug messenger, or instance.
            c.vkDestroySurfaceKHR(impl.instance, impl.surface, null);
            impl.allocator.destroy(impl);
            return;
        }
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

    /// R83 — Create a VulkanBackend that shares the device from `primary`.
    /// Only the surface + swapchain are created; device, command pool, and
    /// graphics queue are reused (not owned).
    ///
    /// The returned backend has `is_shared = true`. Its `deinit` will NOT
    /// destroy the device; call `primary.deinit()` separately when done.
    ///
    /// Note: Full GPU implementation is deferred (requires surfaceKHR creation
    /// for the secondary platform and swapchain setup). Returns error.Unimplemented
    /// until the GPU path is wired in.
    pub fn initShared(
        gpa: std.mem.Allocator,
        primary: *VulkanBackend,
        platform: *Platform,
    ) !VulkanBackend {
        _ = gpa;
        _ = primary;
        _ = platform;
        // Stub: full implementation requires creating a new VkSurfaceKHR for the
        // secondary platform and a new VkSwapchainKHR bound to it, while reusing
        // the primary's device, physical_device, command_pool, and graphics_queue.
        // Headless tests verify the is_shared flag path, not the GPU init path.
        return error.Unimplemented;
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

    /// Read the last rendered frame back to CPU memory and write it as a PNG.
    /// Must be called after endFrame() on the same frame.  Blocks until GPU idle.
    /// `pixels_rgba` receives raw RGBA bytes (width*height*4); caller must free.
    pub fn readbackFrameRgba(self: *VulkanBackend, gpa: std.mem.Allocator) ![]u8 {
        const impl: *VulkanImpl = @ptrCast(@alignCast(self._impl));
        const w = impl.swapchain_extent.width;
        const h = impl.swapchain_extent.height;
        if (w == 0 or h == 0) return error.ZeroSize;

        // Wait for GPU to finish all work.
        _ = c.vkDeviceWaitIdle(impl.device);

        const n_bytes: u64 = @as(u64, w) * h * 4;

        // Create host-visible staging buffer.
        var buf_info = std.mem.zeroes(c.VkBufferCreateInfo);
        buf_info.sType = c.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO;
        buf_info.size = n_bytes;
        buf_info.usage = c.VK_BUFFER_USAGE_TRANSFER_DST_BIT;
        buf_info.sharingMode = c.VK_SHARING_MODE_EXCLUSIVE;
        var staging_buf: c.VkBuffer = null;
        if (c.vkCreateBuffer(impl.device, &buf_info, null, &staging_buf) != c.VK_SUCCESS)
            return error.GpuReadbackFailed;
        defer c.vkDestroyBuffer(impl.device, staging_buf, null);

        var mem_req = std.mem.zeroes(c.VkMemoryRequirements);
        c.vkGetBufferMemoryRequirements(impl.device, staging_buf, &mem_req);

        var alloc_info = std.mem.zeroes(c.VkMemoryAllocateInfo);
        alloc_info.sType = c.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
        alloc_info.allocationSize = mem_req.size;
        alloc_info.memoryTypeIndex = findMemoryType(impl, mem_req.memoryTypeBits, c.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | c.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT) catch
            return error.GpuReadbackFailed;
        var staging_mem: c.VkDeviceMemory = null;
        if (c.vkAllocateMemory(impl.device, &alloc_info, null, &staging_mem) != c.VK_SUCCESS)
            return error.GpuReadbackFailed;
        defer c.vkFreeMemory(impl.device, staging_mem, null);
        _ = c.vkBindBufferMemory(impl.device, staging_buf, staging_mem, 0);

        // Record a one-shot command buffer.
        var cb_info = std.mem.zeroes(c.VkCommandBufferAllocateInfo);
        cb_info.sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO;
        cb_info.commandPool = impl.command_pool;
        cb_info.level = c.VK_COMMAND_BUFFER_LEVEL_PRIMARY;
        cb_info.commandBufferCount = 1;
        var cb: c.VkCommandBuffer = null;
        _ = c.vkAllocateCommandBuffers(impl.device, &cb_info, &cb);
        defer c.vkFreeCommandBuffers(impl.device, impl.command_pool, 1, &cb);

        var begin_info = std.mem.zeroes(c.VkCommandBufferBeginInfo);
        begin_info.sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;
        begin_info.flags = c.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;
        _ = c.vkBeginCommandBuffer(cb, &begin_info);

        // Use the most recently presented swapchain image.
        const img_idx = impl.current_image_index;
        const img = impl.swapchain_images[img_idx];

        // Transition: PRESENT_SRC → TRANSFER_SRC
        {
            var b = std.mem.zeroes(c.VkImageMemoryBarrier);
            b.sType = c.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER;
            b.oldLayout = c.VK_IMAGE_LAYOUT_PRESENT_SRC_KHR;
            b.newLayout = c.VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL;
            b.srcAccessMask = c.VK_ACCESS_MEMORY_READ_BIT;
            b.dstAccessMask = c.VK_ACCESS_TRANSFER_READ_BIT;
            b.srcQueueFamilyIndex = c.VK_QUEUE_FAMILY_IGNORED;
            b.dstQueueFamilyIndex = c.VK_QUEUE_FAMILY_IGNORED;
            b.image = img;
            b.subresourceRange.aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT;
            b.subresourceRange.levelCount = 1;
            b.subresourceRange.layerCount = 1;
            c.vkCmdPipelineBarrier(cb, c.VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT, c.VK_PIPELINE_STAGE_TRANSFER_BIT, 0, 0, null, 0, null, 1, &b);
        }

        // Copy image to buffer.
        var region = std.mem.zeroes(c.VkBufferImageCopy);
        region.imageSubresource.aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT;
        region.imageSubresource.layerCount = 1;
        region.imageExtent = .{ .width = w, .height = h, .depth = 1 };
        c.vkCmdCopyImageToBuffer(cb, img, c.VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, staging_buf, 1, &region);

        // Transition back: TRANSFER_SRC → PRESENT_SRC
        {
            var b = std.mem.zeroes(c.VkImageMemoryBarrier);
            b.sType = c.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER;
            b.oldLayout = c.VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL;
            b.newLayout = c.VK_IMAGE_LAYOUT_PRESENT_SRC_KHR;
            b.srcAccessMask = c.VK_ACCESS_TRANSFER_READ_BIT;
            b.dstAccessMask = c.VK_ACCESS_MEMORY_READ_BIT;
            b.srcQueueFamilyIndex = c.VK_QUEUE_FAMILY_IGNORED;
            b.dstQueueFamilyIndex = c.VK_QUEUE_FAMILY_IGNORED;
            b.image = img;
            b.subresourceRange.aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT;
            b.subresourceRange.levelCount = 1;
            b.subresourceRange.layerCount = 1;
            c.vkCmdPipelineBarrier(cb, c.VK_PIPELINE_STAGE_TRANSFER_BIT, c.VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT, 0, 0, null, 0, null, 1, &b);
        }

        _ = c.vkEndCommandBuffer(cb);

        var submit = std.mem.zeroes(c.VkSubmitInfo);
        submit.sType = c.VK_STRUCTURE_TYPE_SUBMIT_INFO;
        submit.commandBufferCount = 1;
        submit.pCommandBuffers = &cb;
        _ = c.vkQueueSubmit(impl.graphics_queue, 1, &submit, null);
        _ = c.vkQueueWaitIdle(impl.graphics_queue);

        // Map and copy — BGRA → RGBA swap.
        var mapped: ?*anyopaque = null;
        _ = c.vkMapMemory(impl.device, staging_mem, 0, n_bytes, 0, &mapped);
        const src: [*]const u8 = @ptrCast(mapped.?);
        const rgba = try gpa.alloc(u8, @intCast(n_bytes));
        var i: usize = 0;
        while (i < n_bytes) : (i += 4) {
            rgba[i + 0] = src[i + 2]; // R ← B
            rgba[i + 1] = src[i + 1]; // G
            rgba[i + 2] = src[i + 0]; // B ← R
            rgba[i + 3] = src[i + 3]; // A
        }
        c.vkUnmapMemory(impl.device, staging_mem);

        return rgba;
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

    /// RJ1 — Seam naming (preferred). Creates the quad pipeline.
    pub fn initPipelines(self: *VulkanBackend) !void {
        const impl: *VulkanImpl = @ptrCast(@alignCast(self._impl));
        try vkInitQuadPipeline(impl);
    }

    /// Acceptance-test surface (09.acceptance_test.zig calls this).
    /// Delegates to initPipelines — same behavior, different name.
    pub fn initQuadPipeline(self: *VulkanBackend, _allocator: std.mem.Allocator) !void {
        _ = _allocator;
        return self.initPipelines();
    }

    /// Acceptance-test surface (09.acceptance_test.zig calls this).
    /// Delegates through the internal helper.
    pub fn deinitQuadPipeline(self: *VulkanBackend) void {
        const impl: *VulkanImpl = @ptrCast(@alignCast(self._impl));
        vkDeinitQuadPipeline(impl);
    }

    /// RJ1 — Resize the swapchain to the given dimensions (RD5: dpi_scale deferred).
    pub fn resize(self: *VulkanBackend, w: u32, h: u32, dpi_scale: f32) void {
        _ = dpi_scale; // RD5 deferred
        const impl: *VulkanImpl = @ptrCast(@alignCast(self._impl));
        impl.swapchain_extent.width = w;
        impl.swapchain_extent.height = h;
        vkRecreateSwapchain(impl) catch {};
    }

    /// RJ1 — Upload a glyph atlas to the GPU.
    pub fn uploadAtlas(self: *VulkanBackend, atlas: *const anyopaque) BackendError!struct { backend_obj: *anyopaque } {
        const impl: *VulkanImpl = @ptrCast(@alignCast(self._impl));
        const cpu_atlas: *const anyopaque = @ptrCast(@alignCast(atlas));
        const gpu_atlas = vkUploadAtlasRgba8(
            impl.device,
            impl.physical_device,
            impl.command_pool,
            impl.graphics_queue,
            cpu_atlas.pixels,
            cpu_atlas.width,
            cpu_atlas.height,
        ) catch return BackendError.ShaderLoadFailed;
        return .{ .backend_obj = @ptrCast(gpu_atlas.image.?) };
    }

    /// RJ1 — Upload an SDF atlas to the GPU.
    pub fn uploadSdfAtlas(self: *VulkanBackend, atlas: *const anyopaque) BackendError!struct { backend_obj: *anyopaque } {
        const impl: *VulkanImpl = @ptrCast(@alignCast(self._impl));
        const cpu_atlas: *const anyopaque = @ptrCast(@alignCast(atlas));
        const gpu_atlas = vkUploadAtlas(
            impl.device,
            impl.physical_device,
            impl.command_pool,
            impl.graphics_queue,
            cpu_atlas.pixels,
            cpu_atlas.width,
            cpu_atlas.height,
        ) catch return BackendError.ShaderLoadFailed;
        return .{ .backend_obj = @ptrCast(gpu_atlas.image.?) };
    }

    /// RJ1 — Upload arbitrary image pixels to the GPU.
    pub fn uploadImage(self: *VulkanBackend, pixels: []const u8, w: u32, h: u32) BackendError!struct { backend_obj: *anyopaque } {
        const impl: *VulkanImpl = @ptrCast(@alignCast(self._impl));
        const gpu_atlas = vkUploadAtlasRgba8(
            impl.device,
            impl.physical_device,
            impl.command_pool,
            impl.graphics_queue,
            pixels,
            w,
            h,
        ) catch return BackendError.ShaderLoadFailed;
        return .{ .backend_obj = @ptrCast(gpu_atlas.image.?) };
    }

    /// RJ1 — Query GPU capabilities.
    pub fn capabilities(self: *const VulkanBackend) struct { max_texture_dim: u32, subpixel_text: bool, present_modes: u8 } {
        const impl: *const VulkanImpl = @ptrCast(@alignCast(self._impl));
        return .{
            .max_texture_dim = impl.device_properties.limits.maxImageDimension2D,
            .subpixel_text = true, // Vulkan supports RD2
            .present_modes = 0, // TBD: bitmask of supported present modes
        };
    }

    /// GpuBackend contract (RJ0/RJ1): drawFrame(commands, handles: AtlasHandles).
    /// handles.glyph.backend_obj is a *const GpuAtlas (glyph texture atlas, binding 0).
    /// handles.sdf and handles.image are reserved for future backends; VulkanBackend
    /// uses the separately-bound SDF/image atlases via updateSdfAtlas/updateSubpixelAtlas.
    pub fn drawFrame(self: *VulkanBackend, commands: []const DrawCommand, handles: AtlasHandles) void {
        const impl: *VulkanImpl = @ptrCast(@alignCast(self._impl));
        const glyph_atlas: *const GpuAtlas = @ptrCast(@alignCast(handles.glyph.backend_obj));
        vkDrawFrame(impl, commands, glyph_atlas);
    }

    /// M13-03 RD2 — Upload/replace the subpixel atlas GPU texture at binding=1.
    /// `atlas` is a *const GpuAtlas (or any struct with image/image_view/sampler/memory fields).
    /// Destroys any previously set subpixel atlas.
    pub fn updateSubpixelAtlas(self: *VulkanBackend, atlas: *const anyopaque) void {
        const impl: *VulkanImpl = @ptrCast(@alignCast(self._impl));
        const gpu_atlas: *const GpuAtlas = @ptrCast(@alignCast(atlas));
        // Destroy previous subpixel atlas if present.
        if (impl.subpixel_atlas_sampler) |s| c.vkDestroySampler(impl.device, s, null);
        if (impl.subpixel_atlas_view) |v| c.vkDestroyImageView(impl.device, v, null);
        if (impl.subpixel_atlas_image) |img| c.vkDestroyImage(impl.device, img, null);
        if (impl.subpixel_atlas_mem) |mem| c.vkFreeMemory(impl.device, mem, null);
        impl.subpixel_atlas_image = @ptrCast(gpu_atlas.image.?);
        impl.subpixel_atlas_view = @ptrCast(gpu_atlas.image_view.?);
        impl.subpixel_atlas_sampler = @ptrCast(gpu_atlas.sampler.?);
        impl.subpixel_atlas_mem = @ptrCast(gpu_atlas.memory.?);
    }

    /// M13-04 RD3 — Upload/replace the SDF icon atlas GPU texture at binding=2.
    /// `atlas` is a *const GpuSdfAtlas. Destroys any previously set SDF atlas.
    pub fn updateSdfAtlas(self: *VulkanBackend, atlas: *const anyopaque) void {
        const impl: *VulkanImpl = @ptrCast(@alignCast(self._impl));
        const gpu_atlas: *const GpuSdfAtlas = @ptrCast(@alignCast(atlas));
        // Destroy previous SDF atlas if present.
        if (impl.sdf_atlas_sampler) |s| c.vkDestroySampler(impl.device, s, null);
        if (impl.sdf_atlas_view) |v| c.vkDestroyImageView(impl.device, v, null);
        if (impl.sdf_atlas_image) |img| c.vkDestroyImage(impl.device, img, null);
        if (impl.sdf_atlas_mem) |mem| c.vkFreeMemory(impl.device, mem, null);
        impl.sdf_atlas_image = @ptrCast(gpu_atlas.image.?);
        impl.sdf_atlas_view = @ptrCast(gpu_atlas.image_view.?);
        impl.sdf_atlas_sampler = @ptrCast(gpu_atlas.sampler.?);
        impl.sdf_atlas_mem = @ptrCast(gpu_atlas.memory.?);
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
    impl.present_mode = present_mode; // R13: store for reuse on recreate

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

/// R13: always use FIFO (vsync, guaranteed by Vulkan spec).
/// FIFO blocks in vkQueuePresentKHR at the vertical blanking interval — no explicit sleep needed.
/// MAILBOX is a named constant for reference only; do not enable without a spec change.
fn chooseSwapPresentMode(_impl: *VulkanImpl) c.VkPresentModeKHR {
    _ = _impl; // present mode is always FIFO; no query needed
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

/// M13-03 RD2 — Create a 1x1 RGBA8 black dummy texture for binding=1 (subpixel atlas fallback).
/// Writes it directly to the descriptor set so binding=1 is always valid.
fn createDummySubpixelAtlas(impl: *VulkanImpl) !void {
    const dev = impl.device;
    const phys = impl.physical_device;
    const pool = impl.command_pool;
    const q = impl.graphics_queue;

    // Staging buffer: 4 bytes (1x1 RGBA8 = 4 bytes).
    const img_size: c.VkDeviceSize = 4;
    var stg_buf: c.VkBuffer = undefined;
    var stg_buf_info = std.mem.zeroes(c.VkBufferCreateInfo);
    stg_buf_info.sType = c.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO;
    stg_buf_info.size = img_size;
    stg_buf_info.usage = c.VK_BUFFER_USAGE_TRANSFER_SRC_BIT;
    stg_buf_info.sharingMode = c.VK_SHARING_MODE_EXCLUSIVE;
    if (c.vkCreateBuffer(dev, &stg_buf_info, null, &stg_buf) != c.VK_SUCCESS)
        return error.ShaderLoadFailed;
    defer c.vkDestroyBuffer(dev, stg_buf, null);

    var stg_req: c.VkMemoryRequirements = undefined;
    c.vkGetBufferMemoryRequirements(dev, stg_buf, &stg_req);
    const stg_type = findMemTypeLocal(phys, stg_req.memoryTypeBits, c.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | c.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT) orelse return error.ShaderLoadFailed;

    var stg_ma = std.mem.zeroes(c.VkMemoryAllocateInfo);
    stg_ma.sType = c.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
    stg_ma.allocationSize = stg_req.size;
    stg_ma.memoryTypeIndex = stg_type;
    var stg_mem: c.VkDeviceMemory = undefined;
    if (c.vkAllocateMemory(dev, &stg_ma, null, &stg_mem) != c.VK_SUCCESS)
        return error.ShaderLoadFailed;
    defer c.vkFreeMemory(dev, stg_mem, null);
    _ = c.vkBindBufferMemory(dev, stg_buf, stg_mem, 0);

    var mapped: ?*anyopaque = null;
    _ = c.vkMapMemory(dev, stg_mem, 0, img_size, 0, &mapped);
    const black_rgba = [4]u8{ 0, 0, 0, 0 };
    @memcpy(@as([*]u8, @ptrCast(mapped.?))[0..4], &black_rgba);
    c.vkUnmapMemory(dev, stg_mem);

    // Create 1x1 RGBA8 image.
    var ii = std.mem.zeroes(c.VkImageCreateInfo);
    ii.sType = c.VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO;
    ii.imageType = c.VK_IMAGE_TYPE_2D;
    ii.format = c.VK_FORMAT_R8G8B8A8_UNORM;
    ii.extent = .{ .width = 1, .height = 1, .depth = 1 };
    ii.mipLevels = 1;
    ii.arrayLayers = 1;
    ii.samples = c.VK_SAMPLE_COUNT_1_BIT;
    ii.tiling = c.VK_IMAGE_TILING_OPTIMAL;
    ii.usage = c.VK_IMAGE_USAGE_TRANSFER_DST_BIT | c.VK_IMAGE_USAGE_SAMPLED_BIT;
    ii.initialLayout = c.VK_IMAGE_LAYOUT_UNDEFINED;
    ii.sharingMode = c.VK_SHARING_MODE_EXCLUSIVE;
    var img: c.VkImage = undefined;
    if (c.vkCreateImage(dev, &ii, null, &img) != c.VK_SUCCESS)
        return error.ShaderLoadFailed;
    errdefer c.vkDestroyImage(dev, img, null);

    var ir: c.VkMemoryRequirements = undefined;
    c.vkGetImageMemoryRequirements(dev, img, &ir);
    const img_type = findMemTypeLocal(phys, ir.memoryTypeBits, c.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT) orelse return error.ShaderLoadFailed;

    var ima = std.mem.zeroes(c.VkMemoryAllocateInfo);
    ima.sType = c.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
    ima.allocationSize = ir.size;
    ima.memoryTypeIndex = img_type;
    var img_mem: c.VkDeviceMemory = undefined;
    if (c.vkAllocateMemory(dev, &ima, null, &img_mem) != c.VK_SUCCESS)
        return error.ShaderLoadFailed;
    errdefer c.vkFreeMemory(dev, img_mem, null);
    _ = c.vkBindImageMemory(dev, img, img_mem, 0);

    // One-shot command buffer.
    var cba = std.mem.zeroes(c.VkCommandBufferAllocateInfo);
    cba.sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO;
    cba.commandPool = pool;
    cba.level = c.VK_COMMAND_BUFFER_LEVEL_PRIMARY;
    cba.commandBufferCount = 1;
    var cb: c.VkCommandBuffer = undefined;
    if (c.vkAllocateCommandBuffers(dev, &cba, &cb) != c.VK_SUCCESS)
        return error.ShaderLoadFailed;
    defer c.vkFreeCommandBuffers(dev, pool, 1, &cb);

    var bi = std.mem.zeroes(c.VkCommandBufferBeginInfo);
    bi.sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;
    bi.flags = c.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;
    _ = c.vkBeginCommandBuffer(cb, &bi);

    atlasTransition(cb, img, c.VK_IMAGE_LAYOUT_UNDEFINED, c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL);

    var cp = std.mem.zeroes(c.VkBufferImageCopy);
    cp.imageSubresource.aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT;
    cp.imageSubresource.layerCount = 1;
    cp.imageExtent = .{ .width = 1, .height = 1, .depth = 1 };
    c.vkCmdCopyBufferToImage(cb, stg_buf, img, c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &cp);

    atlasTransition(cb, img, c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, c.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL);

    _ = c.vkEndCommandBuffer(cb);
    var si = std.mem.zeroes(c.VkSubmitInfo);
    si.sType = c.VK_STRUCTURE_TYPE_SUBMIT_INFO;
    si.commandBufferCount = 1;
    si.pCommandBuffers = &cb;
    _ = c.vkQueueSubmit(q, 1, &si, null);
    _ = c.vkQueueWaitIdle(q);

    // Image view.
    var ivi = std.mem.zeroes(c.VkImageViewCreateInfo);
    ivi.sType = c.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO;
    ivi.image = img;
    ivi.viewType = c.VK_IMAGE_VIEW_TYPE_2D;
    ivi.format = c.VK_FORMAT_R8G8B8A8_UNORM;
    ivi.subresourceRange.aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT;
    ivi.subresourceRange.levelCount = 1;
    ivi.subresourceRange.layerCount = 1;
    var iv: c.VkImageView = undefined;
    if (c.vkCreateImageView(dev, &ivi, null, &iv) != c.VK_SUCCESS)
        return error.ShaderLoadFailed;
    errdefer c.vkDestroyImageView(dev, iv, null);

    // Sampler.
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
        return error.ShaderLoadFailed;

    // Write binding=1 descriptor.
    var img_info = std.mem.zeroes(c.VkDescriptorImageInfo);
    img_info.imageLayout = c.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
    img_info.imageView = iv;
    img_info.sampler = samp;
    var write = std.mem.zeroes(c.VkWriteDescriptorSet);
    write.sType = c.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
    write.dstSet = impl.quad_desc_set;
    write.dstBinding = 1;
    write.descriptorCount = 1;
    write.descriptorType = c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER;
    write.pImageInfo = &img_info;
    c.vkUpdateDescriptorSets(impl.device, 1, &write, 0, null);

    impl.dummy_subpixel_image = img;
    impl.dummy_subpixel_view = iv;
    impl.dummy_subpixel_sampler = samp;
    impl.dummy_subpixel_mem = img_mem;
}

/// M13-04 RD3 — Create a 1x1 R8 black dummy texture for SDF atlas binding=2.
fn createDummySdfAtlas(impl: *VulkanImpl) !void {
    const dev = impl.device;
    const phys = impl.physical_device;
    const pool = impl.command_pool;
    const q = impl.graphics_queue;

    // Staging buffer: 1 byte (1x1 R8 = 1 byte).
    const img_size: c.VkDeviceSize = 1;
    var stg_buf: c.VkBuffer = undefined;
    var stg_buf_info = std.mem.zeroes(c.VkBufferCreateInfo);
    stg_buf_info.sType = c.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO;
    stg_buf_info.size = img_size;
    stg_buf_info.usage = c.VK_BUFFER_USAGE_TRANSFER_SRC_BIT;
    stg_buf_info.sharingMode = c.VK_SHARING_MODE_EXCLUSIVE;
    if (c.vkCreateBuffer(dev, &stg_buf_info, null, &stg_buf) != c.VK_SUCCESS)
        return error.ShaderLoadFailed;
    defer c.vkDestroyBuffer(dev, stg_buf, null);

    var stg_req: c.VkMemoryRequirements = undefined;
    c.vkGetBufferMemoryRequirements(dev, stg_buf, &stg_req);
    const stg_type = findMemTypeLocal(phys, stg_req.memoryTypeBits, c.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | c.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT) orelse return error.ShaderLoadFailed;

    var stg_ma = std.mem.zeroes(c.VkMemoryAllocateInfo);
    stg_ma.sType = c.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
    stg_ma.allocationSize = stg_req.size;
    stg_ma.memoryTypeIndex = stg_type;
    var stg_mem: c.VkDeviceMemory = undefined;
    if (c.vkAllocateMemory(dev, &stg_ma, null, &stg_mem) != c.VK_SUCCESS)
        return error.ShaderLoadFailed;
    defer c.vkFreeMemory(dev, stg_mem, null);
    _ = c.vkBindBufferMemory(dev, stg_buf, stg_mem, 0);

    var mapped: ?*anyopaque = null;
    _ = c.vkMapMemory(dev, stg_mem, 0, img_size, 0, &mapped);
    const black = [1]u8{0};
    @memcpy(@as([*]u8, @ptrCast(mapped.?))[0..1], &black);
    c.vkUnmapMemory(dev, stg_mem);

    // Create 1x1 R8 image.
    var ii = std.mem.zeroes(c.VkImageCreateInfo);
    ii.sType = c.VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO;
    ii.imageType = c.VK_IMAGE_TYPE_2D;
    ii.format = c.VK_FORMAT_R8_UNORM;
    ii.extent = .{ .width = 1, .height = 1, .depth = 1 };
    ii.mipLevels = 1;
    ii.arrayLayers = 1;
    ii.samples = c.VK_SAMPLE_COUNT_1_BIT;
    ii.tiling = c.VK_IMAGE_TILING_OPTIMAL;
    ii.usage = c.VK_IMAGE_USAGE_TRANSFER_DST_BIT | c.VK_IMAGE_USAGE_SAMPLED_BIT;
    ii.initialLayout = c.VK_IMAGE_LAYOUT_UNDEFINED;
    ii.sharingMode = c.VK_SHARING_MODE_EXCLUSIVE;
    var img: c.VkImage = undefined;
    if (c.vkCreateImage(dev, &ii, null, &img) != c.VK_SUCCESS)
        return error.ShaderLoadFailed;
    errdefer c.vkDestroyImage(dev, img, null);

    var ir: c.VkMemoryRequirements = undefined;
    c.vkGetImageMemoryRequirements(dev, img, &ir);
    const img_type = findMemTypeLocal(phys, ir.memoryTypeBits, c.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT) orelse return error.ShaderLoadFailed;

    var ima = std.mem.zeroes(c.VkMemoryAllocateInfo);
    ima.sType = c.VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
    ima.allocationSize = ir.size;
    ima.memoryTypeIndex = img_type;
    var img_mem: c.VkDeviceMemory = undefined;
    if (c.vkAllocateMemory(dev, &ima, null, &img_mem) != c.VK_SUCCESS)
        return error.ShaderLoadFailed;
    errdefer c.vkFreeMemory(dev, img_mem, null);
    _ = c.vkBindImageMemory(dev, img, img_mem, 0);

    // One-shot command buffer.
    var cba = std.mem.zeroes(c.VkCommandBufferAllocateInfo);
    cba.sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO;
    cba.commandPool = pool;
    cba.level = c.VK_COMMAND_BUFFER_LEVEL_PRIMARY;
    cba.commandBufferCount = 1;
    var cb: c.VkCommandBuffer = undefined;
    if (c.vkAllocateCommandBuffers(dev, &cba, &cb) != c.VK_SUCCESS)
        return error.ShaderLoadFailed;
    defer c.vkFreeCommandBuffers(dev, pool, 1, &cb);

    var bi = std.mem.zeroes(c.VkCommandBufferBeginInfo);
    bi.sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;
    bi.flags = c.VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;
    _ = c.vkBeginCommandBuffer(cb, &bi);

    atlasTransition(cb, img, c.VK_IMAGE_LAYOUT_UNDEFINED, c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL);

    var cp = std.mem.zeroes(c.VkBufferImageCopy);
    cp.imageSubresource.aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT;
    cp.imageSubresource.layerCount = 1;
    cp.imageExtent = .{ .width = 1, .height = 1, .depth = 1 };
    c.vkCmdCopyBufferToImage(cb, stg_buf, img, c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &cp);

    atlasTransition(cb, img, c.VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, c.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL);

    _ = c.vkEndCommandBuffer(cb);
    var si = std.mem.zeroes(c.VkSubmitInfo);
    si.sType = c.VK_STRUCTURE_TYPE_SUBMIT_INFO;
    si.commandBufferCount = 1;
    si.pCommandBuffers = &cb;
    _ = c.vkQueueSubmit(q, 1, &si, null);
    _ = c.vkQueueWaitIdle(q);

    // Image view.
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
        return error.ShaderLoadFailed;
    errdefer c.vkDestroyImageView(dev, iv, null);

    // Sampler (use LINEAR for SDF smooth interpolation).
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
        return error.ShaderLoadFailed;

    // Write binding=2 descriptor.
    var img_info = std.mem.zeroes(c.VkDescriptorImageInfo);
    img_info.imageLayout = c.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
    img_info.imageView = iv;
    img_info.sampler = samp;
    var write = std.mem.zeroes(c.VkWriteDescriptorSet);
    write.sType = c.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
    write.dstSet = impl.quad_desc_set;
    write.dstBinding = 2;
    write.descriptorCount = 1;
    write.descriptorType = c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER;
    write.pImageInfo = &img_info;
    c.vkUpdateDescriptorSets(impl.device, 1, &write, 0, null);

    impl.dummy_sdf_image = img;
    impl.dummy_sdf_view = iv;
    impl.dummy_sdf_sampler = samp;
    impl.dummy_sdf_mem = img_mem;
}

/// M13-03 RD2 — Upload an RGBA8 bitmap to a VK_FORMAT_R8G8B8A8_UNORM GPU image.
/// Returns GpuAtlas handles (image, view, sampler, memory).
pub fn vkUploadAtlasRgba8(
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
    const img_size: c.VkDeviceSize = @as(u64, atlas_w) * atlas_h * 4;

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
    const stg_type = findMemTypeLocal(phys, stg_req.memoryTypeBits, c.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | c.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT) orelse return error.GpuUploadFailed;

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

    // Create RGBA8 image
    var ii = std.mem.zeroes(c.VkImageCreateInfo);
    ii.sType = c.VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO;
    ii.imageType = c.VK_IMAGE_TYPE_2D;
    ii.format = c.VK_FORMAT_R8G8B8A8_UNORM;
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
    const img_type = findMemTypeLocal(phys, ir.memoryTypeBits, c.VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT) orelse return error.GpuUploadFailed;

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
    ivi.format = c.VK_FORMAT_R8G8B8A8_UNORM;
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

fn vkInitQuadPipeline(impl: *VulkanImpl) !void {

    // --- Descriptor set layout: binding 0 = grayscale atlas, binding 1 = subpixel atlas, binding 2 = SDF atlas ---
    var ds_bindings: [3]c.VkDescriptorSetLayoutBinding = undefined;
    ds_bindings[0] = std.mem.zeroes(c.VkDescriptorSetLayoutBinding);
    ds_bindings[0].binding = 0;
    ds_bindings[0].descriptorType = c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER;
    ds_bindings[0].descriptorCount = 1;
    ds_bindings[0].stageFlags = c.VK_SHADER_STAGE_FRAGMENT_BIT;
    ds_bindings[1] = std.mem.zeroes(c.VkDescriptorSetLayoutBinding);
    ds_bindings[1].binding = 1;
    ds_bindings[1].descriptorType = c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER;
    ds_bindings[1].descriptorCount = 1;
    ds_bindings[1].stageFlags = c.VK_SHADER_STAGE_FRAGMENT_BIT;
    ds_bindings[2] = std.mem.zeroes(c.VkDescriptorSetLayoutBinding);
    ds_bindings[2].binding = 2;
    ds_bindings[2].descriptorType = c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER;
    ds_bindings[2].descriptorCount = 1;
    ds_bindings[2].stageFlags = c.VK_SHADER_STAGE_FRAGMENT_BIT;

    var dsl_info = std.mem.zeroes(c.VkDescriptorSetLayoutCreateInfo);
    dsl_info.sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO;
    dsl_info.bindingCount = 3;
    dsl_info.pBindings = &ds_bindings;
    if (c.vkCreateDescriptorSetLayout(impl.device, &dsl_info, null, &impl.quad_desc_set_layout) != c.VK_SUCCESS)
        return error.ShaderLoadFailed;

    // --- Descriptor pool ---
    var pool_sizes: [1]c.VkDescriptorPoolSize = undefined;
    pool_sizes[0] = std.mem.zeroes(c.VkDescriptorPoolSize);
    pool_sizes[0].type = c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER;
    pool_sizes[0].descriptorCount = 3;
    var pool_info = std.mem.zeroes(c.VkDescriptorPoolCreateInfo);
    pool_info.sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO;
    pool_info.maxSets = 1;
    pool_info.poolSizeCount = 1;
    pool_info.pPoolSizes = &pool_sizes;
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

    // --- Create dummy 1x1 RGBA8 black texture for subpixel atlas binding=1 ---
    try createDummySubpixelAtlas(impl);

    // M13-04 RD3: Create dummy 1x1 R8 black texture for SDF atlas binding=2 ---
    try createDummySdfAtlas(impl);

    // --- Push constants: mat4 ortho (64 bytes) + clip data (36 bytes) = 100 bytes total ---
    // RD1: clipRect (16 bytes @ 64), clipRadii (16 bytes @ 80), clipEnabled (4 bytes @ 96).
    // Both stages share the full range so the GLSL push_constant block is fully contained
    // per VUID-VkGraphicsPipelineCreateInfo-layout-10069.
    var push_ranges: [1]c.VkPushConstantRange = undefined;
    push_ranges[0] = .{ .stageFlags = c.VK_SHADER_STAGE_VERTEX_BIT | c.VK_SHADER_STAGE_FRAGMENT_BIT, .offset = 0, .size = 100 };

    var pl_info = std.mem.zeroes(c.VkPipelineLayoutCreateInfo);
    pl_info.sType = c.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO;
    pl_info.setLayoutCount = 1;
    pl_info.pSetLayouts = &impl.quad_desc_set_layout;
    pl_info.pushConstantRangeCount = 1;
    pl_info.pPushConstantRanges = &push_ranges;
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

    var attr_descs: [5]c.VkVertexInputAttributeDescription = undefined;
    attr_descs[0] = .{ .location = 0, .binding = 0, .format = c.VK_FORMAT_R32G32_SFLOAT, .offset = @offsetOf(QuadVertex, "pos") };
    attr_descs[1] = .{ .location = 1, .binding = 0, .format = c.VK_FORMAT_R32G32_SFLOAT, .offset = @offsetOf(QuadVertex, "uv") };
    attr_descs[2] = .{ .location = 2, .binding = 0, .format = c.VK_FORMAT_R8G8B8A8_UNORM, .offset = @offsetOf(QuadVertex, "color") };
    attr_descs[3] = .{ .location = 3, .binding = 0, .format = c.VK_FORMAT_R8G8B8A8_UNORM, .offset = @offsetOf(QuadVertex, "color_b") };
    attr_descs[4] = .{ .location = 4, .binding = 0, .format = c.VK_FORMAT_R32_UINT, .offset = @offsetOf(QuadVertex, "mode") };

    var vi = std.mem.zeroes(c.VkPipelineVertexInputStateCreateInfo);
    vi.sType = c.VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO;
    vi.vertexBindingDescriptionCount = 1;
    vi.pVertexBindingDescriptions = &vib;
    vi.vertexAttributeDescriptionCount = 5;
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
    const mem_type = try findMemoryType(impl, mem_req.memoryTypeBits, c.VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | c.VK_MEMORY_PROPERTY_HOST_COHERENT_BIT);

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
    // M13-03 RD2: destroy dummy subpixel atlas
    if (impl.dummy_subpixel_sampler) |s| c.vkDestroySampler(impl.device, s, null);
    if (impl.dummy_subpixel_view) |v| c.vkDestroyImageView(impl.device, v, null);
    if (impl.dummy_subpixel_image) |img| c.vkDestroyImage(impl.device, img, null);
    if (impl.dummy_subpixel_mem) |mem| c.vkFreeMemory(impl.device, mem, null);
    // Destroy real subpixel atlas if present.
    if (impl.subpixel_atlas_sampler) |s| c.vkDestroySampler(impl.device, s, null);
    if (impl.subpixel_atlas_view) |v| c.vkDestroyImageView(impl.device, v, null);
    if (impl.subpixel_atlas_image) |img| c.vkDestroyImage(impl.device, img, null);
    if (impl.subpixel_atlas_mem) |mem| c.vkFreeMemory(impl.device, mem, null);
    // M13-04 RD3: destroy dummy SDF atlas
    if (impl.dummy_sdf_sampler) |s| c.vkDestroySampler(impl.device, s, null);
    if (impl.dummy_sdf_view) |v| c.vkDestroyImageView(impl.device, v, null);
    if (impl.dummy_sdf_image) |img| c.vkDestroyImage(impl.device, img, null);
    if (impl.dummy_sdf_mem) |mem| c.vkFreeMemory(impl.device, mem, null);
    // Destroy real SDF atlas if present.
    if (impl.sdf_atlas_sampler) |s| c.vkDestroySampler(impl.device, s, null);
    if (impl.sdf_atlas_view) |v| c.vkDestroyImageView(impl.device, v, null);
    if (impl.sdf_atlas_image) |img| c.vkDestroyImage(impl.device, img, null);
    if (impl.sdf_atlas_mem) |mem| c.vkFreeMemory(impl.device, mem, null);
    impl.quad_pipeline_ready = false;
    impl.quad_pipeline = null;
    impl.quad_pipeline_layout = null;
    impl.quad_desc_pool = null;
    impl.quad_desc_set_layout = null;
    impl.quad_desc_set = null;
    impl.quad_vertex_buf = null;
    impl.quad_vertex_mem = null;}

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

    // Update descriptor set to point at the current atlas image/sampler (binding 0).
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

        // M13-03 RD2: Update binding 1 — subpixel atlas or dummy fallback.
        var sp_img_info = std.mem.zeroes(c.VkDescriptorImageInfo);
        sp_img_info.imageLayout = c.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
        if (impl.subpixel_atlas_view != null and impl.subpixel_atlas_sampler != null) {
            sp_img_info.imageView = impl.subpixel_atlas_view.?;
            sp_img_info.sampler = impl.subpixel_atlas_sampler.?;
        } else {
            sp_img_info.imageView = impl.dummy_subpixel_view.?;
            sp_img_info.sampler = impl.dummy_subpixel_sampler.?;
        }
        var sp_write = std.mem.zeroes(c.VkWriteDescriptorSet);
        sp_write.sType = c.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
        sp_write.dstSet = impl.quad_desc_set;
        sp_write.dstBinding = 1;
        sp_write.descriptorCount = 1;
        sp_write.descriptorType = c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER;
        sp_write.pImageInfo = &sp_img_info;
        c.vkUpdateDescriptorSets(impl.device, 1, &sp_write, 0, null);

        // M13-04 RD3: Update binding 2 — SDF atlas or dummy fallback.
        var sdf_img_info = std.mem.zeroes(c.VkDescriptorImageInfo);
        sdf_img_info.imageLayout = c.VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
        if (impl.sdf_atlas_view != null and impl.sdf_atlas_sampler != null) {
            sdf_img_info.imageView = impl.sdf_atlas_view.?;
            sdf_img_info.sampler = impl.sdf_atlas_sampler.?;
        } else {
            sdf_img_info.imageView = impl.dummy_sdf_view.?;
            sdf_img_info.sampler = impl.dummy_sdf_sampler.?;
        }
        var sdf_write = std.mem.zeroes(c.VkWriteDescriptorSet);
        sdf_write.sType = c.VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
        sdf_write.dstSet = impl.quad_desc_set;
        sdf_write.dstBinding = 2;
        sdf_write.descriptorCount = 1;
        sdf_write.descriptorType = c.VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER;
        sdf_write.pImageInfo = &sdf_img_info;
        c.vkUpdateDescriptorSets(impl.device, 1, &sdf_write, 0, null);
    }

    // Build vertex data: expand each DrawCommand into 6 vertices.
    // Strategy: collect all quads into the buffer, then make one draw call.
    // Scissor changes require separate draw calls; we track per-scissor ranges.
    const max_verts = MAX_QUADS * VERTS_PER_QUAD;
    var mapped: ?*anyopaque = null;
    const buf_size: c.VkDeviceSize = @as(u64, max_verts) * @sizeOf(QuadVertex);
    _ = c.vkMapMemory(impl.device, impl.quad_vertex_mem, 0, buf_size, 0, &mapped);
    const verts: [*]QuadVertex = @ptrCast(@alignCast(mapped.?));

    var vert_count: u32 = 0;
    const W = @as(f32, @floatFromInt(impl.swapchain_extent.width));
    const H = @as(f32, @floatFromInt(impl.swapchain_extent.height));

    // Scissor draw-range tracking (R42), extended with clip_rounded state (RD1).
    const ScissorRange = struct { scissor: c.VkRect2D, first_vert: u32, clip_rounded: ?ClipRounded = null };
    var scissor_ranges: [64]ScissorRange = undefined;
    var scissor_range_count: u32 = 0;

    // Scissor stack.
    var scissor_stack: [8]c.VkRect2D = undefined;
    var scissor_depth: u8 = 0;
    var current_scissor = c.VkRect2D{ .offset = .{ .x = 0, .y = 0 }, .extent = impl.swapchain_extent };

    // RD1: Current rounded clip state (carried into new scissor ranges).
    var current_clip: ?ClipRounded = null;

    // Start with the full-viewport scissor range.
    scissor_ranges[0] = .{ .scissor = current_scissor, .first_vert = 0, .clip_rounded = null };
    scissor_range_count = 1;

    for (commands) |cmd| {
        switch (cmd) {
            .set_scissor => |sr| {
                // Push to stack and set new intersected scissor.
                if (scissor_depth < 8) {
                    scissor_stack[scissor_depth] = current_scissor;
                    scissor_depth += 1;
                }
                const ax0: i64 = current_scissor.offset.x;
                const ay0: i64 = current_scissor.offset.y;
                const ax1: i64 = ax0 + current_scissor.extent.width;
                const ay1: i64 = ay0 + current_scissor.extent.height;
                const bx0: i64 = sr.x;
                const by0: i64 = sr.y;
                const bx1: i64 = bx0 + sr.w;
                const by1: i64 = by0 + sr.h;
                const ix0 = @max(ax0, bx0);
                const iy0 = @max(ay0, by0);
                const ix1 = @min(ax1, bx1);
                const iy1 = @min(ay1, by1);
                const iw: u32 = @intCast(@max(0, ix1 - ix0));
                const ih: u32 = @intCast(@max(0, iy1 - iy0));
                current_scissor = .{
                    .offset = .{ .x = @intCast(ix0), .y = @intCast(iy0) },
                    .extent = .{ .width = iw, .height = ih },
                };
                // Start a new draw-range for the new scissor (carry forward clip state).
                if (scissor_range_count < 64) {
                    scissor_ranges[scissor_range_count] = .{ .scissor = current_scissor, .first_vert = vert_count, .clip_rounded = current_clip };
                    scissor_range_count += 1;
                }
            },
            .restore_scissor => {
                if (scissor_depth > 0) {
                    scissor_depth -= 1;
                    current_scissor = scissor_stack[scissor_depth];
                }
                // Start a new draw-range for the restored scissor (carry forward clip state).
                if (scissor_range_count < 64) {
                    scissor_ranges[scissor_range_count] = .{ .scissor = current_scissor, .first_vert = vert_count, .clip_rounded = current_clip };
                    scissor_range_count += 1;
                }
            },
            .clip_rounded_begin => |cr| {
                // RD1: Start new range with rounded clip enabled.
                if (scissor_range_count < 64) {
                    current_clip = cr;
                    scissor_ranges[scissor_range_count] = .{ .scissor = current_scissor, .first_vert = vert_count, .clip_rounded = current_clip };
                    scissor_range_count += 1;
                }
            },
            .clip_rounded_end => {
                // RD1: Start new range with rounded clip disabled.
                if (scissor_range_count < 64) {
                    current_clip = null;
                    scissor_ranges[scissor_range_count] = .{ .scissor = current_scissor, .first_vert = vert_count, .clip_rounded = null };
                    scissor_range_count += 1;
                }
            },
            .filled_rect => |r| {
                if (vert_count + VERTS_PER_QUAD <= max_verts) {
                    emitQuad(verts, &vert_count, r.rect, .{}, r.color, .{ 0, 0, 0, 0 }, 0);
                }
            },
            .border_rect => |br| {
                if (vert_count + VERTS_PER_QUAD <= max_verts) {
                    emitQuad(verts, &vert_count, br.rect, .{}, br.color, .{ 0, 0, 0, 0 }, 0);
                }
            },
            .glyph => |g| {
                if (vert_count + VERTS_PER_QUAD <= max_verts) {
                    emitQuad(verts, &vert_count, g.dst, g.uv, g.color, .{ 0, 0, 0, 0 }, g.mode);
                }
            },
            .image_rect => |img| {
                if (vert_count + VERTS_PER_QUAD <= max_verts) {
                    emitQuad(verts, &vert_count, img.dst, img.uv, img.tint, .{ 0, 0, 0, 0 }, 0);
                }
            },
            .sdf_icon => |si| {
                if (vert_count + VERTS_PER_QUAD <= max_verts) {
                    emitQuad(verts, &vert_count, si.dst, si.uv, si.color, .{ 0, 0, 0, 0 }, 4);
                }
            },
            .gradient_rect => |gr| {
                if (vert_count + VERTS_PER_QUAD <= max_verts) {
                    const col_b = [4]u8{ gr.color_b.r, gr.color_b.g, gr.color_b.b, gr.color_b.a };
                    const uv = switch (gr.direction) {
                        .right => Rect09{ .x = 0, .y = 0, .w = 1, .h = 0 },
                        .bottom => Rect09{ .x = 0, .y = 0, .w = 0, .h = 1 },
                        .bottom_right => Rect09{ .x = 0, .y = 0, .w = 1, .h = 1 },
                    };
                    emitQuad(verts, &vert_count, gr.rect, uv, gr.color_a, col_b, 2);
                }
            },
            .aa_filled_rect => |r| {
                if (vert_count + VERTS_PER_QUAD <= max_verts) {
                    emitQuad(verts, &vert_count, r.rect, .{}, r.color, .{ 0, 0, 0, 0 }, 5);
                }
            },
            .aa_filled_circle => |circ| {
                if (vert_count + VERTS_PER_QUAD <= max_verts) {
                    const sq_rect = Rect09{
                        .x = circ.center_x - circ.radius,
                        .y = circ.center_y - circ.radius,
                        .w = circ.radius * 2,
                        .h = circ.radius * 2,
                    };
                    const sq_uv = Rect09{ .x = 0, .y = 0, .w = 1, .h = 1 };
                    emitQuad(verts, &vert_count, sq_rect, sq_uv, circ.color, .{ 0, 0, 0, 0 }, 6);
                }
            },
        }
    }
    c.vkUnmapMemory(impl.device, impl.quad_vertex_mem);

    if (vert_count == 0) return; // render pass still active; endFrame will close it

    const cb = impl.command_buffer;
    c.vkCmdBindPipeline(cb, c.VK_PIPELINE_BIND_POINT_GRAPHICS, impl.quad_pipeline);

    const viewport = c.VkViewport{ .x = 0, .y = 0, .width = W, .height = H, .minDepth = 0, .maxDepth = 1 };
    c.vkCmdSetViewport(cb, 0, 1, &viewport);

    // Orthographic projection: pixel coords to NDC. Column-major.
    const ortho = [16]f32{
        2.0 / W, 0,       0, 0,
        0,       2.0 / H, 0, 0,
        0,       0,       1, 0,
        -1,      -1,      0, 1,
    };
    c.vkCmdPushConstants(cb, impl.quad_pipeline_layout, c.VK_SHADER_STAGE_VERTEX_BIT | c.VK_SHADER_STAGE_FRAGMENT_BIT, 0, 64, &ortho);
    c.vkCmdBindDescriptorSets(cb, c.VK_PIPELINE_BIND_POINT_GRAPHICS, impl.quad_pipeline_layout, 0, 1, &impl.quad_desc_set, 0, null);

    const vb_offset: c.VkDeviceSize = 0;
    c.vkCmdBindVertexBuffers(cb, 0, 1, &impl.quad_vertex_buf, &vb_offset);

    // Issue one draw call per scissor range (R42), with per-range clip push constants (RD1).
    var ri: u32 = 0;
    while (ri < scissor_range_count) : (ri += 1) {
        const first = scissor_ranges[ri].first_vert;
        const last = if (ri + 1 < scissor_range_count) scissor_ranges[ri + 1].first_vert else vert_count;
        if (last <= first) continue;
        c.vkCmdSetScissor(cb, 0, 1, &scissor_ranges[ri].scissor);

        // RD1: Push clip constants for this range.
        if (scissor_ranges[ri].clip_rounded) |cr| {
            const clip_rect = [4]f32{ cr.rect.x, cr.rect.y, cr.rect.w, cr.rect.h };
            const clip_radii = [4]f32{ cr.radius_tl, cr.radius_tr, cr.radius_br, cr.radius_bl };
            const clip_enabled: u32 = 1;
            c.vkCmdPushConstants(cb, impl.quad_pipeline_layout, c.VK_SHADER_STAGE_VERTEX_BIT | c.VK_SHADER_STAGE_FRAGMENT_BIT, 64, 16, &clip_rect);
            c.vkCmdPushConstants(cb, impl.quad_pipeline_layout, c.VK_SHADER_STAGE_VERTEX_BIT | c.VK_SHADER_STAGE_FRAGMENT_BIT, 80, 16, &clip_radii);
            c.vkCmdPushConstants(cb, impl.quad_pipeline_layout, c.VK_SHADER_STAGE_VERTEX_BIT | c.VK_SHADER_STAGE_FRAGMENT_BIT, 96, 4, &clip_enabled);
        } else {
            const clip_disabled: u32 = 0;
            c.vkCmdPushConstants(cb, impl.quad_pipeline_layout, c.VK_SHADER_STAGE_VERTEX_BIT | c.VK_SHADER_STAGE_FRAGMENT_BIT, 96, 4, &clip_disabled);
        }

        c.vkCmdDraw(cb, last - first, 1, first, 0);
    }
}

fn emitQuad(
    verts: [*]QuadVertex,
    count: *u32,
    rect: Rect09,
    uv: Rect09,
    color: Color09,
    color_b: [4]u8,
    mode: u32,
) void {
    const px0 = rect.x;
    const py0 = rect.y;
    const px1 = rect.x + rect.w;
    const py1 = rect.y + rect.h;
    const ux0 = uv.x;
    const vy0 = uv.y;
    const ux1 = uv.x + uv.w;
    const vy1 = uv.y + uv.h;
    const col = [4]u8{ color.r, color.g, color.b, color.a };
    verts[count.*] = .{ .pos = .{ px0, py0 }, .uv = .{ ux0, vy0 }, .color = col, .color_b = color_b, .mode = mode };
    count.* += 1;
    verts[count.*] = .{ .pos = .{ px1, py0 }, .uv = .{ ux1, vy0 }, .color = col, .color_b = color_b, .mode = mode };
    count.* += 1;
    verts[count.*] = .{ .pos = .{ px0, py1 }, .uv = .{ ux0, vy1 }, .color = col, .color_b = color_b, .mode = mode };
    count.* += 1;
    verts[count.*] = .{ .pos = .{ px1, py0 }, .uv = .{ ux1, vy0 }, .color = col, .color_b = color_b, .mode = mode };
    count.* += 1;
    verts[count.*] = .{ .pos = .{ px1, py1 }, .uv = .{ ux1, vy1 }, .color = col, .color_b = color_b, .mode = mode };
    count.* += 1;
    verts[count.*] = .{ .pos = .{ px0, py1 }, .uv = .{ ux0, vy1 }, .color = col, .color_b = color_b, .mode = mode };
    count.* += 1;
}
