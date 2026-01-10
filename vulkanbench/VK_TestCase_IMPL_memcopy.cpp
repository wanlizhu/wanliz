#include "objects/VK_buffer.h"
#include "objects/VK_common.h"
#include "VK_TestCase.h"

VK_TestCase_memcopy::VK_TestCase_memcopy(VK_device& device) 
    : m_device(device) 
{}

void VK_TestCase_memcopy::run_subtest(const std::string& name) {
    m_resultsTable.push_back({
        "Subtest Name", "Size (MB)", "Src Mem Flags", "Dst Mem Flags", "CPU (GB/s)", "GPU (GB/s)"
    });

    if (name.empty() || name == "buf2bug") {
        subtest_buf2buf();
    }
    if (name.empty() || name == "buf2img") {
        subtest_buf2img();
    }
    if (name.empty() || name == "img2img") {
        subtest_img2img();
    }

    print_table(m_resultsTable);
}

void VK_TestCase_memcopy::subtest_buf2buf() {
    VK_buffer_group src_buffers;
    src_buffers.init(
        VK_config::opt_as_int("group-size"), 
        &m_device, 
        m_sizeInBytes, 
        VK_BUFFER_USAGE_TRANSFER_SRC_BIT | VK_BUFFER_USAGE_TRANSFER_DST_BIT, 
        VK_createInfo_memType::init_with_flags(VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT)
    );

    if (VK_config::opt_as_bool("profile")) {
        subtest_buf2buf_profile(src_buffers);
    } else {
        subtest_buf2buf_regular(src_buffers);
    }

    src_buffers.deinit();
}

void VK_TestCase_memcopy::subtest_buf2buf_profile(VK_buffer_group& src_buffers) {
    VK_buffer_group dst_buffers;
    dst_buffers.init(
        VK_config::opt_as_int("group-size"), 
        &m_device, 
        m_sizeInBytes,
        VK_BUFFER_USAGE_TRANSFER_SRC_BIT | VK_BUFFER_USAGE_TRANSFER_DST_BIT, 
        VK_createInfo_memType::init_with_flags(VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT)
    );

    if (VK_config::opt_as_int("group-size") == 1) {
        dst_buffers[0].copy_from_buffer(src_buffers.random_pick());
    } else {
        std::cout << "Running buffer->buffer for 10 seconds ...\n";
        std::vector<VK_gpu_timer> timers;

        auto start_time = std::chrono::steady_clock::now();
        while (std::chrono::steady_clock::now() - start_time < std::chrono::seconds(10)) {
            VkCommandBuffer cmdbuf = m_device.cmdqueue.alloc_and_begin_command_buffer("buf2buf:profile");
            for (int i = 0; i < MAX_CMDBUF_SIZE; i++) {
                auto timer = dst_buffers.random_pick().copy_from_buffer(src_buffers.random_pick(), cmdbuf);
                timers.push_back(timer);
            }
            m_device.cmdqueue.submit_and_wait_command_buffer(cmdbuf);
        }

        VK_GB_per_second speed(m_sizeInBytes, timers);
        printf("buffer->buffer | %s | Src = %s | Dst = %s | GPU = %7.3f (GB/s)\n", 
            human_readable_size(m_sizeInBytes).c_str(), 
            (std::to_string(src_buffers[0].memoryTypeIndex) + " (" + VkMemoryPropertyFlags_str(src_buffers[0].memoryFlags, true) + ")").c_str(),
            (std::to_string(dst_buffers[0].memoryTypeIndex) + " (" + VkMemoryPropertyFlags_str(dst_buffers[0].memoryFlags, true) + ")").c_str(),
            speed.gpu_speed
        );
        m_device.cmdqueue.free_semaphores_bound_for(NULL);
    }

    m_resultsTable.clear();
    dst_buffers.deinit();
    printf("\n");
}

