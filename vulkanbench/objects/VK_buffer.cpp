#include "VK_buffer.h"
#include "VK_common.h"
#include "VK_image.h"
#include "VK_device.h"
#include <cstdint>

bool VK_buffer::init(
    VK_device* device, 
    size_t size,
    VkBufferUsageFlags usageFlags, 
    VK_createInfo_memType memType
) {
    this->device_ptr = device;
    this->sizeInBytes = size;
    this->usageFlags = usageFlags;

    VkBufferCreateInfo bufferInfo = {};
    bufferInfo.sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO;
    bufferInfo.size = size;
    bufferInfo.usage = usageFlags;
    bufferInfo.sharingMode = VK_SHARING_MODE_EXCLUSIVE;

    VkResult result = vkCreateBuffer(device->handle, &bufferInfo, nullptr, &handle);
    if (result != VK_SUCCESS) {
        throw std::runtime_error("Failed to create buffer");
    }

    VkMemoryRequirements memReqs;
    vkGetBufferMemoryRequirements(device->handle, handle, &memReqs);

    if (memType.index == UINT32_MAX) {
        memoryFlags = memType.flags;
        memoryTypeIndex = device->physdev.find_first_memtype_supports(
            memType.flags,
            memReqs.memoryTypeBits
        );
    } else {
        if ((memReqs.memoryTypeBits & (1u << memType.index)) == 0) {
            throw std::runtime_error("Requested memory type index is not supported by buffer");
        }
        memoryFlags = device->physdev.flags_of_memory_type_index(memType.index);
        memoryTypeIndex = memType.index;
    }

    if (memoryTypeIndex == UINT32_MAX) {
        throw std::runtime_error("Failed to get desired memory type index");
    }

    VkMemoryAllocateInfo allocInfo = {};
    allocInfo.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
    allocInfo.allocationSize = memReqs.size;
    allocInfo.memoryTypeIndex = memoryTypeIndex;

    result = vkAllocateMemory(device->handle, &allocInfo, nullptr, &memory);
    if (result != VK_SUCCESS) {
        throw std::runtime_error("Failed to allocate memory");
    }

    result = vkBindBufferMemory(device->handle, handle, memory, 0);
    if (result != VK_SUCCESS) {
        throw std::runtime_error("Failed to bind buffer memory");
    }

    return true;
}

void VK_buffer::deinit() {
    if (refcount > 0) {
        vkDeviceWaitIdle(device_ptr->handle);
    }
    if (memory != VK_NULL_HANDLE) {
        vkFreeMemory(device_ptr->handle, memory, nullptr);
        memory = VK_NULL_HANDLE;
    }
    if (handle != VK_NULL_HANDLE) {
        vkDestroyBuffer(device_ptr->handle, handle, nullptr);
        handle = VK_NULL_HANDLE;
    }
    device_ptr = nullptr;
}

