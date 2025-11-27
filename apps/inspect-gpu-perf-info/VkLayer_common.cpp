#include "VkLayer_common.h"

PFN_vkGetInstanceProcAddr g_pfn_vkGetInstanceProcAddr = NULL;
PFN_vkGetDeviceProcAddr g_pfn_vkGetDeviceProcAddr = NULL;
std::unordered_map<std::string, PFN_vkVoidFunction> g_hooked_functions;

VkLayer_redirect_STDOUT::VkLayer_redirect_STDOUT(const char* pathstr) {
    std::cout.flush();
    std::fflush(nullptr);
    
    original_stdout = dup(STDOUT_FILENO);
    if (original_stdout < 0) {
        std::cout << "Failed to duplicate stdout" << std::endl;
        return;
    }

    std::filesystem::path path(pathstr);
    if (path.has_parent_path() && !std::filesystem::exists(path.parent_path())) {
        std::filesystem::create_directories(path.parent_path());
    }

    int target_fd = open(pathstr, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (target_fd < 0) {
        std::cout << "Failed to open " << pathstr << std::endl;
        return;
    }

    if (dup2(target_fd, STDOUT_FILENO) < 0) {
        std::cout << "Failed to duplicate stdout to " << pathstr << std::endl;
        close(target_fd);
        close(original_stdout);
        return;
    }

    close(target_fd);
}

VkLayer_redirect_STDOUT::~VkLayer_redirect_STDOUT() {
    if (original_stdout >= 0) {
        dup2(original_stdout, STDOUT_FILENO);
        close(original_stdout);
    }
}

VkLayer_profiler::VkLayer_profiler() {
    setenv("__GL_DEBUG_MASK", "RM", 1);
    setenv("__GL_DEBUG_LEVEL", "30", 1);
    setenv("__GL_DEBUG_OPTIONS", "LOG_TO_FILE", 1);
    setenv("__GL_DEBUG_FILENAME", "/tmp/rm-api-loggings", 1);
    system("sudo rm -f /tmp/gpu-page-tables-start /tmp/gpu-page-tables-end");
    system("sudo inspect-gpu-page-tables >/tmp/gpu-page-tables-start");
    startTime_cpu = std::chrono::high_resolution_clock::now();
}

void VkLayer_profiler::end() {
    auto endTime_cpu = std::chrono::high_resolution_clock::now();
    auto nanosec_cpu = std::chrono::duration_cast<std::chrono::nanoseconds>(endTime_cpu - startTime_cpu);
    setenv("__GL_DEBUG_MASK", "", 1);
    setenv("__GL_DEBUG_LEVEL", "", 1);
    setenv("__GL_DEBUG_OPTIONS", "", 1);
    setenv("__GL_DEBUG_FILENAME", "", 1);
    
    printf("CPU time: %ld ns (%f ms)\n", nanosec_cpu.count(), nanosec_cpu.count() / 1000000.0f);
    if (std::filesystem::exists("/tmp/rm-api-loggings")) {
        printf("\n");
        system("python3 /usr/local/bin/process-vidheap.py /tmp/rm-api-loggings");
    }
    if (std::filesystem::exists("/tmp/gpu-page-tables-start")) {
        printf("\n");
        system("sudo inspect-gpu-page-tables >/tmp/gpu-page-tables-end");
        system("python3 /usr/local/bin/process-page-tables.py /tmp/gpu-page-tables-start /tmp/gpu-page-tables-end");
    }
}
