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
    std::map<VkCommandBuffer, std::vector<VkSemaphore>> semaphores;

    inline operator VkQueue() const { return handle; }
    void init(VK_device* device_ptr, uint32_t family, bool presenting);
    void deinit();

    void create_command_pool();
    VkCommandBuffer alloc_and_begin_command_buffer(const std::string& name);
    VkSemaphore allocate_semaphore_bound_for(VkCommandBuffer cmdbuf);
    void cmdbuf_debug_range_begin(VkCommandBuffer cmdbuf, const std::string& label, VK_color color);
    void cmdbuf_debug_range_end(VkCommandBuffer cmdbuf);
    void submit_and_wait_command_buffer(VkCommandBuffer cmdbuf);
};