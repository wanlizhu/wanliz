#pragma once
#include "VK_common.h"
#include "VK_physdev.h"
#include "VK_query_pool.h"
#include "VK_swapchain.h"

struct VK_device {
    VkDevice handle = NULL;
    VK_queue cmdqueue;
    VK_physdev physdev;
    VK_swapchain swapchain;
    VK_query_pool querypool;

    inline operator VkDevice() const { return handle; }
    bool init(int index, uint32_t queueFlags, int window_width, int window_height);
    void deinit();
};