#include "VK_common.h"
#include "VK_device.h"

VK_gpu_timer::VK_gpu_timer(VK_device* device_ptr) {
    m_device_ptr = device_ptr;
}

void VK_gpu_timer::cpu_begin() {
    m_cpu_begin_tp = std::chrono::high_resolution_clock::now();
}

void VK_gpu_timer::cpu_end() {
    auto cpu_end_tp = std::chrono::high_resolution_clock::now();
    cpu_ns = std::chrono::duration_cast<std::chrono::nanoseconds>(cpu_end_tp - m_cpu_begin_tp).count();

    if (m_gpu_begin_id != UINT32_MAX && !m_gpu_time_acquired) {
        uint64_t gpu_begin_tp = m_device_ptr->querypool.read_timestamp(m_gpu_begin_id);
        uint64_t gpu_end_tp = m_device_ptr->querypool.read_timestamp(m_gpu_end_id);
        gpu_ns = gpu_end_tp - gpu_begin_tp;
        m_gpu_time_acquired = true;
    }
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

bool VK_gpu_timer::validate() const {
    if (cpu_ns == 0 || gpu_ns == 0) {
        return false;
    }
    if (m_gpu_begin_id != UINT32_MAX) {
        return m_gpu_time_acquired;
    }
    return true;
}

std::string VkResult_str(VkResult result) {
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
    if (rows.empty()) return;
    
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