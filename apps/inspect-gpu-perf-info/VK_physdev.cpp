#include "VK_physdev.h"

std::vector<VK_physdev> VK_physdev::LIST() {
    std::vector<VK_physdev> out;
    uint32_t count = 0;
    vkEnumeratePhysicalDevices(VK_instance::GET(), &count, NULL);

    for (uint32_t i = 0; i < count; i++) {
        out.push_back(VK_physdev(i));
    }

    return out;
}

std::string VK_physdev::INFO() {
    nlohmann::json array = nlohmann::json::array();

    for (const auto &physdev : LIST()) {
        array.push_back(physdev.info());
    }

    return array.dump(4);
}

VK_physdev::VK_physdev(uint32_t idx) {
    uint32_t count = 0;
    vkEnumeratePhysicalDevices(VK_instance::GET(), &count, NULL);
    std::vector<VkPhysicalDevice> devices(count);
    vkEnumeratePhysicalDevices(VK_instance::GET(), &count, devices.data());

    if (idx < 0 || idx >= count) {
        throw std::runtime_error("Index out of range");
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
    vkGetPhysicalDeviceQueueFamilyProperties(handle, &count, NULL);
    for (uint32_t i = 0; i < q_count; i++) {
        queues.push_back(VK_queue(handle, NULL, i));
    }

    vkGetPhysicalDeviceMemoryProperties(handle, &memory);

    driver = {};
    driver.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DRIVER_PROPERTIES;
    VkPhysicalDeviceProperties2 props2{};
    props2.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PROPERTIES_2;
    props2.pNext = &driver;
    vkGetPhysicalDeviceProperties2(handle, &props2);

    if (FIND_IN_VEC(VK_EXT_PCI_BUS_INFO_EXTENSION_NAME, extensions)) {
        VkPhysicalDevicePCIBusInfoPropertiesEXT pciInfo{};
        pciInfo.sType =
            VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PCI_BUS_INFO_PROPERTIES_EXT;
        VkPhysicalDeviceProperties2 props2{};
        props2.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PROPERTIES_2;
        props2.pNext = &pciInfo;
        vkGetPhysicalDeviceProperties2(handle, &props2);

        std::ostringstream oss;
        oss << std::hex << std::setfill('0') << std::setw(4)
            << pciInfo.pciDomain << ':' << std::setw(2) << pciInfo.pciBus << ':'
            << std::setw(2) << pciInfo.pciDevice << '.' << std::setw(1)
            << pciInfo.pciFunction;
        pci_bus_id = oss.str();
    }
}

nlohmann::json VK_physdev::info() const {
    std::string vendorID = std::to_string(properties.vendorID);
    if (properties.vendorID == 0x10de) {
        vendorID += " (NVIDIA)";
    } else if (properties.vendorID == 0x1002) {
        vendorID += " (AMD)";
    } else if (properties.vendorID == 0x8086) {
        vendorID += " (Intel)";
    }

    std::string type = "unknown";
    if (properties.deviceType == VK_PHYSICAL_DEVICE_TYPE_INTEGRATED_GPU) {
        type = "iGPU";
    } else if (properties.deviceType == VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU) {
        type = "dGPU";
    } else if (properties.deviceType == VK_PHYSICAL_DEVICE_TYPE_VIRTUAL_GPU) {
        type = "vGPU";
    } else if (properties.deviceType == VK_PHYSICAL_DEVICE_TYPE_CPU) {
        type = "CPU";
    }

    auto print_version = [&](uint32_t v) -> std::string {
        uint32_t major = VK_API_VERSION_MAJOR(v);
        uint32_t minor = VK_API_VERSION_MINOR(v);
        uint32_t patch = VK_API_VERSION_PATCH(v);
        std::ostringstream oss;
        oss << major << "." << minor << "." << patch;
        return oss.str();
    };

    auto print_hex = [](uint32_t num) -> std::string {
        std::ostringstream oss;
        oss << "0x" << std::hex << std::setw(4) << std::setfill('0') << num;
        return oss.str();
    };

    auto print_driver_id = [&]() -> std::string {
        switch (static_cast<int>(driver.driverID)) {
        case 1:
            return "VK_DRIVER_ID_AMD_PROPRIETARY";
        case 2:
            return "VK_DRIVER_ID_AMD_OPEN_SOURCE";
        case 3:
            return "VK_DRIVER_ID_MESA_RADV";
        case 4:
            return "VK_DRIVER_ID_NVIDIA_PROPRIETARY";
        case 5:
            return "VK_DRIVER_ID_INTEL_PROPRIETARY_WINDOWS";
        case 6:
            return "VK_DRIVER_ID_INTEL_OPEN_SOURCE_MESA";
        case 7:
            return "VK_DRIVER_ID_IMAGINATION_PROPRIETARY";
        case 8:
            return "VK_DRIVER_ID_QUALCOMM_PROPRIETARY";
        case 9:
            return "VK_DRIVER_ID_ARM_PROPRIETARY";
        case 10:
            return "VK_DRIVER_ID_GOOGLE_SWIFTSHADER";
        case 11:
            return "VK_DRIVER_ID_GGP_PROPRIETARY";
        case 12:
            return "VK_DRIVER_ID_BROADCOM_PROPRIETARY";
        case 13:
            return "VK_DRIVER_ID_MESA_LLVMPIPE";
        case 14:
            return "VK_DRIVER_ID_MOLTENVK";
        case 15:
            return "VK_DRIVER_ID_COREAVI_PROPRIETARY";
        case 16:
            return "VK_DRIVER_ID_JUICE_PROPRIETARY";
        case 17:
            return "VK_DRIVER_ID_VERISILICON_PROPRIETARY";
        case 18:
            return "VK_DRIVER_ID_MESA_TURNIP";
        case 19:
            return "VK_DRIVER_ID_MESA_V3DV";
        case 20:
            return "VK_DRIVER_ID_MESA_PANVK";
        case 21:
            return "VK_DRIVER_ID_SAMSUNG_PROPRIETARY";
        case 22:
            return "VK_DRIVER_ID_MESA_VENUS";
        case 23:
            return "VK_DRIVER_ID_MESA_DOZEN";
        case 24:
            return "VK_DRIVER_ID_MESA_NVK";
        case 25:
            return "VK_DRIVER_ID_IMAGINATION_OPEN_SOURCE_MESA";
        case 26:
            return "VK_DRIVER_ID_MESA_HONEYKRISP";
        default:
            return "unknown";
        }
    };

    auto print_size = [](uint64_t bytes) -> std::string {
        static const char *units[] = {"B", "KB", "MB", "GB", "TB", "PB"};
        int unit_index = 0;
        double size = static_cast<double>(bytes);
        while (size >= 1024.0 && unit_index < 5) {
            size /= 1024.0;
            unit_index += 1;
        }
        std::ostringstream oss;
        oss << std::fixed << std::setprecision(size < 10 ? 2 : 1) << size << " "
            << units[unit_index];
        return oss.str();
    };

    auto print_heap_flags = [](VkMemoryHeapFlags flags) -> std::string {
        std::ostringstream oss;
        auto add = [&](const char *name) {
            if (oss.tellp() > 0)
                oss << "|";
            oss << name;
        };
        if (flags & VK_MEMORY_HEAP_DEVICE_LOCAL_BIT)
            add("DEVICE_LOCAL");
        if (flags & 0x00000002)
            add("MULTI_INSTANCE");
        if (flags & 0x00000008)
            add("TILE_MEMORY");
        if (oss.tellp() == 0) {
            oss << "*system memory*";
        }
        return oss.str();
    };

    auto print_type_flags = [](VkMemoryPropertyFlags flags) -> std::string {
        std::ostringstream oss;
        auto add = [&](const char *name) {
            if (oss.tellp() > 0)
                oss << "|";
            oss << name;
        };
        if (flags & VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT)
            add("DEVICE_LOCAL");
        if (flags & VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT)
            add("HOST_VISIBLE");
        if (flags & VK_MEMORY_PROPERTY_HOST_COHERENT_BIT)
            add("HOST_COHERENT");
        if (flags & VK_MEMORY_PROPERTY_HOST_CACHED_BIT)
            add("HOST_CACHED");
        if (flags & 0x00000010)
            add("LAZY_ALLOC");
        if (flags & 0x00000020)
            add("PROTECTED");
        if (flags & 0x00000040)
            add("DEVICE_COHERENT");
        if (flags & 0x00000080)
            add("DEVICE_UNCACHED");
        if (flags & 0x00000100)
            add("RDMA");
        return oss.str();
    };

    auto print_mem_heaps = [&]() -> nlohmann::json {
        nlohmann::json array = nlohmann::json::array();

        for (uint32_t i = 0; i < memory.memoryHeapCount; i++) {
            nlohmann::json types = nlohmann::json::object();
            for (uint32_t j = 0; j < memory.memoryTypeCount; j++) {
                if (memory.memoryTypes[j].heapIndex == i) {
                    types["type index " + std::to_string(j)] =
                        print_type_flags(memory.memoryTypes[j].propertyFlags);
                }
            }
            nlohmann::json item = {
                {"index", i},
                {"size", print_size(memory.memoryHeaps[i].size)},
                {"flags", print_heap_flags(memory.memoryHeaps[i].flags)},
                {"types", types}};
            array.push_back(item);
        }

        return array;
    };

    nlohmann::json object = {
        {"index", index},
        {"name", properties.deviceName},
        {"type", type},
        {"PCI bus id", pci_bus_id},
        {"vulkan version", print_version(properties.apiVersion)},
        {"vendor id", vendorID},
        {"device id", print_hex(properties.deviceID) + " (" +
                          std::to_string(properties.deviceID) + ")"},
        {"driver id", print_driver_id()},
        {"driver name", driver.driverName},
        {"driver info", driver.driverInfo},
        {"memory heaps", print_mem_heaps()}};

    return object;
}