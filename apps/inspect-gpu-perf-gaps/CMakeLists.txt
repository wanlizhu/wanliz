cmake_minimum_required(VERSION 3.10)
project("inspect-gpu-perf-gaps")

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

if (MSVC)
    # Make SYSTEM includes use /I instead of /external:I
    set(CMAKE_INCLUDE_SYSTEM_FLAG_C   "/I")
    set(CMAKE_INCLUDE_SYSTEM_FLAG_CXX "/I")
endif()

find_package(Vulkan REQUIRED)

add_executable(inspect-gpu-perf-gaps 
    "main.cpp"
    "common.h"
    "VK_physdev.cpp" 
    "VK_physdev.h" 
    "VK_instance.cpp"
    "VK_instance.h"
    "VK_queue.cpp"
    "VK_queue.h"
)

target_link_libraries(inspect-gpu-perf-gaps PRIVATE Vulkan::Vulkan)

