#pragma once
#include "objects/VK_common.h"
#include "objects/VK_device.h"
#include "objects/VK_image.h"
#include "objects/VK_buffer.h"

struct VK_TestCase_buffercopy {
    void run(VK_device& device, const std::string& title);

private:
    VK_gpu_timer single_test_case(VK_device& device, VK_buffer& srcbuf, size_t size, VkMemoryPropertyFlags memFlags);
    void print_results(const std::string& title);

private:
    std::map<size_t, std::map<VkMemoryPropertyFlags, VK_gpu_timer>> results;
};

struct VK_TestCase_imagebuffercopy {
    void run(VK_device& device, const std::string& title);

private:
    void run_with_srcimg(VK_device& device, const std::string& title, VK_image& srcimg);
    VK_gpu_timer single_test_case(VK_device& device, VK_image& srcimg, size_t width, VkMemoryPropertyFlags memFlags);
    void print_results(const std::string& title);

private:
    std::map<size_t, std::map<VkMemoryPropertyFlags, VK_gpu_timer>> results;
    size_t imageSizeMin;
    size_t imageSizeMax;
    size_t imageSizeTestNum;
    size_t imageSizeInterval;
    std::vector<VkMemoryPropertyFlags> memFlagsList;
};