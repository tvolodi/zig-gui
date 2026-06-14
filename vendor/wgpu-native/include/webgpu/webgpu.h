// webgpu.h — wgpu-native stub header for zig-gui M23-01 (RJ4)
//
// This is a STUB. It declares the minimum types and function signatures needed
// for webgpu_backend.zig to compile. Actual runtime operation requires the real
// wgpu-native library (https://github.com/gfx-rs/wgpu-native).
//
// Replace this file with the real wgpu.h from wgpu-native when linking for
// production use (add wgpu_native.lib / libwgpu_native.a to the link path).

#ifndef WEBGPU_H
#define WEBGPU_H

#include <stdint.h>
#include <stddef.h>

// ---------------------------------------------------------------------------
// Handle types — all opaque pointers in the C API
// ---------------------------------------------------------------------------

typedef struct WGPUInstanceImpl*        WGPUInstance;
typedef struct WGPUAdapterImpl*         WGPUAdapter;
typedef struct WGPUDeviceImpl*          WGPUDevice;
typedef struct WGPUQueueImpl*           WGPUQueue;
typedef struct WGPUSurfaceImpl*         WGPUSurface;
typedef struct WGPUSwapChainImpl*       WGPUSwapChain;
typedef struct WGPURenderPipelineImpl*  WGPURenderPipeline;
typedef struct WGPUBindGroupImpl*       WGPUBindGroup;
typedef struct WGPUBindGroupLayoutImpl* WGPUBindGroupLayout;
typedef struct WGPUBufferImpl*          WGPUBuffer;
typedef struct WGPUTextureImpl*         WGPUTexture;
typedef struct WGPUTextureViewImpl*     WGPUTextureView;
typedef struct WGPUSamplerImpl*         WGPUSampler;
typedef struct WGPUShaderModuleImpl*    WGPUShaderModule;
typedef struct WGPUCommandEncoderImpl*  WGPUCommandEncoder;
typedef struct WGPURenderPassEncoderImpl* WGPURenderPassEncoder;
typedef struct WGPUCommandBufferImpl*   WGPUCommandBuffer;
typedef struct WGPUPipelineLayoutImpl*  WGPUPipelineLayout;

// ---------------------------------------------------------------------------
// Enumerations
// ---------------------------------------------------------------------------

typedef enum WGPUTextureFormat {
    WGPUTextureFormat_Undefined = 0x00000000,
    WGPUTextureFormat_BGRA8Unorm = 0x00000017,
    WGPUTextureFormat_RGBA8Unorm = 0x00000012,
    WGPUTextureFormat_R8Unorm    = 0x00000001,
    WGPUTextureFormat_Force32 = 0x7FFFFFFF,
} WGPUTextureFormat;

typedef enum WGPUPresentMode {
    WGPUPresentMode_Fifo        = 0x00000000,
    WGPUPresentMode_Mailbox     = 0x00000001,
    WGPUPresentMode_Immediate   = 0x00000002,
    WGPUPresentMode_Force32 = 0x7FFFFFFF,
} WGPUPresentMode;

typedef enum WGPUSType {
    WGPUSType_Invalid = 0x00000000,
    WGPUSType_SurfaceDescriptorFromWindowsHWND = 0x00000004,
    WGPUSType_ShaderModuleWGSLDescriptor = 0x00000006,
    WGPUSType_Force32 = 0x7FFFFFFF,
} WGPUSType;

typedef enum WGPUBackendType {
    WGPUBackendType_Undefined = 0x00000000,
    WGPUBackendType_Vulkan    = 0x00000007,
    WGPUBackendType_D3D12     = 0x00000006,
    WGPUBackendType_Metal     = 0x00000005,
    WGPUBackendType_Force32 = 0x7FFFFFFF,
} WGPUBackendType;

typedef enum WGPUPowerPreference {
    WGPUPowerPreference_Undefined     = 0x00000000,
    WGPUPowerPreference_LowPower      = 0x00000001,
    WGPUPowerPreference_HighPerformance = 0x00000002,
    WGPUPowerPreference_Force32 = 0x7FFFFFFF,
} WGPUPowerPreference;

