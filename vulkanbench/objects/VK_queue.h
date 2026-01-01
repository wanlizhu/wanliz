#pragma once
#include "VK_common.h"
#include "VK_query_pool.h"

struct VK_queue {
    VK_device* device_ptr = nullptr;
    VkQueue handle = NULL;
    uint32_t family_index = UINT32_MAX;
    VkQueueFamilyProperties properties = {};
    bool supportPresenting = false;
    VkCommandPool commandPool = NULL;

    inline operator VkQueue() const { return handle; }
    bool init(VK_device* device_ptr, uint32_t family, bool presenting);
    void deinit();

    void create_command_pool();
    VkCommandBuffer alloc_and_begin_command_buffer(const std::string& name);
    void cmdbuf_debug_range_begin(VkCommandBuffer cmdbuf, const std::string& label, VK_color color);
    void cmdbuf_debug_range_end(VkCommandBuffer cmdbuf);
    void submit_and_wait_command_buffer(VkCommandBuffer cmdbuf);
};