#pragma once

#include <vulkan/vulkan.h>
#include <vulkan/vk_layer.h>
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
#ifdef __linux__
#include <sys/wait.h>
#include <unistd.h>
#include <fcntl.h>
#include <stdlib.h>
#endif 

#define VK_LAYER_EXPORT __attribute__((visibility("default")))
#define VK_DEFINE_ORIGINAL_FUNC(name) static PFN_##name original_pfn_##name = NULL; \
    if (original_pfn_##name == NULL) { \
        original_pfn_##name = (PFN_##name)g_pfn_vkGetDeviceProcAddr(device, #name); \
    } assert(original_pfn_##name)

extern PFN_vkGetInstanceProcAddr g_pfn_vkGetInstanceProcAddr;
extern PFN_vkGetDeviceProcAddr g_pfn_vkGetDeviceProcAddr;
extern std::unordered_map<std::string, PFN_vkVoidFunction> g_hooked_functions;

struct VkLayer_redirect_STDOUT {
    VkLayer_redirect_STDOUT(const char* path);
    ~VkLayer_redirect_STDOUT();

private:
    int original_stdout;
};

struct VkLayer_profiler {
    std::chrono::high_resolution_clock::time_point startTime_cpu;

    VkLayer_profiler();
    void end();
};