#include "VK_physdev.h"

int main(int argc, char **argv) {
    std::cout << VK_physdev::INFO() << std::endl;
#ifdef __linux__
    if (argc > 1) {
        pid_t childProc = fork();
        if (childProc == 0) { // Inside child process
            setenv("VK_INSTANCE_LAYERS", "VK_LAYER_inspect_gpu_perf_info", 1);
            
        } else if (childProc > 0) { // Inside parent process
            // TODO: communicate with child proc
        }
    }
#endif 

    return 0;
}