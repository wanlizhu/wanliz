#include "VK_physdev.h"

const char* realpath(const char* name) {
    std::string cmdline = "which " + name + " 2>/dev/null";
    FILE* pipe = popen(cmdline.c_str(), "r");
    if (pipe) {
        static char buf[4096] = {};
        memset(buf, 0, sizeof(buf));
        int n = fgets(buf, sizeof(buf), pipe);
        if (buf[n - 1] == '\n') {
            buf[n - 1] = '\0';
        }
        pclose(pipe);
        return buf;
    }
    return name;
}

int main(int argc, char **argv) {
    std::cout << VK_physdev::INFO() << std::endl;
#ifdef __linux__
    if (argc > 1) {
        pid_t childProc = fork();
        if (childProc == 0) { // Inside child process
            setenv("VK_INSTANCE_LAYERS", "VK_LAYER_inspect_gpu_perf_info", 1);
            execv(realpath(argv[1]), argv + 1);
        } else if (childProc > 0) { // Inside parent process
            waitpid(childProc, NULL, 0);
        }
    }
#endif

    return 0;
}