#include "VK_common.h"
#include "VK_device.h"

cxxopts::ParseResult VK_config::args;

VK_gpu_timer::VK_gpu_timer(VK_device* device_ptr) {
    m_device_ptr = device_ptr;
}

bool VK_config::opt_starts_with(const char* name, const char* prefix) {
    std::string value = args[std::string(name)].as<std::string>();
    return str_starts_with(value.c_str(), prefix);
}

bool VK_config::opt_starts_with(const char* name, const std::vector<const char*>& prefixList) {
    for (const auto& prefix : prefixList) {
        if (VK_config::opt_starts_with(name, prefix)) {
            return true;
        }
    }
    return false;
}

std::string VK_config::opt_substr_before(const char* name, const char* separator) {
    std::string value = args[std::string(name)].as<std::string>();
    size_t pos = value.find(separator);
    if (pos == std::string::npos) {
        return value;
    }
    return value.substr(0, pos);
}

std::string VK_config::opt_substr_after(const char*name, const char* separator) {
    std::string value = args[std::string(name)].as<std::string>();
    size_t pos = value.find(separator);
    if (pos == std::string::npos) {
        return "";
    }
    return value.substr(pos + strlen(separator));
}

int VK_config::opt_as_int(const char* name) {
    return args[name].as<int>();
}

bool VK_config::opt_as_bool(const char* name) {
    return args[name].as<bool>();
}

std::string VK_config::opt_as_string(const char* name) {
    return args[name].as<std::string>();
}

void VK_gpu_timer::reset() {
    cpu_ns = 0;
    gpu_ns = 0;
    m_cpu_begin_tp = std::nullopt;
    m_gpu_begin_id = UINT32_MAX;
    m_gpu_end_id = UINT32_MAX;
    m_gpu_time_acquired = false;
}

void VK_gpu_timer::cpu_begin() {
    m_cpu_begin_tp = std::chrono::high_resolution_clock::now();
}

void VK_gpu_timer::cpu_end() {
    assert(m_cpu_begin_tp.has_value());
    auto cpu_end_tp = std::chrono::high_resolution_clock::now();
    cpu_ns = std::chrono::duration_cast<std::chrono::nanoseconds>(cpu_end_tp - m_cpu_begin_tp.value()).count();
}

void VK_gpu_timer::gpu_begin(VkCommandBuffer cmdbuf) {
    m_gpu_time_acquired = false;
    m_device_ptr->querypool.reset(cmdbuf);
    m_gpu_begin_id = m_device_ptr->querypool.write_timestamp(cmdbuf);
}

void VK_gpu_timer::gpu_end(VkCommandBuffer cmdbuf) {
    assert(m_gpu_begin_id != UINT32_MAX);
    m_gpu_end_id = m_device_ptr->querypool.write_timestamp(cmdbuf, VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT);
}

void VK_gpu_timer::readback_gpu_timestamps() {
    if (m_gpu_begin_id != UINT32_MAX && !m_gpu_time_acquired) {
        uint64_t gpu_begin_tp = m_device_ptr->querypool.read_timestamp(m_gpu_begin_id);
        uint64_t gpu_end_tp = m_device_ptr->querypool.read_timestamp(m_gpu_end_id);
        gpu_ns = gpu_end_tp - gpu_begin_tp;
        m_gpu_time_acquired = true;
    }
}

VK_GB_per_second::VK_GB_per_second(size_t bytes, std::vector<VK_gpu_timer>& timers) {
    constexpr double GB = 1024.0 * 1024.0 * 1024.0;

    auto median_of = [](std::vector<double>& a) -> double {
        const std::size_t n = a.size();
        const std::size_t mid = n / 2;

        std::nth_element(a.begin(), a.begin() + mid, a.end());
        double m = a[mid];

        if ((n % 2) == 0) {
            std::nth_element(a.begin(), a.begin() + (mid - 1), a.end());
            m = 0.5 * (m + a[mid - 1]);
        }
        return m;
    };

    std::vector<double> cpu_speed_list;
    for (const auto& timer : timers) {
        cpu_speed_list.push_back((double)bytes / timer.cpu_ns * (1e9 / GB));
    }
    cpu_robust_CoV = robust_CoV(cpu_speed_list);
    cpu_speed = median_of(cpu_speed_list);

    std::vector<double> gpu_speed_list;
    for (auto& timer : timers) {
        timer.readback_gpu_timestamps();
        gpu_speed_list.push_back((double)bytes / timer.gpu_ns * (1e9 / GB));
    }
    gpu_robust_CoV = robust_CoV(gpu_speed_list);
    gpu_speed = median_of(gpu_speed_list);
}

