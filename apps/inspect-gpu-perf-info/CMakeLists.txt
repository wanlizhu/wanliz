cmake_minimum_required(VERSION 3.10)
project("inspect-gpu-perf-info")

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)
file(CREATE_LINK 
    "${CMAKE_BINARY_DIR}/compile_commands.json"
    "${CMAKE_SOURCE_DIR}/compile_commands.json"
    SYMBOLIC)

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

target_compile_definitions(inspect-gpu-perf-info PRIVATE CMAKE_BINARY_DIR="${CMAKE_BINARY_DIR}")
target_include_directories(inspect-gpu-perf-info PRIVATE ${Vulkan_INCLUDE_DIRS})
target_link_libraries(inspect-gpu-perf-info PRIVATE Vulkan::Vulkan)

add_library(VkLayer_inspect_gpu_perf_info SHARED
    "common.h"
    "VkLayer_inspect_gpu_perf_info.cpp"
)
configure_file(
    "${CMAKE_SOURCE_DIR}/VkLayer_inspect_gpu_perf_info.json.in"
    "${CMAKE_BINARY_DIR}/VkLayer_inspect_gpu_perf_info.json"
    @ONLY
)

install(CODE "
    file(CREATE_LINK 
        \"${CMAKE_BINARY_DIR}/inspect-gpu-perf-info\"
        /usr/local/bin/inspect-gpu-perf-info
        SYMBOLIC
    )
")