#include "VkLayer_hooked_create_device.h"

VKAPI_ATTR VkResult VKAPI_CALL HKed_vkCreateDevice(
    VkPhysicalDevice physicalDevice,
    const VkDeviceCreateInfo* pCreateInfo,
    const VkAllocationCallbacks* pAllocator,
    VkDevice* pDevice
) {
    VkLayerDeviceCreateInfo* layerCreateInfo = (VkLayerDeviceCreateInfo*)pCreateInfo->pNext;
    while (layerCreateInfo && 
           (layerCreateInfo->sType != VK_STRUCTURE_TYPE_LOADER_DEVICE_CREATE_INFO ||
            layerCreateInfo->function != VK_LAYER_LINK_INFO)) {
        layerCreateInfo = (VkLayerDeviceCreateInfo*)layerCreateInfo->pNext;
    }
    
    if (!layerCreateInfo) {
        return VK_ERROR_INITIALIZATION_FAILED;
    }
    
    PFN_vkGetInstanceProcAddr pfn_vkGetInstanceProcAddr = layerCreateInfo->u.pLayerInfo->pfnNextGetInstanceProcAddr;
    PFN_vkGetDeviceProcAddr pfn_vkGetDeviceProcAddr = layerCreateInfo->u.pLayerInfo->pfnNextGetDeviceProcAddr;
    layerCreateInfo->u.pLayerInfo = layerCreateInfo->u.pLayerInfo->pNext;
    
    PFN_vkCreateDevice pfn_vkCreateDevice = (PFN_vkCreateDevice)pfn_vkGetInstanceProcAddr(VK_NULL_HANDLE, "vkCreateDevice");
    VkResult result = pfn_vkCreateDevice(physicalDevice, pCreateInfo, pAllocator, pDevice);
    
    if (result != VK_SUCCESS) {
        return result;
    }
    
    std::lock_guard<std::mutex> lock(g_dispatch_map_mutex);
    g_dispatch_map_per_device.insert(std::make_pair(GET_ID(*pDevice), VK_device_dispatch_table(*pDevice, pfn_vkGetDeviceProcAddr)));
    
    return VK_SUCCESS;
}

VKAPI_ATTR void VKAPI_CALL HKed_vkDestroyDevice(
    VkDevice device,
    const VkAllocationCallbacks* pAllocator
) {
    std::lock_guard<std::mutex> lock(g_dispatch_map_mutex);
    DEVICE_PFN_TABLE(device).pfn_vkDestroyDevice(device, pAllocator);
    g_dispatch_map_per_device.erase(GET_ID(device));
}

VKAPI_ATTR PFN_vkVoidFunction VKAPI_CALL HKed_vkGetDeviceProcAddr(
    VkDevice device, 
    const char* pName
) {
    if (auto it = g_hooked_functions.find(pName); it != g_hooked_functions.end()) {
        return it->second;
    }
    return device ? DEVICE_PFN_TABLE(device).pfn_vkGetDeviceProcAddr(device, pName) : nullptr;
}