#pragma once
#include "VK_common.h"

struct VK_query_pool {
    static constexpr int MAX_QUERY_NUM = 2;
    VK_device* device_ptr = nullptr;
    VkQueryPool handle = NULL;
    uint32_t next_query_id = 0;
    
    inline operator VkQueryPool() const { return handle; }
    void init(VK_device* device_ptr);
    void deinit();
    void reset(VkCommandBuffer cmdbuf);
    uint32_t write_timestamp(VkCommandBuffer cmdbuf, VkPipelineStageFlagBits stage = VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT);
    uint64_t read_timestamp(uint32_t query_id);
};