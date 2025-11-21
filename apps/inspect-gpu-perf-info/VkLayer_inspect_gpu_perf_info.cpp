#include "VkLayer_common.h"
#include "VkLayer_hooked_create_instance.h"
#include "VkLayer_hooked_create_device.h"
#include "VkLayer_hooked_mem_alloc.h"

std::unordered_map<std::string, PFN_vkVoidFunction> g_hooked_functions;
std::unordered_map<void*, VK_instance_dispatch_table> g_dispatch_map_per_instance;
std::unordered_map<void*, VK_device_dispatch_table> g_dispatch_map_per_device;
std::mutex g_dispatch_map_mutex;

VK_instance_dispatch_table::VK_instance_dispatch_table(
    VkInstance instance, 
    PFN_vkGetInstanceProcAddr _vkGetInstanceProcAddr
) {
#define GET_INSTANCE_PFN(name) pfn_##name = (PFN_##name)_vkGetInstanceProcAddr(instance, #name)
    GET_INSTANCE_PFN(vkCreateInstance);
    GET_INSTANCE_PFN(vkDestroyInstance);
    GET_INSTANCE_PFN(vkGetInstanceProcAddr);
#undef GET_INSTANCE_PFN
}

VK_device_dispatch_table::VK_device_dispatch_table(
    VkDevice device, 
    PFN_vkGetDeviceProcAddr _vkGetDeviceProcAddr
) {
#define GET_DEVICE_PFN(name) pfn_##name = (PFN_##name)_vkGetDeviceProcAddr(device, #name) 
    GET_DEVICE_PFN(vkCreateDevice);
    GET_DEVICE_PFN(vkDestroyDevice);
    GET_DEVICE_PFN(vkGetDeviceProcAddr);
    GET_DEVICE_PFN(vkAllocateMemory);
    GET_DEVICE_PFN(vkFreeMemory);    
#undef GET_DEVICE_PFN
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

    g_hooked_functions["vkCreateInstance"] = (PFN_vkVoidFunction)HKed_vkCreateInstance;
    g_hooked_functions["vkDestroyInstance"] = (PFN_vkVoidFunction)HKed_vkDestroyInstance;
    g_hooked_functions["vkCreateDevice"] = (PFN_vkVoidFunction)HKed_vkCreateDevice;
    g_hooked_functions["vkDestroyDevice"] = (PFN_vkVoidFunction)HKed_vkDestroyDevice;
    g_hooked_functions["vkAllocateMemory"] = (PFN_vkVoidFunction)HKed_vkAllocateMemory;
    g_hooked_functions["vkFreeMemory"] = (PFN_vkVoidFunction)HKed_vkFreeMemory;

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
