cmake_minimum_required(VERSION 3.10)
project("inspect-gpu-perf-info")

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

find_package(Vulkan REQUIRED)

add_executable(inspect-gpu-perf-info 
    "main.cpp"
    "common.h"
    "VK_physdev.cpp" 
    "VK_physdev.h" 
    "VK_instance.cpp"
    "VK_instance.h"
    "VK_queue.cpp"
    "VK_queue.h"
)

target_include_directories(inspect-gpu-perf-info PRIVATE ${Vulkan_INCLUDE_DIRS})
target_link_libraries(inspect-gpu-perf-info PRIVATE Vulkan::Vulkan)