typedef enum WGPURequestAdapterStatus {
    WGPURequestAdapterStatus_Success = 0x00000000,
    WGPURequestAdapterStatus_Error   = 0x00000002,
    WGPURequestAdapterStatus_Force32 = 0x7FFFFFFF,
} WGPURequestAdapterStatus;

typedef enum WGPURequestDeviceStatus {
    WGPURequestDeviceStatus_Success = 0x00000000,
    WGPURequestDeviceStatus_Error   = 0x00000002,
    WGPURequestDeviceStatus_Force32 = 0x7FFFFFFF,
} WGPURequestDeviceStatus;

typedef enum WGPUBufferUsage {
    WGPUBufferUsage_None    = 0x00000000,
    WGPUBufferUsage_Vertex  = 0x00000020,
    WGPUBufferUsage_CopyDst = 0x00000008,
    WGPUBufferUsage_MapWrite = 0x00000004,
    WGPUBufferUsage_Force32 = 0x7FFFFFFF,
} WGPUBufferUsage;

typedef uint32_t WGPUBufferUsageFlags;
typedef uint32_t WGPUColorWriteMaskFlags;

typedef enum WGPUTextureUsage {
    WGPUTextureUsage_None             = 0x00000000,
    WGPUTextureUsage_CopyDst          = 0x00000002,
    WGPUTextureUsage_TextureBinding   = 0x00000004,
    WGPUTextureUsage_RenderAttachment = 0x00000010,
    WGPUTextureUsage_Force32 = 0x7FFFFFFF,
} WGPUTextureUsage;

typedef uint32_t WGPUTextureUsageFlags;

typedef enum WGPUTextureDimension {
    WGPUTextureDimension_2D     = 0x00000001,
    WGPUTextureDimension_Force32 = 0x7FFFFFFF,
} WGPUTextureDimension;

typedef enum WGPUTextureViewDimension {
    WGPUTextureViewDimension_2D     = 0x00000002,
    WGPUTextureViewDimension_Force32 = 0x7FFFFFFF,
} WGPUTextureViewDimension;

typedef enum WGPUTextureAspect {
    WGPUTextureAspect_All       = 0x00000000,
    WGPUTextureAspect_Force32 = 0x7FFFFFFF,
} WGPUTextureAspect;

typedef enum WGPULoadOp {
    WGPULoadOp_Clear     = 0x00000001,
    WGPULoadOp_Load      = 0x00000002,
    WGPULoadOp_Force32 = 0x7FFFFFFF,
} WGPULoadOp;

typedef enum WGPUStoreOp {
    WGPUStoreOp_Store    = 0x00000001,
    WGPUStoreOp_Discard  = 0x00000002,
    WGPUStoreOp_Force32 = 0x7FFFFFFF,
} WGPUStoreOp;

typedef enum WGPUVertexFormat {
    WGPUVertexFormat_Float32x2  = 0x00000015,
    WGPUVertexFormat_Float32x4  = 0x00000017,
    WGPUVertexFormat_Uint32     = 0x0000000D,
    WGPUVertexFormat_Unorm8x4   = 0x00000005,
    WGPUVertexFormat_Force32 = 0x7FFFFFFF,
} WGPUVertexFormat;

typedef enum WGPUVertexStepMode {
    WGPUVertexStepMode_Vertex   = 0x00000000,
    WGPUVertexStepMode_Force32 = 0x7FFFFFFF,
} WGPUVertexStepMode;

typedef enum WGPUPrimitiveTopology {
    WGPUPrimitiveTopology_TriangleList = 0x00000003,
    WGPUPrimitiveTopology_Force32 = 0x7FFFFFFF,
} WGPUPrimitiveTopology;

typedef enum WGPUCullMode {
    WGPUCullMode_None    = 0x00000000,
    WGPUCullMode_Force32 = 0x7FFFFFFF,
} WGPUCullMode;

