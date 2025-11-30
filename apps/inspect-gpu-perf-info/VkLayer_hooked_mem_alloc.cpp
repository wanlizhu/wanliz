#include "VkLayer_hooked_mem_alloc.h"

VKAPI_ATTR VkResult VKAPI_CALL hooked_vkAllocateMemory(
    VkDevice device,
    const VkMemoryAllocateInfo* pAllocateInfo,
    const VkAllocationCallbacks* pAllocator,
    VkDeviceMemory* pMemory
) {
    VK_DEFINE_ORIGINAL_FUNC(vkAllocateMemory);

    static int index = 0;
    static int enableRMLog = -1;
    static int enableGPUPagesDump = -1;
    static int enableGNUPerfRecord = -1;
    if (enableRMLog == -1) {
        enableRMLog = (getenv("ENABLE_RMLOG") && getenv("ENABLE_RMLOG")[0] == '1') ? 1 : 0;
    }
    if (enableGPUPagesDump == -1) {
        enableGPUPagesDump = (getenv("ENABLE_GPU_PAGES_DUMP") && getenv("ENABLE_GPU_PAGES_DUMP")[0] == '1') ? 1 : 0;
        if (enableGPUPagesDump == 1) {
            bool foundTools = VkLayer_which("inspect-gpu-page-tables") && VkLayer_which("merge-gpu-pages.sh");
#ifdef __aarch64__
            foundTools = foundTools && std::filesystem::exists("/dev/nvidia-soc-iommu-inspect");
#endif 
            enableGPUPagesDump = foundTools ? 1 : 0;
        }
    }
    if (enableGNUPerfRecord == -1) {
        enableGNUPerfRecord = (getenv("ENABLE_GNU_PERF_RECORD") && getenv("ENABLE_GNU_PERF_RECORD")[0] == '1') ? 1 : 0;
    }

    std::chrono::high_resolution_clock::time_point begin;
    VkLayer_GNU_Linux_perf perf;
    if (enableRMLog == 1 || enableGPUPagesDump == 1 || enableGNUPerfRecord == 1) {
        index += 1;
        fprintf(stderr, "vkAllocateMemory BEGIN INDEX=%d\n", index);
        if (enableGPUPagesDump == 1) {
            system("sudo rm -rf /tmp/pages.begin /tmp/pages.end /tmp/pages.new /tmp/pages.new.merged");
            system("sudo inspect-gpu-page-tables >/tmp/pages.begin 2>&1");
        }
        if (enableGNUPerfRecord == 1) {
            perf.record();
        }
        begin = std::chrono::high_resolution_clock::now();
    }
    
    VkResult result = original_pfn_vkAllocateMemory(device, pAllocateInfo, pAllocator, pMemory);
    
    if (enableRMLog == 1 || enableGPUPagesDump == 1 || enableGNUPerfRecord == 1) {
        auto end = std::chrono::high_resolution_clock::now();
        auto duration = std::chrono::duration_cast<std::chrono::nanoseconds>(end - begin);
        if (enableGNUPerfRecord == 1) {
            perf.end(std::string("-vkAllocateMemory-") + std::to_string(index));
        }

        char* new_pages = nullptr;
        if (enableGPUPagesDump == 1) {
            system("sudo inspect-gpu-page-tables >/tmp/pages.end 2>&1");
            system("diff --old-line-format='' --new-line-format='%L' --unchanged-line-format='' /tmp/pages.begin /tmp/pages.end >/tmp/pages.new");
            system("merge-gpu-pages.sh /tmp/pages.new >/tmp/pages.new.merged");
            new_pages = VkLayer_readbuf("/tmp/pages.new.merged", true);
            for (int i = 0; new_pages && i < strlen(new_pages); i++) 
                if (new_pages[i] == '\n') 
                    new_pages[i] = '\t';
        }

        fprintf(stderr, "vkAllocateMemory ENDED AFTER %08ld NS => NewPages: [%s] => GNUPerf: %s\n", duration.count(), new_pages ? new_pages : "", perf.output.c_str());
        fprintf(stdout, "vkAllocateMemory ENDED AFTER %08ld NS => NewPages: [%s] => GNUPerf: %s\n", duration.count(), new_pages ? new_pages : "", perf.output.c_str());
    }

    return result;
}

VKAPI_ATTR void VKAPI_CALL hooked_vkFreeMemory(
    VkDevice device,
    VkDeviceMemory memory,
    const VkAllocationCallbacks* pAllocator
) {
    VK_DEFINE_ORIGINAL_FUNC(vkFreeMemory);
    original_pfn_vkFreeMemory(device, memory, pAllocator);
}

uint64_t GPU_VirtualAddress(VkDevice device, VkDeviceMemory memory, size_t size) {
    if (!VkLayer_DeviceAddressFeature::enabled) {
        return 0;
    }

    VkBufferCreateInfo bufferCreateInfo = {};
    bufferCreateInfo.sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO;
    bufferCreateInfo.size = size;
    bufferCreateInfo.usage = VK_BUFFER_USAGE_SHADER_DEVICE_ADDRESS_BIT | VK_BUFFER_USAGE_STORAGE_BUFFER_BIT;
    bufferCreateInfo.sharingMode = VK_SHARING_MODE_EXCLUSIVE;

    VkBuffer buffer = VK_NULL_HANDLE;
    if (vkCreateBuffer(device, &bufferCreateInfo, NULL, &buffer) != VK_SUCCESS) {
        return 0;
    }

    if (vkBindBufferMemory(device, buffer, memory, 0) != VK_SUCCESS) {
        vkDestroyBuffer(device, buffer, NULL);
        return 0;
    }

    VkBufferDeviceAddressInfo addressInfo = {};
    addressInfo.sType = VK_STRUCTURE_TYPE_BUFFER_DEVICE_ADDRESS_INFO;
    addressInfo.buffer = buffer;
    uint64_t address = (uint64_t)vkGetBufferDeviceAddress(device, &addressInfo);
    vkDestroyBuffer(device, buffer, NULL);

    return address;
}
