#pragma once
#include "VK_common.h"

struct VK_queue {
    VkQueue handle = NULL;
    uint32_t family_index = UINT32_MAX;
    VkQueueFamilyProperties properties = {};

    VK_queue(VkPhysicalDevice physdev, VkDevice device, uint32_t family);
};