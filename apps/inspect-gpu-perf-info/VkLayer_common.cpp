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

VkLayer_gpu_page_tables VkLayer_gpu_page_tables::capture() {
    std::string cmdline = 
        "sudo rm -f /tmp/gpu_page_tables.txt; " 
        "sudo inspect-gpu-page-tables > /tmp/gpu_page_tables.txt";
    if (std::system(cmdline.c_str()) != 0) {
        printf("Failed to capture GPU page tables\n");
        return {};
    }

    return load("/tmp/gpu_page_tables.txt");
}

VkLayer_gpu_page_tables VkLayer_gpu_page_tables::load(const std::string& path) {
    std::ifstream file(path);
    std::string line;
    std::regex pattern(R"(^\s*(0x[0-9A-Fa-f]+)\s*-\s*(0x[0-9A-Fa-f]+)\s*=>\s*(0x[0-9A-Fa-f]+)\s*-\s*(0x[0-9A-Fa-f]+)\s*\(([^)]*)\)\s*\(([^)]*)\)\s*$)");
    std::smatch match;

    VkLayer_gpu_page_tables result;
    while (std::getline(file, line)) {
        std::regex_search(line, match, pattern);
        if (match.size() == 7) {
            VkLayer_vidmem_range range;
            range.va_start = std::stoull(match[1].str(), nullptr, 16);
            range.va_end = std::stoull(match[2].str(), nullptr, 16);
            range.pa_start = std::stoull(match[3].str(), nullptr, 16);
            range.pa_end = std::stoull(match[4].str(), nullptr, 16);
            range.aperture = match[5].str();
            range.tags = match[6].str();
            result.ranges.push_back(range);
        }
    }

    return result;
}

void VkLayer_gpu_page_tables::print() const {
    std::vector<VkLayer_vidmem_range> records = ranges;
    if (records.size() == 0) {
        return;
    }
    std::sort(records.begin(), records.end(),
        [](const VkLayer_vidmem_range& a, const VkLayer_vidmem_range& b) {
            return a.va_start < b.va_start;
        });

    size_t prev_count = 0;
    while (prev_count != records.size()) {
        std::vector<VkLayer_vidmem_range> merged;
        merged.push_back(records[0]);
        for (std::size_t i = 1; i < records.size(); ++i) {
            auto& last = merged.back();
            const auto& current = records[i];
            if (current.va_start == last.va_end + 1 &&
                current.aperture == last.aperture &&
                current.tags == last.tags) {
                last.va_end = current.va_end;
                last.pa_end = current.pa_end;
            } else {
                merged.push_back(current);
            }
        }
        prev_count = records.size();
        records = merged;
    }

    for (const auto& record : records) {
        printf("\t0x%016lx - 0x%016lx => (%s) (%s)\n",
            record.va_start, record.va_end, 
            record.aperture.c_str(), record.tags.c_str());
    }
}
    
std::optional<VkLayer_vidmem_range> VkLayer_gpu_page_tables::find(uint64_t va) const {
    for (const auto& range : ranges) {
        if (va >= range.va_start && va < range.va_end) {
            return range;
        }
    }

    return std::nullopt;
}

VkLayer_gpu_page_tables VkLayer_gpu_page_tables::operator-(const VkLayer_gpu_page_tables& other) const {
    VkLayer_gpu_page_tables result;
    for (const auto& range : ranges) {
        if (other.find(range.va_start) == std::nullopt) {
            result.ranges.push_back(range);
        }
    }

    return result;
}

VkLayer_profiler::VkLayer_profiler() {
    setenv("__GL_DEBUG_MASK", "RM", 1);
    setenv("__GL_DEBUG_LEVEL", "30", 1);
    setenv("__GL_DEBUG_OPTIONS", "LOG_TO_FILE", 1);
    setenv("__GL_DEBUG_FILENAME", "/tmp/rm_api_loggings.txt", 1);
    startPageTables.capture();
    startTime_cpu = std::chrono::high_resolution_clock::now();
}

void VkLayer_profiler::end() {
    auto endTime_cpu = std::chrono::high_resolution_clock::now();
    auto nanosec_cpu = std::chrono::duration_cast<std::chrono::nanoseconds>(endTime_cpu - startTime_cpu);
    VkLayer_gpu_page_tables newpages = VkLayer_gpu_page_tables::capture() - startPageTables;
    setenv("__GL_DEBUG_MASK", "", 1);
    setenv("__GL_DEBUG_LEVEL", "", 1);
    setenv("__GL_DEBUG_OPTIONS", "", 1);
    setenv("__GL_DEBUG_FILENAME", "", 1);
    
    printf("CPU time: %ld ns (%f ms)\n", nanosec_cpu.count(), nanosec_cpu.count() / 1000000.0f);
    if (std::filesystem::exists("/tmp/rm_api_loggings.txt")) {
        printf("\n");
        std::system("python3 /usr/local/bin/process-vidheap.py /tmp/rm_api_loggings.txt");
    }
    printf("\n");
    newpages.print();
}
