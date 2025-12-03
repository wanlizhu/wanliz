cmake_minimum_required(VERSION 3.10)
project("inspect-gpu-perf-info")

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

# Define target: inspect-gpu-perf-info
add_executable(inspect-gpu-perf-info 
    "main.cpp" 
    "VK_common.h" "VK_common.cpp"
    "VkLayer_igpi_helper/VkLayer_common.cpp" "VkLayer_igpi_helper/VkLayer_common.h"
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
    message(STATUS "Configure without NVML")
endif()

# Define target: VkLayer_igpi_helper
add_library(VkLayer_igpi_helper SHARED
    "VkLayer_igpi_helper/dllmain.cpp"
    "VkLayer_igpi_helper/VkLayer_common.cpp" "VkLayer_igpi_helper/VkLayer_common.h"
    "VkLayer_igpi_helper/VkLayer_hooked_create_instance.cpp" "VkLayer_igpi_helper/VkLayer_hooked_create_instance.h"
    "VkLayer_igpi_helper/VkLayer_hooked_create_device.cpp" "VkLayer_igpi_helper/VkLayer_hooked_create_device.h"
    "VkLayer_igpi_helper/VkLayer_hooked_mem_alloc.cpp" "VkLayer_igpi_helper/VkLayer_hooked_mem_alloc.h"
)
configure_file(
    "${CMAKE_SOURCE_DIR}/VkLayer_igpi_helper/VK_LAYER_igpi_helper.json.in"
    "${CMAKE_BINARY_DIR}/VK_LAYER_igpi_helper.json"
    @ONLY
)
target_include_directories(VkLayer_igpi_helper PRIVATE 
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_CURRENT_SOURCE_DIR}/VkLayer_igpi_helper 
)
target_link_libraries(VkLayer_igpi_helper PRIVATE Vulkan::Vulkan)
