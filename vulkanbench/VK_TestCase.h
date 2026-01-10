#pragma once
#include "objects/VK_common.h"
#include "objects/VK_device.h"
#include "objects/VK_image.h"
#include "objects/VK_buffer.h"

#define MAX_CMDBUF_SIZE 1000

struct VK_TestCase_memcopy {
    VK_TestCase_memcopy(VK_device& device);
    void run_subtest(const std::string& name);

private:
    void subtest_buf2buf();
    void subtest_buf2buf_profile(VK_buffer_group& src_buffers);
    void subtest_buf2buf_regular(VK_buffer_group& src_buffers);

    void subtest_buf2img();
    void subtest_buf2img_profile(VK_buffer_group& src_buffers);
    void subtest_buf2img_regular(VK_buffer_group& src_buffers);

    void subtest_img2img();
    void subtest_img2img_profile(VK_image_group& src_images);
    void subtest_img2img_regular(VK_image_group& src_images);

private:
    VK_device& m_device;
    size_t m_sizeInBytes = VK_config::opt_as_int("size") * 1024 * 1024;
    VkExtent2D m_imageExtent = {0, 0};
    std::vector<std::vector<std::string>> m_resultsTable;
};