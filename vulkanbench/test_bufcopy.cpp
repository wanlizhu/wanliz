#include "objects/VK_buffer.h"
#include "objects/VK_common.h"
#include "test_cases.h"
#include <stdexcept>
#include <sstream>

void VK_test_bufcopy::run() {
    if (!device.init(-1, VK_QUEUE_TRANSFER_BIT, 0, 0)) {
        throw std::runtime_error("Failed to init logical device");
    }
    
    size_t bufferSizeMin = 32 * 1024 * 1024;
    size_t bufferSizeMax = std::min<size_t>(2ULL * 1024 * 1024 * 1024, device.physdev.maxAllocSize);
    size_t bufferSizeTestNum = 1;
    size_t bufferSizeInterval = (bufferSizeMax - bufferSizeMin) / bufferSizeTestNum;
    std::vector<VkMemoryPropertyFlags> memFlagsList = {
        VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT, 
        VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_CACHED_BIT,
        VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
    }; 

    std::cout << "Initializing benchmark resources\n";
    VK_buffer srcbuf;
    srcbuf.init(&device, bufferSizeMax, VK_BUFFER_USAGE_TRANSFER_SRC_BIT | VK_BUFFER_USAGE_TRANSFER_DST_BIT, VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT);
    srcbuf.write_noise();

    std::map<size_t, std::map<VkMemoryPropertyFlags, VK_gpu_timer>> results;

    // Loop test cases
    for (size_t size = bufferSizeMin; size <= bufferSizeMax; size += bufferSizeInterval) {
        std::vector<uint32_t> testedTypes;
        for (const auto& memFlags : memFlagsList) {
            uint32_t memtypeIndex = device.physdev.find_first_memtype_supports(memFlags);
            if (std::find(testedTypes.begin(), testedTypes.end(), memtypeIndex) != testedTypes.end()) {
                continue;
            }
            testedTypes.push_back(memtypeIndex);

            std::cout << "Testing " << human_readable_size(size) << " DL -> " << VkMemoryPropertyFlags_str(memFlags, true) << "\n";
            VK_gpu_timer timer = single_test_case(srcbuf, size, memFlags);
            results[size][memFlags].cpu_ns += timer.cpu_ns;
            results[size][memFlags].gpu_ns += timer.gpu_ns;
            results[size][memFlags].loops += 1;
        }
    }

    srcbuf.deinit();
    device.deinit();

    // After the loop, print results
    std::cout << "\nIndex,\tSize Copied,\tSRC,\tDST,\t\tCPU (GB/s),\tGPU (GB/s)\n";
    uint32_t index = 1;
    for (const auto& [size, map2] : results) {
        for (const auto& [memFlags, timer] : map2) {
            constexpr double GiB = 1024.0 * 1024.0 * 1024.0;
            double cpu_speed = (timer.cpu_ns > 0) ? (double)size * timer.loops / timer.cpu_ns * (1e9 / GiB) : 0.0;
            double gpu_speed = (timer.gpu_ns > 0) ? (double)size * timer.loops / timer.gpu_ns * (1e9 / GiB) : 0.0;
            
            std::cout << index++ << ",\t" 
                      << human_readable_size(size) << ",\t" 
                      << "DL,\t"
                      << VkMemoryPropertyFlags_str(memFlags, true) << ",\t\t"
                      << std::setprecision(5) << cpu_speed << ",\t\t"
                      << std::setprecision(5) << gpu_speed << std::endl;
        }
    }
}

VK_gpu_timer VK_test_bufcopy::single_test_case(
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