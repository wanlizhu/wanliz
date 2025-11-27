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
#ifdef __linux__
#include <sys/wait.h>
#include <unistd.h>
#include <fcntl.h>
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
    std::chrono::high_resolution_clock::time_point startTime;
    std::string startPageTablesFilePath;
    std::string rmApiLoggingsFilePath;

    VkLayer_profiler();
    void end();

private:
    void capture_gpu_page_tables(const std::string& path);
    void capture_rm_api_loggings(const std::string& path);
};