#include "VK_common.h"

#ifdef __linux__
const char* realpath(const char* name) {
    std::string cmdline = std::string("which ")+ name + " 2>/dev/null";
    FILE* pipe = popen(cmdline.c_str(), "r");
    if (pipe) {
        static char buf[4096] = {};
        memset(buf, 0, sizeof(buf));
        int n = strlen(fgets(buf, sizeof(buf), pipe));
        if (n > 0 && buf[n - 1] == '\n') {
            buf[n - 1] = '\0';
        }
        pclose(pipe);
        return buf;
    }
    return name;
}
#else
const char* realpath(const char* name) {
    throw std::runtime_error("NO IMPL");
}
#endif 