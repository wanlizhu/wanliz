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
    startPageTablesFilePath = std::filesystem::temp_directory_path() / "gpu_page_tables.txt";
    rmApiLoggingsFilePath = std::filesystem::temp_directory_path() / "rm_api_loggings.txt";
    capture_gpu_page_tables(startPageTablesFilePath);
    capture_rm_api_loggings(rmApiLoggingsFilePath);

    startTime = std::chrono::high_resolution_clock::now();
}

void VkLayer_profiler::end() {

}

void VkLayer_profiler::capture_gpu_page_tables(const std::string& path) {

}

void VkLayer_profiler::capture_rm_api_loggings(const std::string& path) {
    setenv("__GL_DEBUG_MASK", "RM");
    setenv("__GL_DEBUG_LEVEL", "30");
    setenv("__GL_DEBUG_OPTIONS", "LOG_TO_FILE");
    setenv("__GL_DEBUG_FILENAME", path.c_str());
}