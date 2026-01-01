cmake_minimum_required(VERSION 3.10)

option(ENABLE_RT_SHADER_COMPILE OFF "Enable runtime shader compilation")

if(UNIX AND NOT APPLE)
    execute_process(COMMAND uname -m OUTPUT_VARIABLE HOST_ARCH OUTPUT_STRIP_TRAILING_WHITESPACE ERROR_QUIET)
    if(NOT HOST_ARCH)
        set(HOST_ARCH "${CMAKE_HOST_SYSTEM_PROCESSOR}")
    endif()
    if(NOT DEFINED CMAKE_TARGET_ARCH)
        set(CMAKE_TARGET_ARCH "${HOST_ARCH}")
    endif()

    string(TOLOWER "${CMAKE_TARGET_ARCH}" TARGET_ARCH_LOWER)
    if(TARGET_ARCH_LOWER MATCHES "^(amd64|x86_64|x64)$")
        set(TARGET_ARCH "x86_64")
    elseif(TARGET_ARCH_LOWER MATCHES "^(arm64|aarch64)$")
        set(TARGET_ARCH "aarch64")
    else()
        message(FATAL_ERROR "Unsupported CMAKE_TARGET_ARCH: ${CMAKE_TARGET_ARCH}")
    endif()
else()
    set(HOST_ARCH   "x86_64")
    set(TARGET_ARCH "x86_64")
endif()

set(CMAKE_C_COMPILER clang)
set(CMAKE_CXX_COMPILER clang++)

set(CROSS_COMPILE OFF)
if(HOST_ARCH STREQUAL "x86_64" AND TARGET_ARCH STREQUAL "aarch64")
    if(NOT EXISTS "/usr/lib/aarch64-linux-gnu/libc.so.6")
        find_program(SUDO_CMD sudo REQUIRED)
        execute_process(COMMAND ${SUDO_CMD} -n true RESULT_VARIABLE SUDO_CMD_OK)
        if(NOT SUDO_CMD_OK EQUAL 0)
            message(FATAL_ERROR "passwordless sudo required for auto-install of aarch64 cross-compile dependencies")
        endif()
        
        message(STATUS "Installing aarch64 cross-compile dependencies...")
        execute_process(COMMAND ${SUDO_CMD} -n bash ${CMAKE_CURRENT_LIST_DIR}/install-aarch64-deps.sh RESULT_VARIABLE _deps_res)
        if(NOT _deps_res EQUAL 0)
            message(FATAL_ERROR "install-aarch64-deps.sh failed")
        endif()
    endif()

    set(CROSS_COMPILE ON)
    set(CMAKE_SYSTEM_NAME Linux)
    set(CMAKE_SYSTEM_PROCESSOR aarch64)
    set(CMAKE_TRY_COMPILE_TARGET_TYPE STATIC_LIBRARY)

    set(CMAKE_C_COMPILER clang)
    set(CMAKE_C_COMPILER_TARGET aarch64-linux-gnu)
    set(CMAKE_CXX_COMPILER clang++)
    set(CMAKE_CXX_COMPILER_TARGET aarch64-linux-gnu)

    set(CMAKE_FIND_ROOT_PATH "/usr/aarch64-linux-gnu" "/usr/lib/aarch64-linux-gnu")
    set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
    set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
    set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)

    set(ENV{VULKAN_SDK} "")
    set(ENV{PKG_CONFIG_PATH} "")
    set(ENV{PKG_CONFIG_LIBDIR} "/usr/lib/aarch64-linux-gnu/pkgconfig:/usr/share/pkgconfig")
    set(Vulkan_LIBRARY "/usr/lib/aarch64-linux-gnu/libvulkan.so" CACHE FILEPATH "" FORCE)
    set(Vulkan_INCLUDE_DIR "/usr/include" CACHE PATH "" FORCE)
    set(X11_X11_INCLUDE_PATH "/usr/include" CACHE PATH "" FORCE)
    set(X11_X11_LIB "/usr/lib/aarch64-linux-gnu/libX11.so" CACHE FILEPATH "" FORCE)