double VK_GB_per_second::robust_CoV(const std::vector<double>& samples) {
    std::vector<double> samples_dup = samples;
    for (double v : samples_dup) {
        if (!std::isfinite(v)) {
            throw std::invalid_argument("robust_CoV: infinite value in samples");
        }
        if (v < 0.0) {
            throw std::invalid_argument("robust_CoV: negative value in samples");
        }
    }

    auto median_of = [](std::vector<double>& a) -> double {
        const std::size_t n = a.size();
        const std::size_t mid = n / 2;

        std::nth_element(a.begin(), a.begin() + mid, a.end());
        double m = a[mid];

        if ((n % 2) == 0) {
            std::nth_element(a.begin(), a.begin() + (mid - 1), a.end());
            m = 0.5 * (m + a[mid - 1]);
        }
        return m;
    };

    double med = median_of(samples_dup);
    if (med == 0.0) {
        bool all_zero = true;
        for (double v : samples) {
            if (v != 0.0) { all_zero = false; break; }
        }
        if (all_zero) {
            return 0.0;
        }
        return std::numeric_limits<double>::infinity();
    }

    std::vector<double> dev;
    dev.reserve(samples.size());
    for (double v : samples) {
        dev.push_back(std::fabs(v - med));
    }

    double mad = median_of(dev);
    constexpr double k = 1.4826;
    double robust_sigma = k * mad;

    return robust_sigma / med;
}

VK_createInfo_memType VK_createInfo_memType::init_with_flags(VkMemoryPropertyFlags _flags) {
    VK_createInfo_memType inst;
    inst.flags = _flags;
    return inst;
}

VK_createInfo_memType VK_createInfo_memType::init_with_index(uint32_t _index) {
    VK_createInfo_memType inst;
    inst.index = _index;
    return inst;
}

bool str_starts_with(const char* str, const char* substr) {
    if (!str || !substr) {
        return false;
    }

    while (*substr) {
        if (*str++ != *substr++) {
            return false;
        }
    }

    return true;
}

bool str_ends_with(const char* str, const char* substr) {
    if (!str || !substr) {
        return false;
    }

    size_t str_len = strlen(str);
    size_t substr_len = strlen(substr);
    if (substr_len > str_len) {
        return false;
    }

    return strcmp(str + str_len - substr_len, substr) == 0;
}

bool str_contains(const char* str, const char* substr) {
    if (!str || !substr) {
        return false;
    }

    return strstr(str, substr) != nullptr;
}

const char* str_after_rchar(const char* str, char chr) {
    if (!str) {
        return nullptr;
    }

    const char* last = strrchr(str, chr);
    return last ? last + 1 : str;
}

const char* str_home_dir() {
    static std::string home;

    if (home.empty()) {
#ifdef _WIN32
        if (const char* p = std::getenv("USERPROFILE")) {
            home = p;
        } else if (const char* d = std::getenv("HOMEDRIVE")) {
            if (const char* h = std::getenv("HOMEPATH")) {
                home = std::string(d) + h;
            }
        }
#else
        if (const char* h = std::getenv("HOME")) {
            home = h;
        } else {
            throw std::runtime_error("$env{HOME} is not defined");
        }
#endif
        if (home.back() == '/') {
            home.pop_back();
        }
    }

    return home.c_str();
}

