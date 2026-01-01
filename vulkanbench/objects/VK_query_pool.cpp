#include "VK_query_pool.h"
#include "VK_device.h"
#include <stdexcept>

bool VK_query_pool::init(VK_device* dev_ptr) {
    device_ptr = dev_ptr;

    VkQueryPoolCreateInfo queryPoolInfo = {};
    queryPoolInfo.sType = VK_STRUCTURE_TYPE_QUERY_POOL_CREATE_INFO;
    queryPoolInfo.queryType = VK_QUERY_TYPE_TIMESTAMP;
    queryPoolInfo.queryCount = MAX_QUERY_NUM;

    VkResult result = vkCreateQueryPool(device_ptr->handle, &queryPoolInfo, nullptr, &handle);
    if (result != VK_SUCCESS) {
        std::cerr << "Failed to create timestamp query pool" << std::endl;
        return false;
    }

    next_query_id = 0;
    return true;
}

void VK_query_pool::deinit() {
    if (device_ptr != nullptr && handle != VK_NULL_HANDLE) {
        vkDestroyQueryPool(device_ptr->handle, handle, nullptr);
        handle = VK_NULL_HANDLE;
    }
    
    next_query_id = 0;
    device_ptr = nullptr;
}

void VK_query_pool::reset(VkCommandBuffer cmdbuf) {
    if (cmdbuf == VK_NULL_HANDLE || handle == VK_NULL_HANDLE) {
        return;
    }
    
    vkCmdResetQueryPool(cmdbuf, handle, 0, MAX_QUERY_NUM);
    next_query_id = 0;
}

uint32_t VK_query_pool::write_timestamp(VkCommandBuffer cmdbuf, VkPipelineStageFlagBits stage) {
    uint32_t query_id = next_query_id++;
    if (query_id >= MAX_QUERY_NUM) {
        throw std::runtime_error("VK_query_pool requires a reset");
    }
    vkCmdWriteTimestamp(cmdbuf, stage, handle, query_id);
    return query_id;
}

uint64_t VK_query_pool::read_timestamp(uint32_t query_id) {
    uint64_t timestamp = 0;
    VkResult result = vkGetQueryPoolResults(
        device_ptr->handle,
        handle,
        query_id,
        1,
        sizeof(uint64_t),
        &timestamp,
        sizeof(uint64_t),
        VK_QUERY_RESULT_64_BIT | VK_QUERY_RESULT_WAIT_BIT
    );

    if (result != VK_SUCCESS) {
        throw std::runtime_error("Failed to read GPU timestamp");
    }

    float timestampPeriod = device_ptr->physdev.properties.limits.timestampPeriod;

    if (std::abs(timestampPeriod - 1.0f) < std::numeric_limits<float>::epsilon()) {
        return timestamp;
    }

    return static_cast<uint64_t>(timestamp * timestampPeriod);
}