void VK_buffer::write(const void* src, uint32_t sizeMax) {
    if (refcount > 0) {
        throw std::runtime_error("GPU refcount is not zero");
    }

    size_t copySize = (sizeMax > 0 && sizeMax < sizeInBytes) ? sizeMax : sizeInBytes;

    if (memoryFlags & VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT) {
        void* data = nullptr;
        VkResult result = vkMapMemory(device_ptr->handle, memory, 0, copySize, 0, &data);
        if (result == VK_SUCCESS && data) {
            memcpy(data, src, copySize);
            vkUnmapMemory(device_ptr->handle, memory);
        }
        return;
    }

    VkCommandBuffer internal = device_ptr->cmdqueue.alloc_and_begin_command_buffer("VK_buffer::write");

    VkBufferCreateInfo stagingBufferInfo = {};
    stagingBufferInfo.sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO;
    stagingBufferInfo.size = copySize;
    stagingBufferInfo.usage = VK_BUFFER_USAGE_TRANSFER_SRC_BIT;
    stagingBufferInfo.sharingMode = VK_SHARING_MODE_EXCLUSIVE;

    VkBuffer stagingBuffer = VK_NULL_HANDLE;
    VkDeviceMemory stagingMemory = VK_NULL_HANDLE;
    VkResult result = vkCreateBuffer(device_ptr->handle, &stagingBufferInfo, nullptr, &stagingBuffer);
    if (result != VK_SUCCESS) {
        throw std::runtime_error("Failed to create buffer");
    }

    VkMemoryRequirements memReqs;
    vkGetBufferMemoryRequirements(device_ptr->handle, stagingBuffer, &memReqs);

    uint32_t memoryTypeIndex = device_ptr->physdev.find_first_memtype_supports(
        VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
        memReqs.memoryTypeBits
    );
    if (memoryTypeIndex == UINT32_MAX) {
        throw std::runtime_error("Failed to get desired memory type index");
    }

    VkMemoryAllocateInfo allocInfo = {};
    allocInfo.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
    allocInfo.allocationSize = memReqs.size;
    allocInfo.memoryTypeIndex = memoryTypeIndex;

    result = vkAllocateMemory(device_ptr->handle, &allocInfo, nullptr, &stagingMemory);
    if (result != VK_SUCCESS) {
        throw std::runtime_error("Failed to allocate memory");
    }

    result = vkBindBufferMemory(device_ptr->handle, stagingBuffer, stagingMemory, 0);
    if (result != VK_SUCCESS) {
        throw std::runtime_error("Failed to bind buffer memory");
    }

    void* data = nullptr;
    result = vkMapMemory(device_ptr->handle, stagingMemory, 0, copySize, 0, &data);
    if (result == VK_SUCCESS && data) {
        memcpy(data, src, copySize);
        vkUnmapMemory(device_ptr->handle, stagingMemory);
    }

    VkBufferCopy copyRegion = {};
    copyRegion.srcOffset = 0;
    copyRegion.dstOffset = 0;
    copyRegion.size = copySize;

    vkCmdCopyBuffer(internal, stagingBuffer, handle, 1, &copyRegion);

    device_ptr->cmdqueue.submit_and_wait_command_buffer(internal);
    vkFreeMemory(device_ptr->handle, stagingMemory, nullptr);
    vkDestroyBuffer(device_ptr->handle, stagingBuffer, nullptr);
}

void VK_buffer::write_noise() {
    if (sizeInBytes == 0) {
        return;
    }

    std::random_device rd;
    std::mt19937_64 gen(rd());

    std::vector<uint8_t> randomData(sizeInBytes);
    uint64_t* ptr64 = reinterpret_cast<uint64_t*>(randomData.data());
    for (size_t i = 0; i < sizeInBytes / 8 / 4; i+=4) {
        ptr64[i] = gen();
        ptr64[i + 1] = ptr64[i] & (i > 1 ? ptr64[i-1] : 0x31415926);
        ptr64[i + 2] = ptr64[i] & ptr64[i + 1];
        ptr64[i + 3] = ptr64[i] & ptr64[i + 2];
    }
   
    write(randomData.data(), static_cast<uint32_t>(sizeInBytes));
}

VK_gpu_timer VK_buffer::copy_from_buffer(VK_buffer& src) {
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

    VkCommandBuffer internal = device_ptr->cmdqueue.alloc_and_begin_command_buffer("VK_buffer::copy_from_buffer");

    VkBufferCopy copyRegion = {};
    copyRegion.srcOffset = 0;
    copyRegion.dstOffset = 0;
    copyRegion.size = copySize;

    timer.gpu_begin(internal);
    vkCmdCopyBuffer(internal, src.handle, handle, 1, &copyRegion);
    timer.gpu_end(internal);

    device_ptr->cmdqueue.submit_and_wait_command_buffer(internal);

    timer.cpu_end();
    return timer;
}

