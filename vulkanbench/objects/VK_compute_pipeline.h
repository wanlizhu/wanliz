#pragma once
#include "VK_common.h"
#include "VK_shader.h"

struct VK_compute_pipeline {
    VK_device* device_ptr = nullptr;
    VkPipeline handle = NULL;
    VkPipelineLayout layout = NULL;
    VkDescriptorPool descPool = NULL;
    VkDescriptorSet descSet = NULL;
    VkDescriptorSetLayout descSetLayout = NULL;
    std::map<std::string, VkDescriptorSetLayoutBinding> bindingMap;

    inline operator VkPipeline() const { return handle; }
    bool init(
        VK_device* device_ptr, 
        const VK_shader& shader
    );
    void deinit();
};