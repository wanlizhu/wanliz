#pragma once
#include "VkLayer_common.h"

VKAPI_ATTR VkResult VKAPI_CALL HKed_vkCreateDevice(
    VkPhysicalDevice physicalDevice,
    const VkDeviceCreateInfo* pCreateInfo,
    const VkAllocationCallbacks* pAllocator,
    VkDevice* pDevice
);

VKAPI_ATTR void VKAPI_CALL HKed_vkDestroyDevice(
    VkDevice device,
    const VkAllocationCallbacks* pAllocator
);

VKAPI_ATTR PFN_vkVoidFunction VKAPI_CALL HKed_vkGetDeviceProcAddr(
    VkDevice device, 
    const char* pName
);