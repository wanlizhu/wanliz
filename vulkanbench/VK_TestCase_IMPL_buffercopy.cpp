#include "objects/VK_buffer.h"
#include "objects/VK_common.h"
#include "VK_TestCase.h"

void VK_TestCase_buffercopy::run(VK_device& device, const std::string& title) {
    size_t cp_dst_buffer_size_min = 32 * 1024 * 1024;
    size_t cp_dst_buffer_size_max = std::min<size_t>(2ULL * 1024 * 1024 * 1024, device.physdev.maxAllocSize);
    size_t cp_dst_buffer_size_test_num = 1;
    size_t cp_dst_buffer_size_interval = (cp_dst_buffer_size_max - cp_dst_buffer_size_min) / cp_dst_buffer_size_test_num;

    std::vector<VkMemoryPropertyFlags> cp_dst_mem_flags_list = {
        VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT, 
        VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_CACHED_BIT,
        VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
    }; 
    std::vector<uint32_t> cp_dst_mem_index_list;
    for (const auto& memFlags : cp_dst_mem_flags_list) {
        uint32_t memtypeIndex = device.physdev.find_first_memtype_supports(memFlags);
        if (std::find(cp_dst_mem_index_list.begin(), cp_dst_mem_index_list.end(), memtypeIndex) != cp_dst_mem_index_list.end()) {
            continue;
        }
        cp_dst_mem_index_list.push_back(memtypeIndex);
    }

    VK_buffer cp_src_buffer;
    VK_createInfo_memType cp_src_memType;
    cp_src_memType.flags = VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT;
    cp_src_buffer.init(
        &device, 
        cp_dst_buffer_size_max, 
        VK_BUFFER_USAGE_TRANSFER_SRC_BIT | VK_BUFFER_USAGE_TRANSFER_DST_BIT, 
        cp_src_memType
    );
    cp_src_buffer.write_noise();

    for (size_t size = cp_dst_buffer_size_min; size <= cp_dst_buffer_size_max; size += cp_dst_buffer_size_interval) {
        for (const auto& cp_dst_mem_type_index : cp_dst_mem_index_list) {
            VK_gpu_timer timer = single_test_case(device, cp_src_buffer, size, cp_dst_mem_type_index);
            results[size][cp_dst_mem_type_index].cpu_ns += timer.cpu_ns;
            results[size][cp_dst_mem_type_index].gpu_ns += timer.gpu_ns;
            results[size][cp_dst_mem_type_index].loops += 1;
        }
    }

    cp_src_buffer.deinit();
    print_results(device, title, cp_src_buffer.memoryTypeIndex);
}

VK_gpu_timer VK_TestCase_buffercopy::single_test_case(
    VK_device& device,
    VK_buffer& cp_src_buffer,
    size_t size,
    uint32_t cp_dst_mem_type_index
) {
    VK_buffer dstbuf;
    VK_createInfo_memType memType;
    memType.index = cp_dst_mem_type_index;

    dstbuf.init(&device, size, VK_BUFFER_USAGE_TRANSFER_DST_BIT, memType);
    VK_gpu_timer timer = dstbuf.copy_from_buffer(cp_src_buffer);
    dstbuf.deinit();

    return timer;
}

void VK_TestCase_buffercopy::print_results(
    VK_device& device, 
    const std::string& title, 
    uint32_t cp_src_mem_type_index
) {
    std::vector<std::vector<std::string>> rows;
    rows.push_back({"Index", "Buffer size", "SRC memType", "DST memType", "CPU (GiB/s)", "GPU (GiB/s)"});
    
    uint32_t index = 1;
    VkMemoryPropertyFlags cp_src_mem_type_flags = device.physdev.flags_of_memory_type_index(cp_src_mem_type_index);

    for (const auto& [size, map2] : results) {
        for (const auto& [cp_dst_mem_type_index, timer] : map2) {
            VkMemoryPropertyFlags cp_dst_mem_flags = device.physdev.flags_of_memory_type_index(cp_dst_mem_type_index);

            constexpr double GiB = 1024.0 * 1024.0 * 1024.0;
            double cpu_speed = (timer.cpu_ns > 0) ? (double)size * timer.loops / timer.cpu_ns * (1e9 / GiB) : 0.0;
            double gpu_speed = (timer.gpu_ns > 0) ? (double)size * timer.loops / timer.gpu_ns * (1e9 / GiB) : 0.0;
            
            std::ostringstream cpu_oss, gpu_oss;
            cpu_oss << std::fixed << std::setprecision(3) << cpu_speed;
            gpu_oss << std::fixed << std::setprecision(3) << gpu_speed;
            
            rows.push_back({
                std::string("B->B:") + std::to_string(index++),
                human_readable_size(size),
                std::to_string(cp_src_mem_type_index) + " (" + VkMemoryPropertyFlags_str(cp_src_mem_type_flags, true) + ")",
                std::to_string(cp_dst_mem_type_index) + " (" + VkMemoryPropertyFlags_str(cp_dst_mem_flags, true) + ")",
                cpu_oss.str(),
                gpu_oss.str()
            });
        }
    }
    
    std::cout << "\n";
    if (!title.empty()) {
        std::cout << title << "\n";
    }

    print_table(rows);
}