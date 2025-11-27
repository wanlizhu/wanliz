#include "VkLayer_common.h"

PFN_vkGetInstanceProcAddr g_pfn_vkGetInstanceProcAddr = NULL;
PFN_vkGetDeviceProcAddr g_pfn_vkGetDeviceProcAddr = NULL;
std::unordered_map<std::string, PFN_vkVoidFunction> g_hooked_functions;
VkInstance g_VkInstance = NULL;
std::unordered_map<VkDevice, VkPhysicalDevice> g_physicalDeviceMap;

VkLayer_redirect_STDOUT::VkLayer_redirect_STDOUT(const char* pathstr) {
#ifdef __linux__
    std::cout.flush();
    std::fflush(nullptr);
    
    original_stdout = dup(STDOUT_FILENO);
    if (original_stdout < 0) {
        std::cout << "Failed to duplicate stdout" << std::endl;
        return;
    }

    std::filesystem::path path(pathstr);
    if (path.has_parent_path() && !std::filesystem::exists(path.parent_path())) {
        std::filesystem::create_directories(path.parent_path());
    }

    int target_fd = open(pathstr, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (target_fd < 0) {
        std::cout << "Failed to open " << pathstr << std::endl;
        return;
    }

    if (dup2(target_fd, STDOUT_FILENO) < 0) {
        std::cout << "Failed to duplicate stdout to " << pathstr << std::endl;
        close(target_fd);
        close(original_stdout);
        return;
    }

    close(target_fd);
#endif 
}

VkLayer_redirect_STDOUT::~VkLayer_redirect_STDOUT() {
#ifdef __linux__
    if (original_stdout >= 0) {
        dup2(original_stdout, STDOUT_FILENO);
        close(original_stdout);
    }
#endif 
}

VkLayer_redirect_STDERR::VkLayer_redirect_STDERR(const char* pathstr) {
#ifdef __linux__
    std::cerr.flush();
    std::fflush(nullptr);

    original_stderr = dup(STDERR_FILENO);
    if (original_stderr < 0) {
        std::cout << "Failed to duplicate stderr" << std::endl;
        return;
    }

    std::filesystem::path path(pathstr);
    if (path.has_parent_path() && !std::filesystem::exists(path.parent_path())) {
        std::filesystem::create_directories(path.parent_path());
    }

    int target_fd = open(pathstr, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (target_fd < 0) {
        std::cout << "Failed to open " << pathstr << std::endl;
        return;
    }

    if (dup2(target_fd, STDERR_FILENO) < 0) {
        std::cout << "Failed to duplicate stderr to " << pathstr << std::endl;
        close(target_fd);
        close(original_stderr);
        return;
    }

    close(target_fd);
#endif 
}

VkLayer_redirect_STDERR::~VkLayer_redirect_STDERR() {
#ifdef __linux__
    if (original_stderr >= 0) {
        dup2(original_stderr, STDERR_FILENO);
        close(original_stderr);
    }
#endif 
}

void VkLayer_DeviceAddressFeature::add(
    VkPhysicalDevice physicalDevice,
    VkDeviceCreateInfo* pDeviceCreateInfo
) {
    if (!enable) {
        return;
    }

    VkPhysicalDeviceBufferDeviceAddressFeatures requiredFeature;
    requiredFeature.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_BUFFER_DEVICE_ADDRESS_FEATURES;
    requiredFeature.pNext = NULL;
    requiredFeature.bufferDeviceAddress = VK_FALSE;

    VkPhysicalDeviceFeatures2 physicalDeviceFeatures2;
    physicalDeviceFeatures2.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2;
    physicalDeviceFeatures2.pNext = &requiredFeature;
    vkGetPhysicalDeviceFeatures2(physicalDevice, &physicalDeviceFeatures2);

    if (!requiredFeature.bufferDeviceAddress) {
        printf("VkPhysicalDeviceBufferDeviceAddressFeatures ... [SKIPPED]");
        return;
    }

    static VkPhysicalDeviceBufferDeviceAddressFeatures bufferAddressFeature = {};
    bufferAddressFeature.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_BUFFER_DEVICE_ADDRESS_FEATURES;
    bufferAddressFeature.pNext = const_cast<void*>(pDeviceCreateInfo->pNext);
    bufferAddressFeature.bufferDeviceAddress = VK_TRUE;
    pDeviceCreateInfo->pNext = &bufferAddressFeature;

    printf("VkPhysicalDeviceBufferDeviceAddressFeatures ... [ENABLED]");
}