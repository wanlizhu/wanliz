#include "VK_image.h"
#include "VK_buffer.h"
#include "VK_device.h"
#include "VK_compute_pipeline.h"

bool VK_image::init(
    VK_device* device, 
    VkFormat format, 
    VkExtent2D extent, 
    VkImageUsageFlags usageFlags, 
    VkMemoryPropertyFlags memoryFlags
) {
    this->device_ptr = device;
    this->format = format;
    this->extent = extent;
    this->usageFlags = usageFlags;
    this->memoryFlags = memoryFlags;

    if (format == VK_FORMAT_D16_UNORM || 
        format == VK_FORMAT_D32_SFLOAT ||
        format == VK_FORMAT_D16_UNORM_S8_UINT ||
        format == VK_FORMAT_D24_UNORM_S8_UINT ||
        format == VK_FORMAT_D32_SFLOAT_S8_UINT) {
        aspectFlags = VK_IMAGE_ASPECT_DEPTH_BIT;
        if (format == VK_FORMAT_D16_UNORM_S8_UINT ||
            format == VK_FORMAT_D24_UNORM_S8_UINT ||
            format == VK_FORMAT_D32_SFLOAT_S8_UINT) {
            aspectFlags |= VK_IMAGE_ASPECT_STENCIL_BIT;
        }
    } else {
        aspectFlags = VK_IMAGE_ASPECT_COLOR_BIT;
    }

    VkImageCreateInfo imageInfo = {};
    imageInfo.sType = VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO;
    imageInfo.imageType = VK_IMAGE_TYPE_2D;
    imageInfo.format = format;
    imageInfo.extent.width = extent.width;
    imageInfo.extent.height = extent.height;
    imageInfo.extent.depth = 1;
    imageInfo.mipLevels = 1;
    imageInfo.arrayLayers = 1;
    imageInfo.samples = VK_SAMPLE_COUNT_1_BIT;
    imageInfo.tiling = VK_IMAGE_TILING_OPTIMAL;
    imageInfo.usage = usageFlags;
    imageInfo.sharingMode = VK_SHARING_MODE_EXCLUSIVE;
    imageInfo.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED;

    VkResult result = vkCreateImage(device->handle, &imageInfo, nullptr, &handle);
    if (result != VK_SUCCESS) {
        return false;
    }

    VkMemoryRequirements memReqs;
    vkGetImageMemoryRequirements(device->handle, handle, &memReqs);
    sizeInBytes = static_cast<uint32_t>(memReqs.size);

    uint32_t memoryTypeIndex = device->physdev.find_first_memtype_supports(
        memoryFlags, 
        memReqs.memoryTypeBits
    );
    if (memoryTypeIndex == UINT32_MAX) {
        vkDestroyImage(device->handle, handle, nullptr);
        handle = VK_NULL_HANDLE;
        return false;
    }

    VkMemoryAllocateInfo allocInfo = {};
    allocInfo.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
    allocInfo.allocationSize = memReqs.size;
    allocInfo.memoryTypeIndex = memoryTypeIndex;

    result = vkAllocateMemory(device->handle, &allocInfo, nullptr, &memory);
    if (result != VK_SUCCESS) {
        vkDestroyImage(device->handle, handle, nullptr);
        handle = VK_NULL_HANDLE;
        return false;
    }

    result = vkBindImageMemory(device->handle, handle, memory, 0);
    if (result != VK_SUCCESS) {
        vkFreeMemory(device->handle, memory, nullptr);
        vkDestroyImage(device->handle, handle, nullptr);
        handle = VK_NULL_HANDLE;
        memory = VK_NULL_HANDLE;
        return false;
    }

    VkImageViewCreateInfo viewInfo = {};
    viewInfo.sType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO;
    viewInfo.image = handle;
    viewInfo.viewType = VK_IMAGE_VIEW_TYPE_2D;
    viewInfo.format = format;
    viewInfo.components.r = VK_COMPONENT_SWIZZLE_IDENTITY;
    viewInfo.components.g = VK_COMPONENT_SWIZZLE_IDENTITY;
    viewInfo.components.b = VK_COMPONENT_SWIZZLE_IDENTITY;
    viewInfo.components.a = VK_COMPONENT_SWIZZLE_IDENTITY;
    viewInfo.subresourceRange.aspectMask = aspectFlags;
    viewInfo.subresourceRange.baseMipLevel = 0;
    viewInfo.subresourceRange.levelCount = 1;
    viewInfo.subresourceRange.baseArrayLayer = 0;
    viewInfo.subresourceRange.layerCount = 1;

    result = vkCreateImageView(device->handle, &viewInfo, nullptr, &view);
    if (result != VK_SUCCESS) {
        vkFreeMemory(device->handle, memory, nullptr);
        vkDestroyImage(device->handle, handle, nullptr);
        handle = VK_NULL_HANDLE;
        memory = VK_NULL_HANDLE;
        return false;
    }

    currentImageLayout = VK_IMAGE_LAYOUT_UNDEFINED;
    return true;
}

