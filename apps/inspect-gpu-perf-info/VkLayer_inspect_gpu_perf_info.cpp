#include "VkLayer_common.h"
#include <vulkan/vk_layer.h>

std::unordered_map<void*, VK_instance_dispatch_table> g_dispatch_map_per_instance;
std::unordered_map<void*, VK_device_dispatch_table> g_dispatch_map_per_device;
std::mutex g_dispatch_map_mutex;

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
    
    VK_device_dispatch_table deviceTable = {};
    deviceTable.pfn_vkGetDeviceProcAddr = pfn_vkGetDeviceProcAddr;
    deviceTable.pfn_vkDestroyDevice = (PFN_vkDestroyDevice)pfn_vkGetDeviceProcAddr(*pDevice, "vkDestroyDevice");
    deviceTable.pfn_vkAllocateMemory = (PFN_vkAllocateMemory)pfn_vkGetDeviceProcAddr(*pDevice, "vkAllocateMemory");
    deviceTable.pfn_vkFreeMemory = (PFN_vkFreeMemory)pfn_vkGetDeviceProcAddr(*pDevice, "vkFreeMemory");
    
    std::lock_guard<std::mutex> lock(g_dispatch_map_mutex);
    g_dispatch_map_per_device[GET_ID(*pDevice)] = deviceTable;
    
    return VK_SUCCESS;
}

VKAPI_ATTR void VKAPI_CALL HKed_vkDestroyDevice(
    VkDevice device,
    const VkAllocationCallbacks* pAllocator
) {
    
    std::lock_guard<std::mutex> lock(g_dispatch_map_mutex);
    g_dispatch_map_per_device[GET_ID(device)].pfn_vkDestroyDevice(device, pAllocator);
    g_dispatch_map_per_device.erase(GET_ID(device));
}

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
    
    VK_instance_dispatch_table instanceTable = {};
    instanceTable.pfn_vkGetInstanceProcAddr = pfn_vkGetInstanceProcAddr;
    instanceTable.pfn_vkDestroyInstance = (PFN_vkDestroyInstance)pfn_vkGetInstanceProcAddr(*pInstance, "vkDestroyInstance");
    instanceTable.pfn_vkEnumerateDeviceExtensionProperties = 
        (PFN_vkEnumerateDeviceExtensionProperties)pfn_vkGetInstanceProcAddr(*pInstance, "vkEnumerateDeviceExtensionProperties");
    
    std::lock_guard<std::mutex> lock(g_dispatch_map_mutex);
    g_dispatch_map_per_instance[GET_ID(*pInstance)] = instanceTable;
    
    return VK_SUCCESS;
}

VKAPI_ATTR void VKAPI_CALL HKed_vkDestroyInstance(
    VkInstance instance,
    const VkAllocationCallbacks* pAllocator
) {
    
    std::lock_guard<std::mutex> lock(g_dispatch_map_mutex);
    g_dispatch_map_per_instance[GET_ID(instance)].pfn_vkDestroyInstance(instance, pAllocator);
    g_dispatch_map_per_instance.erase(GET_ID(instance));
}

VKAPI_ATTR PFN_vkVoidFunction VKAPI_CALL HKed_vkGetDeviceProcAddr(
    VkDevice device, 
    const char* pName
) {
    if (std::strcmp(pName, "vkGetDeviceProcAddr") == 0) {
        return (PFN_vkVoidFunction)HKed_vkGetDeviceProcAddr;
    }
    if (std::strcmp(pName, "vkDestroyDevice") == 0) {
        return (PFN_vkVoidFunction)HKed_vkDestroyDevice;
    }
    if (std::strcmp(pName, "vkAllocateMemory") == 0) {
        return (PFN_vkVoidFunction)HKed_vkAllocateMemory;
    }
    if (std::strcmp(pName, "vkFreeMemory") == 0) {
        return (PFN_vkVoidFunction)HKed_vkFreeMemory;
    }
    
    if (device) {
        return g_dispatch_map_per_device[GET_ID(device)].pfn_vkGetDeviceProcAddr(device, pName);
    }
    
    return nullptr;
}

VKAPI_ATTR PFN_vkVoidFunction VKAPI_CALL HKed_vkGetInstanceProcAddr(
    VkInstance instance, 
    const char* pName
) {
    if (std::strcmp(pName, "vkGetInstanceProcAddr") == 0) {
        return (PFN_vkVoidFunction)HKed_vkGetInstanceProcAddr;
    }
    if (std::strcmp(pName, "vkCreateInstance") == 0) {
        return (PFN_vkVoidFunction)HKed_vkCreateInstance;
    }
    if (std::strcmp(pName, "vkDestroyInstance") == 0) {
        return (PFN_vkVoidFunction)HKed_vkDestroyInstance;
    }
    if (std::strcmp(pName, "vkCreateDevice") == 0) {
        return (PFN_vkVoidFunction)HKed_vkCreateDevice;
    }
    if (std::strcmp(pName, "vkGetDeviceProcAddr") == 0) {
        return (PFN_vkVoidFunction)HKed_vkGetDeviceProcAddr;
    }
    
    if (instance) {
        return g_dispatch_map_per_instance[GET_ID(instance)].pfn_vkGetInstanceProcAddr(instance, pName);
    }
    
    return nullptr;
}

extern "C" VK_LAYER_EXPORT VKAPI_ATTR VkResult VKAPI_CALL vkNegotiateLoaderLayerInterfaceVersion(
    VkNegotiateLayerInterface* pVersionStruct
) {
    if (pVersionStruct->loaderLayerInterfaceVersion > 2) {
        pVersionStruct->loaderLayerInterfaceVersion = 2;
    }
    
    pVersionStruct->pfnGetInstanceProcAddr = HKed_vkGetInstanceProcAddr;
    pVersionStruct->pfnGetDeviceProcAddr = HKed_vkGetDeviceProcAddr;
    pVersionStruct->pfnGetPhysicalDeviceProcAddr = nullptr;

    std::cout << "[inspect gpu perf info] Hello World" << std::endl;
    
    return VK_SUCCESS;
}

extern "C" {
    VK_LAYER_EXPORT VKAPI_ATTR PFN_vkVoidFunction VKAPI_CALL vkGetInstanceProcAddr(VkInstance instance, const char* pName) {
        return HKed_vkGetInstanceProcAddr(instance, pName);
    }
    
    VK_LAYER_EXPORT VKAPI_ATTR PFN_vkVoidFunction VKAPI_CALL vkGetDeviceProcAddr(VkDevice device, const char* pName) {
        return HKed_vkGetDeviceProcAddr(device, pName);
    }
}
