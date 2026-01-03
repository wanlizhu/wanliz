#include "VK_TestCase.h"
#include "objects/VK_common.h"

int main(int argc, char **argv) {
    if (argc == 2 && str_starts_with(argv[1], "-pi=")) {
        VK_config::pi_capture_mode = str_after_rchar(argv[1], '=');
    }

    VK_device device;
    device.init(-1, VK_QUEUE_TRANSFER_BIT, 0, 0);

    VK_TestCase_buffercopy test_b2b;
    VK_TestCase_imagebuffercopy test_i2b;

    test_b2b.run(device, "Test case: buffer(device_local) -> staging buffer(...)");
    test_i2b.run(device, "Test case:  image(device_local) -> staging buffer(...)");

    device.deinit();
    return 0;
}