void VK_image::deinit() {
    if (refcount > 0) {
        vkDeviceWaitIdle(device_ptr->handle);
    }
    if (view != VK_NULL_HANDLE) {
        vkDestroyImageView(device_ptr->handle, view, nullptr);
        view = VK_NULL_HANDLE;
    }
    if (memory != VK_NULL_HANDLE) {
        vkFreeMemory(device_ptr->handle, memory, nullptr);
        memory = VK_NULL_HANDLE;
    }
    if (handle != VK_NULL_HANDLE) {
        vkDestroyImage(device_ptr->handle, handle, nullptr);
        handle = VK_NULL_HANDLE;
    }
    device_ptr = nullptr;
}

void VK_image::image_layout_transition(
    VkCommandBuffer cmdbuf, 
    VkImageLayout dstLayout
) {
    VkImageMemoryBarrier barrier = {};
    barrier.sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER;
    barrier.oldLayout = currentImageLayout;
    barrier.newLayout = dstLayout;
    barrier.srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
    barrier.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
    barrier.image = handle;
    barrier.subresourceRange.aspectMask = aspectFlags;
    barrier.subresourceRange.baseMipLevel = 0;
    barrier.subresourceRange.levelCount = 1;
    barrier.subresourceRange.baseArrayLayer = 0;
    barrier.subresourceRange.layerCount = 1;

    VkPipelineStageFlags srcStage = VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT;
    VkPipelineStageFlags dstStage = VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT;

    switch (currentImageLayout) {
        case VK_IMAGE_LAYOUT_UNDEFINED:
            barrier.srcAccessMask = 0;
            srcStage = VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT;
            break;
        case VK_IMAGE_LAYOUT_GENERAL:
            barrier.srcAccessMask = VK_ACCESS_SHADER_READ_BIT | VK_ACCESS_SHADER_WRITE_BIT;
            srcStage = VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT;
            break;
        case VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL:
            barrier.srcAccessMask = VK_ACCESS_TRANSFER_READ_BIT;
            srcStage = VK_PIPELINE_STAGE_TRANSFER_BIT;
            break;
        case VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL:
            barrier.srcAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT;
            srcStage = VK_PIPELINE_STAGE_TRANSFER_BIT;
            break;
        case VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL:
            barrier.srcAccessMask = VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT;
            srcStage = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
            break;
        case VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL:
            barrier.srcAccessMask = VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT;
            srcStage = VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT | VK_PIPELINE_STAGE_LATE_FRAGMENT_TESTS_BIT;
            break;
        case VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL:
            barrier.srcAccessMask = VK_ACCESS_SHADER_READ_BIT;
            srcStage = VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT;
            break;
        default:
            barrier.srcAccessMask = 0;
            srcStage = VK_PIPELINE_STAGE_ALL_COMMANDS_BIT;
            break;
    }

    switch (dstLayout) {
        case VK_IMAGE_LAYOUT_GENERAL:
            barrier.dstAccessMask = VK_ACCESS_SHADER_READ_BIT | VK_ACCESS_SHADER_WRITE_BIT;
            dstStage = VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT;
            break;
        case VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL:
            barrier.dstAccessMask = VK_ACCESS_TRANSFER_READ_BIT;
            dstStage = VK_PIPELINE_STAGE_TRANSFER_BIT;
            break;
        case VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL:
            barrier.dstAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT;
            dstStage = VK_PIPELINE_STAGE_TRANSFER_BIT;
            break;
        case VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL:
            barrier.dstAccessMask = VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT;
            dstStage = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
            break;
        case VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL:
            barrier.dstAccessMask = VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT;
            dstStage = VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT | VK_PIPELINE_STAGE_LATE_FRAGMENT_TESTS_BIT;
            break;
        case VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL:
            barrier.dstAccessMask = VK_ACCESS_SHADER_READ_BIT;
            dstStage = VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT;
            break;
        case VK_IMAGE_LAYOUT_PRESENT_SRC_KHR:
            barrier.dstAccessMask = VK_ACCESS_MEMORY_READ_BIT;
            dstStage = VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT;
            break;
        default:
            barrier.dstAccessMask = 0;
            dstStage = VK_PIPELINE_STAGE_ALL_COMMANDS_BIT;
            break;
    }

    vkCmdPipelineBarrier(
        cmdbuf,
        srcStage,
        dstStage,
        0,
        0, nullptr,
        0, nullptr,
        1, &barrier
    );

    currentImageLayout = dstLayout;
}

