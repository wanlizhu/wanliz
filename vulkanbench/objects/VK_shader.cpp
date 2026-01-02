#include "VK_shader.h"
#include "VK_device.h"

#ifdef ENABLE_RT_SHADER_COMPILE
bool VK_shader::init_from_glsl_string(
    VK_device* dev_ptr,
    const std::string& glsl, 
    VkShaderStageFlagBits stage, 
    const std::map<std::string, std::string>& macros
) {
    if (dev_ptr == nullptr) {
        throw std::runtime_error("Device pointer is null");
    }

    device_ptr = dev_ptr;
    glsl_code = glsl;
    shaderc_shader_kind kind;
    stageFlags = stage;
    
    switch (stage) {
        case VK_SHADER_STAGE_VERTEX_BIT:
            kind = shaderc_glsl_vertex_shader;
            break;
        case VK_SHADER_STAGE_FRAGMENT_BIT:
            kind = shaderc_glsl_fragment_shader;
            break;
        case VK_SHADER_STAGE_COMPUTE_BIT:
            kind = shaderc_glsl_compute_shader;
            break;
        case VK_SHADER_STAGE_GEOMETRY_BIT:
            kind = shaderc_glsl_geometry_shader;
            break;
        case VK_SHADER_STAGE_TESSELLATION_CONTROL_BIT:
            kind = shaderc_glsl_tess_control_shader;
            break;
        case VK_SHADER_STAGE_TESSELLATION_EVALUATION_BIT:
            kind = shaderc_glsl_tess_evaluation_shader;
            break;
        default:
            throw std::runtime_error("Unsupported shader stage");
    }

    shaderc_compiler_t compiler = shaderc_compiler_initialize();
    if (!compiler) {
        throw std::runtime_error("Failed to initialize shaderc compiler");
    }

    shaderc_compile_options_t options = shaderc_compile_options_initialize();
    shaderc_compile_options_set_optimization_level(options, shaderc_optimization_level_performance);
    shaderc_compile_options_set_target_env(options, shaderc_target_env_vulkan, shaderc_env_version_vulkan_1_3);
    
    for (const auto& [name, value] : macros) {
        shaderc_compile_options_add_macro_definition(
            options, name.c_str(), name.length(), 
            value.c_str(), value.length()
        );
    }

    shaderc_compilation_result_t result = shaderc_compile_into_spv(
        compiler, glsl.c_str(), glsl.size(), kind, "shader", "main", options);

    if (shaderc_result_get_compilation_status(result) != shaderc_compilation_status_success) {
        std::string errorMsg = shaderc_result_get_error_message(result);
        throw std::runtime_error("Shader compilation failed: " + errorMsg);
    }

    const uint32_t* spirv_data = reinterpret_cast<const uint32_t*>(shaderc_result_get_bytes(result));
    size_t spirv_size = shaderc_result_get_length(result) / sizeof(uint32_t);
    spirv_code = std::vector<uint32_t>(spirv_data, spirv_data + spirv_size);

    shaderc_result_release(result);
    shaderc_compile_options_release(options);
    shaderc_compiler_release(compiler);

    VkShaderModuleCreateInfo createInfo = {};
    createInfo.sType = VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO;
    createInfo.codeSize = spirv_code.size() * sizeof(uint32_t);
    createInfo.pCode = spirv_code.data();

    VkResult vkResult = vkCreateShaderModule(device_ptr->handle, &createInfo, nullptr, &handle);
    if (vkResult != VK_SUCCESS) {
        throw std::runtime_error("Failed to create shader module");
    }

    return true;
}

bool VK_shader::init_from_glsl_file(
    VK_device* dev_ptr,
    const std::filesystem::path& path,
    VkShaderStageFlagBits stage, 
    const std::map<std::string, std::string>& macros
) {
    if (dev_ptr == nullptr) {
        throw std::runtime_error("Device pointer is null");
    }

    std::ifstream file(path);
    if (!file.is_open()) {
        throw std::runtime_error("Failed to open shader file: " + path.string());
    }

    std::stringstream buffer;
    buffer << file.rdbuf();
    file.close();

    return init_from_glsl_string(dev_ptr, buffer.str(), stage, macros);
}

void VK_shader::deinit() {
    if (device_ptr != nullptr && handle != VK_NULL_HANDLE) {
        vkDestroyShaderModule(device_ptr->handle, handle, nullptr);
        handle = VK_NULL_HANDLE;
    }
    spirv_code.clear();
    glsl_code.clear();
    device_ptr = nullptr;
}

