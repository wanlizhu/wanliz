#pragma once

#include <vulkan/vulkan.h>
#include <unordered_map>
#include <mutex>
#include <cstring>
#include <iostream>

#define VK_LAYER_EXPORT __attribute__((visibility("default")))
#define GET_ID(handle) (*(void**)(handle))

struct VK_instance_dispatch_table {
    PFN_vkGetInstanceProcAddr pfn_vkGetInstanceProcAddr;
    PFN_vkDestroyInstance pfn_vkDestroyInstance;
    PFN_vkEnumerateDeviceExtensionProperties pfn_vkEnumerateDeviceExtensionProperties;
};

struct VK_device_dispatch_table {
    PFN_vkGetDeviceProcAddr pfn_vkGetDeviceProcAddr;
    PFN_vkDestroyDevice pfn_vkDestroyDevice;
    PFN_vkAllocateMemory pfn_vkAllocateMemory;
    PFN_vkFreeMemory pfn_vkFreeMemory;
};

extern std::unordered_map<void*, VK_instance_dispatch_table> g_dispatch_map_per_instance;
extern std::unordered_map<void*, VK_device_dispatch_table> g_dispatch_map_per_device;
extern std::mutex g_dispatch_map_mutex;

VKAPI_ATTR VkResult VKAPI_CALL HKed_vkAllocateMemory(
    VkDevice device,
    const VkMemoryAllocateInfo* pAllocateInfo,
    const VkAllocationCallbacks* pAllocator,
    VkDeviceMemory* pMemory
);

VKAPI_ATTR void VKAPI_CALL HKed_vkFreeMemory(
    VkDevice device,
    VkDeviceMemory memory,
    const VkAllocationCallbacks* pAllocator
);

