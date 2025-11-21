#pragma once

#include <vulkan/vulkan.h>
#include <vulkan/vk_layer.h>
#include <unordered_map>
#include <mutex>
#include <cstring>
#include <iostream>

#define VK_LAYER_EXPORT __attribute__((visibility("default")))
#define GET_ID(handle) (*(void**)(handle))
#define INSTANCE_PFN_TABLE(instance) g_dispatch_map_per_instance.at(GET_ID(instance))
#define DEVICE_PFN_TABLE(device) g_dispatch_map_per_device.at(GET_ID(device))

struct VK_instance_dispatch_table {
    PFN_vkGetInstanceProcAddr pfn_vkGetInstanceProcAddr;
    PFN_vkDestroyInstance pfn_vkDestroyInstance;
    PFN_vkEnumerateDeviceExtensionProperties pfn_vkEnumerateDeviceExtensionProperties;

    VK_instance_dispatch_table(VkInstance instance, PFN_vkGetInstanceProcAddr _vkGetInstanceProcAddr);
};

struct VK_device_dispatch_table {
    PFN_vkGetDeviceProcAddr pfn_vkGetDeviceProcAddr;
    PFN_vkDestroyDevice pfn_vkDestroyDevice;
    PFN_vkAllocateMemory pfn_vkAllocateMemory;
    PFN_vkFreeMemory pfn_vkFreeMemory;

    VK_device_dispatch_table(VkDevice device, PFN_vkGetDeviceProcAddr _vkGetDeviceProcAddr);
};

extern std::unordered_map<std::string, PFN_vkVoidFunction> g_hooked_functions;
extern std::unordered_map<void*, VK_instance_dispatch_table> g_dispatch_map_per_instance;
extern std::unordered_map<void*, VK_device_dispatch_table> g_dispatch_map_per_device;
extern std::mutex g_dispatch_map_mutex;