void VK_image::write(
    const void* src, 
    size_t sizeMax
) {
    if (refcount > 0) {
        throw std::runtime_error("GPU refcount is not zero");
    }

    size_t copySize = (sizeMax > 0 && sizeMax < sizeInBytes) ? sizeMax : sizeInBytes;

    VK_buffer stagingBuffer;
    if (!stagingBuffer.init(device_ptr, 
        copySize, 
        VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
        VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT)) {
        throw std::runtime_error("Failed to create staging buffer");
    }

    void* data = nullptr;
    VkResult result = vkMapMemory(device_ptr->handle, stagingBuffer.memory, 0, copySize, 0, &data);
    if (result == VK_SUCCESS && data) {
        memcpy(data, src, copySize);
        vkUnmapMemory(device_ptr->handle, stagingBuffer.memory);
    }

    VkCommandBuffer internal = device_ptr->cmdqueue.alloc_and_begin_command_buffer("VK_image::write");
    if (internal == VK_NULL_HANDLE) {
        throw std::runtime_error("Failed to allocate command buffer");
    }

    VkImageLayout oldLayout = currentImageLayout;
    image_layout_transition(internal, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL);

    VkBufferImageCopy region = {};
    region.bufferOffset = 0;
    region.bufferRowLength = 0;
    region.bufferImageHeight = 0;
    region.imageSubresource.aspectMask = aspectFlags;
    region.imageSubresource.mipLevel = 0;
    region.imageSubresource.baseArrayLayer = 0;
    region.imageSubresource.layerCount = 1;
    region.imageOffset = {0, 0, 0};
    region.imageExtent = {extent.width, extent.height, 1};

    vkCmdCopyBufferToImage(
        internal,
        stagingBuffer.handle,
        handle,
        currentImageLayout,
        1,
        &region
    );

    if (oldLayout != VK_IMAGE_LAYOUT_UNDEFINED && oldLayout != currentImageLayout) {
        image_layout_transition(internal, oldLayout);
    }

    device_ptr->cmdqueue.submit_and_wait_command_buffer(internal);
    stagingBuffer.deinit();
}

void VK_image::write_noise() {
    if (sizeInBytes == 0) {
        return;
    }

    std::random_device rd;
    std::mt19937 gen(rd());
    std::uniform_int_distribution<uint16_t> dist(0, 255);

    std::vector<uint8_t> randomData(sizeInBytes);
    for (uint32_t i = 0; i < sizeInBytes; i++) {
        randomData[i] = static_cast<uint8_t>(dist(gen));
    }

    write(randomData.data(), sizeInBytes);
}

