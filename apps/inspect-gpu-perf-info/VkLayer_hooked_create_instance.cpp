#include "VkLayer_hooked_create_instance.h"

VKAPI_ATTR VkResult VKAPI_CALL hooked_vkCreateInstance(
    const VkInstanceCreateInfo* pCreateInfo,
    const VkAllocationCallbacks* pAllocator,
    VkInstance* pInstance
) {
    VkLayerInstanceCreateInfo* layerCreateInfo = (VkLayerInstanceCreateInfo*)pCreateInfo->pNext;
    while (layerCreateInfo &&
           (layerCreateInfo->sType != VK_STRUCTURE_TYPE_LOADER_INSTANCE_CREATE_INFO ||
            layerCreateInfo->function != VK_LAYER_LINK_INFO)) {
        layerCreateInfo = (VkLayerInstanceCreateInfo*)layerCreateInfo->pNext;
    }
    
    if (!layerCreateInfo) {
        return VK_ERROR_INITIALIZATION_FAILED;
    }
    
    g_pfn_vkGetInstanceProcAddr = layerCreateInfo->u.pLayerInfo->pfnNextGetInstanceProcAddr;
    layerCreateInfo->u.pLayerInfo = layerCreateInfo->u.pLayerInfo->pNext;
    
    PFN_vkCreateInstance original_pfn_vkCreateInstance = (PFN_vkCreateInstance)g_pfn_vkGetInstanceProcAddr(VK_NULL_HANDLE, "vkCreateInstance");
    VkResult result = original_pfn_vkCreateInstance(pCreateInfo, pAllocator, pInstance);
    if (result == VK_SUCCESS) {
        g_VkInstance = *pInstance;
    }

    return result;
}

VKAPI_ATTR PFN_vkVoidFunction VKAPI_CALL hooked_vkGetInstanceProcAddr(
    VkInstance instance, 
    const char* pName
) {
    auto it = g_hooked_functions.find(pName);
    if (it != g_hooked_functions.end()) {
        return it->second;
    }

    return instance ? g_pfn_vkGetInstanceProcAddr(instance, pName) : nullptr;
}