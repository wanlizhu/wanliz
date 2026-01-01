#include "objects/VK_buffer.h"
#include "objects/VK_common.h"
#include "VK_TestCase.h"
#include <string>

void VK_TestCase_imagebuffercopy::run(VK_device& device, const std::string& title) {
    imageSizeMin = 1024;
    imageSizeMax = 4096;
    imageSizeTestNum = 1;
    imageSizeInterval = (imageSizeMax - imageSizeMin) / imageSizeTestNum;
    memFlagsList = {
        VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT, 
        VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_CACHED_BIT,
        VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
    }; 

    VK_image srcimg;
    srcimg.init(
        &device,
        VK_FORMAT_R32G32B32A32_SFLOAT,
        VkExtent2D{ (uint32_t)imageSizeMax, (uint32_t)imageSizeMax },
        VK_IMAGE_USAGE_TRANSFER_SRC_BIT | VK_IMAGE_USAGE_TRANSFER_DST_BIT | VK_IMAGE_USAGE_SAMPLED_BIT,
        VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
        VK_IMAGE_TILING_OPTIMAL
    );
    srcimg.write_noise();
    run_with_srcimg(device, title, srcimg);
}

void VK_TestCase_imagebuffercopy::run_with_srcimg(VK_device& device, const std::string& title, VK_image& srcimg) {
    // Loop test cases
    for (size_t size = imageSizeMin; size <= imageSizeMax; size += imageSizeInterval) {
        std::vector<uint32_t> testedTypes;
        for (const auto& memFlags : memFlagsList) {
            uint32_t memtypeIndex = device.physdev.find_first_memtype_supports(memFlags);
            if (std::find(testedTypes.begin(), testedTypes.end(), memtypeIndex) != testedTypes.end()) {
                continue;
            }
            testedTypes.push_back(memtypeIndex);

            VK_gpu_timer timer = single_test_case(device, srcimg, size, memFlags);
            results[size][memFlags].cpu_ns += timer.cpu_ns;
            results[size][memFlags].gpu_ns += timer.gpu_ns;
            results[size][memFlags].loops += 1;
        }
    }

    srcimg.deinit();
    print_results(title);
}

VK_gpu_timer VK_TestCase_imagebuffercopy::single_test_case(
    VK_device& device,
    VK_image& srcimg,
    size_t width,
    VkMemoryPropertyFlags memFlags
) {
    VK_buffer dstbuf;
    dstbuf.init(
        &device, 
        sizeof(float) * 4 * width * width, 
        VK_BUFFER_USAGE_TRANSFER_DST_BIT, 
        memFlags
    );
    
    VK_gpu_timer timer = dstbuf.copy_from_image(srcimg);

    dstbuf.deinit();
    return timer;
}

void VK_TestCase_imagebuffercopy::print_results(const std::string& title) {
    std::vector<std::vector<std::string>> rows;
    rows.push_back({"Index", "Image size", "SRC memFlags", "DST memFlags", "CPU (GiB/s)", "GPU (GiB/s)"});
    
    uint32_t index = 1;
    for (const auto& [size, map2] : results) {
        for (const auto& [memFlags, timer] : map2) {
            constexpr double GiB = 1024.0 * 1024.0 * 1024.0;
            size_t sizeInBytes = sizeof(float) * 4 * size * size;
            double cpu_speed = (timer.cpu_ns > 0) ? (double)sizeInBytes * timer.loops / timer.cpu_ns * (1e9 / GiB) : 0.0;
            double gpu_speed = (timer.gpu_ns > 0) ? (double)sizeInBytes * timer.loops / timer.gpu_ns * (1e9 / GiB) : 0.0;
            
            std::ostringstream cpu_oss, gpu_oss;
            cpu_oss << std::fixed << std::setprecision(3) << cpu_speed;
            gpu_oss << std::fixed << std::setprecision(3) << gpu_speed;
            
            rows.push_back({
                std::to_string(index++),
                std::to_string(size) + "x" + std::to_string(size) + " (" + human_readable_size(sizeof(float)*4*size*size) + ")",
                "DEVICE_LOCAL",
                VkMemoryPropertyFlags_str(memFlags, true),
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