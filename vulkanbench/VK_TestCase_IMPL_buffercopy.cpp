#include "objects/VK_buffer.h"
#include "objects/VK_common.h"
#include "VK_TestCase.h"

void VK_TestCase_buffercopy::run(VK_device& device, const std::string& title) {
    size_t bufferSizeMin = 32 * 1024 * 1024;
    size_t bufferSizeMax = std::min<size_t>(2ULL * 1024 * 1024 * 1024, device.physdev.maxAllocSize);
    size_t bufferSizeTestNum = 1;
    size_t bufferSizeInterval = (bufferSizeMax - bufferSizeMin) / bufferSizeTestNum;
    std::vector<VkMemoryPropertyFlags> memFlagsList = {
        VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT, 
        VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_CACHED_BIT,
        VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
    }; 

    VK_buffer srcbuf;
    srcbuf.init(&device, bufferSizeMax, VK_BUFFER_USAGE_TRANSFER_SRC_BIT | VK_BUFFER_USAGE_TRANSFER_DST_BIT, VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT);
    srcbuf.write_noise();

    // Loop test cases
    for (size_t size = bufferSizeMin; size <= bufferSizeMax; size += bufferSizeInterval) {
        std::vector<uint32_t> testedTypes;
        for (const auto& memFlags : memFlagsList) {
            uint32_t memtypeIndex = device.physdev.find_first_memtype_supports(memFlags);
            if (std::find(testedTypes.begin(), testedTypes.end(), memtypeIndex) != testedTypes.end()) {
                continue;
            }
            testedTypes.push_back(memtypeIndex);

            VK_gpu_timer timer = single_test_case(device, srcbuf, size, memFlags);
            results[size][memFlags].cpu_ns += timer.cpu_ns;
            results[size][memFlags].gpu_ns += timer.gpu_ns;
            results[size][memFlags].loops += 1;
        }
    }

    srcbuf.deinit();
    print_results(title);
}

VK_gpu_timer VK_TestCase_buffercopy::single_test_case(
    VK_device& device,
    VK_buffer& srcbuf,
    size_t size,
    VkMemoryPropertyFlags memFlags
) {
    VK_buffer dstbuf;
    dstbuf.init(&device, size, VK_BUFFER_USAGE_TRANSFER_DST_BIT, memFlags);
    
    VK_gpu_timer timer = dstbuf.copy_from_buffer(srcbuf);

    dstbuf.deinit();
    return timer;
}

void VK_TestCase_buffercopy::print_results(const std::string& title) {
    std::vector<std::vector<std::string>> rows;
    rows.push_back({"Index", "Buffer size", "SRC memFlags", "DST memFlags", "CPU (GiB/s)", "GPU (GiB/s)"});
    
    uint32_t index = 1;
    for (const auto& [size, map2] : results) {
        for (const auto& [memFlags, timer] : map2) {
            constexpr double GiB = 1024.0 * 1024.0 * 1024.0;
            double cpu_speed = (timer.cpu_ns > 0) ? (double)size * timer.loops / timer.cpu_ns * (1e9 / GiB) : 0.0;
            double gpu_speed = (timer.gpu_ns > 0) ? (double)size * timer.loops / timer.gpu_ns * (1e9 / GiB) : 0.0;
            
            std::ostringstream cpu_oss, gpu_oss;
            cpu_oss << std::fixed << std::setprecision(3) << cpu_speed;
            gpu_oss << std::fixed << std::setprecision(3) << gpu_speed;
            
            rows.push_back({
                std::to_string(index++),
                human_readable_size(size),
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