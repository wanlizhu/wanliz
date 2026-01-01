#include "VK_compute_pipeline.h"
#include "VK_device.h"

bool VK_compute_pipeline::init(
    VK_device* dev_ptr, 
    const VK_shader& shader
) {
    if (dev_ptr == nullptr || shader.handle == VK_NULL_HANDLE) {
        std::cerr << "Invalid device or shader" << std::endl;
        return false;
    }

    device_ptr = dev_ptr;
    std::vector<std::string> variable_names = shader.reflect_all_variables();
    std::vector<VkDescriptorSetLayoutBinding> bindings;
    bindingMap.clear();
    
    for (const auto& var_name : variable_names) {
        auto binding_opt = shader.reflect_binding_with_name(var_name);
        if (binding_opt) {
            bindings.push_back(*binding_opt);
            bindingMap[var_name] = *binding_opt;
        }
    }

    VkDescriptorSetLayoutCreateInfo descSetLayoutInfo = {};
    descSetLayoutInfo.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO;
    descSetLayoutInfo.bindingCount = static_cast<uint32_t>(bindings.size());
    descSetLayoutInfo.pBindings = bindings.empty() ? nullptr : bindings.data();

    VkResult result = vkCreateDescriptorSetLayout(device_ptr->handle, &descSetLayoutInfo, nullptr, &descSetLayout);
    if (result != VK_SUCCESS) {
        std::cerr << "Failed to create descriptor set layout" << std::endl;
        return false;
    }

    VkPipelineLayoutCreateInfo pipelineLayoutInfo = {};
    pipelineLayoutInfo.sType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO;
    pipelineLayoutInfo.setLayoutCount = descSetLayout != VK_NULL_HANDLE ? 1 : 0;
    pipelineLayoutInfo.pSetLayouts = descSetLayout != VK_NULL_HANDLE ? &descSetLayout : nullptr;
    pipelineLayoutInfo.pushConstantRangeCount = 0;
    pipelineLayoutInfo.pPushConstantRanges = nullptr;

    result = vkCreatePipelineLayout(device_ptr->handle, &pipelineLayoutInfo, nullptr, &layout);
    if (result != VK_SUCCESS) {
        std::cerr << "Failed to create pipeline layout" << std::endl;
        vkDestroyDescriptorSetLayout(device_ptr->handle, descSetLayout, nullptr);
        descSetLayout = VK_NULL_HANDLE;
        return false;
    }

    VkComputePipelineCreateInfo pipelineInfo = {};
    pipelineInfo.sType = VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO;
    pipelineInfo.stage.sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
    pipelineInfo.stage.stage = VK_SHADER_STAGE_COMPUTE_BIT;
    pipelineInfo.stage.module = shader.handle;
    pipelineInfo.stage.pName = "main";
    pipelineInfo.layout = layout;

    result = vkCreateComputePipelines(device_ptr->handle, VK_NULL_HANDLE, 1, &pipelineInfo, nullptr, &handle);
    if (result != VK_SUCCESS) {
        std::cerr << "Failed to create compute pipeline" << std::endl;
        vkDestroyPipelineLayout(device_ptr->handle, layout, nullptr);
        vkDestroyDescriptorSetLayout(device_ptr->handle, descSetLayout, nullptr);
        layout = VK_NULL_HANDLE;
        descSetLayout = VK_NULL_HANDLE;
        return false;
    }

    descPool = VK_NULL_HANDLE;
    descSet = VK_NULL_HANDLE;

    if (!bindings.empty()) {
        std::map<VkDescriptorType, uint32_t> descriptorTypeCounts;
        for (const auto& binding : bindings) {
            descriptorTypeCounts[binding.descriptorType] += binding.descriptorCount;
        }

        std::vector<VkDescriptorPoolSize> poolSizes;
        for (const auto& [type, count] : descriptorTypeCounts) {
            VkDescriptorPoolSize poolSize = {};
            poolSize.type = type;
            poolSize.descriptorCount = count;
            poolSizes.push_back(poolSize);
        }

        VkDescriptorPoolCreateInfo poolInfo = {};
        poolInfo.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO;
        poolInfo.poolSizeCount = static_cast<uint32_t>(poolSizes.size());
        poolInfo.pPoolSizes = poolSizes.data();
        poolInfo.maxSets = 1;

        result = vkCreateDescriptorPool(device_ptr->handle, &poolInfo, nullptr, &descPool);
        if (result != VK_SUCCESS) {
            std::cerr << "Failed to create descriptor pool" << std::endl;
            vkDestroyPipeline(device_ptr->handle, handle, nullptr);
            vkDestroyPipelineLayout(device_ptr->handle, layout, nullptr);
            vkDestroyDescriptorSetLayout(device_ptr->handle, descSetLayout, nullptr);
            handle = VK_NULL_HANDLE;
            layout = VK_NULL_HANDLE;
            descSetLayout = VK_NULL_HANDLE;
            return false;
        }

        VkDescriptorSetAllocateInfo allocInfo = {};
        allocInfo.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO;
        allocInfo.descriptorPool = descPool;
        allocInfo.descriptorSetCount = 1;
        allocInfo.pSetLayouts = &descSetLayout;

        result = vkAllocateDescriptorSets(device_ptr->handle, &allocInfo, &descSet);
        if (result != VK_SUCCESS) {
            std::cerr << "Failed to allocate descriptor set" << std::endl;
            vkDestroyDescriptorPool(device_ptr->handle, descPool, nullptr);
            vkDestroyPipeline(device_ptr->handle, handle, nullptr);
            vkDestroyPipelineLayout(device_ptr->handle, layout, nullptr);
            vkDestroyDescriptorSetLayout(device_ptr->handle, descSetLayout, nullptr);
            descPool = VK_NULL_HANDLE;
            handle = VK_NULL_HANDLE;
            layout = VK_NULL_HANDLE;
            descSetLayout = VK_NULL_HANDLE;
            return false;
        }
    }

    return true;
}

void VK_compute_pipeline::deinit() {
    if (device_ptr != nullptr) {
        if (descPool != VK_NULL_HANDLE) {
            vkDestroyDescriptorPool(device_ptr->handle, descPool, nullptr);
            descPool = VK_NULL_HANDLE;
            descSet = VK_NULL_HANDLE;
        }
        if (handle != VK_NULL_HANDLE) {
            vkDestroyPipeline(device_ptr->handle, handle, nullptr);
            handle = VK_NULL_HANDLE;
        }
        if (layout != VK_NULL_HANDLE) {
            vkDestroyPipelineLayout(device_ptr->handle, layout, nullptr);
            layout = VK_NULL_HANDLE;
        }
        if (descSetLayout != VK_NULL_HANDLE) {
            vkDestroyDescriptorSetLayout(device_ptr->handle, descSetLayout, nullptr);
            descSetLayout = VK_NULL_HANDLE;
        }
    }
    bindingMap.clear();
    device_ptr = nullptr;
}