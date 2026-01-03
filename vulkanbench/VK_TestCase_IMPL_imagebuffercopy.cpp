#include "objects/VK_buffer.h"
#include "objects/VK_common.h"
#include "VK_TestCase.h"
#include <string>

void adjust_image_width_max(
    VK_device& device, 
    size_t group_size, 
    std::vector<uint32_t> cp_dst_mem_index_list, 
    size_t* image_width_max
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

    size_t bytes_per_pixel = sizeof(float) * 4;
    size_t current_size = bytes_per_pixel * (*image_width_max) * (*image_width_max);
    VkDeviceSize max_allowed = current_size;

    for (uint32_t i = 0; i < mem_props.memoryHeapCount; i++) {
        if (heap_usage[i] == 0) {
            continue;
        }
        VkDeviceSize heap_size = mem_props.memoryHeaps[i].size;
        VkDeviceSize available = heap_size * 80 / 100;
        VkDeviceSize per_allocation = available / heap_usage[i];
        if (per_allocation < max_allowed) {
            max_allowed = per_allocation;
        }
    }

    if (max_allowed < current_size) {
        size_t new_width = (size_t)std::sqrt((double)max_allowed / bytes_per_pixel);
        *image_width_max = new_width;
        std::cout << "IMG->BUF: Resize image max width to " << new_width << " (" << human_readable_size(bytes_per_pixel * new_width * new_width) << ")\n";
    }
}

void VK_TestCase_imagebuffercopy::run(VK_device& device, const std::string& title) {
    cp_src_image_group_size = 10;
    cp_src_image_width_min = 1024;
    cp_src_image_width_max = 4096;
    cp_src_image_width_test_num = 1;

    std::vector<VkMemoryPropertyFlags> cp_dst_memType_flags_list = {
        VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
        VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_CACHED_BIT,
        VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
    };
    for (const auto& cp_dst_memType_flags : cp_dst_memType_flags_list) {
        uint32_t cp_dst_memType_index = device.physdev.find_first_memtype_supports(cp_dst_memType_flags);
        if (std::find(cp_dst_mem_index_list.begin(), cp_dst_mem_index_list.end(), cp_dst_memType_index) != cp_dst_mem_index_list.end()) {
            continue;
        }
        cp_dst_mem_index_list.push_back(cp_dst_memType_index);
    }

    if (!VK_config::pi_capture_mode.empty()) {
        if (VK_config::pi_capture_mode == "img") {
            adjust_image_width_max(
                device, 
                cp_src_image_group_size, 
                cp_dst_mem_index_list, 
                &cp_src_image_width_max
            );
            run_for_pi_capture(device);
        }
        return;
    }

    adjust_image_width_max(
        device, 
        cp_src_image_group_size, 
        cp_dst_mem_index_list, 
        &cp_src_image_width_max
    );
    run_with_new_src_image(device, title, VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT);
}

void VK_TestCase_imagebuffercopy::run_for_pi_capture(VK_device& device) {
    VK_image_group cp_src_image_group;
    VK_createInfo_memType cp_src_memType;
    cp_src_memType.flags = VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT;
    cp_src_image_group.init(
        cp_src_image_group_size,
        &device,
        VK_FORMAT_R32G32B32A32_SFLOAT,
        VkExtent2D{ (uint32_t)cp_src_image_width_max, (uint32_t)cp_src_image_width_max },
        VK_IMAGE_USAGE_TRANSFER_SRC_BIT | VK_IMAGE_USAGE_TRANSFER_DST_BIT | VK_IMAGE_USAGE_SAMPLED_BIT,
        cp_src_memType,
        VK_IMAGE_TILING_OPTIMAL
    );
    cp_src_image_group.write_noise();

    VK_buffer cp_dst_buffer;
    VK_createInfo_memType memType;
    memType.flags = VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT;
    cp_dst_buffer.init(
        &device,
        sizeof(float) * 4 * cp_src_image_width_max * cp_src_image_width_max,
        VK_BUFFER_USAGE_TRANSFER_DST_BIT,
        memType
    );

    std::cout << "IMG->BUF: Running for 10 seconds ...\n";

    auto start_time = std::chrono::steady_clock::now();
    while (std::chrono::steady_clock::now() - start_time < std::chrono::seconds(10)) {
        cp_dst_buffer.copy_from_image(cp_src_image_group.random_pick());
    }

    cp_dst_buffer.deinit();
    cp_src_image_group.deinit();
}