std::vector<std::string> VK_shader::reflect_all_variables() const {
    std::vector<std::string> variable_names;
    
    if (spirv_code.empty()) {
        return variable_names;
    }

    spvc_context context = nullptr;
    spvc_parsed_ir ir = nullptr;
    spvc_compiler compiler = nullptr;
    spvc_resources resources = nullptr;

    if (spvc_context_create(&context) != SPVC_SUCCESS) {
        return variable_names;
    }

    if (spvc_context_parse_spirv(context, spirv_code.data(), spirv_code.size(), &ir) != SPVC_SUCCESS) {
        spvc_context_destroy(context);
        return variable_names;
    }

    if (spvc_context_create_compiler(context, SPVC_BACKEND_NONE, ir, SPVC_CAPTURE_MODE_TAKE_OWNERSHIP, &compiler) != SPVC_SUCCESS) {
        spvc_context_destroy(context);
        return variable_names;
    }

    if (spvc_compiler_create_shader_resources(compiler, &resources) != SPVC_SUCCESS) {
        spvc_context_destroy(context);
        return variable_names;
    }

    const spvc_reflected_resource* resource_list = nullptr;
    size_t resource_count = 0;

    spvc_resources_get_resource_list_for_type(resources, SPVC_RESOURCE_TYPE_UNIFORM_BUFFER, &resource_list, &resource_count);
    for (size_t i = 0; i < resource_count; i++) {
        if (resource_list[i].name) {
            variable_names.push_back(resource_list[i].name);
        }
    }

    spvc_resources_get_resource_list_for_type(resources, SPVC_RESOURCE_TYPE_STORAGE_BUFFER, &resource_list, &resource_count);
    for (size_t i = 0; i < resource_count; i++) {
        if (resource_list[i].name) {
            variable_names.push_back(resource_list[i].name);
        }
    }

    spvc_resources_get_resource_list_for_type(resources, SPVC_RESOURCE_TYPE_SAMPLED_IMAGE, &resource_list, &resource_count);
    for (size_t i = 0; i < resource_count; i++) {
        if (resource_list[i].name) {
            variable_names.push_back(resource_list[i].name);
        }
    }

    spvc_resources_get_resource_list_for_type(resources, SPVC_RESOURCE_TYPE_STORAGE_IMAGE, &resource_list, &resource_count);
    for (size_t i = 0; i < resource_count; i++) {
        if (resource_list[i].name) {
            variable_names.push_back(resource_list[i].name);
        }
    }

    spvc_resources_get_resource_list_for_type(resources, SPVC_RESOURCE_TYPE_SEPARATE_IMAGE, &resource_list, &resource_count);
    for (size_t i = 0; i < resource_count; i++) {
        if (resource_list[i].name) {
            variable_names.push_back(resource_list[i].name);
        }
    }

    spvc_resources_get_resource_list_for_type(resources, SPVC_RESOURCE_TYPE_SEPARATE_SAMPLERS, &resource_list, &resource_count);
    for (size_t i = 0; i < resource_count; i++) {
        if (resource_list[i].name) {
            variable_names.push_back(resource_list[i].name);
        }
    }

    spvc_context_destroy(context);
    return variable_names;
}

