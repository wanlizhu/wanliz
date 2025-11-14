#pragma once
#include "VK_instance.h"

VKAPI_ATTR VkBool32 VKAPI_CALL debugCallback(
    VkDebugUtilsMessageSeverityFlagBitsEXT messageSeverity,
    VkDebugUtilsMessageTypeFlagsEXT messageType,
    const VkDebugUtilsMessengerCallbackDataEXT* pCallbackData,
    void* pUserData
) {
    std::cerr << pCallbackData->pMessage << std::endl;
    return VK_FALSE;
}

VK_instance& VK_instance::GET() {
    static VK_instance instance;
    return instance;
}

VK_instance::VK_instance() {
    uint32_t maxApiVersion = VK_API_VERSION_1_3;
    auto _vkEnumerateInstanceVersion = LOAD_VK_API_FROM_INST(vkEnumerateInstanceVersion, NULL);
    if (_vkEnumerateInstanceVersion) {
        _vkEnumerateInstanceVersion(&maxApiVersion);
    }

    std::vector<const char*> validationLayers = {
        "VK_LAYER_KHRONOS_validation"
    };
    std::vector<const char*> extensions = {
        VK_EXT_DEBUG_UTILS_EXTENSION_NAME
    };

    VkApplicationInfo appInfo{};
    appInfo.sType = VK_STRUCTURE_TYPE_APPLICATION_INFO;
    appInfo.pApplicationName = "Inspect GPU Perf Gaps";
    appInfo.applicationVersion = 0;
    appInfo.pEngineName = "No Engine";
    appInfo.engineVersion = 0;
    appInfo.apiVersion = maxApiVersion;

    VkDebugUtilsMessengerCreateInfoEXT debugCreateInfo{};
    debugCreateInfo.sType = VK_STRUCTURE_TYPE_DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT;
    debugCreateInfo.messageSeverity =
        VK_DEBUG_UTILS_MESSAGE_SEVERITY_VERBOSE_BIT_EXT |
        VK_DEBUG_UTILS_MESSAGE_SEVERITY_INFO_BIT_EXT |
        VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT |
        VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT;
    debugCreateInfo.messageType =
        VK_DEBUG_UTILS_MESSAGE_TYPE_GENERAL_BIT_EXT |
        VK_DEBUG_UTILS_MESSAGE_TYPE_VALIDATION_BIT_EXT |
        VK_DEBUG_UTILS_MESSAGE_TYPE_PERFORMANCE_BIT_EXT;
    debugCreateInfo.pfnUserCallback = debugCallback;
    debugCreateInfo.pUserData = nullptr;

    VkInstanceCreateInfo createInfo{};
    createInfo.sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO;
    createInfo.pApplicationInfo = &appInfo;
    createInfo.enabledLayerCount = (int)validationLayers.size();
    createInfo.ppEnabledLayerNames = validationLayers.data();
    createInfo.enabledExtensionCount = (int)extensions.size();
    createInfo.ppEnabledExtensionNames = extensions.data();
    createInfo.pNext = &debugCreateInfo;

    VkResult res = vkCreateInstance(&createInfo, nullptr, &handle);
    if (res != VK_SUCCESS || handle == NULL) {
        throw std::runtime_error("VkResult: " + std::to_string(res));
    }

    auto _vkCreateDebugUtilsMessengerEXT = LOAD_VK_API_FROM_INST(vkCreateDebugUtilsMessengerEXT, handle);
    if (_vkCreateDebugUtilsMessengerEXT) {
        res = _vkCreateDebugUtilsMessengerEXT(handle, &debugCreateInfo, NULL, &debugMessenger);
        if (res != VK_SUCCESS || debugMessenger == NULL) {
            throw std::runtime_error("VkResult: " + std::to_string(res));
        }
    }
}

VK_instance::~VK_instance() {
    if (debugMessenger) {
        auto _vkDestroyDebugUtilsMessengerEXT = LOAD_VK_API_FROM_INST(vkDestroyDebugUtilsMessengerEXT, handle);
        _vkDestroyDebugUtilsMessengerEXT(handle, debugMessenger, NULL);
    }
    vkDestroyInstance(handle, NULL);
}