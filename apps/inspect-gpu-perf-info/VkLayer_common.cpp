#include "VkLayer_common.h"

PFN_vkGetInstanceProcAddr g_pfn_vkGetInstanceProcAddr = NULL;
PFN_vkGetDeviceProcAddr g_pfn_vkGetDeviceProcAddr = NULL;
std::unordered_map<std::string, PFN_vkVoidFunction> g_hooked_functions;
VkInstance g_VkInstance = NULL;
std::unordered_map<VkDevice, VkPhysicalDevice> g_physicalDeviceMap;

void VkLayer_redirect_STDOUT::begin(const char* pathstr) {
#ifdef __linux__
    pathstr = pathstr ? pathstr : getenv("IGPI_LOG_FILE");
    if (pathstr == nullptr) {
        return;
    }

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
#endif 
}

void VkLayer_redirect_STDOUT::end() {
#ifdef __linux__
    if (original_stdout >= 0) {
        dup2(original_stdout, STDOUT_FILENO);
        close(original_stdout);
    }
#endif 
}

void VkLayer_redirect_STDERR::begin(const char* pathstr) {
#ifdef __linux__
    pathstr = pathstr ? pathstr : getenv("IGPI_LOG_FILE");
    if (pathstr == nullptr) {
        return;
    }

    std::cerr.flush();
    std::fflush(nullptr);

    original_stderr = dup(STDERR_FILENO);
    if (original_stderr < 0) {
        std::cout << "Failed to duplicate stderr" << std::endl;
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

    if (dup2(target_fd, STDERR_FILENO) < 0) {
        std::cout << "Failed to duplicate stderr to " << pathstr << std::endl;
        close(target_fd);
        close(original_stderr);
        return;
    }

    close(target_fd);
#endif 
}

void VkLayer_redirect_STDERR::end() {
#ifdef __linux__
    if (original_stderr >= 0) {
        dup2(original_stderr, STDERR_FILENO);
        close(original_stderr);
    }
#endif 
}

bool VkLayer_DeviceAddressFeature::enabled = false;
void VkLayer_DeviceAddressFeature::enable(
    VkPhysicalDevice physicalDevice,
    VkDeviceCreateInfo* pDeviceCreateInfo
) {
    if (!physicalDevice) {
        return;
    }

    VkPhysicalDeviceBufferDeviceAddressFeatures requiredFeature = {};
    requiredFeature.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_BUFFER_DEVICE_ADDRESS_FEATURES;
    requiredFeature.pNext = NULL;
    requiredFeature.bufferDeviceAddress = VK_FALSE;

    VkPhysicalDeviceFeatures2 physicalDeviceFeatures2 = {};
    physicalDeviceFeatures2.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2;
    physicalDeviceFeatures2.pNext = &requiredFeature;

    auto pfn_vkGetPhysicalDeviceFeatures2 = (PFN_vkGetPhysicalDeviceFeatures2)g_pfn_vkGetInstanceProcAddr(VK_NULL_HANDLE, "vkGetPhysicalDeviceFeatures2");
    if (pfn_vkGetPhysicalDeviceFeatures2) {
        pfn_vkGetPhysicalDeviceFeatures2(physicalDevice, &physicalDeviceFeatures2);
    }

    if (!requiredFeature.bufferDeviceAddress) {
        printf("VkPhysicalDeviceBufferDeviceAddressFeatures ... [NOT AVAILABLE]\n");
        enabled = false;
        return;
    }

    static VkPhysicalDeviceBufferDeviceAddressFeatures bufferAddressFeature = {};
    bufferAddressFeature.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_BUFFER_DEVICE_ADDRESS_FEATURES;
    bufferAddressFeature.pNext = const_cast<void*>(pDeviceCreateInfo->pNext);
    bufferAddressFeature.bufferDeviceAddress = VK_TRUE;
    pDeviceCreateInfo->pNext = &bufferAddressFeature;

    printf("VkPhysicalDeviceBufferDeviceAddressFeatures ... [ENABLED]");
    enabled = true;
}

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

void VkLayer_GNU_Linux_perf::record() {
    int max_freq = 100000;
    int sys_fd = open("/proc/sys/kernel/perf_event_max_sample_rate", O_RDONLY);
    if (sys_fd >= 0) {
        char sysbuf[64];
        int num = (int)::read(sys_fd, sysbuf, sizeof(sysbuf) - 1);
        close(sys_fd);
        if (num > 0) {
            sysbuf[num] = '\0';
            max_freq = std::atoi(sysbuf);
        }
    } else {
        fprintf(stderr, "Failed to open /proc/sys/kernel/perf_event_max_sample_rate\n");
    }

    perf_event_attr attr;
    std::memset(&attr, 0, sizeof(attr));
    attr.size = sizeof(attr);
    attr.type = PERF_TYPE_HARDWARE;
    attr.config = PERF_COUNT_HW_CPU_CYCLES;
    attr.disabled = 1;
    attr.sample_type = PERF_SAMPLE_IP | PERF_SAMPLE_CALLCHAIN;
    attr.freq = 1;
    attr.sample_freq = (unsigned int)max_freq;
    attr.exclude_kernel = 0;
    attr.exclude_hv = 1;

    pid_t thread_id = (pid_t)syscall(SYS_gettid);
    perf_event_fd = (int)syscall(SYS_perf_event_open, &attr, thread_id, -1, -1, PERF_FLAG_FD_CLOEXEC);
    if (perf_event_fd < 0) {
        fprintf(stderr, "Failed to call SYS_perf_event_open\n");
        return;
    }

    long pagesize = sysconf(_SC_PAGESIZE);
    if (pagesize <= 0) { 
        fprintf(stderr, "Failed to get page size\n");
        close(perf_event_fd); 
        return; 
    }

    perf_mmap_size = (size_t)(pagesize * (1 + 256));
    perf_mmap_base = mmap(nullptr, perf_mmap_size, PROT_READ | PROT_WRITE, MAP_SHARED, perf_event_fd, 0);
    if (perf_mmap_base == MAP_FAILED) { 
        fprintf(stderr, "Failed to map perf_mmap_base\n");
        close(perf_event_fd); 
        return; 
    }

    ioctl(perf_event_fd, PERF_EVENT_IOC_RESET, 0);
    ioctl(perf_event_fd, PERF_EVENT_IOC_ENABLE, 0);
}

void VkLayer_GNU_Linux_perf::end(const std::string& suffix) {
    if (perf_event_fd < 0) {
        return;
    }

    ioctl(perf_event_fd, PERF_EVENT_IOC_DISABLE, 0);

    output = std::string("/tmp/perf") + suffix + ".txt";
    FILE* output_file = fopen(output.c_str(), "w");

    std::vector<char> recordbuf;
    auto meta = (perf_event_mmap_page*)perf_mmap_base;
    char* data = (char*)perf_mmap_base + meta->data_offset;
    size_t buffer_size = meta->data_size;
    uint64_t head = meta->data_head;
    uint64_t tail = meta->data_tail;

    __sync_synchronize();
    while (tail < head) {
        size_t offset = (size_t)(tail % buffer_size);
        auto header = (perf_event_header*)(data + offset);
        if (!header->size) {
            break;
        }

        size_t rec_size = header->size;
        if (rec_size > buffer_size) {
            tail += rec_size;
            break;
        }

        char* rec_ptr = nullptr;
        if (offset + rec_size <= buffer_size) {
            rec_ptr = data + offset;
        } else {
            if (recordbuf.size() < rec_size) {
                recordbuf.resize(rec_size);
            }
            size_t first = buffer_size - offset;
            std::memcpy(recordbuf.data(), data + offset, first);
            std::memcpy(recordbuf.data() + first, data, rec_size - first);
            rec_ptr = recordbuf.data();
            header = (perf_event_header*)rec_ptr;
        }

        if (header->type == PERF_RECORD_SAMPLE) {
            char* pos = rec_ptr + sizeof(perf_event_header);
            char* end = rec_ptr + rec_size;

            if (pos + sizeof(uint64_t) * 2 <= end) {
                uint64_t ip = 0;
                memcpy(&ip, pos, sizeof(ip));
                pos += sizeof(ip);

                uint64_t nr = 0;
                memcpy(&nr, pos, sizeof(nr));
                pos += sizeof(nr);

                std::vector<std::string> frames;
                for (uint64_t i = 0;
                     i < nr && pos + sizeof(std::uint64_t) <= end;
                     ++i) 
                {
                    uint64_t pc = 0;
                    memcpy(&pc, pos, sizeof(pc));
                    pos += sizeof(pc);

                    if (pc == PERF_CONTEXT_KERNEL ||
                        pc == PERF_CONTEXT_USER ||
                        pc == PERF_CONTEXT_HV ||
                        pc == PERF_CONTEXT_GUEST ||
                        pc == PERF_CONTEXT_GUEST_KERNEL) {
                        continue;
                    }

                    Dl_info info;
                    const char* name = nullptr;
                    if (pc && dladdr((void*)pc, &info) != 0 && info.dli_sname) {
                        name = info.dli_sname;
                    }

                    char buf[256];
                    if (name) snprintf(buf, sizeof(buf), "%s", name);
                    else snprintf(buf, sizeof(buf), "0x%llx", (unsigned long long)pc);
                    frames.emplace_back(buf);
                }

                if (!frames.empty()) {
                    for (size_t i = frames.size(); i-- > 0;) {
                        fputs(frames[i].c_str(), output_file);
                        if (i != 0) std::fputc(';', output_file);
                    }
                    fputs(" 1\n", output_file);
                }
            }
        }

        tail += rec_size;
    }
    __sync_synchronize();
    meta->data_tail = tail;

    fclose(output_file);
    munmap(perf_mmap_base, perf_mmap_size);
    close(perf_event_fd);
    perf_mmap_base = nullptr;
    perf_mmap_size = 0;
    perf_event_fd = -1;
}