std::optional<VkDescriptorSetLayoutBinding> VK_shader::reflect_binding_with_name(const std::string& name) const {
    if (spirv_code.empty()) {
        return std::nullopt;
    }

    spvc_context context = nullptr;
    spvc_parsed_ir ir = nullptr;
    spvc_compiler compiler = nullptr;
    spvc_resources resources = nullptr;

    if (spvc_context_create(&context) != SPVC_SUCCESS) {
        return std::nullopt;
    }

    if (spvc_context_parse_spirv(context, spirv_code.data(), spirv_code.size(), &ir) != SPVC_SUCCESS) {
        spvc_context_destroy(context);
        return std::nullopt;
    }

    if (spvc_context_create_compiler(context, SPVC_BACKEND_NONE, ir, SPVC_CAPTURE_MODE_TAKE_OWNERSHIP, &compiler) != SPVC_SUCCESS) {
        spvc_context_destroy(context);
        return std::nullopt;
    }

    if (spvc_compiler_create_shader_resources(compiler, &resources) != SPVC_SUCCESS) {
        spvc_context_destroy(context);
        return std::nullopt;
    }

    const spvc_reflected_resource* resource_list = nullptr;
    size_t resource_count = 0;

    spvc_resources_get_resource_list_for_type(resources, SPVC_RESOURCE_TYPE_UNIFORM_BUFFER, &resource_list, &resource_count);
    for (size_t i = 0; i < resource_count; i++) {
        const char* resource_name = resource_list[i].name;
        if (resource_name && name == resource_name) {
            VkDescriptorSetLayoutBinding binding = {};
            binding.binding = spvc_compiler_get_decoration(compiler, resource_list[i].id, SpvDecorationBinding);
            binding.descriptorType = VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER;
            binding.descriptorCount = 1;
            binding.stageFlags = stageFlags;
            binding.pImmutableSamplers = nullptr;
            
            spvc_context_destroy(context);
            return binding;
        }
    }

    spvc_resources_get_resource_list_for_type(resources, SPVC_RESOURCE_TYPE_STORAGE_BUFFER, &resource_list, &resource_count);
    for (size_t i = 0; i < resource_count; i++) {
        const char* resource_name = resource_list[i].name;
        if (resource_name && name == resource_name) {
            VkDescriptorSetLayoutBinding binding = {};
            binding.binding = spvc_compiler_get_decoration(compiler, resource_list[i].id, SpvDecorationBinding);
            binding.descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER;
            binding.descriptorCount = 1;
            binding.stageFlags = stageFlags;
            binding.pImmutableSamplers = nullptr;
            
            spvc_context_destroy(context);
            return binding;
        }
    }

    spvc_resources_get_resource_list_for_type(resources, SPVC_RESOURCE_TYPE_SAMPLED_IMAGE, &resource_list, &resource_count);
    for (size_t i = 0; i < resource_count; i++) {
        const char* resource_name = resource_list[i].name;
        if (resource_name && name == resource_name) {
            VkDescriptorSetLayoutBinding binding = {};
            binding.binding = spvc_compiler_get_decoration(compiler, resource_list[i].id, SpvDecorationBinding);
            binding.descriptorType = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER;
            binding.descriptorCount = 1;
            binding.stageFlags = stageFlags;
            binding.pImmutableSamplers = nullptr;
            
            spvc_context_destroy(context);
            return binding;
        }
    }

    spvc_resources_get_resource_list_for_type(resources, SPVC_RESOURCE_TYPE_STORAGE_IMAGE, &resource_list, &resource_count);
    for (size_t i = 0; i < resource_count; i++) {
        const char* resource_name = resource_list[i].name;
        if (resource_name && name == resource_name) {
            VkDescriptorSetLayoutBinding binding = {};
            binding.binding = spvc_compiler_get_decoration(compiler, resource_list[i].id, SpvDecorationBinding);
            binding.descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_IMAGE;
            binding.descriptorCount = 1;
            binding.stageFlags = stageFlags;
            binding.pImmutableSamplers = nullptr;
            
            spvc_context_destroy(context);
            return binding;
        }
    }

    spvc_resources_get_resource_list_for_type(resources, SPVC_RESOURCE_TYPE_SEPARATE_IMAGE, &resource_list, &resource_count);
    for (size_t i = 0; i < resource_count; i++) {
        const char* resource_name = resource_list[i].name;
        if (resource_name && name == resource_name) {
            VkDescriptorSetLayoutBinding binding = {};
            binding.binding = spvc_compiler_get_decoration(compiler, resource_list[i].id, SpvDecorationBinding);
            binding.descriptorType = VK_DESCRIPTOR_TYPE_SAMPLED_IMAGE;
            binding.descriptorCount = 1;
            binding.stageFlags = stageFlags;
            binding.pImmutableSamplers = nullptr;
            
            spvc_context_destroy(context);
            return binding;
        }
    }

    spvc_resources_get_resource_list_for_type(resources, SPVC_RESOURCE_TYPE_SEPARATE_SAMPLERS, &resource_list, &resource_count);
    for (size_t i = 0; i < resource_count; i++) {
        const char* resource_name = resource_list[i].name;
        if (resource_name && name == resource_name) {
            VkDescriptorSetLayoutBinding binding = {};
            binding.binding = spvc_compiler_get_decoration(compiler, resource_list[i].id, SpvDecorationBinding);
            binding.descriptorType = VK_DESCRIPTOR_TYPE_SAMPLER;
            binding.descriptorCount = 1;
            binding.stageFlags = stageFlags;
            binding.pImmutableSamplers = nullptr;
            
            spvc_context_destroy(context);
            return binding;
        }
    }

    spvc_context_destroy(context);
    return std::nullopt;
}
#endif // #ifdef ENABLE_RT_SHADER_COMPILE