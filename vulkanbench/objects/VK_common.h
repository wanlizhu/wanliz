#pragma once
#ifdef _WIN32
#include <basetsd.h>
#endif
#include <iostream>
#include <fstream>
#include <sstream>
#include <string>
#include <cstring>
#include <stdexcept>
#include <algorithm>
#include <vector>
#include <filesystem>
#include <thread>
#include <mutex>
#include <condition_variable>
#include <chrono>
#include <optional>
#include <unordered_map>
#include <unordered_set>
#include <map>
#include <set>
#include <algorithm>
#include <functional>
#include <typeindex>
#include <typeinfo>
#include <type_traits>
#include <cstdint>
#include <cassert>
#include <cstdlib>
#include <memory>
#include <random>
#include <stdexcept>
#include <ratio>
#include <chrono>
#include <iomanip>
#include <stdexcept>
#include <string>
#include "cxxopts.hpp"

#ifdef ENABLE_RT_SHADER_COMPILE
#include <shaderc/shaderc.h>
#include <spirv_cross/spirv_cross_c.h>
#endif 

#ifdef _WIN32
#define VK_USE_PLATFORM_WIN32_KHR
#define NOMINMAX
#include <windows.h>
#elif defined(__linux__)
#define VK_USE_PLATFORM_XLIB_KHR
#endif
#include <vulkan/vulkan_core.h>
#ifdef _WIN32
#include <vulkan/vulkan_win32.h>
#endif
#ifdef __linux__
#include <sys/wait.h>
#include <unistd.h>
#include <fcntl.h>
#include <X11/Xlib.h>
#include <vulkan/vulkan_xlib.h>
#undef Bool
#undef True
#undef False
#endif

#define STR_EQUAL(a, b) ((a == nullptr || b == nullptr) ? false : (strcmp(a, b) == 0))

struct VK_device;
struct VK_buffer;
struct VK_image;

enum class VK_color {
    WHITE,
    BLACK,
    RED,
    GREEN,
    BLUE
};

struct VK_config {
    static cxxopts::ParseResult args;
};

struct VK_gpu_timer {
    uint64_t cpu_ns = 0;
    uint64_t gpu_ns = 0;

    VK_gpu_timer() = default;
    VK_gpu_timer(VK_device* device_ptr);
    void cpu_begin();
    void cpu_end();
    void gpu_begin(VkCommandBuffer cmdbuf);
    void gpu_end(VkCommandBuffer cmdbuf);
    bool validate() const;

private:
    VK_device* m_device_ptr = nullptr;
    std::chrono::high_resolution_clock::time_point m_cpu_begin_tp;
    uint32_t m_gpu_begin_id = UINT32_MAX;
    uint32_t m_gpu_end_id = UINT32_MAX;
    bool m_gpu_time_acquired = false;
};

struct VK_GB_per_second {
    double cpu_speed = 0.0;
    double cpu_robust_CoV = 0.0;
    double gpu_speed = 0.0;
    double gpu_robust_CoV = 0.0;

    VK_GB_per_second() = default;
    VK_GB_per_second(size_t bytes, const std::vector<VK_gpu_timer>& timers);

private:
    double robust_CoV(const std::vector<double>& samples);
};

struct VK_createInfo_memType {
    VkMemoryPropertyFlags flags = 0; // Use flags only if index is invalid
    uint32_t index = UINT32_MAX; // Try to use index first
};

bool str_starts_with(const char* str, const char* substr);
bool str_ends_with(const char* str, const char* substr);
bool str_contains(const char* str, const char* substr);
const char* str_after_rchar(const char* str, char chr);

std::string VkResult_str(VkResult result);
std::string VkMemoryPropertyFlags_str(VkMemoryPropertyFlags flags, bool short_str);
std::string human_readable_size(size_t bytes);
void print_table(const std::vector<std::vector<std::string>>& rows, std::ostream& out = std::cout);