void VK_TestCase_memcopy::subtest_buf2buf_regular(VK_buffer_group& src_buffers) {
    src_buffers.write_noise();
    for (const auto& flags : std::vector<VkMemoryPropertyFlags>{
        VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
        VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT
    }) {
        VK_buffer_group dst_buffers;
        dst_buffers.init(
            VK_config::opt_as_int("group-size"), 
            &m_device, 
            m_sizeInBytes,
            VK_BUFFER_USAGE_TRANSFER_SRC_BIT | VK_BUFFER_USAGE_TRANSFER_DST_BIT, 
            VK_createInfo_memType::init_with_flags(flags)
        );

        std::vector<VK_gpu_timer> timers;
        for (int i = 0; i < VK_config::opt_as_int("loops"); i++) {
            timers.push_back(dst_buffers.random_pick().copy_from_buffer(src_buffers.random_pick()));
        }

        VK_GB_per_second speed(m_sizeInBytes, timers);
        m_resultsTable.push_back({
            "buffer->buffer", 
            human_readable_size(m_sizeInBytes), 
            std::to_string(src_buffers[0].memoryTypeIndex) + " (" + VkMemoryPropertyFlags_str(src_buffers[0].memoryFlags, true) + ")",
            std::to_string(dst_buffers[0].memoryTypeIndex) + " (" + VkMemoryPropertyFlags_str(dst_buffers[0].memoryFlags, true) + ")",
            str_format("%.3f", speed.cpu_speed), 
            str_format("%.3f", speed.gpu_speed)
        });

        dst_buffers.deinit();
    }
}

void VK_TestCase_memcopy::subtest_buf2img() {
    VK_buffer_group src_buffers;
    src_buffers.init(
        VK_config::opt_as_int("group-size"), 
        &m_device, 
        m_sizeInBytes, 
        VK_BUFFER_USAGE_TRANSFER_SRC_BIT | VK_BUFFER_USAGE_TRANSFER_DST_BIT, 
        VK_createInfo_memType::init_with_flags(VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT)
    );

    if (m_imageExtent.width <= 0 || m_imageExtent.height <= 0) {
        int sq_px = std::ceil((double)m_sizeInBytes / (sizeof(float) * 4.0));
        int width = std::ceil(std::sqrt(sq_px));
        assert(width * width >= sq_px);
        m_imageExtent.width = width;
        m_imageExtent.height = width;
    }

    if (VK_config::opt_as_bool("profile")) {
        subtest_buf2img_profile(src_buffers);
    } else {
        subtest_buf2img_regular(src_buffers);
    }

    src_buffers.deinit();
}

void VK_TestCase_memcopy::subtest_buf2img_profile(VK_buffer_group& src_buffers) {
    VK_image_group dst_images;
    dst_images.init(
        VK_config::opt_as_int("group-size"),
        &m_device,
        VK_FORMAT_R32G32B32A32_SFLOAT,
        m_imageExtent,
        VK_IMAGE_USAGE_TRANSFER_SRC_BIT | VK_IMAGE_USAGE_TRANSFER_DST_BIT | VK_IMAGE_USAGE_SAMPLED_BIT,
        VK_createInfo_memType::init_with_flags(VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT),
        VK_IMAGE_TILING_LINEAR
    );

    if (VK_config::opt_as_int("group-size") == 1) {
        dst_images[0].copy_from_buffer(src_buffers.random_pick());
    } else {
        std::cout << "Running buffer->image  for 10 seconds ...\n";
        std::vector<VK_gpu_timer> timers;

        auto start_time = std::chrono::steady_clock::now();
        while (std::chrono::steady_clock::now() - start_time < std::chrono::seconds(10)) {
            VkCommandBuffer cmdbuf = m_device.cmdqueue.alloc_and_begin_command_buffer("buf2img:profile");
            for (int i = 0; i < MAX_CMDBUF_SIZE; i++) {
                auto timer = dst_images.random_pick().copy_from_buffer(src_buffers.random_pick(), cmdbuf);
                timers.push_back(timer);
            }
            m_device.cmdqueue.submit_and_wait_command_buffer(cmdbuf);
        }

        VK_GB_per_second speed(m_sizeInBytes, timers);
        printf("buffer->image  | %s | Src = %s | Dst = %s | GPU = %7.3f (GB/s)\n", 
            human_readable_size(m_sizeInBytes).c_str(), 
            (std::to_string(src_buffers[0].memoryTypeIndex) + " (" + VkMemoryPropertyFlags_str(src_buffers[0].memoryFlags, true) + ")").c_str(),
            (std::to_string(dst_images[0].memoryTypeIndex) + " (" + VkMemoryPropertyFlags_str(dst_images[0].memoryFlags, true) + ")").c_str(),
            speed.gpu_speed
        );
        m_device.cmdqueue.free_semaphores_bound_for(NULL);
    }

    m_resultsTable.clear();
    dst_images.deinit();
    printf("\n");
}

