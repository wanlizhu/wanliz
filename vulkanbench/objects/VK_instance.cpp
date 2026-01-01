#include "VK_instance.h"

VKAPI_ATTR VkBool32 VKAPI_CALL debugCallback(
    VkDebugUtilsMessageSeverityFlagBitsEXT messageSeverity,
    VkDebugUtilsMessageTypeFlagsEXT messageType,
    const VkDebugUtilsMessengerCallbackDataEXT* pCallbackData,
    void* pUserData
) {
    if (messageSeverity >= VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT) {
        std::cerr << pCallbackData->pMessage << std::endl;
    }
    return VK_FALSE;
}

VK_instance& VK_instance::GET() {
    static VK_instance instance;
    static bool inited = false;
    if (!inited) {
        instance.init();
        inited = true;
    }

    return instance;
}

bool VK_instance::init() {
    uint32_t maxApiVersion = VK_API_VERSION_1_3;
    auto _vkEnumerateInstanceVersion = reinterpret_cast<PFN_vkEnumerateInstanceVersion>(vkGetInstanceProcAddr(NULL, "vkEnumerateInstanceVersion"));
    if (_vkEnumerateInstanceVersion) {
        _vkEnumerateInstanceVersion(&maxApiVersion);
    }

    if (maxApiVersion < VK_API_VERSION_1_3) {
        throw std::runtime_error("Vulkan 1.3 is required");
    }

    uint32_t requestedApiVersion = maxApiVersion;
    if (requestedApiVersion > VK_API_VERSION_1_3) {
        requestedApiVersion = VK_API_VERSION_1_3;
    }

    bool foundRequiredLayers = false;
    std::vector<const char*> validationLayers = {
        "VK_LAYER_KHRONOS_validation"
    };

    uint32_t availableExtCount = 0;
    vkEnumerateInstanceExtensionProperties(nullptr, &availableExtCount, nullptr);
    std::vector<VkExtensionProperties> availableExts(availableExtCount);
    vkEnumerateInstanceExtensionProperties(nullptr, &availableExtCount, availableExts.data());

    auto hasExt = [&](const char* extName) -> bool {
        for (const auto& ext : availableExts) {
            if (strcmp(ext.extensionName, extName) == 0) {
                return true;
            }
        }
        return false;
    };

    std::vector<const char*> extensions;
    bool enableDebugUtils = false;

    if (hasExt(VK_KHR_SURFACE_EXTENSION_NAME)) {
        extensions.push_back(VK_KHR_SURFACE_EXTENSION_NAME);
#ifdef _WIN32
        if (hasExt(VK_KHR_WIN32_SURFACE_EXTENSION_NAME)) {
            extensions.push_back(VK_KHR_WIN32_SURFACE_EXTENSION_NAME);
        }
#elif defined(__linux__)
        if (hasExt(VK_KHR_XLIB_SURFACE_EXTENSION_NAME)) {
            extensions.push_back(VK_KHR_XLIB_SURFACE_EXTENSION_NAME);
        }
#endif
    }

    if (hasExt(VK_EXT_DEBUG_UTILS_EXTENSION_NAME)) {
        extensions.push_back(VK_EXT_DEBUG_UTILS_EXTENSION_NAME);
        enableDebugUtils = true;
    }

    uint32_t availableLayerCount = 0;
    vkEnumerateInstanceLayerProperties(&availableLayerCount, nullptr);
    std::vector<VkLayerProperties> availableLayers(availableLayerCount);
    vkEnumerateInstanceLayerProperties(&availableLayerCount, availableLayers.data());
    for (const VkLayerProperties& layer : availableLayers) {
        if (strcmp(layer.layerName, "VK_LAYER_KHRONOS_validation") == 0) {
            foundRequiredLayers = true;
        }
    }


    VkApplicationInfo appInfo{};
    appInfo.sType = VK_STRUCTURE_TYPE_APPLICATION_INFO;
    appInfo.pApplicationName = "Inspect GPU Perf Info";
    appInfo.applicationVersion = 0;
    appInfo.pEngineName = "No Engine";
    appInfo.engineVersion = 0;
    appInfo.apiVersion = requestedApiVersion;

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
    createInfo.enabledLayerCount = foundRequiredLayers ? (int)validationLayers.size() : 0;
    createInfo.ppEnabledLayerNames = foundRequiredLayers ? validationLayers.data() : nullptr;
    createInfo.enabledExtensionCount = (int)extensions.size();
    createInfo.ppEnabledExtensionNames = extensions.empty() ? nullptr : extensions.data();
    createInfo.pNext = enableDebugUtils ? &debugCreateInfo : nullptr;

    VkResult res = vkCreateInstance(&createInfo, nullptr, &handle);
    if (res != VK_SUCCESS || handle == VK_NULL_HANDLE) {
        throw std::runtime_error("VkResult: " + VkResult_str(res));
    }

    if (enableDebugUtils) {
        auto _vkCreateDebugUtilsMessengerEXT = reinterpret_cast<PFN_vkCreateDebugUtilsMessengerEXT>(vkGetInstanceProcAddr(handle, "vkCreateDebugUtilsMessengerEXT"));
        if (_vkCreateDebugUtilsMessengerEXT) {
            res = _vkCreateDebugUtilsMessengerEXT(handle, &debugCreateInfo, NULL, &debugMessenger);
            if (res != VK_SUCCESS || debugMessenger == VK_NULL_HANDLE) {
                throw std::runtime_error("VkResult: " + VkResult_str(res));
            }
        }
    }

    return true;
}

void VK_instance::deinit() {
    if (!handle) {
        return;
    }

    if (debugMessenger) {
        auto _vkDestroyDebugUtilsMessengerEXT = reinterpret_cast<PFN_vkDestroyDebugUtilsMessengerEXT>(vkGetInstanceProcAddr(handle, "vkDestroyDebugUtilsMessengerEXT"));
        if (_vkDestroyDebugUtilsMessengerEXT) {
            _vkDestroyDebugUtilsMessengerEXT(handle, debugMessenger, NULL);
        }
        debugMessenger = VK_NULL_HANDLE;
    }
    vkDestroyInstance(handle, NULL);
    handle = VK_NULL_HANDLE;
}