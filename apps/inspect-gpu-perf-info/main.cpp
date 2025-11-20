#include "VK_physdev.h"

int main(int argc, char **argv) {
    std::cout << VK_physdev::INFO() << std::endl;
#ifdef __linux__
    if (argc > 1) {
        pid_t childProc = fork();
        if (childProc == 0) { // Inside child process
            
        } else if (childProc > 0) { // Inside parent process
            // TODO: communicate with child proc
        }
    }
#endif 

    return 0;
}