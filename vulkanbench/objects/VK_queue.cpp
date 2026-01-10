#include "VK_queue.h"
#include "VK_device.h"
#include "VK_instance.h"

void VK_queue::init(VK_device* dev_ptr, uint32_t family, bool presenting) {
    if (dev_ptr == nullptr) {
        throw std::runtime_error("Invalid device pointer");
    }

    device_ptr = dev_ptr;
    family_index = family;
    supportPresenting = presenting;
    commandPool = VK_NULL_HANDLE;
    handle = VK_NULL_HANDLE;

    uint32_t queueFamilyCount = 0;
    vkGetPhysicalDeviceQueueFamilyProperties(device_ptr->physdev.handle, &queueFamilyCount, nullptr);
    std::vector<VkQueueFamilyProperties> queueFamilies(queueFamilyCount);
    vkGetPhysicalDeviceQueueFamilyProperties(device_ptr->physdev.handle, &queueFamilyCount, queueFamilies.data());
    
    if (family_index < queueFamilyCount) {
        properties = queueFamilies[family_index];
    } else {
        throw std::runtime_error("Invalid queue family index");
    }

    vkGetDeviceQueue(device_ptr->handle, family_index, 0, &handle);
    if (handle == VK_NULL_HANDLE) {
        throw std::runtime_error("Failed to get device queue");
    }

    create_command_pool();
    if (commandPool == VK_NULL_HANDLE) {
        throw std::runtime_error("Failed to create command pool");
    }
}

void VK_queue::deinit() {
    if (device_ptr == nullptr) {
        return;
    }
    
    if (device_ptr != nullptr && commandPool != VK_NULL_HANDLE) {
        vkDestroyCommandPool(device_ptr->handle, commandPool, nullptr);
        commandPool = VK_NULL_HANDLE;
    }
    
    handle = VK_NULL_HANDLE;
    family_index = UINT32_MAX;
    properties = {};
    supportPresenting = false;
    device_ptr = nullptr;
}

void VK_queue::create_command_pool() {
    VkCommandPoolCreateInfo poolInfo = {};
    poolInfo.sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO;
    poolInfo.queueFamilyIndex = family_index;
    poolInfo.flags = VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT;

    VkResult result = vkCreateCommandPool(device_ptr->handle, &poolInfo, nullptr, &commandPool);
    if (result != VK_SUCCESS) {
        throw std::runtime_error("Failed to create command pool");
    }
}

VkCommandBuffer VK_queue::alloc_and_begin_command_buffer(const std::string& name) {
    if (device_ptr == nullptr || commandPool == VK_NULL_HANDLE) {
        throw std::runtime_error("Cannot allocate command buffer: pool not created");
    }

    VkCommandBufferAllocateInfo allocInfo = {};
    allocInfo.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO;
    allocInfo.commandPool = commandPool;
    allocInfo.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY;
    allocInfo.commandBufferCount = 1;

    VkCommandBuffer commandBuffer = VK_NULL_HANDLE;
    VkResult result = vkAllocateCommandBuffers(device_ptr->handle, &allocInfo, &commandBuffer);
    if (result != VK_SUCCESS) {
        throw std::runtime_error("Failed to allocate command buffer");
    }

    if (!name.empty()) {
        auto pfnSetDebugUtilsObjectNameEXT = reinterpret_cast<PFN_vkSetDebugUtilsObjectNameEXT>(
            vkGetDeviceProcAddr(device_ptr->handle, "vkSetDebugUtilsObjectNameEXT")
        );
        if (pfnSetDebugUtilsObjectNameEXT) {
            VkDebugUtilsObjectNameInfoEXT nameInfo = {};
            nameInfo.sType = VK_STRUCTURE_TYPE_DEBUG_UTILS_OBJECT_NAME_INFO_EXT;
            nameInfo.objectType = VK_OBJECT_TYPE_COMMAND_BUFFER;
            nameInfo.objectHandle = reinterpret_cast<uint64_t>(commandBuffer);
            nameInfo.pObjectName = name.c_str();
            pfnSetDebugUtilsObjectNameEXT(device_ptr->handle, &nameInfo);
        }
    }

    VkCommandBufferBeginInfo beginInfo = {};
    beginInfo.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;
    beginInfo.flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;

    result = vkBeginCommandBuffer(commandBuffer, &beginInfo);
    if (result != VK_SUCCESS) {
        throw std::runtime_error("Failed to begin command buffer");
    }

    return commandBuffer;
}

