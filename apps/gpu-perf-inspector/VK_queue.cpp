#include "VK_queue.h"

VK_queue::VK_queue(VkPhysicalDevice physdev, VkDevice device, uint32_t family)
    : family_index(family) {
    if (physdev) {
        uint32_t count = 0;
        vkGetPhysicalDeviceQueueFamilyProperties(physdev, &count, NULL);
        std::vector<VkQueueFamilyProperties> props(count);
        vkGetPhysicalDeviceQueueFamilyProperties(physdev, &count, props.data());
        properties = props[family_index];
    }

    if (device) {
        vkGetDeviceQueue(device, family_index, 0, &handle);
    }
}