VK_gpu_timer VK_image::copy_from_buffer(VK_buffer& src) {
    if (refcount > 0 || src.refcount > 0) {
        throw std::runtime_error("GPU refcount is not zero");
    }

    VK_gpu_timer timer(device_ptr);
    timer.cpu_begin();

    size_t copySize = std::min(sizeInBytes, src.sizeInBytes);
    bool srcHostVisible = (src.memoryFlags & VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT) != 0;
    bool dstHostVisible = (memoryFlags & VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT) != 0;

    if (srcHostVisible && dstHostVisible) {
        timer.cpu_begin();
        void* srcData = nullptr;
        void* dstData = nullptr;
        vkMapMemory(device_ptr->handle, src.memory, 0, copySize, 0, &srcData);
        vkMapMemory(device_ptr->handle, memory, 0, copySize, 0, &dstData);
        memcpy(dstData, srcData, copySize);
        vkUnmapMemory(device_ptr->handle, src.memory);
        vkUnmapMemory(device_ptr->handle, memory);
        timer.cpu_end();
        return timer;
    }

    VkCommandBuffer internal = device_ptr->cmdqueue.alloc_and_begin_command_buffer("VK_image::copy_from_buffer");

    VkImageLayout oldLayout = currentImageLayout;
    image_layout_transition(internal, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL);

    VkBufferImageCopy region = {};
    region.bufferOffset = 0;
    region.bufferRowLength = 0;
    region.bufferImageHeight = 0;
    region.imageSubresource.aspectMask = aspectFlags;
    region.imageSubresource.mipLevel = 0;
    region.imageSubresource.baseArrayLayer = 0;
    region.imageSubresource.layerCount = 1;
    region.imageOffset = {0, 0, 0};
    region.imageExtent = {extent.width, extent.height, 1};

    timer.gpu_begin(internal);
    vkCmdCopyBufferToImage(
        internal,
        src.handle,
        handle,
        currentImageLayout,
        1,
        &region
    );
    timer.gpu_end(internal);

    if (oldLayout != VK_IMAGE_LAYOUT_UNDEFINED && oldLayout != currentImageLayout) {
        image_layout_transition(internal, oldLayout);
    }

    device_ptr->cmdqueue.submit_and_wait_command_buffer(internal);

    timer.cpu_end();
    return timer;
}

