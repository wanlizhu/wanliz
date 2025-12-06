#pragma once
#include "VK_instance.h"
#include "VK_queue.h"

struct VK_physdev {
    VkPhysicalDevice handle = NULL;
    uint32_t index = UINT32_MAX;
    VkPhysicalDeviceFeatures features = {};
    VkPhysicalDeviceProperties properties = {};
    VkPhysicalDeviceDriverProperties driver = {};
    VkPhysicalDeviceMemoryProperties memory = {};
    std::string pci_bus_id = "";
    std::vector<std::string> extensions = {};
    std::vector<VK_queue> queues = {};

    static std::vector<VK_physdev> LIST();
    static std::string INFO();
    
    VK_physdev(uint32_t idx);
    nlohmann::json info() const;
};