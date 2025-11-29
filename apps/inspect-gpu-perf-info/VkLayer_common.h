#pragma once

#include "vulkan/vulkan.h"
#include "vulkan/vk_layer.h"
#include <unordered_map>
#include <filesystem>
#include <mutex>
#include <cstring>
#include <iostream>
#include <cassert>
#include <chrono>
#include <string>
#include <vector>
#include <regex>
#include <fstream>
#include <sstream>
#include <cstdio>
#include <cstdlib>
#include <algorithm>
#include <functional>
#include <typeindex>
#include <typeinfo>
#include <type_traits>
#include <cstdint>
#include <cassert>
#include <cstring>
#include <cstdlib>
#include <stdexcept>
#include <thread>
#include <optional>
#include <inttypes.h>
#include <iterator>
#include <cctype>
#ifdef __linux__
#include <sys/wait.h>
#include <unistd.h>
#include <fcntl.h>
#include <stdlib.h>
#endif 

#ifdef __linux__
#define VK_LAYER_EXPORT __attribute__((visibility("default")))
#else 
#define VK_LAYER_EXPORT
#endif 

#define VK_DEFINE_ORIGINAL_FUNC(name) static PFN_##name original_pfn_##name = NULL; \
    if (original_pfn_##name == NULL) { \
        original_pfn_##name = (PFN_##name)g_pfn_vkGetDeviceProcAddr(device, #name); \
    } assert(original_pfn_##name)

extern PFN_vkGetInstanceProcAddr g_pfn_vkGetInstanceProcAddr;
extern PFN_vkGetDeviceProcAddr g_pfn_vkGetDeviceProcAddr;
extern std::unordered_map<std::string, PFN_vkVoidFunction> g_hooked_functions;
extern VkInstance g_VkInstance;
extern std::unordered_map<VkDevice, VkPhysicalDevice> g_physicalDeviceMap;

struct VkLayer_redirect_STDOUT {
    VkLayer_redirect_STDOUT(const char* path);
    ~VkLayer_redirect_STDOUT();

private:
    int original_stdout;
};

struct VkLayer_redirect_STDERR {
    VkLayer_redirect_STDERR(const char* path);
    ~VkLayer_redirect_STDERR();

private:
    int original_stderr;
};

struct VkLayer_DeviceAddressFeature {
    static bool enabled;
    static void enable(
        VkPhysicalDevice physicalDevice, 
        VkDeviceCreateInfo* pDeviceCreateInfo
    );
};

char* VkLayer_readbuf(const char* path, bool trim);