#include "VkLayer_hooked_mem_alloc.h"

VKAPI_ATTR VkResult VKAPI_CALL HKed_vkAllocateMemory(
    VkDevice device,
    const VkMemoryAllocateInfo* pAllocateInfo,
    const VkAllocationCallbacks* pAllocator,
    VkDeviceMemory* pMemory
) {
    VK_DEFINE_ORIGINAL_FUNC(vkAllocateMemory);

    static int index = 0;
    static int debugMemAlloc = -1;
    static bool foundGPUPagesTool = false;
    if (debugMemAlloc == -1) {
        debugMemAlloc = (getenv("DEBUG_MEM_ALLOC") && getenv("DEBUG_MEM_ALLOC")[0] == '1') ? 1 : 0;
        if (debugMemAlloc) {
        foundGPUPagesTool = VkLayer_which("inspect-gpu-page-tables") && VkLayer_which("merge-gpu-pages.sh");
#ifdef __aarch64__
        foundGPUPagesTool = foundGPUPagesTool && std::filesystem::exists("/dev/nvidia-soc-iommu-inspect");
#endif 
        }
    }

    std::chrono::high_resolution_clock::time_point begin;
    VkLayer_GNU_Linux_perf perf;
    if (debugMemAlloc == 1) {
        index += 1;
        fprintf(stderr, "vkAllocateMemory BEGIN INDEX=%d\n", index);
        if (foundGPUPagesTool) {
            system("sudo rm -rf /tmp/pages.begin /tmp/pages.end /tmp/pages.new /tmp/pages.new.merged");
            system("sudo inspect-gpu-page-tables >/tmp/pages.begin 2>&1");
        }

        perf.record();
        begin = std::chrono::high_resolution_clock::now();
    }
    
    VkResult result = original_pfn_vkAllocateMemory(device, pAllocateInfo, pAllocator, pMemory);
    
    if (debugMemAlloc == 1) {
        auto end = std::chrono::high_resolution_clock::now();
        auto duration = std::chrono::duration_cast<std::chrono::nanoseconds>(end - begin);
        perf.end(std::string("-vkAllocateMemory-") + std::to_string(index));

        char* new_pages = nullptr;
        if (foundGPUPagesTool) {
            system("sudo inspect-gpu-page-tables >/tmp/pages.end 2>&1");
            system("diff --old-line-format='' --new-line-format='%L' --unchanged-line-format='' /tmp/pages.begin /tmp/pages.end >/tmp/pages.new");
            system("merge-gpu-pages.sh /tmp/pages.new >/tmp/pages.new.merged");
            new_pages = VkLayer_readbuf("/tmp/pages.new.merged", true);
        }
        for (int i = 0; i < strlen(new_pages); i++) if (new_pages[i] == '\n') new_pages[i] = '\t';
        fprintf(stderr, "vkAllocateMemory ENDED AFTER %08ld NS => [%s] => %s\n", duration.count(), new_pages ? new_pages : "", perf.output.c_str());
        fprintf(stdout, "vkAllocateMemory ENDED AFTER %08ld NS => [%s] => %s\n", duration.count(), new_pages ? new_pages : "", perf.output.c_str());
    }

    return result;
}

VKAPI_ATTR void VKAPI_CALL HKed_vkFreeMemory(
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
