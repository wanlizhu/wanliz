#include "VK_TestCase.h"
#include "objects/VK_common.h"


int main(int argc, char **argv) {
    cxxopts::Options options("vulkanbench", "Vulkan benchmark app for Linux and Windows platforms");
    options.add_options("global options")
        ("p,profile", "Run for PI profiling", cxxopts::value<std::string>())
        ("d,device", "GPU device index to use", cxxopts::value<int>()->default_value("-1"));
    VK_config::args = options.parse(argc, argv);

    VK_device device;
    device.init(VK_config::args["device"].as<int>(), VK_QUEUE_TRANSFER_BIT, 0, 0);

    VK_TestCase_buffercopy test_b2b;
    VK_TestCase_imagebuffercopy test_i2b;

    test_b2b.run(device, "Test case: buffer(device_local) -> staging buffer(...)");
    test_i2b.run(device, "Test case:  image(device_local) -> staging buffer(...)");

    device.deinit();
    return 0;
}