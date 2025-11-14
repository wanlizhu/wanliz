#include "VK_physdev.h"
#include "argparse.h"

int main(int argc, char** argv) {
    /*argparse::ArgumentParser program("inspect-gpu-perf-gaps");
    program.add_argument("subcmd").help("sub-command: <info>");
    
    try {
        program.parse_args(argc, argv);
    } catch (const std::runtime_error& e) {
        std::cerr << e.what() << "\n";
        std::cerr << program;
        return 1;
    }

    auto subcmd = program.get<std::string>("subcmd");
    if (subcmd == "info") {
        std::cout << VK_physdev::INFO() << std::endl;
    }*/
    std::cout << VK_physdev::INFO() << std::endl;

    return 0;
}