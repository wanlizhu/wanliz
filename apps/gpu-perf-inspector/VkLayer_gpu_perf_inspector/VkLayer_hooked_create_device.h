#pragma once
#include "VkLayer_common.h"

VKAPI_ATTR VkResult VKAPI_CALL hooked_vkCreateDevice(
    VkPhysicalDevice physicalDevice,
    const VkDeviceCreateInfo* pCreateInfo,
    const VkAllocationCallbacks* pAllocator,
    VkDevice* pDevice
);

VKAPI_ATTR PFN_vkVoidFunction VKAPI_CALL hooked_vkGetDeviceProcAddr(
    VkDevice device, 
    const char* pName
);