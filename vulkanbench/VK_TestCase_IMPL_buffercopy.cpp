#include "objects/VK_buffer.h"
#include "objects/VK_common.h"
#include "VK_TestCase.h"

void adjust_buffer_size_max(
    VK_device& device, 
    size_t group_size, 
    std::vector<uint32_t> cp_dst_mem_index_list, 
    size_t* buffer_size_max
) {
    const auto& mem_props = device.physdev.memory;
    std::vector<VkDeviceSize> heap_usage(mem_props.memoryHeapCount, 0);

    uint32_t src_mem_index = device.physdev.find_first_memtype_supports(VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT);
    uint32_t src_heap_index = mem_props.memoryTypes[src_mem_index].heapIndex;
    heap_usage[src_heap_index] += group_size;

    for (uint32_t mem_index : cp_dst_mem_index_list) {
        uint32_t heap_index = mem_props.memoryTypes[mem_index].heapIndex;
        heap_usage[heap_index] += 1;
    }

    VkDeviceSize max_allowed = *buffer_size_max;
    for (uint32_t i = 0; i < mem_props.memoryHeapCount; i++) {
        if (heap_usage[i] == 0) {
            continue;
        }
        VkDeviceSize heap_size = mem_props.memoryHeaps[i].size;
        VkDeviceSize available = heap_size * 80 / 100;
        VkDeviceSize per_buffer = available / heap_usage[i];
        if (per_buffer < max_allowed) {
            max_allowed = per_buffer;
        }
    }

    if (max_allowed < *buffer_size_max) {
        *buffer_size_max = max_allowed;
        std::cout << "BUF->BUF: Resize buffer max size to " << human_readable_size(max_allowed) << "\n";
    }
}

void VK_TestCase_buffercopy::run(VK_device& device, const std::string& title) {
    cp_src_buffer_group_size = 10;
    cp_dst_buffer_size_min = 32 * 1024 * 1024;
    cp_dst_buffer_size_max = std::min<size_t>(2ULL * 1024 * 1024 * 1024, device.physdev.maxAllocSize);
    cp_dst_buffer_size_test_num = 1;

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
    
    if (!VK_config::pi_capture_mode.empty()) {
        if (VK_config::pi_capture_mode == "buf") {
            adjust_buffer_size_max(device, cp_src_buffer_group_size, cp_dst_mem_index_list, &cp_dst_buffer_size_max);
            run_for_pi_capture(device);
        }
        return;
    }

    adjust_buffer_size_max(device, cp_src_buffer_group_size, cp_dst_mem_index_list, &cp_dst_buffer_size_max);
    VK_buffer_group cp_src_buffer_group;
    VK_createInfo_memType cp_src_memType;
    cp_src_memType.flags = VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT;
    cp_src_buffer_group.init(
        cp_src_buffer_group_size,
        &device, 
        cp_dst_buffer_size_max, 
        VK_BUFFER_USAGE_TRANSFER_SRC_BIT | VK_BUFFER_USAGE_TRANSFER_DST_BIT, 
        cp_src_memType
    );
    cp_src_buffer_group.write_noise();

    size_t cp_dst_buffer_size_interval = (cp_dst_buffer_size_max - cp_dst_buffer_size_min) / cp_dst_buffer_size_test_num;
    for (size_t size = cp_dst_buffer_size_min; size <= cp_dst_buffer_size_max; size += cp_dst_buffer_size_interval) {
        for (const auto& cp_dst_memType_index : cp_dst_mem_index_list) {
            VK_gpu_timer timer = single_test_case(device, cp_src_buffer_group, size, cp_dst_memType_index);
            results[size][cp_dst_memType_index].cpu_ns += timer.cpu_ns;
            results[size][cp_dst_memType_index].gpu_ns += timer.gpu_ns;
            results[size][cp_dst_memType_index].loops += 1;
        }
    }

    cp_src_buffer_group.deinit();
    print_results(device, title, cp_src_buffer_group.buffers[0].memoryTypeIndex);
}

void VK_TestCase_buffercopy::run_for_pi_capture(VK_device& device) {
    VK_buffer_group cp_src_buffer_group;
    VK_createInfo_memType cp_src_memType;
    cp_src_memType.flags = VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT;
    cp_src_buffer_group.init(
        cp_src_buffer_group_size,
        &device,
        cp_dst_buffer_size_max,
        VK_BUFFER_USAGE_TRANSFER_SRC_BIT | VK_BUFFER_USAGE_TRANSFER_DST_BIT,
        cp_src_memType
    );
    cp_src_buffer_group.write_noise();

    VK_buffer cp_dst_buffer;
    VK_createInfo_memType cp_dst_memType;
    cp_dst_memType.flags = VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT;
    cp_dst_buffer.init(
        &device, 
        cp_dst_buffer_size_max, 
        VK_BUFFER_USAGE_TRANSFER_DST_BIT, 
        cp_dst_memType
    );

    std::cout << "BUF->BUF: Running for 10 seconds ...\n";

    auto start_time = std::chrono::steady_clock::now();
    while (std::chrono::steady_clock::now() - start_time < std::chrono::seconds(10)) {
        cp_dst_buffer.copy_from_buffer(cp_src_buffer_group.random_pick());
    }
    
    cp_dst_buffer.deinit();
    cp_src_buffer_group.deinit();
}

VK_gpu_timer VK_TestCase_buffercopy::single_test_case(
    VK_device& device,
    VK_buffer_group& cp_src_buffer_group,
    size_t size,
    uint32_t cp_dst_memType_index
) {
    VK_buffer cp_dst_buffer;
    VK_createInfo_memType cp_dst_memType;
    cp_dst_memType.index = cp_dst_memType_index;

    cp_dst_buffer.init(&device, size, VK_BUFFER_USAGE_TRANSFER_DST_BIT, cp_dst_memType);
    VK_gpu_timer timer = cp_dst_buffer.copy_from_buffer(cp_src_buffer_group.random_pick());
    cp_dst_buffer.deinit();

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
    VkMemoryPropertyFlags cp_src_memType_flags = device.physdev.flags_of_memory_type_index(cp_src_mem_type_index);

    for (const auto& [size, map2] : results) {
        for (const auto& [cp_dst_memType_index, timer] : map2) {
            VkMemoryPropertyFlags cp_dst_memType_flags = device.physdev.flags_of_memory_type_index(cp_dst_memType_index);

            constexpr double GiB = 1024.0 * 1024.0 * 1024.0;
            double cpu_speed = (timer.cpu_ns > 0) ? (double)size * timer.loops / timer.cpu_ns * (1e9 / GiB) : 0.0;
            double gpu_speed = (timer.gpu_ns > 0) ? (double)size * timer.loops / timer.gpu_ns * (1e9 / GiB) : 0.0;
            
            std::ostringstream cpu_oss, gpu_oss;
            cpu_oss << std::fixed << std::setprecision(3) << cpu_speed;
            gpu_oss << std::fixed << std::setprecision(3) << gpu_speed;
            
            rows.push_back({
                std::string("BUF->BUF:") + std::to_string(index++),
                human_readable_size(size),
                std::to_string(cp_src_mem_type_index) + " (" + VkMemoryPropertyFlags_str(cp_src_memType_flags, true) + ")",
                std::to_string(cp_dst_memType_index) + " (" + VkMemoryPropertyFlags_str(cp_dst_memType_flags, true) + ")",
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