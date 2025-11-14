cmake_minimum_required (VERSION 3.8)
project ("inspect-gpu-perf-gaps")

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(Vulkan REQUIRED)

add_executable (inspect-gpu-perf-gaps 
    "main.cpp"
    "common.h"
    "VK_physdev.cpp" 
    "VK_physdev.h" 
    "VK_instance.cpp"
    "VK_instance.h"
    "VK_queue.cpp"
    "VK_queue.h")

target_link_libraries(inspect-gpu-perf-gaps PRIVATE Vulkan::Vulkan)