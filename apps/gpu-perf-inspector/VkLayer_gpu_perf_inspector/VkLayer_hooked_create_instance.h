#pragma once
#include "VkLayer_common.h"

VKAPI_ATTR VkResult VKAPI_CALL hooked_vkCreateInstance(
    const VkInstanceCreateInfo* pCreateInfo,
    const VkAllocationCallbacks* pAllocator,
    VkInstance* pInstance
);

VKAPI_ATTR PFN_vkVoidFunction VKAPI_CALL hooked_vkGetInstanceProcAddr(
    VkInstance instance, 
    const char* pName
);