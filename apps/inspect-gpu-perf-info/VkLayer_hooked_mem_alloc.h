#pragma once
#include "VkLayer_common.h"

VKAPI_ATTR VkResult VKAPI_CALL HKed_vkAllocateMemory(
    VkDevice device,
    const VkMemoryAllocateInfo* pAllocateInfo,
    const VkAllocationCallbacks* pAllocator,
    VkDeviceMemory* pMemory
);

VKAPI_ATTR void VKAPI_CALL HKed_vkFreeMemory(
    VkDevice device,
    VkDeviceMemory memory,
    const VkAllocationCallbacks* pAllocator
);

uint64_t GPU_VirtualAddress(VkDevice device, VkDeviceMemory memory, size_t size);