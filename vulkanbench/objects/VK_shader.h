#pragma once
#include "VK_common.h"

struct VK_shader {
    VK_device* device_ptr = nullptr;
    VkShaderModule handle = NULL;
    VkShaderStageFlags stageFlags = 0;
    std::vector<uint32_t> spirv_code;
    std::string glsl_code;
    
    inline operator VkShaderModule() const { return handle; }
    bool init_from_glsl_file(
        VK_device* device_ptr,
        const std::filesystem::path& path,
        VkShaderStageFlagBits stage, 
        const std::map<std::string, std::string>& macros
    );
    bool init_from_glsl_string(
        VK_device* device_ptr,
        const std::string& glsl, 
        VkShaderStageFlagBits stage, 
        const std::map<std::string, std::string>& macros
    );
    void deinit();
    std::vector<std::string> reflect_all_variables() const;
    std::optional<VkDescriptorSetLayoutBinding> reflect_binding_with_name(const std::string& name) const;
};