typedef enum WGPUFrontFace {
    WGPUFrontFace_CCW    = 0x00000000,
    WGPUFrontFace_Force32 = 0x7FFFFFFF,
} WGPUFrontFace;

typedef enum WGPUBlendOperation {
    WGPUBlendOperation_Add      = 0x00000000,
    WGPUBlendOperation_Force32 = 0x7FFFFFFF,
} WGPUBlendOperation;

typedef enum WGPUBlendFactor {
    WGPUBlendFactor_Zero             = 0x00000000,
    WGPUBlendFactor_One              = 0x00000001,
    WGPUBlendFactor_OneMinusSrcAlpha = 0x0000000A,
    WGPUBlendFactor_Force32 = 0x7FFFFFFF,
} WGPUBlendFactor;

typedef enum WGPUShaderStage {
    WGPUShaderStage_None     = 0x00000000,
    WGPUShaderStage_Vertex   = 0x00000001,
    WGPUShaderStage_Fragment = 0x00000002,
    WGPUShaderStage_Compute  = 0x00000004,
} WGPUShaderStage;

typedef uint32_t WGPUShaderStageFlags;

typedef enum WGPUSamplerBindingType {
    WGPUSamplerBindingType_Filtering = 0x00000001,
    WGPUSamplerBindingType_Force32 = 0x7FFFFFFF,
} WGPUSamplerBindingType;

typedef enum WGPUTextureSampleType {
    WGPUTextureSampleType_Float       = 0x00000001,
    WGPUTextureSampleType_Force32 = 0x7FFFFFFF,
} WGPUTextureSampleType;

typedef enum WGPUAddressMode {
    WGPUAddressMode_ClampToEdge = 0x00000000,
    WGPUAddressMode_Force32 = 0x7FFFFFFF,
} WGPUAddressMode;

typedef enum WGPUFilterMode {
    WGPUFilterMode_Linear   = 0x00000001,
    WGPUFilterMode_Force32 = 0x7FFFFFFF,
} WGPUFilterMode;

typedef enum WGPUMipmapFilterMode {
    WGPUMipmapFilterMode_Nearest = 0x00000000,
    WGPUMipmapFilterMode_Force32 = 0x7FFFFFFF,
} WGPUMipmapFilterMode;

// ---------------------------------------------------------------------------
// Chained struct (extension mechanism)
// ---------------------------------------------------------------------------

typedef struct WGPUChainedStruct {
    struct WGPUChainedStruct const* next;
    WGPUSType sType;
} WGPUChainedStruct;

// ---------------------------------------------------------------------------
// Core descriptors
// ---------------------------------------------------------------------------

typedef struct WGPUInstanceDescriptor {
    WGPUChainedStruct const* nextInChain;
} WGPUInstanceDescriptor;

typedef struct WGPURequestAdapterOptions {
    WGPUChainedStruct const* nextInChain;
    WGPUSurface compatibleSurface;
    WGPUPowerPreference powerPreference;
    WGPUBackendType backendType;
    int forceFallbackAdapter; // WGPUBool
} WGPURequestAdapterOptions;

typedef struct WGPUDeviceDescriptor {
    WGPUChainedStruct const* nextInChain;
    const char* label;
    size_t requiredFeatureCount;
    const int* requiredFeatures;
    const void* requiredLimits;
    struct {
        WGPUChainedStruct const* nextInChain;
        const char* label;
    } defaultQueue;
    const char* deviceLostMessage;
    void* deviceLostUserdata;
} WGPUDeviceDescriptor;

typedef struct WGPUSurfaceDescriptor {
    WGPUChainedStruct const* nextInChain;
    const char* label;
} WGPUSurfaceDescriptor;

typedef struct WGPUSurfaceDescriptorFromWindowsHWND {
    WGPUChainedStruct chain;
    void* hinstance;
    void* hwnd;
} WGPUSurfaceDescriptorFromWindowsHWND;

