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

    if (name.empty() || name == "buf") {
        subtest_buffer_to_buffer();
    }
    if (name.empty() || name == "img") {
        subtest_buffer_to_image();
    }

    print_table(m_resultsTable);
}

void VK_TestCase_memcopy::subtest_buffer_to_buffer() {
    VK_buffer_group src_buffers;
    src_buffers.init(
        VK_config::args["group-size"].as<int>(), 
        &m_device, 
        m_sizeInBytes, 
        VK_BUFFER_USAGE_TRANSFER_SRC_BIT | VK_BUFFER_USAGE_TRANSFER_DST_BIT, 
        VK_createInfo_memType::init_with_flags(VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT)
    );

    if (VK_config::args["profile"].as<bool>()) {
        VK_buffer_group dst_buffers;
        dst_buffers.init(
            VK_config::args["group-size"].as<int>(), 
            &m_device, 
            m_sizeInBytes,
            VK_BUFFER_USAGE_TRANSFER_SRC_BIT | VK_BUFFER_USAGE_TRANSFER_DST_BIT, 
            VK_createInfo_memType::init_with_flags(VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT)
        );

        if (VK_config::args["group-size"].as<int>() == 1) {
            dst_buffers[0].copy_from_buffer(src_buffers.random_pick());
        } else {
            std::cout << "Running for 10 seconds ...\n";
            auto start_time = std::chrono::steady_clock::now();
            while (std::chrono::steady_clock::now() - start_time < std::chrono::seconds(10)) {
                VkCommandBuffer cmdbuf = m_device.cmdqueue.alloc_and_begin_command_buffer("buf2buf:profile");
                for (int i = 0; i < 1000; i++) {
                    dst_buffers.random_pick().copy_from_buffer(src_buffers.random_pick(), &cmdbuf);
                }
                m_device.cmdqueue.submit_and_wait_command_buffer(cmdbuf);
            }
        }

        m_resultsTable.clear();
        dst_buffers.deinit();
    } else {
        src_buffers.write_noise();
        for (const auto& flags : std::vector<VkMemoryPropertyFlags>{
            VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
            VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT
        }) {
            VK_buffer_group dst_buffers;
            dst_buffers.init(
                VK_config::args["group-size"].as<int>(), 
                &m_device, 
                m_sizeInBytes,
                VK_BUFFER_USAGE_TRANSFER_SRC_BIT | VK_BUFFER_USAGE_TRANSFER_DST_BIT, 
                VK_createInfo_memType::init_with_flags(flags)
            );

            std::vector<VK_gpu_timer> timers;
            for (int i = 0; i < VK_config::args["loops"].as<int>(); i++) {
                timers.push_back(dst_buffers.random_pick().copy_from_buffer(src_buffers.random_pick()));
            }

            VK_GB_per_second speed(m_sizeInBytes, timers);
            m_resultsTable.push_back({
                "buffer -> buffer", 
                human_readable_size(m_sizeInBytes), 
                std::to_string(src_buffers[0].memoryTypeIndex) + " (" + VkMemoryPropertyFlags_str(src_buffers[0].memoryFlags, true) + ")",
                std::to_string(dst_buffers[0].memoryTypeIndex) + " (" + VkMemoryPropertyFlags_str(dst_buffers[0].memoryFlags, true) + ")",
                str_format("%.3f", speed.cpu_speed), 
                str_format("%.3f", speed.gpu_speed)
            });

            dst_buffers.deinit();
        }
    }
}

void VK_TestCase_memcopy::subtest_buffer_to_image() {
    VK_buffer_group src_buffers;
    src_buffers.init(
        VK_config::args["group-size"].as<int>(), 
        &m_device, 
        m_sizeInBytes, 
        VK_BUFFER_USAGE_TRANSFER_SRC_BIT | VK_BUFFER_USAGE_TRANSFER_DST_BIT, 
        VK_createInfo_memType::init_with_flags(VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT)
    );

    if (VK_config::args["profile"].as<bool>()) {
        VK_image_group dst_images;
        dst_images.init(
            VK_config::args["group-size"].as<int>(),
            &m_device,
            VK_FORMAT_R32G32B32A32_SFLOAT,
            m_imageExtent,
            VK_IMAGE_USAGE_TRANSFER_SRC_BIT | VK_IMAGE_USAGE_TRANSFER_DST_BIT | VK_IMAGE_USAGE_SAMPLED_BIT,
            VK_createInfo_memType::init_with_flags(VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT),
            VK_IMAGE_TILING_LINEAR
        );

        if (VK_config::args["group-size"].as<int>() == 1) {
            dst_images[0].copy_from_buffer(src_buffers.random_pick());
        } else {
            std::cout << "Running for 10 seconds ...\n";
            auto start_time = std::chrono::steady_clock::now();
            while (std::chrono::steady_clock::now() - start_time < std::chrono::seconds(10)) {
                VkCommandBuffer cmdbuf = m_device.cmdqueue.alloc_and_begin_command_buffer("buf2buf:profile");
                for (int i = 0; i < 1000; i++) {
                    dst_images.random_pick().copy_from_buffer(src_buffers.random_pick(), &cmdbuf);
                }
                m_device.cmdqueue.submit_and_wait_command_buffer(cmdbuf);
            }
        }

        m_resultsTable.clear();
        dst_images.deinit();
    } else {
        src_buffers.write_noise();
        for (const auto& flags : std::vector<VkMemoryPropertyFlags>{
            VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
            VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT
        }) {
            VK_image_group dst_images;
            dst_images.init(
                VK_config::args["group-size"].as<int>(),
                &m_device,
                VK_FORMAT_R32G32B32A32_SFLOAT,
                m_imageExtent,
                VK_IMAGE_USAGE_TRANSFER_SRC_BIT | VK_IMAGE_USAGE_TRANSFER_DST_BIT | VK_IMAGE_USAGE_SAMPLED_BIT,
                VK_createInfo_memType::init_with_flags(flags),
                VK_IMAGE_TILING_LINEAR
            );

            std::vector<VK_gpu_timer> timers;
            for (int i = 0; i < VK_config::args["loops"].as<int>(); i++) {
                timers.push_back(dst_images.random_pick().copy_from_buffer(src_buffers.random_pick()));
            }

            assert(m_sizeInBytes == (sizeof(float) * 4 * m_imageExtent.width * m_imageExtent.height));
            VK_GB_per_second speed(m_sizeInBytes, timers);
            m_resultsTable.push_back({
                "buffer -> image", 
                std::to_string(m_imageExtent.width) + "x" + std::to_string(m_imageExtent.height) + " (" + human_readable_size(m_sizeInBytes) + ")", 
                std::to_string(src_buffers[0].memoryTypeIndex) + " (" + VkMemoryPropertyFlags_str(src_buffers[0].memoryFlags, true) + ")",
                std::to_string(dst_images[0].memoryTypeIndex) + " (" + VkMemoryPropertyFlags_str(dst_images[0].memoryFlags, true) + ")",
                str_format("%.3f", speed.cpu_speed), 
                str_format("%.3f", speed.gpu_speed)
            });

            dst_images.deinit();
        }
    }
}