void VK_TestCase_memcopy::subtest_buf2img_regular(VK_buffer_group& src_buffers) {
    src_buffers.write_noise();
    for (const auto& flags : std::vector<VkMemoryPropertyFlags>{
        VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
        VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT
    }) {
        VK_image_group dst_images;
        dst_images.init(
            VK_config::opt_as_int("group-size"),
            &m_device,
            VK_FORMAT_R32G32B32A32_SFLOAT,
            m_imageExtent,
            VK_IMAGE_USAGE_TRANSFER_SRC_BIT | VK_IMAGE_USAGE_TRANSFER_DST_BIT | VK_IMAGE_USAGE_SAMPLED_BIT,
            VK_createInfo_memType::init_with_flags(flags),
            VK_IMAGE_TILING_LINEAR
        );

        std::vector<VK_gpu_timer> timers;
        for (int i = 0; i < VK_config::opt_as_int("loops"); i++) {
            timers.push_back(dst_images.random_pick().copy_from_buffer(src_buffers.random_pick()));
        }

        assert(m_sizeInBytes == (sizeof(float) * 4 * m_imageExtent.width * m_imageExtent.height));
        VK_GB_per_second speed(m_sizeInBytes, timers);
        m_resultsTable.push_back({
            "buffer->image", 
            std::to_string(m_imageExtent.width) + "x" + std::to_string(m_imageExtent.height), 
            std::to_string(src_buffers[0].memoryTypeIndex) + " (" + VkMemoryPropertyFlags_str(src_buffers[0].memoryFlags, true) + ")",
            std::to_string(dst_images[0].memoryTypeIndex) + " (" + VkMemoryPropertyFlags_str(dst_images[0].memoryFlags, true) + ")",
            str_format("%.3f", speed.cpu_speed), 
            str_format("%.3f", speed.gpu_speed)
        });

        dst_images.deinit();
    }
}

void VK_TestCase_memcopy::subtest_img2img() {
    VK_image_group src_images;
    src_images.init(
        VK_config::opt_as_int("group-size"),
        &m_device,
        VK_FORMAT_R32G32B32A32_SFLOAT,
        m_imageExtent,
        VK_IMAGE_USAGE_TRANSFER_SRC_BIT | VK_IMAGE_USAGE_TRANSFER_DST_BIT | VK_IMAGE_USAGE_SAMPLED_BIT,
        VK_createInfo_memType::init_with_flags(VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT),
        VK_IMAGE_TILING_LINEAR
    );

    if (m_imageExtent.width <= 0 || m_imageExtent.height <= 0) {
        int sq_px = std::ceil((double)m_sizeInBytes / (sizeof(float) * 4.0));
        int width = std::ceil(std::sqrt(sq_px));
        assert(width * width >= sq_px);
        m_imageExtent.width = width;
        m_imageExtent.height = width;
    }

    if (VK_config::opt_as_bool("profile")) {
        subtest_img2img_profile(src_images);
    } else {
        subtest_img2img_regular(src_images);
    }

    src_images.deinit();
}

