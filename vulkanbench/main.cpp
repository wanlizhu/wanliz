#include "VK_TestCase.h"
#include "objects/VK_common.h"


int main(int argc, char **argv) {
    cxxopts::Options options("vulkanbench", "Vulkan benchmark app for Linux and Windows platforms");
    options.add_options("global options")
        ("testcase", "Test case name to run", cxxopts::value<std::string>()->default_value("memcopy"))
        ("n,nodisplay", "Run in offscreen mode", cxxopts::value<bool>()->default_value("false"))
        ("p,profile", "Run for PI profiling", cxxopts::value<bool>()->default_value("false"))
        ("d,device", "GPU device index to use", cxxopts::value<int>()->default_value("-1"))
        ("g,group-size", "Size of src/dst buffer/image group", cxxopts::value<int>()->default_value("100"))
        ("l,loops", "The number of loops to run for average value", cxxopts::value<int>()->default_value("10"));
    VK_config::args = options.parse(argc, argv);

    VK_device device;
    device.init(VK_config::args["device"].as<int>(), VK_QUEUE_TRANSFER_BIT, 0, 0);

    if (VK_config::arg_starts_with("testcase", {"memcopy", "all"})) {
        VK_TestCase_memcopy memcopy(device);
        memcopy.run_subtest(VK_config::arg_substr_after("testcase", ":"));
    }

    device.deinit();
    return 0;
}