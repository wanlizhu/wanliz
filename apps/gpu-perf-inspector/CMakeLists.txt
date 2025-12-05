cmake_minimum_required(VERSION 3.10)
project(gpu-perf-inspector)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)
string(TOLOWER "${CMAKE_SYSTEM_PROCESSOR}" ARCH)

# Define target: gpu-perf-inspector
add_executable(gpu-perf-inspector
    "main.cpp" 
    "VK_common.h" "VK_common.cpp"
    "VkLayer_gpu_perf_inspector/VkLayer_common.cpp" "VkLayer_gpu_perf_inspector/VkLayer_common.h"
    "VK_physdev.cpp" "VK_physdev.h" 
    "VK_instance.cpp" "VK_instance.h"
    "VK_queue.cpp" "VK_queue.h"
)

# Link against Vulkan
find_package(Vulkan)
if (NOT Vulkan_FOUND)
    execute_process(COMMAND bash -lic [=[
        sudo apt install -y libvulkan1 libvulkan-dev vulkan-tools vulkan-utility-libraries-dev
    ]=])
    find_package(Vulkan REQUIRED)
endif()
target_include_directories(gpu-perf-inspector PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})
target_link_libraries(gpu-perf-inspector PRIVATE Vulkan::Vulkan)

# Link against NVML (optional)
find_path(NVML_INCLUDE_DIR nvml.h PATHS /usr/include /usr/local/include)
find_library(NVML_LIBRARY nvidia-ml PATHS /usr/lib/${CMAKE_LIBRARY_ARCHITECTURE} /usr/lib)
if (NVML_LIBRARY AND NVML_INCLUDE_DIR)
    target_compile_definitions(gpu-perf-inspector PRIVATE NVML_FOUND=1)
    target_include_directories(gpu-perf-inspector PRIVATE ${NVML_INCLUDE_DIR})
    target_link_libraries(gpu-perf-inspector PRIVATE ${NVML_LIBRARY})
    message(STATUS "Found NVML: ${NVML_LIBRARY}")
else()
    message(STATUS "Configuring without NVML")
endif()

# Define target: VkLayer_gpu_perf_inspector
add_library(VkLayer_gpu_perf_inspector SHARED
    "VkLayer_gpu_perf_inspector/dllmain.cpp"
    "VkLayer_gpu_perf_inspector/VkLayer_common.cpp" "VkLayer_gpu_perf_inspector/VkLayer_common.h"
    "VkLayer_gpu_perf_inspector/VkLayer_hooked_create_instance.cpp" "VkLayer_gpu_perf_inspector/VkLayer_hooked_create_instance.h"
    "VkLayer_gpu_perf_inspector/VkLayer_hooked_create_device.cpp" "VkLayer_gpu_perf_inspector/VkLayer_hooked_create_device.h"
    "VkLayer_gpu_perf_inspector/VkLayer_hooked_mem_alloc.cpp" "VkLayer_gpu_perf_inspector/VkLayer_hooked_mem_alloc.h"
)
configure_file(
    "${CMAKE_SOURCE_DIR}/VkLayer_gpu_perf_inspector/VK_LAYER_gpu_perf_inspector.json.in"
    "${CMAKE_BINARY_DIR}/VK_LAYER_gpu_perf_inspector.json"
    @ONLY
)
target_include_directories(VkLayer_gpu_perf_inspector PRIVATE 
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_CURRENT_SOURCE_DIR}/VkLayer_gpu_perf_inspector 
)
target_link_libraries(VkLayer_gpu_perf_inspector PRIVATE Vulkan::Vulkan)
