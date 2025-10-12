cmake_minimum_required(VERSION 3.10.0 FATAL_ERROR)

project(nvperf-test)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

if(WIN32)
    include(FetchContent)
    set(GLFW_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
    set(GLFW_BUILD_TESTS    OFF CACHE BOOL "" FORCE)
    set(GLFW_BUILD_DOCS     OFF CACHE BOOL "" FORCE)
    FetchContent_Declare(glfw
        GIT_REPOSITORY https://github.com/glfw/glfw.git
        GIT_TAG        3.3.9   # pin a version you want
    )
    FetchContent_MakeAvailable(glfw) 
else()
    find_package(glfw3)
endif()

find_package(OpenGL)
find_package(Vulkan)
find_package(Threads)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

file(GLOB_RECURSE GLAD_SOURCE glad/*.c glad/*.cpp glad/*.h)
file(GLOB_RECURSE WINDOW_SOURCE window/*.c window/*.cpp window/*.h)
file(GLOB_RECURSE MSAA_SOURCE msaa/*.c msaa/*.cpp msaa/*.h)
file(GLOB_RECURSE MSAA_SHADER msaa/*.glsl)
add_executable(nvperf-test-msaa ${GLAD_SOURCE} ${WINDOW_SOURCE} ${MSAA_SOURCE} ${MSAA_SHADER})
target_include_directories(nvperf-test-msaa PUBLIC 
    ${CMAKE_CURRENT_LIST_DIR}
    ${CMAKE_CURRENT_LIST_DIR}/window 
)
target_link_libraries(nvperf-test-msaa PUBLIC 
    OpenGL::GL Vulkan::Vulkan 
    Threads::Threads glfw
    $<$<PLATFORM_ID:Linux>:X11>
)
add_custom_command(TARGET nvperf-test-msaa POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E create_symlink "${CMAKE_CURRENT_LIST_DIR}/msaa/shader.vert.glsl" "$<TARGET_FILE_DIR:nvperf-test-msaa>/shader.vert.glsl"
    COMMAND ${CMAKE_COMMAND} -E create_symlink "${CMAKE_CURRENT_LIST_DIR}/msaa/shader.frag.glsl" "$<TARGET_FILE_DIR:nvperf-test-msaa>/shader.frag.glsl"
)
if(WIN32)
    set_target_properties(nvperf-test-msaa PROPERTIES VS_DEBUGGER_WORKING_DIRECTORY "$<TARGET_FILE_DIR:nvperf-test-msaa>")
endif()