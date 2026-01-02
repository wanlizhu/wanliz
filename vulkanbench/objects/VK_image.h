#pragma once
#include "VK_common.h"

struct VK_image : public VK_refcounted_object {
    VK_device* device_ptr = nullptr;
    VkImage handle = NULL;
    VkImageView view = NULL;
    VkImageUsageFlags usageFlags = 0;
    VkImageAspectFlags aspectFlags = 0;
    VkFormat format = VK_FORMAT_UNDEFINED;
    VkImageLayout currentImageLayout = VK_IMAGE_LAYOUT_UNDEFINED;
    VkExtent2D extent = {};
    size_t sizeInBytes = 0;
    VkDeviceMemory memory = NULL;
    VkMemoryPropertyFlags memoryFlags = 0;
    uint32_t memoryTypeIndex = UINT32_MAX;

    inline operator VkImage() const { return handle; }
    bool init(
        VK_device* device_ptr, 
        VkFormat format, 
        VkExtent2D extent, 
        VkImageUsageFlags usageFlags, 
        VK_createInfo_memType memType,
        VkImageTiling tiling = VK_IMAGE_TILING_OPTIMAL
    );
    void deinit();
    void write(const void* src, size_t sizeMax);
    void write_noise();
    VK_gpu_timer copy_from_buffer(VK_buffer& src);
    VK_gpu_timer copy_from_image(VK_image& src);
    std::shared_ptr<std::vector<uint8_t>> readback();
    void image_layout_transition(VkCommandBuffer cmdbuf, VkImageLayout dstLayout);
};