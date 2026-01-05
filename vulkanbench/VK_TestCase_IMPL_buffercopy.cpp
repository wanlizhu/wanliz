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
    m_cp_dst_buffer_size_list = { 256 * 1024 * 1024 };
    std::sort(m_cp_dst_buffer_size_list.begin(), m_cp_dst_buffer_size_list.end());

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
    
    if (VK_config::args.count("profile")) {
        if (VK_config::args["profile"].as<std::string>() == "buf") {
            run_for_pi_capture(device);
        }
        return;
    }

    VK_buffer_group cp_src_buffer_group;
    VK_createInfo_memType cp_src_memType;
    cp_src_memType.flags = VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT;
    cp_src_buffer_group.init(
        VK_TEST_RESOURCE_GROUP_SIZE,
        &device, 
        m_cp_dst_buffer_size_list.back(),
        VK_BUFFER_USAGE_TRANSFER_SRC_BIT | VK_BUFFER_USAGE_TRANSFER_DST_BIT, 
        cp_src_memType
    );
    cp_src_buffer_group.write_noise();

    for (const auto& size : m_cp_dst_buffer_size_list) {
        for (const auto& cp_dst_memType_index : cp_dst_mem_index_list) {
            m_results[size][cp_dst_memType_index] = single_test_case(device, cp_src_buffer_group, size, cp_dst_memType_index);
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
        VK_config::args["pushbuffer-dump"].as<bool>() ? 1 : VK_TEST_RESOURCE_GROUP_SIZE,
        &device,
        m_cp_dst_buffer_size_list.back(),
        VK_BUFFER_USAGE_TRANSFER_SRC_BIT | VK_BUFFER_USAGE_TRANSFER_DST_BIT,
        cp_src_memType
    );
    if (!VK_config::args["pushbuffer-dump"].as<bool>()) {
        cp_src_buffer_group.write_noise();
    }

    VK_buffer cp_dst_buffer;
    VK_createInfo_memType cp_dst_memType;
    cp_dst_memType.flags = VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT;
    cp_dst_buffer.init(
        &device, 
        m_cp_dst_buffer_size_list.back(),
        VK_BUFFER_USAGE_TRANSFER_DST_BIT, 
        cp_dst_memType
    );

    if (VK_config::args["pushbuffer-dump"].as<bool>()) {
        cp_dst_buffer.copy_from_buffer(cp_src_buffer_group.random_pick());
    } else {
        std::cout << "BUF->BUF: Running for 10 seconds ...\n";
        auto start_time = std::chrono::steady_clock::now();
        while (std::chrono::steady_clock::now() - start_time < std::chrono::seconds(10)) {
            cp_dst_buffer.copy_from_buffer(cp_src_buffer_group.random_pick());
        }
    }
    
    cp_dst_buffer.deinit();
    cp_src_buffer_group.deinit();
}

VK_GB_per_second VK_TestCase_buffercopy::single_test_case(
    VK_device& device,
    VK_buffer_group& cp_src_buffer_group,
    size_t size,
    uint32_t cp_dst_memType_index
) {
    VK_buffer cp_dst_buffer;
    VK_createInfo_memType cp_dst_memType;
    cp_dst_memType.index = cp_dst_memType_index;

    std::vector<VK_gpu_timer> timers;
    for (int i = 0; i < VK_TEST_AVERAGE_OF_LOOPS; i++) {
        cp_dst_buffer.init(&device, size, VK_BUFFER_USAGE_TRANSFER_DST_BIT, cp_dst_memType);
        timers.push_back(cp_dst_buffer.copy_from_buffer(cp_src_buffer_group.random_pick()));
        cp_dst_buffer.deinit();
    }

    return VK_GB_per_second(cp_src_buffer_group.buffers[0].sizeInBytes, timers);
}

void VK_TestCase_buffercopy::print_results(
    VK_device& device, 
    const std::string& title, 
    uint32_t cp_src_mem_type_index
) {
    std::vector<std::vector<std::string>> rows;
    rows.push_back({"Index", "Buffer size", "SRC memory props", "DST memory props", "CPU (GB/s)", "CPU CoV", "GPU (GB/s)", "GPU CoV"});
    
    uint32_t index = 1;
    VkMemoryPropertyFlags cp_src_memType_flags = device.physdev.flags_of_memory_type_index(cp_src_mem_type_index);

    for (const auto& [size, level2_mappings] : m_results) {
        for (const auto& [cp_dst_memType_index, speed] : level2_mappings) {
            VkMemoryPropertyFlags cp_dst_memType_flags = device.physdev.flags_of_memory_type_index(cp_dst_memType_index);

            std::ostringstream cpu_oss, gpu_oss;
            cpu_oss << std::fixed << std::setprecision(3) << speed.cpu_speed;
            gpu_oss << std::fixed << std::setprecision(3) << speed.gpu_speed;
            std::ostringstream cpu_cov_oss, gpu_cov_oss;
            cpu_cov_oss << std::fixed << std::setprecision(3) << speed.cpu_robust_CoV * 100.0 << "%";
            gpu_cov_oss << std::fixed << std::setprecision(3) << speed.gpu_robust_CoV * 100.0 << "%";

            rows.push_back({
                std::string("BUF->BUF:") + std::to_string(index++),
                human_readable_size(size),
                std::to_string(cp_src_mem_type_index) + " (" + VkMemoryPropertyFlags_str(cp_src_memType_flags, true) + ")",
                std::to_string(cp_dst_memType_index) + " (" + VkMemoryPropertyFlags_str(cp_dst_memType_flags, true) + ")",
                cpu_oss.str(), cpu_cov_oss.str(),
                gpu_oss.str(), gpu_cov_oss.str()
            });
        }
    }
    
    std::cout << "\n";
    if (!title.empty()) {
        std::cout << title << "\n";
    }

    print_table(rows);
}