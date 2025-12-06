#include "VkLayer_common.h"

PFN_vkGetInstanceProcAddr g_pfn_vkGetInstanceProcAddr = NULL;
PFN_vkGetDeviceProcAddr g_pfn_vkGetDeviceProcAddr = NULL;
std::unordered_map<std::string, PFN_vkVoidFunction> g_hooked_functions;
VkInstance g_VkInstance = NULL;
std::unordered_map<VkDevice, VkPhysicalDevice> g_physicalDeviceMap;

char* VkLayer_readbuf(const char* path, bool trim) {
    static std::string buffer;
    std::ifstream file(path);
    if (!file) {
        static char nil = '\0';
        return &nil;
    }

    buffer.assign(std::istreambuf_iterator<char>(file), std::istreambuf_iterator<char>());
    if (trim) {
        while (!buffer.empty() && std::isspace((unsigned char)buffer.front())) {
            buffer.erase(buffer.begin());
        }
        while (!buffer.empty() && std::isspace((unsigned char)buffer.back())) {
            buffer.pop_back();
        }
    }

    return buffer.data();
}

const char* VkLayer_which(const std::string& cmdname) {
    static std::string out;
    std::istringstream env_path(std::getenv("PATH"));
    std::string dir;
    while (std::getline(env_path, dir, ':')) {
        out = dir + "/" + cmdname;
#ifdef __linux__
        if (access(out.c_str(), X_OK) == 0) {
#else
        if (std::filesystem::exists(out)) {
#endif 
            return out.c_str();
        }
    }
    return nullptr;
}

void VkLayer_exec(const char* fmt, ...) {
    char cmdline[4096] = {};
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(cmdline, sizeof(cmdline), fmt, ap);
    va_end(ap);
    system(cmdline);
}

void VkLayer_RM_logs::begin() {
    fprintf(stderr, "vkAllocateMemory begin index=%d\n", (int)timer.index);
    if (VkLayer_which("dump-gpu-pages.sh")) system("dump-gpu-pages.sh -begin");
    timer.begin();
}

void VkLayer_RM_logs::end() {
    timer.end();
    if (VkLayer_which("dump-gpu-pages.sh")) system("dump-gpu-pages.sh -end >&2");
    fprintf(stderr, "vkAllocateMemory end in %s\n", timer.cpu_time_desc.c_str());
}

void VkLayer_timer::begin() {
    cpu_time = {};
    cpu_time_desc = "";
    cpu_begin = std::chrono::high_resolution_clock::now();
}

void VkLayer_timer::end() {
    auto cpu_end = std::chrono::high_resolution_clock::now();
    cpu_time = std::chrono::duration_cast<std::chrono::nanoseconds>(cpu_end - cpu_begin);
    cpu_time_desc = std::to_string(cpu_time.count()) + " nsec";
    index += 1;
}