void VK_TestCase_imagebuffercopy::run_with_new_src_image(
    VK_device& device, 
    const std::string& title, 
    VkMemoryPropertyFlags cp_src_memType_flags
) {
    VK_image_group cp_src_image_group;
    VK_createInfo_memType cp_src_memType;
    cp_src_memType.flags = cp_src_memType_flags;
    cp_src_image_group.init(
        cp_src_image_group_size,
        &device,
        VK_FORMAT_R32G32B32A32_SFLOAT,
        VkExtent2D{ (uint32_t)cp_src_image_width_max, (uint32_t)cp_src_image_width_max },
        VK_IMAGE_USAGE_TRANSFER_SRC_BIT | VK_IMAGE_USAGE_TRANSFER_DST_BIT | VK_IMAGE_USAGE_SAMPLED_BIT,
        cp_src_memType,
        VK_IMAGE_TILING_OPTIMAL
    );
    cp_src_image_group.write_noise();

    cp_src_image_width_interval = (cp_src_image_width_max - cp_src_image_width_min) / cp_src_image_width_test_num;
    for (size_t size = cp_src_image_width_min; size <= cp_src_image_width_max; size += cp_src_image_width_interval) {
        for (const auto& cp_dst_memType_index : cp_dst_mem_index_list) {
            VK_gpu_timer timer = single_test_case(device, cp_src_image_group, size, cp_dst_memType_index);
            results[size][cp_dst_memType_index].cpu_ns += timer.cpu_ns;
            results[size][cp_dst_memType_index].gpu_ns += timer.gpu_ns;
            results[size][cp_dst_memType_index].loops += 1;
        }
    }

    cp_src_image_group.deinit();
    print_results(device, title, cp_src_image_group.images[0].memoryTypeIndex);
}

VK_gpu_timer VK_TestCase_imagebuffercopy::single_test_case(
    VK_device& device,
    VK_image_group& cp_src_image_group,
    size_t width,
    uint32_t cp_dst_memType_index
) {
    VK_buffer cp_dst_buffer;
    VK_createInfo_memType memType;
    memType.index = cp_dst_memType_index;

    cp_dst_buffer.init(
        &device, 
        sizeof(float) * 4 * width * width, 
        VK_BUFFER_USAGE_TRANSFER_DST_BIT, 
        memType
    );
    VK_gpu_timer timer = cp_dst_buffer.copy_from_image(cp_src_image_group.random_pick());
    cp_dst_buffer.deinit();

    return timer;
}

void VK_TestCase_imagebuffercopy::print_results(
    VK_device& device, 
    const std::string& title, 
    uint32_t cp_src_memType_index
) {
    std::vector<std::vector<std::string>> rows;
    rows.push_back({"Index", "Image size", "SRC memType", "DST memType", "CPU (GiB/s)", "GPU (GiB/s)"});
    
    uint32_t index = 1;
    VkMemoryPropertyFlags cp_src_memType_flags = device.physdev.flags_of_memory_type_index(cp_src_memType_index);

    for (const auto& [size, map2] : results) {
        for (const auto& [cp_dst_memType_index, timer] : map2) {
            VkMemoryPropertyFlags cp_dst_memType_flags = device.physdev.flags_of_memory_type_index(cp_dst_memType_index);

            constexpr double GiB = 1024.0 * 1024.0 * 1024.0;
            size_t sizeInBytes = sizeof(float) * 4 * size * size;
            double cpu_speed = (timer.cpu_ns > 0) ? (double)sizeInBytes * timer.loops / timer.cpu_ns * (1e9 / GiB) : 0.0;
            double gpu_speed = (timer.gpu_ns > 0) ? (double)sizeInBytes * timer.loops / timer.gpu_ns * (1e9 / GiB) : 0.0;
            
            std::ostringstream cpu_oss, gpu_oss;
            cpu_oss << std::fixed << std::setprecision(3) << cpu_speed;
            gpu_oss << std::fixed << std::setprecision(3) << gpu_speed;
            
            rows.push_back({
                std::string("IMG->BUF:") + std::to_string(index++),
                std::to_string(size) + "x" + std::to_string(size) + " (" + human_readable_size(sizeof(float)*4*size*size) + ")",
                std::to_string(cp_src_memType_index) + " (" + VkMemoryPropertyFlags_str(cp_src_memType_flags, true) + ")",
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