endif()

project(vulkanbench)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

message(STATUS "Host: ${HOST_ARCH}, Target: ${TARGET_ARCH}")

add_executable(vulkanbench 
    vulkanbench/main.cpp
    vulkanbench/VK_TestCase.h 
    vulkanbench/VK_TestCase_IMPL_buffercopy.cpp 
    vulkanbench/VK_TestCase_IMPL_imagebuffercopy.cpp 
    vulkanbench/objects/VK_common.h              vulkanbench/objects/VK_common.cpp 
    vulkanbench/objects/VK_instance.cpp          vulkanbench/objects/VK_instance.h
    vulkanbench/objects/VK_queue.cpp             vulkanbench/objects/VK_queue.h
    vulkanbench/objects/VK_query_pool.cpp        vulkanbench/objects/VK_query_pool.h
    vulkanbench/objects/VK_physdev.cpp           vulkanbench/objects/VK_physdev.h
    vulkanbench/objects/VK_device.cpp            vulkanbench/objects/VK_device.h
    vulkanbench/objects/VK_swapchain.cpp         vulkanbench/objects/VK_swapchain.h
    vulkanbench/objects/VK_image.cpp             vulkanbench/objects/VK_image.h
    vulkanbench/objects/VK_buffer.cpp            vulkanbench/objects/VK_buffer.h
    vulkanbench/objects/VK_shader.cpp            vulkanbench/objects/VK_shader.h
    vulkanbench/objects/VK_compute_pipeline.cpp  vulkanbench/objects/VK_compute_pipeline.h
)

target_compile_definitions(vulkanbench PRIVATE
    $<$<BOOL:${ENABLE_RT_SHADER_COMPILE}>:ENABLE_RT_SHADER_COMPILE=1>
)

if(UNIX AND NOT APPLE)
    find_package(X11 REQUIRED)
    find_package(Vulkan REQUIRED)
    if(ENABLE_RT_SHADER_COMPILE)
        find_package(PkgConfig REQUIRED)
        pkg_check_modules(SHADERC REQUIRED IMPORTED_TARGET shaderc)
        pkg_check_modules(SPIRV_CROSS_C_SHARED REQUIRED IMPORTED_TARGET spirv-cross-c-shared)
    endif()

    target_include_directories(vulkanbench PRIVATE 
        ${X11_INCLUDE_DIR}
        ${CMAKE_CURRENT_SOURCE_DIR}/vulkanbench
    )
    target_link_libraries(vulkanbench PRIVATE 
        ${X11_LIBRARIES}
        Vulkan::Vulkan 
        $<$<BOOL:${ENABLE_RT_SHADER_COMPILE}>:PkgConfig::SHADERC>
        $<$<BOOL:${ENABLE_RT_SHADER_COMPILE}>:PkgConfig::SPIRV_CROSS_C_SHARED>
    )
else()
    find_package(Vulkan REQUIRED)
    if(ENABLE_RT_SHADER_COMPILE)
        find_library(SHADERC_LIBRARY
            NAMES shaderc_shared shaderc_combined
            PATHS "$ENV{VULKAN_SDK}/Lib"
        )
        find_library(SPIRV_CROSS_C_SHARED_LIBRARY
            NAMES spirv-cross-c-shared
            PATHS "$ENV{VULKAN_SDK}/Lib"
        )
    endif()

    target_include_directories(vulkanbench PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/vulkanbench
        "$ENV{VULKAN_SDK}/Include"
    )
    target_link_libraries(vulkanbench PRIVATE
        Vulkan::Vulkan
        $<$<BOOL:${ENABLE_RT_SHADER_COMPILE}>:${SHADERC_LIBRARY}>
        $<$<BOOL:${ENABLE_RT_SHADER_COMPILE}>:${SPIRV_CROSS_C_SHARED_LIBRARY}>
    )
endif()