typedef struct WGPUSwapChainDescriptor {
    WGPUChainedStruct const* nextInChain;
    const char* label;
    WGPUTextureUsageFlags usage;
    WGPUTextureFormat format;
    uint32_t width;
    uint32_t height;
    WGPUPresentMode presentMode;
} WGPUSwapChainDescriptor;

typedef struct WGPUShaderModuleWGSLDescriptor {
    WGPUChainedStruct chain;
    const char* code;
} WGPUShaderModuleWGSLDescriptor;

typedef struct WGPUShaderModuleDescriptor {
    WGPUChainedStruct const* nextInChain;
    const char* label;
    size_t hintCount;
    const void* hints;
} WGPUShaderModuleDescriptor;

typedef struct WGPUBufferDescriptor {
    WGPUChainedStruct const* nextInChain;
    const char* label;
    WGPUBufferUsageFlags usage;
    uint64_t size;
    int mappedAtCreation; // WGPUBool
} WGPUBufferDescriptor;

typedef struct WGPUExtent3D {
    uint32_t width;
    uint32_t height;
    uint32_t depthOrArrayLayers;
} WGPUExtent3D;

typedef struct WGPUTextureDescriptor {
    WGPUChainedStruct const* nextInChain;
    const char* label;
    WGPUTextureUsageFlags usage;
    WGPUTextureDimension dimension;
    WGPUExtent3D size;
    WGPUTextureFormat format;
    uint32_t mipLevelCount;
    uint32_t sampleCount;
    size_t viewFormatCount;
    const WGPUTextureFormat* viewFormats;
} WGPUTextureDescriptor;

typedef struct WGPUTextureViewDescriptor {
    WGPUChainedStruct const* nextInChain;
    const char* label;
    WGPUTextureFormat format;
    WGPUTextureViewDimension dimension;
    uint32_t baseMipLevel;
    uint32_t mipLevelCount;
    uint32_t baseArrayLayer;
    uint32_t arrayLayerCount;
    WGPUTextureAspect aspect;
} WGPUTextureViewDescriptor;

typedef struct WGPUSamplerDescriptor {
    WGPUChainedStruct const* nextInChain;
    const char* label;
    WGPUAddressMode addressModeU;
    WGPUAddressMode addressModeV;
    WGPUAddressMode addressModeW;
    WGPUFilterMode magFilter;
    WGPUFilterMode minFilter;
    WGPUMipmapFilterMode mipmapFilter;
    float lodMinClamp;
    float lodMaxClamp;
    int compare; // WGPUCompareFunction
    uint16_t maxAnisotropy;
} WGPUSamplerDescriptor;

typedef struct WGPUCommandEncoderDescriptor {
    WGPUChainedStruct const* nextInChain;
    const char* label;
} WGPUCommandEncoderDescriptor;

typedef struct WGPUCommandBufferDescriptor {
    WGPUChainedStruct const* nextInChain;
    const char* label;
} WGPUCommandBufferDescriptor;

typedef struct WGPUColor {
    double r;
    double g;
    double b;
    double a;
} WGPUColor;

typedef struct WGPURenderPassColorAttachment {
    WGPUChainedStruct const* nextInChain;
    WGPUTextureView view;
    WGPUTextureView resolveTarget;
    WGPULoadOp loadOp;
    WGPUStoreOp storeOp;
    WGPUColor clearValue;
} WGPURenderPassColorAttachment;

typedef struct WGPURenderPassDescriptor {
    WGPUChainedStruct const* nextInChain;
    const char* label;
    size_t colorAttachmentCount;
    const WGPURenderPassColorAttachment* colorAttachments;
    const void* depthStencilAttachment;
    const void* occlusionQuerySet;
    size_t timestampWriteCount;
    const void* timestampWrites;
} WGPURenderPassDescriptor;

typedef struct WGPUVertexAttribute {
    WGPUVertexFormat format;
    uint64_t offset;
    uint32_t shaderLocation;
} WGPUVertexAttribute;

