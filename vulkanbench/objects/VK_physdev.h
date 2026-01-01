#pragma once
#include "VK_common.h"
#include "VK_queue.h"

struct VK_physdev {
    VkPhysicalDevice handle = NULL;
    uint32_t index = UINT32_MAX;
    VkPhysicalDeviceFeatures features = {};
    VkPhysicalDeviceProperties properties = {};
    VkPhysicalDeviceDriverProperties driver = {};
    VkPhysicalDeviceMemoryProperties memory = {};
    std::vector<std::string> extensions = {};
    std::vector<VK_queue> queues = {};
    VkDeviceSize maxAllocSize = 0;

    static std::vector<VK_physdev> LIST();
    inline operator VkPhysicalDevice() const { return handle; }
    bool init(int idx);
    void deinit();

    uint32_t find_first_queue_family_supports(VkQueueFlags flags, bool presenting);
    uint32_t find_first_memtype_supports(VkMemoryPropertyFlags flags, uint32_t filters = UINT32_MAX, bool exclusive = false);
};