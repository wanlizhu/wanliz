#include "VkLayer_common.h"

VKAPI_ATTR VkResult VKAPI_CALL HKed_vkAllocateMemory(
    VkDevice device,
    const VkMemoryAllocateInfo* pAllocateInfo,
    const VkAllocationCallbacks* pAllocator,
    VkDeviceMemory* pMemory
) {
    std::cout << "HKed_vkAllocateMemory" << std::endl;
    return DEVICE_PFN_TABLE(device).pfn_vkAllocateMemory(device, pAllocateInfo, pAllocator, pMemory);
}

VKAPI_ATTR void VKAPI_CALL HKed_vkFreeMemory(
    VkDevice device,
    VkDeviceMemory memory,
    const VkAllocationCallbacks* pAllocator
) {
    DEVICE_PFN_TABLE(device).pfn_vkFreeMemory(device, memory, pAllocator);
}

