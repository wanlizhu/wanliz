#pragma once
#include "VK_common.h"

struct VK_instance {
    VkInstance handle = NULL;
    VkDebugUtilsMessengerEXT debugMessenger = NULL;

    static VK_instance& GET();
    inline operator VkInstance() const { return handle; }
    bool init();
    void deinit();
}; 

