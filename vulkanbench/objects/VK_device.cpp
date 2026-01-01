#include "VK_device.h"
#include <stdexcept>
#include <algorithm>

static bool is_blacklisted(const VK_physdev& dev) {
    std::string deviceName = dev.properties.deviceName;
    std::string driverName = dev.driver.driverName;
    
    std::transform(deviceName.begin(), deviceName.end(), deviceName.begin(), ::tolower);
    std::transform(driverName.begin(), driverName.end(), driverName.begin(), ::tolower);
    
    if (deviceName.find("intel") != std::string::npos) return true;
    if (deviceName.find("llvmpipe") != std::string::npos) return true;
    
    return false;
}

static int get_device_score(const VK_physdev& dev) {
    int score = 0;
    
    switch (dev.properties.deviceType) {
        case VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU:   score = 100; break;
        case VK_PHYSICAL_DEVICE_TYPE_INTEGRATED_GPU: score = 50;  break;
        case VK_PHYSICAL_DEVICE_TYPE_VIRTUAL_GPU:    score = 25;  break;
        case VK_PHYSICAL_DEVICE_TYPE_CPU:            score = 10;  break;
        default:                                      score = 0;   break;
    }
    
    std::string deviceName = dev.properties.deviceName;
    std::transform(deviceName.begin(), deviceName.end(), deviceName.begin(), ::tolower);
    if (deviceName.find("nvidia") != std::string::npos) {
        score += 50;
    }
    
    return score;
}

bool VK_device::init(int index, uint32_t queueFlags, int window_width, int window_height) {
    bool presenting = (window_width > 0 && window_height > 0);

    if (index < 0) {
        std::vector<VK_physdev> allDevices = VK_physdev::LIST();
        if (allDevices.empty()) {
            std::cerr << "No Vulkan physical devices found" << std::endl;
            throw std::runtime_error("Failed to create logical device");
        }

        int bestScore = -1;
        uint32_t bestIndex = UINT32_MAX;
        
        for (const auto& dev : allDevices) {
            if (is_blacklisted(dev)) {
                continue;
            }
            
            int score = get_device_score(dev);
            if (score > bestScore) {
                bestScore = score;
                bestIndex = dev.index;
            }
        }
        
        if (bestIndex == UINT32_MAX) {
            std::cerr << "No suitable GPU found (all devices are blacklisted)" << std::endl;
            throw std::runtime_error("Failed to create logical device");
        }

        index = bestIndex;
    }

    if (!physdev.init(index)) {
        std::cerr << "Failed to initialize physical device" << std::endl;
        throw std::runtime_error("Failed to create logical device");
    }
    
    std::cout << "Selected GPU: " << physdev.properties.deviceName << std::endl;

    if (presenting) {
        bool hasSwapchain = false;
        for (const auto& ext : physdev.extensions) {
            if (ext == VK_KHR_SWAPCHAIN_EXTENSION_NAME) {
                hasSwapchain = true;
                break;
            }
        }
        if (!hasSwapchain) {
            std::cerr << "Missing required device extension: " << VK_KHR_SWAPCHAIN_EXTENSION_NAME << std::endl;
            throw std::runtime_error("Failed to create logical device");
        }
    }

    uint32_t queueFamily = physdev.find_first_queue_family_supports(queueFlags, presenting);
    if (queueFamily == UINT32_MAX) {
        std::cerr << "No queue family found that supports requested flags";
        if (presenting) {
            std::cerr << " and presenting";
        }
        std::cerr << std::endl;
        throw std::runtime_error("Failed to create logical device");
    }

    float queuePriority = 1.0f;
    VkDeviceQueueCreateInfo queueCreateInfo = {};
    queueCreateInfo.sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO;
    queueCreateInfo.queueFamilyIndex = queueFamily;
    queueCreateInfo.queueCount = 1;
    queueCreateInfo.pQueuePriorities = &queuePriority;

    std::vector<const char*> deviceExtensions;
    if (presenting) {
        deviceExtensions.push_back(VK_KHR_SWAPCHAIN_EXTENSION_NAME);
    }

    VkDeviceCreateInfo createInfo = {};
    createInfo.sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO;
    createInfo.queueCreateInfoCount = 1;
    createInfo.pQueueCreateInfos = &queueCreateInfo;
    createInfo.enabledExtensionCount = static_cast<uint32_t>(deviceExtensions.size());
    createInfo.ppEnabledExtensionNames = deviceExtensions.empty() ? nullptr : deviceExtensions.data();
    createInfo.pEnabledFeatures = &physdev.features;

    VkResult result = vkCreateDevice(physdev.handle, &createInfo, nullptr, &handle);
    if (result != VK_SUCCESS) {
        std::cerr << "Failed to create logical device" << std::endl;
        throw std::runtime_error("Failed to create logical device");
    }

    if (!cmdqueue.init(this, queueFamily, presenting)) {
        std::cerr << "Failed to initialize command queue" << std::endl;
        vkDestroyDevice(handle, nullptr);
        handle = VK_NULL_HANDLE;
        throw std::runtime_error("Failed to create logical device");
    }

    if (presenting) {
        if (!swapchain.init(this, window_width, window_height)) {
            std::cerr << "Failed to initialize swapchain" << std::endl;
            cmdqueue.deinit();
            vkDestroyDevice(handle, nullptr);
            handle = VK_NULL_HANDLE;
            throw std::runtime_error("Failed to create logical device");
        }
    }

    querypool.init(this);

    std::cout << "[Vulkan Physical Device]\n"
        << "    Index: " << index << "\n"
        << "     Name: " << physdev.properties.deviceName << "\n"
        << "   Driver: " << physdev.driver.driverName << " " << physdev.driver.driverInfo << "\n"
        << "   Vulkan: " << VK_VERSION_MAJOR(physdev.properties.apiVersion) << "." << VK_VERSION_MINOR(physdev.properties.apiVersion) << "." << VK_VERSION_PATCH(physdev.properties.apiVersion) << "\n"
        << "Max Alloc: " << (physdev.maxAllocSize / (1024 * 1024)) << " MB" << "\n"
        << std::endl;

    return true;
}

void VK_device::deinit() {
    if (handle != VK_NULL_HANDLE) {
        vkDeviceWaitIdle(handle);
        querypool.deinit();
        swapchain.deinit();
        cmdqueue.deinit();
        vkDestroyDevice(handle, nullptr);
        handle = VK_NULL_HANDLE;
    }
    physdev.deinit();
}