VK_gpu_timer VK_buffer::copy_from_image(VK_image& src) {
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

    VkCommandBuffer internal = device_ptr->cmdqueue.alloc_and_begin_command_buffer("VK_buffer::copy_from_image");

    VkImageLayout oldLayout = src.currentImageLayout;
    src.image_layout_transition(internal, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL);

    size_t srcPixelCount = (size_t)src.extent.width * src.extent.height;
    size_t pixelSize = (srcPixelCount > 0) ? (src.sizeInBytes / srcPixelCount) : 1;
    size_t maxPixels = sizeInBytes / pixelSize;
    
    uint32_t copyWidth = src.extent.width;
    uint32_t copyHeight = (uint32_t)std::min((size_t)src.extent.height, maxPixels / copyWidth);
    if (copyHeight == 0 && maxPixels > 0) {
        copyWidth = (uint32_t)std::min((size_t)src.extent.width, maxPixels);
        copyHeight = 1;
    }

    VkBufferImageCopy region = {};
    region.bufferOffset = 0;
    region.bufferRowLength = 0;
    region.bufferImageHeight = 0;
    region.imageSubresource.aspectMask = src.aspectFlags;
    region.imageSubresource.mipLevel = 0;
    region.imageSubresource.baseArrayLayer = 0;
    region.imageSubresource.layerCount = 1;
    region.imageOffset = {0, 0, 0};
    region.imageExtent = {copyWidth, copyHeight, 1};

    timer.gpu_begin(internal);
    vkCmdCopyImageToBuffer(
        internal,
        src.handle,
        src.currentImageLayout,
        handle,
        1,
        &region
    );
    timer.gpu_end(internal);

    if (oldLayout != VK_IMAGE_LAYOUT_UNDEFINED && oldLayout != src.currentImageLayout) {
        src.image_layout_transition(internal, oldLayout);
    }

    device_ptr->cmdqueue.submit_and_wait_command_buffer(internal);

    timer.cpu_end();
    return timer;
}

std::shared_ptr<std::vector<uint8_t>> VK_buffer::readback() {
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

    VkCommandBuffer internal = device_ptr->cmdqueue.alloc_and_begin_command_buffer("VK_buffer::readback");

    VkBufferCreateInfo stagingBufferInfo = {};
    stagingBufferInfo.sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO;
    stagingBufferInfo.size = sizeInBytes;
    stagingBufferInfo.usage = VK_BUFFER_USAGE_TRANSFER_DST_BIT;
    stagingBufferInfo.sharingMode = VK_SHARING_MODE_EXCLUSIVE;

    VkBuffer stagingBuffer = VK_NULL_HANDLE;
    VkResult vkResult = vkCreateBuffer(device_ptr->handle, &stagingBufferInfo, nullptr, &stagingBuffer);
    if (vkResult != VK_SUCCESS) {
        throw std::runtime_error("Failed to create staging buffer for readback");
    }

    VkMemoryRequirements memReqs;
    vkGetBufferMemoryRequirements(device_ptr->handle, stagingBuffer, &memReqs);

    uint32_t stagingMemoryTypeIndex = device_ptr->physdev.find_first_memtype_supports(
        VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT,
        memReqs.memoryTypeBits
    );
    if (stagingMemoryTypeIndex == UINT32_MAX) {
        throw std::runtime_error("Failed to find suitable memory type for staging buffer");
    }

    VkMemoryAllocateInfo allocInfo = {};
    allocInfo.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
    allocInfo.allocationSize = memReqs.size;
    allocInfo.memoryTypeIndex = stagingMemoryTypeIndex;

    VkDeviceMemory stagingMemory;
    vkResult = vkAllocateMemory(device_ptr->handle, &allocInfo, nullptr, &stagingMemory);
    if (vkResult != VK_SUCCESS) {
        throw std::runtime_error("Failed to allocate staging memory for readback");
    }

    vkResult = vkBindBufferMemory(device_ptr->handle, stagingBuffer, stagingMemory, 0);
    if (vkResult != VK_SUCCESS) {
        throw std::runtime_error("Failed to bind staging buffer memory for readback");
    }

    VkBufferCopy copyRegion = {};
    copyRegion.srcOffset = 0;
    copyRegion.dstOffset = 0;
    copyRegion.size = sizeInBytes;

    vkCmdCopyBuffer(internal, handle, stagingBuffer, 1, &copyRegion);

    device_ptr->cmdqueue.submit_and_wait_command_buffer(internal);

    void* data = nullptr;
    vkResult = vkMapMemory(device_ptr->handle, stagingMemory, 0, sizeInBytes, 0, &data);
    if (vkResult == VK_SUCCESS && data) {
        memcpy(result->data(), data, sizeInBytes);
        vkUnmapMemory(device_ptr->handle, stagingMemory);
    }

    vkFreeMemory(device_ptr->handle, stagingMemory, nullptr);
    vkDestroyBuffer(device_ptr->handle, stagingBuffer, nullptr);
    return result;
}
