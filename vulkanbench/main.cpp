#include "VK_TestCase.h"

int main(int argc, char **argv) {
    VK_device device;
    if (!device.init(-1, VK_QUEUE_TRANSFER_BIT, 0, 0)) {
        throw std::runtime_error("Failed to init logical device");
    }

    VK_TestCase_buffercopy test_b2b;
    VK_TestCase_imagebuffercopy test_i2b;

    test_b2b.run(device, "Test case: buffer(device_local) -> staging buffer(...)");
    test_i2b.run(device, "Test case:  image(device_local) -> staging buffer(...)");

    device.deinit();
    return 0;
}