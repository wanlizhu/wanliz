#include "VkLayer_common.h"

VKAPI_ATTR VkResult VKAPI_CALL HKed_vkAllocateMemory(
    VkDevice device,
    const VkMemoryAllocateInfo* pAllocateInfo,
    const VkAllocationCallbacks* pAllocator,
    VkDeviceMemory* pMemory
) {
    
    VK_device_dispatch_table& table = g_dispatch_map_per_device[GET_ID(device)];
    VkResult result = table.pfn_vkAllocateMemory(device, pAllocateInfo, pAllocator, pMemory);
    return result;
}

VKAPI_ATTR void VKAPI_CALL HKed_vkFreeMemory(
    VkDevice device,
    VkDeviceMemory memory,
    const VkAllocationCallbacks* pAllocator
) {
    g_dispatch_map_per_device[GET_ID(device)].pfn_vkFreeMemory(device, memory, pAllocator);
}

