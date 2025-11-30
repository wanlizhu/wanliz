#include "VkLayer_common.h"
#include "VkLayer_hooked_create_instance.h"
#include "VkLayer_hooked_create_device.h"
#include "VkLayer_hooked_mem_alloc.h"

extern "C" {
    VK_LAYER_EXPORT VKAPI_ATTR VkResult VKAPI_CALL vkNegotiateLoaderLayerInterfaceVersion(
        VkNegotiateLayerInterface* pVersionStruct
    ) {
        if (pVersionStruct->loaderLayerInterfaceVersion > 2) {
            pVersionStruct->loaderLayerInterfaceVersion = 2;
        }
        pVersionStruct->pfnGetInstanceProcAddr = hooked_vkGetInstanceProcAddr;
        pVersionStruct->pfnGetDeviceProcAddr = hooked_vkGetDeviceProcAddr;
        pVersionStruct->pfnGetPhysicalDeviceProcAddr = nullptr;
    
        g_hooked_functions["vkCreateInstance"] = (PFN_vkVoidFunction)hooked_vkCreateInstance;
        g_hooked_functions["vkCreateDevice"] = (PFN_vkVoidFunction)hooked_vkCreateDevice;
        g_hooked_functions["vkAllocateMemory"] = (PFN_vkVoidFunction)hooked_vkAllocateMemory;
        g_hooked_functions["vkFreeMemory"] = (PFN_vkVoidFunction)hooked_vkFreeMemory;
    
        std::cout << "[inspect gpu perf info] Hello World" << std::endl;
        
        return VK_SUCCESS;
    }

    VK_LAYER_EXPORT VKAPI_ATTR PFN_vkVoidFunction VKAPI_CALL vkGetInstanceProcAddr(VkInstance instance, const char* pName) {
        return hooked_vkGetInstanceProcAddr(instance, pName);
    }
    
    VK_LAYER_EXPORT VKAPI_ATTR PFN_vkVoidFunction VKAPI_CALL vkGetDeviceProcAddr(VkDevice device, const char* pName) {
        return hooked_vkGetDeviceProcAddr(device, pName);
    }
}