const char* str_filename_timestamp() {
    const std::time_t now = std::time(nullptr);
    std::tm tm{};
#ifdef _WIN32
    localtime_s(&tm, &now);
#else
    localtime_r(&now, &tm);
#endif

    std::ostringstream ts;
    ts << std::put_time(&tm, "%Y-%m%d-%H%M-%S");
    static std::string suffix;
    suffix = ts.str();

    return suffix.c_str();
}

const char* str_format(const char* fmt, ...) {
    va_list ap;
    va_start(ap, fmt);

    va_list ap_dup;
    va_copy(ap_dup, ap);
    int N = std::vsnprintf(nullptr, 0, fmt, ap_dup);
    va_end(ap_dup);

    static std::vector<char> buf;
    if (N < 0) {
        buf.assign({'\0'});
    } else {
        buf.resize(N + 1, '\0');
        std::vsnprintf(buf.data(), buf.size(), fmt, ap);
    }
    va_end(ap);

    return buf.data();
}

const char* VkResult_str(VkResult result) {
    switch (static_cast<int>(result)) {
        case 0:             return "VK_SUCCESS";
        case 1:             return "VK_NOT_READY";
        case 2:             return "VK_TIMEOUT";
        case 3:             return "VK_EVENT_SET";
        case 4:             return "VK_EVENT_RESET";
        case 5:             return "VK_INCOMPLETE";

        case -1:            return "VK_ERROR_OUT_OF_HOST_MEMORY";
        case -2:            return "VK_ERROR_OUT_OF_DEVICE_MEMORY";
        case -3:            return "VK_ERROR_INITIALIZATION_FAILED";
        case -4:            return "VK_ERROR_DEVICE_LOST";
        case -5:            return "VK_ERROR_MEMORY_MAP_FAILED";
        case -6:            return "VK_ERROR_LAYER_NOT_PRESENT";
        case -7:            return "VK_ERROR_EXTENSION_NOT_PRESENT";
        case -8:            return "VK_ERROR_FEATURE_NOT_PRESENT";
        case -9:            return "VK_ERROR_INCOMPATIBLE_DRIVER";
        case -10:           return "VK_ERROR_TOO_MANY_OBJECTS";
        case -11:           return "VK_ERROR_FORMAT_NOT_SUPPORTED";
        case -12:           return "VK_ERROR_FRAGMENTED_POOL";
        case -13:           return "VK_ERROR_UNKNOWN";

        case -1000069000:   return "VK_ERROR_OUT_OF_POOL_MEMORY";
        case -1000072003:   return "VK_ERROR_INVALID_EXTERNAL_HANDLE";
        case -1000161000:   return "VK_ERROR_FRAGMENTATION";
        case -1000257000:   return "VK_ERROR_INVALID_OPAQUE_CAPTURE_ADDRESS";
        case  1000297000:   return "VK_PIPELINE_COMPILE_REQUIRED";
        case -1000174001:   return "VK_ERROR_NOT_PERMITTED";

        case -1000000000:   return "VK_ERROR_SURFACE_LOST_KHR";
        case -1000000001:   return "VK_ERROR_NATIVE_WINDOW_IN_USE_KHR";
        case  1000001003:   return "VK_SUBOPTIMAL_KHR";
        case -1000001004:   return "VK_ERROR_OUT_OF_DATE_KHR";
        case -1000003001:   return "VK_ERROR_INCOMPATIBLE_DISPLAY_KHR";

        case -1000011001:   return "VK_ERROR_VALIDATION_FAILED_EXT";
        case -1000012000:   return "VK_ERROR_INVALID_SHADER_NV";

        case -1000023000:   return "VK_ERROR_IMAGE_USAGE_NOT_SUPPORTED_KHR";
        case -1000023001:   return "VK_ERROR_VIDEO_PICTURE_LAYOUT_NOT_SUPPORTED_KHR";
        case -1000023002:   return "VK_ERROR_VIDEO_PROFILE_OPERATION_NOT_SUPPORTED_KHR";
        case -1000023003:   return "VK_ERROR_VIDEO_PROFILE_FORMAT_NOT_SUPPORTED_KHR";
        case -1000023004:   return "VK_ERROR_VIDEO_PROFILE_CODEC_NOT_SUPPORTED_KHR";
        case -1000023005:   return "VK_ERROR_VIDEO_STD_VERSION_NOT_SUPPORTED_KHR";

        case -1000158000:   return "VK_ERROR_INVALID_DRM_FORMAT_MODIFIER_PLANE_LAYOUT_EXT";
        case -1000255000:   return "VK_ERROR_FULL_SCREEN_EXCLUSIVE_MODE_LOST_EXT";

        case  1000268000:   return "VK_THREAD_IDLE_KHR";
        case  1000268001:   return "VK_THREAD_DONE_KHR";
        case  1000268002:   return "VK_OPERATION_DEFERRED_KHR";
        case  1000268003:   return "VK_OPERATION_NOT_DEFERRED_KHR";

        case -1000299000:   return "VK_ERROR_INVALID_VIDEO_STD_PARAMETERS_KHR";
        case -1000338000:   return "VK_ERROR_COMPRESSION_EXHAUSTED_EXT";

        case  1000482000:   return "VK_INCOMPATIBLE_SHADER_BINARY_EXT";
        case  1000483000:   return "VK_PIPELINE_BINARY_MISSING_KHR";
        case -1000483000:   return "VK_ERROR_NOT_ENOUGH_SPACE_KHR";

        case 0x7FFFFFFF:    return "VK_RESULT_MAX_ENUM";
        default:            return "unknown";
    }
}

