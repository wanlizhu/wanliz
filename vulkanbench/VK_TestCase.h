#pragma once
#include "objects/VK_common.h"
#include "objects/VK_device.h"
#include "objects/VK_image.h"
#include "objects/VK_buffer.h"

struct VK_TestCase_buffercopy {
    void run(VK_device& device, const std::string& title);

private:
    VK_gpu_timer single_test_case(
        VK_device& device, 
        VK_buffer& cp_src_buffer, 
        size_t size, 
        uint32_t cp_dst_mem_type_index
    );
    void print_results(
        VK_device& device, 
        const std::string& title, 
        uint32_t cp_src_mem_type_index
    );

private:
    std::map<size_t, std::map<uint32_t, VK_gpu_timer>> results;
};


struct VK_TestCase_imagebuffercopy {
    void run(VK_device& device, const std::string& title);

private:
    void run_with_srcimg(
        VK_device& device, 
        const std::string& title, 
        VkMemoryPropertyFlags cp_src_mem_type_flags
    );
    VK_gpu_timer single_test_case(
        VK_device& device, 
        VK_image& srcimg, 
        size_t width, 
        uint32_t cp_dst_mem_type_index
    );
    void print_results(
        VK_device& device, 
        const std::string& title, 
        uint32_t cp_src_mem_type_index
    );

private:
    std::map<size_t, std::map<uint32_t, VK_gpu_timer>> results;
    std::vector<uint32_t> cp_dst_mem_index_list;
    size_t cp_src_img_width_min;
    size_t cp_src_img_width_max;
    size_t cp_src_img_width_test_num;
    size_t cp_src_img_width_interval;
};