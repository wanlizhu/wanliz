#pragma once
#include "common.h"

#define LOAD_VK_API_FROM_INST(name, instance) reinterpret_cast<PFN_##name>(vkGetInstanceProcAddr(instance, #name))
#define LOAD_VK_API(name) LOAD_VK_API_FROM_INST(name, VK_instance::GET().handle)

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