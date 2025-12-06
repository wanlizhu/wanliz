#pragma once
#include "VK_common.h"

struct VK_instance {
    VkInstance handle = NULL;
    VkDebugUtilsMessengerEXT debugMessenger = NULL;

    static VK_instance& GET();
    
    ~VK_instance();
    inline operator VkInstance() const { return handle; }

private:
    VK_instance();
    VK_instance(const VK_instance&) = delete;
    VK_instance(VK_instance&&) = delete;
    VK_instance& operator=(const VK_instance&) = delete;
    VK_instance& operator=(VK_instance&&) = delete;
};

std::string VkResult_str(VkResult result);