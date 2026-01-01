#pragma once
#include "objects/VK_common.h"
#include "objects/VK_device.h"
#include "objects/VK_image.h"
#include "objects/VK_buffer.h"

struct VK_test_bufcopy {
    VK_device device;

    void run();
    VK_gpu_timer single_test_case(VK_buffer& srcbuf, size_t size, VkMemoryPropertyFlags memFlags);
};