typedef struct WGPUVertexBufferLayout {
    uint64_t arrayStride;
    WGPUVertexStepMode stepMode;
    size_t attributeCount;
    const WGPUVertexAttribute* attributes;
} WGPUVertexBufferLayout;

typedef struct WGPUVertexState {
    WGPUChainedStruct const* nextInChain;
    WGPUShaderModule module;
    const char* entryPoint;
    size_t constantCount;
    const void* constants;
    size_t bufferCount;
    const WGPUVertexBufferLayout* buffers;
} WGPUVertexState;

typedef struct WGPUPrimitiveState {
    WGPUChainedStruct const* nextInChain;
    WGPUPrimitiveTopology topology;
    int stripIndexFormat;
    WGPUFrontFace frontFace;
    WGPUCullMode cullMode;
} WGPUPrimitiveState;

typedef struct WGPUBlendComponent {
    WGPUBlendOperation operation;
    WGPUBlendFactor srcFactor;
    WGPUBlendFactor dstFactor;
} WGPUBlendComponent;

typedef struct WGPUBlendState {
    WGPUBlendComponent color;
    WGPUBlendComponent alpha;
} WGPUBlendState;

typedef struct WGPUColorTargetState {
    WGPUChainedStruct const* nextInChain;
    WGPUTextureFormat format;
    const WGPUBlendState* blend;
    WGPUColorWriteMaskFlags writeMask;
} WGPUColorTargetState;

typedef struct WGPUFragmentState {
    WGPUChainedStruct const* nextInChain;
    WGPUShaderModule module;
    const char* entryPoint;
    size_t constantCount;
    const void* constants;
    size_t targetCount;
    const WGPUColorTargetState* targets;
} WGPUFragmentState;

typedef struct WGPURenderPipelineDescriptor {
    WGPUChainedStruct const* nextInChain;
    const char* label;
    WGPUPipelineLayout layout;
    WGPUVertexState vertex;
    WGPUPrimitiveState primitive;
    const void* depthStencil;
    const void* multisample;
    const WGPUFragmentState* fragment;
} WGPURenderPipelineDescriptor;

typedef struct WGPUBindGroupLayoutEntry {
    WGPUChainedStruct const* nextInChain;
    uint32_t binding;
    WGPUShaderStageFlags visibility;
    struct {
        WGPUChainedStruct const* nextInChain;
        int type; // WGPUBufferBindingType
        int hasDynamicOffset;
        uint64_t minBindingSize;
    } buffer;
    struct {
        WGPUChainedStruct const* nextInChain;
        WGPUSamplerBindingType type;
    } sampler;
    struct {
        WGPUChainedStruct const* nextInChain;
        WGPUTextureSampleType sampleType;
        WGPUTextureViewDimension viewDimension;
        int multisampled;
    } texture;
    struct {
        WGPUChainedStruct const* nextInChain;
        int access;
        WGPUTextureFormat format;
        WGPUTextureViewDimension viewDimension;
    } storageTexture;
} WGPUBindGroupLayoutEntry;

typedef struct WGPUBindGroupLayoutDescriptor {
    WGPUChainedStruct const* nextInChain;
    const char* label;
    size_t entryCount;
    const WGPUBindGroupLayoutEntry* entries;
} WGPUBindGroupLayoutDescriptor;

typedef struct WGPUBindGroupEntry {
    WGPUChainedStruct const* nextInChain;
    uint32_t binding;
    WGPUBuffer buffer;
    uint64_t offset;
    uint64_t size;
    WGPUSampler sampler;
    WGPUTextureView textureView;
} WGPUBindGroupEntry;

typedef struct WGPUBindGroupDescriptor {
    WGPUChainedStruct const* nextInChain;
    const char* label;
    WGPUBindGroupLayout layout;
    size_t entryCount;
    const WGPUBindGroupEntry* entries;
} WGPUBindGroupDescriptor;

typedef struct WGPUPipelineLayoutDescriptor {
    WGPUChainedStruct const* nextInChain;
    const char* label;
    size_t bindGroupLayoutCount;
    const WGPUBindGroupLayout* bindGroupLayouts;
} WGPUPipelineLayoutDescriptor;

