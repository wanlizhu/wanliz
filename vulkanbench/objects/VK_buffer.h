#pragma once
#include "VK_common.h"

struct VK_buffer {
    VK_device* device_ptr = nullptr;
    VkBuffer handle = NULL;
    VkBufferUsageFlags usageFlags = 0;
    size_t sizeInBytes = 0;
    VkDeviceMemory memory = NULL;
    VkMemoryPropertyFlags memoryFlags = 0;
    uint32_t memoryTypeIndex = UINT32_MAX;

    inline operator VkBuffer() const { return handle; }
    void init(
        VK_device* device_ptr, 
        size_t sizeInBytes,
        VkBufferUsageFlags usageFlags, 
        VK_createInfo_memType memType
    );
    void deinit();
    void write(const void* src, uint32_t sizeMax);  
    void write_noise();  
    VK_gpu_timer copy_from_buffer(VK_buffer& src);
    VK_gpu_timer copy_from_image(VK_image& src);
    std::shared_ptr<std::vector<uint8_t>> readback();  
};

struct VK_buffer_group {
    std::vector<VK_buffer> buffers;

    void init(
        size_t buffer_count,
        VK_device* device_ptr,
        size_t sizeInBytes,
        VkBufferUsageFlags usageFlags,
        VK_createInfo_memType memType
    );
    void deinit();
    void write_noise();
    VK_buffer& random_pick();
};