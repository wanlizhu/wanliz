#include "VkLayer_common.h"

VKAPI_ATTR VkResult VKAPI_CALL HKed_vkAllocateMemory(
    VkDevice device,
    const VkMemoryAllocateInfo* pAllocateInfo,
    const VkAllocationCallbacks* pAllocator,
    VkDeviceMemory* pMemory
) {
    VK_DEFINE_ORIGINAL_FUNC(vkAllocateMemory);

    setenv("__GL_DEBUG_MASK", "RM", 1);
    setenv("__GL_DEBUG_LEVEL", "30", 1);
    setenv("__GL_DEBUG_OPTIONS", "LOG_TO_FILE", 1);
    setenv("__GL_DEBUG_FILENAME", "/tmp/rm-api-loggings", 1);

    VkResult result = original_pfn_vkAllocateMemory(device, pAllocateInfo, pAllocator, pMemory);
    
    if (std::filesystem::exists("/usr/local/bin/process-vidheap.py")) {
        system("process-vidheap.py /tmp/rm-api-loggings");
    }

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

