cmake_minimum_required(VERSION 3.10)
project("inspect-gpu-perf-info")

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

add_executable(inspect-gpu-perf-info 
    "main.cpp" 
    "VK_common.h"
    "VK_physdev.cpp" "VK_physdev.h" 
    "VK_instance.cpp" "VK_instance.h"
    "VK_queue.cpp" "VK_queue.h"
)

# Link against Vulkan
find_package(Vulkan REQUIRED)
target_include_directories(inspect-gpu-perf-info PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})
target_link_libraries(inspect-gpu-perf-info PRIVATE Vulkan::Vulkan)

# Link against NVML (optional)
find_path(NVML_INCLUDE_DIR nvml.h PATHS /usr/include /usr/local/include)
find_library(NVML_LIBRARY nvidia-ml PATHS /usr/lib/${CMAKE_LIBRARY_ARCHITECTURE} /usr/lib)
if (NVML_LIBRARY AND NVML_INCLUDE_DIR)
    target_compile_definitions(inspect-gpu-perf-info PRIVATE NVML_FOUND=1)
    target_include_directories(inspect-gpu-perf-info PRIVATE ${NVML_INCLUDE_DIR})
    target_link_libraries(inspect-gpu-perf-info PRIVATE ${NVML_LIBRARY})
    message(STATUS "Found NVML: ${NVML_LIBRARY}")
else()
    message(ERROR ": Not Found NVML")
endif()

add_library(VkLayer_inspect_gpu_perf_info SHARED
    "VkLayer_inspect_gpu_perf_info.cpp"
    "VkLayer_common.cpp" "VkLayer_common.h"
    "VkLayer_hooked_create_instance.cpp" "VkLayer_hooked_create_instance.h"
    "VkLayer_hooked_create_device.cpp" "VkLayer_hooked_create_device.h"
    "VkLayer_hooked_mem_alloc.cpp" "VkLayer_hooked_mem_alloc.h"
)
configure_file(
    "${CMAKE_SOURCE_DIR}/VK_LAYER_inspect_gpu_perf_info.json.in"
    "${CMAKE_BINARY_DIR}/VkLayer_inspect_gpu_perf_info.json"
    @ONLY
)
target_include_directories(VkLayer_inspect_gpu_perf_info PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})
target_link_libraries(VkLayer_inspect_gpu_perf_info PRIVATE Vulkan::Vulkan)

install(CODE "
    file(CREATE_LINK 
        \"${CMAKE_BINARY_DIR}/inspect-gpu-perf-info\"
        /usr/local/bin/inspect-gpu-perf-info
        SYMBOLIC
    )
    file(CREATE_LINK 
        \"${CMAKE_BINARY_DIR}/VkLayer_inspect_gpu_perf_info.json\"
        /usr/share/vulkan/explicit_layer.d/VkLayer_inspect_gpu_perf_info.json
        SYMBOLIC
    )
")