void VK_TestCase_memcopy::subtest_img2img_profile(VK_image_group& src_images) {
    VK_image_group dst_images;
    dst_images.init(
        VK_config::opt_as_int("group-size"),
        &m_device,
        VK_FORMAT_R32G32B32A32_SFLOAT,
        m_imageExtent,
        VK_IMAGE_USAGE_TRANSFER_SRC_BIT | VK_IMAGE_USAGE_TRANSFER_DST_BIT | VK_IMAGE_USAGE_SAMPLED_BIT,
        VK_createInfo_memType::init_with_flags(VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT),
        VK_IMAGE_TILING_LINEAR
    );

    if (VK_config::opt_as_int("group-size") == 1) {
        dst_images[0].copy_from_image(src_images.random_pick());
    } else {
        std::cout << "Running image->image   for 10 seconds ...\n";
        std::vector<VK_gpu_timer> timers;

        auto start_time = std::chrono::steady_clock::now();
        while (std::chrono::steady_clock::now() - start_time < std::chrono::seconds(10)) {
            VkCommandBuffer cmdbuf = m_device.cmdqueue.alloc_and_begin_command_buffer("img2img:profile");
            for (int i = 0; i < MAX_CMDBUF_SIZE; i++) {
                auto timer = dst_images.random_pick().copy_from_image(src_images.random_pick(), cmdbuf);
                timers.push_back(timer);
            }
            m_device.cmdqueue.submit_and_wait_command_buffer(cmdbuf);
        }

        assert(m_sizeInBytes == (sizeof(float) * 4 * m_imageExtent.width * m_imageExtent.height));
        VK_GB_per_second speed(m_sizeInBytes, timers);
        printf("image->image   | %s | Src = %s | Dst = %s | GPU = %7.3f (GB/s)\n", 
            human_readable_size(m_sizeInBytes).c_str(), 
            (std::to_string(src_images[0].memoryTypeIndex) + " (" + VkMemoryPropertyFlags_str(src_images[0].memoryFlags, true) + ")").c_str(),
            (std::to_string(dst_images[0].memoryTypeIndex) + " (" + VkMemoryPropertyFlags_str(dst_images[0].memoryFlags, true) + ")").c_str(),
            speed.gpu_speed
        );
        m_device.cmdqueue.free_semaphores_bound_for(NULL);
    }

    m_resultsTable.clear();
    dst_images.deinit();
    printf("\n");
}

void VK_TestCase_memcopy::subtest_img2img_regular(VK_image_group& src_images) {
    src_images.write_noise();
    for (const auto& flags : std::vector<VkMemoryPropertyFlags>{
        VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
        VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT
    }) {
        VK_image_group dst_images;
        dst_images.init(
            VK_config::opt_as_int("group-size"),
            &m_device,
            VK_FORMAT_R32G32B32A32_SFLOAT,
            m_imageExtent,
            VK_IMAGE_USAGE_TRANSFER_SRC_BIT | VK_IMAGE_USAGE_TRANSFER_DST_BIT | VK_IMAGE_USAGE_SAMPLED_BIT,
            VK_createInfo_memType::init_with_flags(flags),
            VK_IMAGE_TILING_LINEAR
        );

        std::vector<VK_gpu_timer> timers;
        for (int i = 0; i < VK_config::opt_as_int("loops"); i++) {
            timers.push_back(dst_images.random_pick().copy_from_image(src_images.random_pick()));
        }

        assert(m_sizeInBytes == (sizeof(float) * 4 * m_imageExtent.width * m_imageExtent.height));
        VK_GB_per_second speed(m_sizeInBytes, timers);
        m_resultsTable.push_back({
            "image->image", 
            std::to_string(m_imageExtent.width) + "x" + std::to_string(m_imageExtent.height), 
            std::to_string(src_images[0].memoryTypeIndex) + " (" + VkMemoryPropertyFlags_str(src_images[0].memoryFlags, true) + ")",
            std::to_string(dst_images[0].memoryTypeIndex) + " (" + VkMemoryPropertyFlags_str(dst_images[0].memoryFlags, true) + ")",
            str_format("%.3f", speed.cpu_speed), 
            str_format("%.3f", speed.gpu_speed)
        });

        dst_images.deinit();
    }
}