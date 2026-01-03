#include "VK_physdev.h"
#include "VK_instance.h"

std::vector<VK_physdev> VK_physdev::LIST() {
    std::vector<VK_physdev> out;
    uint32_t count = 0;
    VkResult res = vkEnumeratePhysicalDevices(VK_instance::GET(), &count, NULL);
    if (res != VK_SUCCESS || count == 0) {
        return out;
    }

    for (uint32_t i = 0; i < count; i++) {
        VK_physdev d;
        d.init(i);
        out.push_back(d);
    }

    return out;
}

void VK_physdev::init(int idx) {
    handle = VK_NULL_HANDLE;
    index = UINT32_MAX;
    features = {};
    properties = {};
    driver = {};
    memory = {};
    extensions.clear();
    queues.clear();

    uint32_t count = 0;
    VkResult res = vkEnumeratePhysicalDevices(VK_instance::GET(), &count, NULL);
    if (res != VK_SUCCESS || count == 0) {
        throw std::runtime_error("vkEnumeratePhysicalDevices failed");
    }
    std::vector<VkPhysicalDevice> devices(count);
    res = vkEnumeratePhysicalDevices(VK_instance::GET(), &count, devices.data());
    if (res != VK_SUCCESS || count == 0) {
        throw std::runtime_error("vkEnumeratePhysicalDevices failed");
    }

    if (idx >= (int)count) {
        throw std::runtime_error("device index overflow");
    }

    handle = devices[idx];
    index = idx;
    vkGetPhysicalDeviceFeatures(handle, &features);
    vkGetPhysicalDeviceProperties(handle, &properties);

    uint32_t ext_count = 0;
    vkEnumerateDeviceExtensionProperties(handle, NULL, &ext_count, NULL);
    std::vector<VkExtensionProperties> ext_props(ext_count);
    vkEnumerateDeviceExtensionProperties(handle, NULL, &ext_count,
                                         ext_props.data());
    for (const auto &prop : ext_props) {
        extensions.push_back(prop.extensionName);
    }

    uint32_t q_count = 0;
    vkGetPhysicalDeviceQueueFamilyProperties(handle, &q_count, NULL);
    std::vector<VkQueueFamilyProperties> queueFamilyProps(q_count);
    vkGetPhysicalDeviceQueueFamilyProperties(handle, &q_count, queueFamilyProps.data());
    
    for (uint32_t i = 0; i < q_count; i++) {
        VK_queue q;
        q.family_index = i;
        q.properties = queueFamilyProps[i];
        queues.push_back(q);
    }

    vkGetPhysicalDeviceMemoryProperties(handle, &memory);

    VkPhysicalDeviceMaintenance3Properties maintenance3{};
    maintenance3.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_MAINTENANCE_3_PROPERTIES;

    driver = {};
    driver.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DRIVER_PROPERTIES;
    driver.pNext = &maintenance3;

    VkPhysicalDeviceProperties2 props2{};
    props2.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PROPERTIES_2;
    props2.pNext = &driver;
    vkGetPhysicalDeviceProperties2(handle, &props2);

    maxAllocSize = maintenance3.maxMemoryAllocationSize;
}

void VK_physdev::deinit() {}

