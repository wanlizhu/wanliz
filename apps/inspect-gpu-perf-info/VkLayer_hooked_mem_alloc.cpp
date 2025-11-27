#include "VkLayer_common.h"

VKAPI_ATTR VkResult VKAPI_CALL HKed_vkAllocateMemory(
    VkDevice device,
    const VkMemoryAllocateInfo* pAllocateInfo,
    const VkAllocationCallbacks* pAllocator,
    VkDeviceMemory* pMemory
) {
    VK_DEFINE_ORIGINAL_FUNC(vkAllocateMemory);

    VkResult result = original_pfn_vkAllocateMemory(device, pAllocateInfo, pAllocator, pMemory);

    return result;
}

VKAPI_ATTR void VKAPI_CALL HKed_vkFreeMemory(
    VkDevice device,
    VkDeviceMemory memory,
    const VkAllocationCallbacks* pAllocator
) {
    VK_DEFINE_ORIGINAL_FUNC(vkFreeMemory);
    original_pfn_vkFreeMemory(device, memory, pAllocator);
}