VK_gpu_timer VK_image::copy_from_image(VK_image& src) {
    if (refcount > 0 || src.refcount > 0) {
        throw std::runtime_error("GPU refcount is not zero");
    }

    VK_gpu_timer timer(device_ptr);
    timer.cpu_begin();

    size_t copySize = std::min(sizeInBytes, src.sizeInBytes);
    bool srcHostVisible = (src.memoryFlags & VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT) != 0;
    bool dstHostVisible = (memoryFlags & VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT) != 0;

    if (srcHostVisible && dstHostVisible) {
        timer.cpu_begin();
        void* srcData = nullptr;
        void* dstData = nullptr;
        vkMapMemory(device_ptr->handle, src.memory, 0, copySize, 0, &srcData);
        vkMapMemory(device_ptr->handle, memory, 0, copySize, 0, &dstData);
        memcpy(dstData, srcData, copySize);
        vkUnmapMemory(device_ptr->handle, src.memory);
        vkUnmapMemory(device_ptr->handle, memory);
        timer.cpu_end();
        return timer;
    } 

    VkCommandBuffer internal = device_ptr->cmdqueue.alloc_and_begin_command_buffer("VK_image::copy_from_image");

    VkImageLayout srcOldLayout = src.currentImageLayout;
    VkImageLayout dstOldLayout = currentImageLayout;
    src.image_layout_transition(internal, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL);
    image_layout_transition(internal, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL);

    VkImageCopy region = {};
    region.srcSubresource.aspectMask = src.aspectFlags;
    region.srcSubresource.mipLevel = 0;
    region.srcSubresource.baseArrayLayer = 0;
    region.srcSubresource.layerCount = 1;
    region.srcOffset = {0, 0, 0};
    region.dstSubresource.aspectMask = aspectFlags;
    region.dstSubresource.mipLevel = 0;
    region.dstSubresource.baseArrayLayer = 0;
    region.dstSubresource.layerCount = 1;
    region.dstOffset = {0, 0, 0};
    region.extent = {
        std::min(src.extent.width, extent.width),
        std::min(src.extent.height, extent.height),
        1
    };

    timer.gpu_begin(internal);
    vkCmdCopyImage(
        internal,
        src.handle,
        src.currentImageLayout,
        handle,
        currentImageLayout,
        1,
        &region
    );
    timer.gpu_end(internal);

    if (srcOldLayout != VK_IMAGE_LAYOUT_UNDEFINED && srcOldLayout != src.currentImageLayout) {
        src.image_layout_transition(internal, srcOldLayout);
    }
    if (dstOldLayout != VK_IMAGE_LAYOUT_UNDEFINED && dstOldLayout != currentImageLayout) {
        image_layout_transition(internal, dstOldLayout);
    }

    device_ptr->cmdqueue.submit_and_wait_command_buffer(internal);
    timer.cpu_end();

    return timer;
}

std::shared_ptr<std::vector<uint8_t>> VK_image::readback() {
    if (refcount > 0) {
        throw std::runtime_error("GPU refcount is not zero");
    }

    auto result = std::make_shared<std::vector<uint8_t>>(sizeInBytes);

    if (memoryFlags & VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT) {
        void* data = nullptr;
        VkResult vkResult = vkMapMemory(device_ptr->handle, memory, 0, sizeInBytes, 0, &data);
        if (vkResult == VK_SUCCESS && data) {
            memcpy(result->data(), data, sizeInBytes);
            vkUnmapMemory(device_ptr->handle, memory);
        }
        return result;
    }

    VK_buffer stagingBuffer;
    if (!stagingBuffer.init(device_ptr, sizeInBytes, 
        VK_BUFFER_USAGE_TRANSFER_DST_BIT,
        VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT)) {
        return result;
    }

    VkCommandBuffer internal = device_ptr->cmdqueue.alloc_and_begin_command_buffer("VK_image::readback");
    if (internal == VK_NULL_HANDLE) {
        stagingBuffer.deinit();
        return result;
    }

    VkImageLayout oldLayout = currentImageLayout;
    image_layout_transition(internal, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL);

    VkBufferImageCopy region = {};
    region.bufferOffset = 0;
    region.bufferRowLength = 0;
    region.bufferImageHeight = 0;
    region.imageSubresource.aspectMask = aspectFlags;
    region.imageSubresource.mipLevel = 0;
    region.imageSubresource.baseArrayLayer = 0;
    region.imageSubresource.layerCount = 1;
    region.imageOffset = {0, 0, 0};
    region.imageExtent = {extent.width, extent.height, 1};

    vkCmdCopyImageToBuffer(
        internal,
        handle,
        currentImageLayout,
        stagingBuffer.handle,
        1,
        &region
    );

    if (oldLayout != VK_IMAGE_LAYOUT_UNDEFINED && oldLayout != currentImageLayout) {
        image_layout_transition(internal, oldLayout);
    }

    device_ptr->cmdqueue.submit_and_wait_command_buffer(internal);

    void* data = nullptr;
    VkResult vkResult = vkMapMemory(device_ptr->handle, stagingBuffer.memory, 0, sizeInBytes, 0, &data);
    if (vkResult == VK_SUCCESS && data) {
        memcpy(result->data(), data, sizeInBytes);
        vkUnmapMemory(device_ptr->handle, stagingBuffer.memory);
    }

    stagingBuffer.deinit();
    return result;
}