uint32_t VK_physdev::find_first_queue_family_supports(VkQueueFlags flags, bool presenting) const {
    VkSurfaceKHR tempSurface = VK_NULL_HANDLE;
#ifdef __linux__
    Display* display = nullptr;
#endif
#ifdef _WIN32
    HWND hwnd = nullptr;
    bool createdTempWindow = false;
#endif
    
    if (presenting) {
#ifdef _WIN32
        hwnd = GetActiveWindow();
        if (!hwnd) {
            WNDCLASSA wc = {};
            wc.lpfnWndProc = DefWindowProcA;
            wc.hInstance = GetModuleHandle(nullptr);
            wc.lpszClassName = "TempVulkanWindow";
            RegisterClassA(&wc);
            
            hwnd = CreateWindowExA(0, "TempVulkanWindow", "", WS_OVERLAPPEDWINDOW,
                                   0, 0, 1, 1, nullptr, nullptr, GetModuleHandle(nullptr), nullptr);
            createdTempWindow = hwnd != nullptr;
        }

        if (hwnd) {
            VkWin32SurfaceCreateInfoKHR createInfo = {};
            createInfo.sType = VK_STRUCTURE_TYPE_WIN32_SURFACE_CREATE_INFO_KHR;
            createInfo.hinstance = GetModuleHandle(nullptr);
            createInfo.hwnd = hwnd;

            auto vkCreateWin32SurfaceKHR = reinterpret_cast<PFN_vkCreateWin32SurfaceKHR>(vkGetInstanceProcAddr(VK_instance::GET().handle, "vkCreateWin32SurfaceKHR"));
            if (vkCreateWin32SurfaceKHR) {
                vkCreateWin32SurfaceKHR(VK_instance::GET().handle, &createInfo, nullptr, &tempSurface);
            }
        }

#elif defined(__linux__)
        display = XOpenDisplay(nullptr);
        if (display) {
            Window window = DefaultRootWindow(display);

            VkXlibSurfaceCreateInfoKHR createInfo = {};
            createInfo.sType = VK_STRUCTURE_TYPE_XLIB_SURFACE_CREATE_INFO_KHR;
            createInfo.dpy = display;
            createInfo.window = window;

            auto vkCreateXlibSurfaceKHR = reinterpret_cast<PFN_vkCreateXlibSurfaceKHR>(vkGetInstanceProcAddr(VK_instance::GET().handle, "vkCreateXlibSurfaceKHR"));
            if (vkCreateXlibSurfaceKHR) {
                vkCreateXlibSurfaceKHR(VK_instance::GET().handle, &createInfo, nullptr, &tempSurface);
            }
        }
#endif
    }

    if (presenting && tempSurface == VK_NULL_HANDLE) {
#ifdef __linux__
        if (display) {
            XCloseDisplay(display);
        }
#endif
#ifdef _WIN32
        if (createdTempWindow && hwnd) {
            DestroyWindow(hwnd);
        }
#endif
        return UINT32_MAX;
    }

    uint32_t result = UINT32_MAX;
    for (size_t i = 0; i < queues.size(); i++) {
        if ((queues[i].properties.queueFlags & flags) == flags) {
            if (presenting && tempSurface != VK_NULL_HANDLE) {
                VkBool32 presentSupport = false;
                vkGetPhysicalDeviceSurfaceSupportKHR(handle, static_cast<uint32_t>(i), tempSurface, &presentSupport);
                if (!presentSupport) {
                    continue; // This queue family doesn't support presenting
                }
            }
            
            result = static_cast<uint32_t>(i);
            break;
        }
    }

    if (tempSurface != VK_NULL_HANDLE) {
        vkDestroySurfaceKHR(VK_instance::GET().handle, tempSurface, nullptr);
    }
#ifdef __linux__
    if (display) {
        XCloseDisplay(display);
    }
#endif
#ifdef _WIN32
    if (createdTempWindow && hwnd) {
        DestroyWindow(hwnd);
    }
#endif

    return result;
}

uint32_t VK_physdev::find_first_memtype_supports(VkMemoryPropertyFlags flags, uint32_t filters, bool exclusive) const {
    for (uint32_t i = 0; i < memory.memoryTypeCount; i++) {
        if ((filters & (1 << i)) == 0) {
            continue;
        }
        if ((memory.memoryTypes[i].propertyFlags & flags) == flags) {
            if (memory.memoryTypes[i].propertyFlags == flags) {
                return i;
            } else if (exclusive == false) {
                return i;
            }
        }
    }
    return UINT32_MAX;
}

VkMemoryPropertyFlags VK_physdev::flags_of_memory_type_index(uint32_t index) const {
    if (index >= memory.memoryTypeCount) {
        throw std::runtime_error("Memory type index out of range");
    }
    return memory.memoryTypes[index].propertyFlags;
}