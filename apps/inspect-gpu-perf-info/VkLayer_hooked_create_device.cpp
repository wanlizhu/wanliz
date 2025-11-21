#include "VkLayer_hooked_create_device.h"

PFN_vkGetDeviceProcAddr g_pfn_vkGetDeviceProcAddr = NULL;

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
    g_pfn_vkGetDeviceProcAddr = layerCreateInfo->u.pLayerInfo->pfnNextGetDeviceProcAddr;
    layerCreateInfo->u.pLayerInfo = layerCreateInfo->u.pLayerInfo->pNext;
    
    PFN_vkCreateDevice original_pfn_vkCreateDevice = (PFN_vkCreateDevice)pfn_vkGetInstanceProcAddr(VK_NULL_HANDLE, "vkCreateDevice");
    return original_pfn_vkCreateDevice(physicalDevice, pCreateInfo, pAllocator, pDevice);
}

VKAPI_ATTR PFN_vkVoidFunction VKAPI_CALL HKed_vkGetDeviceProcAddr(
    VkDevice device, 
    const char* pName
) {
    auto it = g_hooked_functions.find(pName);
    if (it != g_hooked_functions.end()) {
        return it->second;
    }

    return device ? g_pfn_vkGetDeviceProcAddr(device, pName) : nullptr;
}