#include "VK_physdev.h"
#include "VkLayer_gpu_perf_inspector/VkLayer_common.h"

int main(int argc, char **argv) {
    std::cout << VK_physdev::INFO() << std::endl;
#ifdef __linux__
    if (argc > 1) {
        setenv("VK_INSTANCE_LAYERS", "VK_LAYER_gpu_perf_inspector", 1);
        if (getenv("DISPLAY") == NULL) {
            setenv("DISPLAY", ":0", 1);
            std::cout << "Fallback to DISPLAY=:0" << std::endl;
        }
        if (getenv("ENABLE_RMLOG")) {
            setenv("__GL_DEBUG_MASK", "RM", 1);
            setenv("__GL_DEBUG_LEVEL", "30", 1);
        }
        
        execv(realpath(argv[1]), argv + 1);
    }
#endif

    return 0;
}