#include "VkLayer_hooked_create_instance.h"

VKAPI_ATTR VkResult VKAPI_CALL HKed_vkCreateInstance(
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
    
    PFN_vkGetInstanceProcAddr pfn_vkGetInstanceProcAddr = layerCreateInfo->u.pLayerInfo->pfnNextGetInstanceProcAddr;
    layerCreateInfo->u.pLayerInfo = layerCreateInfo->u.pLayerInfo->pNext;
    
    PFN_vkCreateInstance pfn_vkCreateInstance = (PFN_vkCreateInstance)pfn_vkGetInstanceProcAddr(VK_NULL_HANDLE, "vkCreateInstance");
    VkResult result = pfn_vkCreateInstance(pCreateInfo, pAllocator, pInstance);
    
    if (result != VK_SUCCESS) {
        return result;
    }
    
    std::lock_guard<std::mutex> lock(g_dispatch_map_mutex);
    g_dispatch_map_per_instance.insert(std::make_pair(GET_ID(*pInstance), VK_instance_dispatch_table(*pInstance, pfn_vkGetInstanceProcAddr)));
    
    return VK_SUCCESS;
}

VKAPI_ATTR void VKAPI_CALL HKed_vkDestroyInstance(
    VkInstance instance,
    const VkAllocationCallbacks* pAllocator
) {
    std::lock_guard<std::mutex> lock(g_dispatch_map_mutex);
    g_dispatch_map_per_instance.at(GET_ID(instance)).pfn_vkDestroyInstance(instance, pAllocator);
    g_dispatch_map_per_instance.erase(GET_ID(instance));
}

VKAPI_ATTR PFN_vkVoidFunction VKAPI_CALL HKed_vkGetInstanceProcAddr(
    VkInstance instance, 
    const char* pName
) {
    if (auto it = g_hooked_functions.find(pName); it != g_hooked_functions.end()) {
        return it->second;
    }
    return instance ? INSTANCE_PFN_TABLE(instance).pfn_vkGetInstanceProcAddr(instance, pName) : nullptr;
}