VkSemaphore VK_queue::allocate_semaphore_bound_for(VkCommandBuffer cmdbuf) {
    VkSemaphoreCreateInfo semaphoreInfo = {};
    semaphoreInfo.sType = VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO;

    VkSemaphore semaphore = VK_NULL_HANDLE;
    VkResult result = vkCreateSemaphore(device_ptr->handle, &semaphoreInfo, nullptr, &semaphore);
    if (result != VK_SUCCESS) {
        throw std::runtime_error("Failed to create semaphore");
    }
    semaphores[cmdbuf].push_back(semaphore);

    return semaphore;
}

void VK_queue::cmdbuf_debug_range_begin(VkCommandBuffer cmdbuf, const std::string& label, VK_color color) {
    auto pfnCmdBeginDebugUtilsLabelEXT = reinterpret_cast<PFN_vkCmdBeginDebugUtilsLabelEXT>(
        vkGetInstanceProcAddr(VK_instance::GET().handle, "vkCmdBeginDebugUtilsLabelEXT")
    );
    if (pfnCmdBeginDebugUtilsLabelEXT) {
        VkDebugUtilsLabelEXT labelInfo = {};
        labelInfo.sType = VK_STRUCTURE_TYPE_DEBUG_UTILS_LABEL_EXT;
        labelInfo.pLabelName = label.c_str();
        
        switch (color) {
            case VK_color::WHITE:
                labelInfo.color[0] = 1.0f;
                labelInfo.color[1] = 1.0f;
                labelInfo.color[2] = 1.0f;
                labelInfo.color[3] = 1.0f;
                break;
            case VK_color::BLACK:
                labelInfo.color[0] = 0.0f;
                labelInfo.color[1] = 0.0f;
                labelInfo.color[2] = 0.0f;
                labelInfo.color[3] = 1.0f;
                break;
            case VK_color::RED:
                labelInfo.color[0] = 1.0f;
                labelInfo.color[1] = 0.0f;
                labelInfo.color[2] = 0.0f;
                labelInfo.color[3] = 1.0f;
                break;
            case VK_color::GREEN:
                labelInfo.color[0] = 0.0f;
                labelInfo.color[1] = 1.0f;
                labelInfo.color[2] = 0.0f;
                labelInfo.color[3] = 1.0f;
                break;
            case VK_color::BLUE:
                labelInfo.color[0] = 0.0f;
                labelInfo.color[1] = 0.0f;
                labelInfo.color[2] = 1.0f;
                labelInfo.color[3] = 1.0f;
                break;
        }
        
        pfnCmdBeginDebugUtilsLabelEXT(cmdbuf, &labelInfo);
    }
}

void VK_queue::cmdbuf_debug_range_end(VkCommandBuffer cmdbuf) {
    if (cmdbuf == VK_NULL_HANDLE) {
        return;
    }

    auto pfnCmdEndDebugUtilsLabelEXT = reinterpret_cast<PFN_vkCmdEndDebugUtilsLabelEXT>(
        vkGetInstanceProcAddr(VK_instance::GET().handle, "vkCmdEndDebugUtilsLabelEXT")
    );
    if (pfnCmdEndDebugUtilsLabelEXT) {
        pfnCmdEndDebugUtilsLabelEXT(cmdbuf);
    }
}

void VK_queue::submit_and_wait_command_buffer(VkCommandBuffer cmdbuf) {
    if (cmdbuf == VK_NULL_HANDLE || device_ptr == nullptr) {
        throw std::runtime_error("Invalid command buffer or device pointer");
    }

    VkResult result = vkEndCommandBuffer(cmdbuf);
    if (result != VK_SUCCESS) {
        throw std::runtime_error("Failed to end command buffer");
    }

    VkSubmitInfo submitInfo = {};
    submitInfo.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO;
    submitInfo.commandBufferCount = 1;
    submitInfo.pCommandBuffers = &cmdbuf;

    result = vkQueueSubmit(handle, 1, &submitInfo, VK_NULL_HANDLE);
    if (result != VK_SUCCESS) {
        throw std::runtime_error("Failed to submit command buffer");
    }

    vkQueueWaitIdle(handle);
    
    for (auto& semaphore : semaphores[cmdbuf]) {
        vkDestroySemaphore(device_ptr->handle, semaphore, NULL);
    }
    semaphores[cmdbuf].clear();
    vkFreeCommandBuffers(device_ptr->handle, commandPool, 1, &cmdbuf);
}

