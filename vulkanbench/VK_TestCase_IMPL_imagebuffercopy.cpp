#include "objects/VK_buffer.h"
#include "objects/VK_common.h"
#include "VK_TestCase.h"
#include <string>

void VK_TestCase_imagebuffercopy::run(VK_device& device, const std::string& title) {
    cp_src_img_width_min = 1024;
    cp_src_img_width_max = 4096;
    cp_src_img_width_test_num = 1;
    cp_src_img_width_interval = (cp_src_img_width_max - cp_src_img_width_min) / cp_src_img_width_test_num;
    
    std::vector<VkMemoryPropertyFlags> cp_dst_mem_flags_list = {
        VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
        VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_CACHED_BIT,
        VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
    };
    for (const auto& memFlags : cp_dst_mem_flags_list) {
        uint32_t memtypeIndex = device.physdev.find_first_memtype_supports(memFlags);
        if (std::find(cp_dst_mem_index_list.begin(), cp_dst_mem_index_list.end(), memtypeIndex) != cp_dst_mem_index_list.end()) {
            continue;
        }
        cp_dst_mem_index_list.push_back(memtypeIndex);
    }

    run_with_srcimg(device, title, VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT);
}

void VK_TestCase_imagebuffercopy::run_with_srcimg(
    VK_device& device, 
    const std::string& title, 
    VkMemoryPropertyFlags cp_src_mem_type_flags
) {
    VK_image srcimg;
    VK_createInfo_memType cp_src_memType;
    cp_src_memType.flags = cp_src_mem_type_flags;
    srcimg.init(
        &device,
        VK_FORMAT_R32G32B32A32_SFLOAT,
        VkExtent2D{ (uint32_t)cp_src_img_width_max, (uint32_t)cp_src_img_width_max },
        VK_IMAGE_USAGE_TRANSFER_SRC_BIT | VK_IMAGE_USAGE_TRANSFER_DST_BIT | VK_IMAGE_USAGE_SAMPLED_BIT,
        cp_src_memType,
        VK_IMAGE_TILING_OPTIMAL
    );
    srcimg.write_noise();

    for (size_t size = cp_src_img_width_min; size <= cp_src_img_width_max; size += cp_src_img_width_interval) {
        for (const auto& cp_dst_mem_type_index : cp_dst_mem_index_list) {
            VK_gpu_timer timer = single_test_case(device, srcimg, size, cp_dst_mem_type_index);
            results[size][cp_dst_mem_type_index].cpu_ns += timer.cpu_ns;
            results[size][cp_dst_mem_type_index].gpu_ns += timer.gpu_ns;
            results[size][cp_dst_mem_type_index].loops += 1;
        }
    }

    srcimg.deinit();
    print_results(device, title, srcimg.memoryTypeIndex);
}

VK_gpu_timer VK_TestCase_imagebuffercopy::single_test_case(
    VK_device& device,
    VK_image& srcimg,
    size_t width,
    uint32_t cp_dst_mem_type_index
) {
    VK_buffer dstbuf;
    VK_createInfo_memType memType;
    memType.index = cp_dst_mem_type_index;

    dstbuf.init(
        &device, 
        sizeof(float) * 4 * width * width, 
        VK_BUFFER_USAGE_TRANSFER_DST_BIT, 
        memType
    );
    VK_gpu_timer timer = dstbuf.copy_from_image(srcimg);
    dstbuf.deinit();

    return timer;
}

void VK_TestCase_imagebuffercopy::print_results(
    VK_device& device, 
    const std::string& title, 
    uint32_t cp_src_mem_type_index
) {
    std::vector<std::vector<std::string>> rows;
    rows.push_back({"Index", "Image size", "SRC memType", "DST memType", "CPU (GiB/s)", "GPU (GiB/s)"});
    
    uint32_t index = 1;
    VkMemoryPropertyFlags cp_src_mem_type_flags = device.physdev.flags_of_memory_type_index(cp_src_mem_type_index);

    for (const auto& [size, map2] : results) {
        for (const auto& [cp_dst_mem_type_index, timer] : map2) {
            VkMemoryPropertyFlags cp_dst_mem_flags = device.physdev.flags_of_memory_type_index(cp_dst_mem_type_index);

            constexpr double GiB = 1024.0 * 1024.0 * 1024.0;
            size_t sizeInBytes = sizeof(float) * 4 * size * size;
            double cpu_speed = (timer.cpu_ns > 0) ? (double)sizeInBytes * timer.loops / timer.cpu_ns * (1e9 / GiB) : 0.0;
            double gpu_speed = (timer.gpu_ns > 0) ? (double)sizeInBytes * timer.loops / timer.gpu_ns * (1e9 / GiB) : 0.0;
            
            std::ostringstream cpu_oss, gpu_oss;
            cpu_oss << std::fixed << std::setprecision(3) << cpu_speed;
            gpu_oss << std::fixed << std::setprecision(3) << gpu_speed;
            
            rows.push_back({
                std::string("I->B:") + std::to_string(index++),
                std::to_string(size) + "x" + std::to_string(size) + " (" + human_readable_size(sizeof(float)*4*size*size) + ")",
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