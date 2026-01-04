#pragma once
#include "objects/VK_common.h"
#include "objects/VK_device.h"
#include "objects/VK_image.h"
#include "objects/VK_buffer.h"

#define VK_TEST_RESOURCE_GROUP_SIZE 10
#define VK_TEST_AVERAGE_OF_LOOPS 30

struct VK_TestCase_buffercopy {
    void run(VK_device& device, const std::string& title);

private:
    void run_for_pi_capture(VK_device& device);
    VK_GB_per_second single_test_case(
        VK_device& device, 
        VK_buffer_group& cp_src_buffer_group,
        size_t size, 
        uint32_t cp_dst_mem_type_index
    );
    void print_results(
        VK_device& device, 
        const std::string& title, 
        uint32_t cp_src_mem_type_index
    );

private:
    std::map<size_t, std::map<uint32_t, VK_GB_per_second>> m_results;
    std::vector<size_t> m_cp_dst_buffer_size_list;
};


struct VK_TestCase_imagebuffercopy {
    void run(VK_device& device, const std::string& title);

private:
    void run_for_pi_capture(VK_device& device);
    void run_with_new_src_image(
        VK_device& device, 
        const std::string& title, 
        VkMemoryPropertyFlags cp_src_mem_type_flags,
        VkImageTiling cp_src_image_tiling
    );
    VK_GB_per_second single_test_case(
        VK_device& device, 
        VK_image_group& cp_src_image_group, 
        size_t width, 
        uint32_t cp_dst_mem_type_index
    );
    void print_results(
        VK_device& device, 
        const std::string& title, 
        uint32_t cp_src_mem_type_index
    );

private:
    std::map<size_t, std::map<uint32_t, VK_GB_per_second>> m_results_tiling_optimal;
    std::map<size_t, std::map<uint32_t, VK_GB_per_second>> m_results_tiling_linear;
    std::vector<size_t> m_cp_src_image_width_list;
    std::vector<uint32_t> m_cp_dst_mem_index_list;
};