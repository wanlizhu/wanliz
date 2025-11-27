#include "VkLayer_hooked_mem_alloc.h"

VKAPI_ATTR VkResult VKAPI_CALL HKed_vkAllocateMemory(
    VkDevice device,
    const VkMemoryAllocateInfo* pAllocateInfo,
    const VkAllocationCallbacks* pAllocator,
    VkDeviceMemory* pMemory
) {
    VK_DEFINE_ORIGINAL_FUNC(vkAllocateMemory);

    static int index = 0;
    index += 1;
    auto start = std::chrono::high_resolution_clock::now();
    fprintf(stderr, "vkAllocateMemory START %d\n", index);
    
    VkResult result = original_pfn_vkAllocateMemory(device, pAllocateInfo, pAllocator, pMemory);
    
    auto end = std::chrono::high_resolution_clock::now();
    auto duration = std::chrono::duration_cast<std::chrono::nanoseconds>(end - start);
    uint64_t va = GPU_VirtualAddress(device, *pMemory, pAllocateInfo->allocationSize);
    std::string vaPage = Search_GPU_PageTables(va);
    fprintf(stderr, "vkAllocateMemory ENDED AFTER %lld NS (0x%016" PRIx64 ") [%s]\n", duration.count(), va, vaPage.c_str());

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
    if (!VkLayer_DeviceAddressFeature::enable) {
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

std::string Search_GPU_PageTables(uint64_t va) {
    system("sudo rm -f /tmp/page-tables");
    system("sudo inspect-gpu-page-tables &>/tmp/page-tables");

}