std::string VkMemoryPropertyFlags_str(VkMemoryPropertyFlags flags, bool short_str) {
    std::string result;
    if (flags & VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT)        result += short_str ? "DL|" : "device_local|";
    if (flags & VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT)        result += short_str ? "HV|" : "host_visible|";
    if (flags & VK_MEMORY_PROPERTY_HOST_COHERENT_BIT)       result += short_str ? "HCO|" : "host_coherent|";
    if (flags & VK_MEMORY_PROPERTY_HOST_CACHED_BIT)         result += short_str ? "HCA|" : "host_cached|";
    if (flags & VK_MEMORY_PROPERTY_LAZILY_ALLOCATED_BIT)    result += short_str ? "LZ|" : "lazily_alloc|";
    if (flags & VK_MEMORY_PROPERTY_PROTECTED_BIT)           result += short_str ? "PT|" : "protected|";
    if (!result.empty()) {
        result.erase(result.size() - 1);  
    }
    return result.empty() ? "none" : result;
}

std::string human_readable_size(size_t bytes) {
    const char* units[] = {"B ", "KB", "MB", "GB", "TB"};
    int unit = 0;
    double size = static_cast<double>(bytes);
    while (size >= 1024.0 && unit < 4) {
        size /= 1024.0;
        unit++;
    }
    std::ostringstream oss;
    oss << std::setfill(' ') << std::setw(5) << std::fixed << std::setprecision(1) << size << " " << units[unit];
    return oss.str();
}

void print_table(const std::vector<std::vector<std::string>>& rows, std::ostream& out) {
    if (rows.empty()) {
        return;
    }

    std::vector<size_t> widths(rows[0].size(), 0);
    for (const auto& row : rows) {
        for (size_t i = 0; i < row.size() && i < widths.size(); i++) {
            widths[i] = std::max(widths[i], row[i].size());
        }
    }
    
    for (const auto& row : rows) {
        for (size_t i = 0; i < row.size(); i++) {
            out << std::left << std::setw(widths[i] + 2) << row[i];
        }
        out << "\n";
    }
}

void makedirs(const std::string& path) {
    std::error_code ec;
    if (std::filesystem::create_directories(std::filesystem::path(path), ec)) {
        return;
    }

    if (ec) {
        throw std::runtime_error("Failed to make dirs: " + path + ": " + ec.message());
    }
}

uint64_t monotonic_timestamp_ns() {
    struct timespec ts;
    if (clock_gettime(CLOCK_MONOTONIC, &ts) == 0) {
        return (uint64_t)ts.tv_sec * 1000000000ull + (uint64_t)ts.tv_nsec;
    }
    return 0;
}