typedef struct WGPUImageCopyTexture {
    WGPUChainedStruct const* nextInChain;
    WGPUTexture texture;
    uint32_t mipLevel;
    struct { uint32_t x; uint32_t y; uint32_t z; } origin;
    WGPUTextureAspect aspect;
} WGPUImageCopyTexture;

typedef struct WGPUTextureDataLayout {
    WGPUChainedStruct const* nextInChain;
    uint64_t offset;
    uint32_t bytesPerRow;
    uint32_t rowsPerImage;
} WGPUTextureDataLayout;

// ---------------------------------------------------------------------------
// Callbacks
// ---------------------------------------------------------------------------

typedef void (*WGPURequestAdapterCallback)(WGPURequestAdapterStatus status, WGPUAdapter adapter, const char* message, void* userdata);
typedef void (*WGPURequestDeviceCallback)(WGPURequestDeviceStatus status, WGPUDevice device, const char* message, void* userdata);
typedef void (*WGPUErrorCallback)(int type, const char* message, void* userdata);

// ---------------------------------------------------------------------------
// Function declarations
// ---------------------------------------------------------------------------

#ifdef __cplusplus
extern "C" {
#endif

// Instance
WGPUInstance wgpuCreateInstance(const WGPUInstanceDescriptor* descriptor);
void wgpuInstanceRelease(WGPUInstance instance);
void wgpuInstanceRequestAdapter(WGPUInstance instance, const WGPURequestAdapterOptions* options, WGPURequestAdapterCallback callback, void* userdata);
WGPUSurface wgpuInstanceCreateSurface(WGPUInstance instance, const WGPUSurfaceDescriptor* descriptor);

// wgpu-native extension: synchronous adapter request
WGPUAdapter wgpuInstanceRequestAdapterSync(WGPUInstance instance, const WGPURequestAdapterOptions* options);

// Adapter
void wgpuAdapterRequestDevice(WGPUAdapter adapter, const WGPUDeviceDescriptor* descriptor, WGPURequestDeviceCallback callback, void* userdata);
void wgpuAdapterRelease(WGPUAdapter adapter);

// wgpu-native extension: synchronous device request
WGPUDevice wgpuAdapterRequestDeviceSync(WGPUAdapter adapter, const WGPUDeviceDescriptor* descriptor);

// Device
WGPUQueue wgpuDeviceGetQueue(WGPUDevice device);
WGPUSurface wgpuDeviceCreateSurface(WGPUDevice device, const WGPUSurfaceDescriptor* descriptor);
WGPUSwapChain wgpuDeviceCreateSwapChain(WGPUDevice device, WGPUSurface surface, const WGPUSwapChainDescriptor* descriptor);
WGPUShaderModule wgpuDeviceCreateShaderModule(WGPUDevice device, const WGPUShaderModuleDescriptor* descriptor);
WGPURenderPipeline wgpuDeviceCreateRenderPipeline(WGPUDevice device, const WGPURenderPipelineDescriptor* descriptor);
WGPUBindGroupLayout wgpuDeviceCreateBindGroupLayout(WGPUDevice device, const WGPUBindGroupLayoutDescriptor* descriptor);
WGPUBindGroup wgpuDeviceCreateBindGroup(WGPUDevice device, const WGPUBindGroupDescriptor* descriptor);
WGPUPipelineLayout wgpuDeviceCreatePipelineLayout(WGPUDevice device, const WGPUPipelineLayoutDescriptor* descriptor);
WGPUBuffer wgpuDeviceCreateBuffer(WGPUDevice device, const WGPUBufferDescriptor* descriptor);
WGPUTexture wgpuDeviceCreateTexture(WGPUDevice device, const WGPUTextureDescriptor* descriptor);
WGPUSampler wgpuDeviceCreateSampler(WGPUDevice device, const WGPUSamplerDescriptor* descriptor);
WGPUCommandEncoder wgpuDeviceCreateCommandEncoder(WGPUDevice device, const WGPUCommandEncoderDescriptor* descriptor);
void wgpuDeviceSetUncapturedErrorCallback(WGPUDevice device, WGPUErrorCallback callback, void* userdata);
void wgpuDeviceRelease(WGPUDevice device);

// Queue
void wgpuQueueSubmit(WGPUQueue queue, size_t commandCount, const WGPUCommandBuffer* commands);
void wgpuQueueWriteBuffer(WGPUQueue queue, WGPUBuffer buffer, uint64_t bufferOffset, const void* data, size_t size);
void wgpuQueueWriteTexture(WGPUQueue queue, const WGPUImageCopyTexture* destination, const void* data, size_t dataSize, const WGPUTextureDataLayout* dataLayout, const WGPUExtent3D* writeSize);
void wgpuQueueRelease(WGPUQueue queue);

// SwapChain
WGPUTextureView wgpuSwapChainGetCurrentTextureView(WGPUSwapChain swapChain);
void wgpuSwapChainPresent(WGPUSwapChain swapChain);
void wgpuSwapChainRelease(WGPUSwapChain swapChain);

// Texture
WGPUTextureView wgpuTextureCreateView(WGPUTexture texture, const WGPUTextureViewDescriptor* descriptor);
void wgpuTextureRelease(WGPUTexture texture);

// TextureView
void wgpuTextureViewRelease(WGPUTextureView textureView);

// Sampler
void wgpuSamplerRelease(WGPUSampler sampler);

// Buffer
void* wgpuBufferGetMappedRange(WGPUBuffer buffer, size_t offset, size_t size);
void wgpuBufferUnmap(WGPUBuffer buffer);
void wgpuBufferRelease(WGPUBuffer buffer);

// CommandEncoder
WGPURenderPassEncoder wgpuCommandEncoderBeginRenderPass(WGPUCommandEncoder commandEncoder, const WGPURenderPassDescriptor* descriptor);
WGPUCommandBuffer wgpuCommandEncoderFinish(WGPUCommandEncoder commandEncoder, const WGPUCommandBufferDescriptor* descriptor);
void wgpuCommandEncoderRelease(WGPUCommandEncoder commandEncoder);

// RenderPassEncoder
void wgpuRenderPassEncoderSetPipeline(WGPURenderPassEncoder renderPassEncoder, WGPURenderPipeline pipeline);
void wgpuRenderPassEncoderSetBindGroup(WGPURenderPassEncoder renderPassEncoder, uint32_t groupIndex, WGPUBindGroup group, size_t dynamicOffsetCount, const uint32_t* dynamicOffsets);
void wgpuRenderPassEncoderSetVertexBuffer(WGPURenderPassEncoder renderPassEncoder, uint32_t slot, WGPUBuffer buffer, uint64_t offset, uint64_t size);
void wgpuRenderPassEncoderDraw(WGPURenderPassEncoder renderPassEncoder, uint32_t vertexCount, uint32_t instanceCount, uint32_t firstVertex, uint32_t firstInstance);
void wgpuRenderPassEncoderEnd(WGPURenderPassEncoder renderPassEncoder);
void wgpuRenderPassEncoderRelease(WGPURenderPassEncoder renderPassEncoder);

// RenderPipeline
void wgpuRenderPipelineRelease(WGPURenderPipeline renderPipeline);

// BindGroup
void wgpuBindGroupRelease(WGPUBindGroup bindGroup);
void wgpuBindGroupLayoutRelease(WGPUBindGroupLayout bindGroupLayout);
void wgpuPipelineLayoutRelease(WGPUPipelineLayout pipelineLayout);

// CommandBuffer
void wgpuCommandBufferRelease(WGPUCommandBuffer commandBuffer);

// ShaderModule
void wgpuShaderModuleRelease(WGPUShaderModule shaderModule);

// Surface
void wgpuSurfaceRelease(WGPUSurface surface);

#ifdef __cplusplus
} // extern "C"
#endif

#endif // WEBGPU_H
