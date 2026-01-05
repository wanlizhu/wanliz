#include "VK_TestCase.h"
#include "objects/VK_common.h"


int main(int argc, char **argv) {
    cxxopts::Options options("vulkanbench", "Vulkan benchmark app for Linux and Windows platforms");
    options.add_options("global options")
        ("n,nodisplay", "Run in offscreen mode", cxxopts::value<bool>()->default_value("false"))
        ("p,profile", "Run for PI profiling (=buf, =img)", cxxopts::value<std::string>())
        ("d,device", "GPU device index to use", cxxopts::value<int>()->default_value("-1"))
        ("b,pushbuffer-dump", "Make a pushbuffer dump (for develop/debug driver)", cxxopts::value<bool>()->default_value("false"));
    VK_config::args = options.parse(argc, argv);

    if (VK_config::args["pushbuffer-dump"].as<bool>()) {
        // 0x00000001 ENABLE — enable pushbuffer dumping
        // 0x00000002 PER_FRAME_LOGFILE — new dump file for every frame
        // 0x00000080 ENTRY_POINT_ANNOTATIONS — include API entrypoint annotations
        // 0x00000100 APP_REGIME_ANNOTATIONS — include app regime annotations
        // 0x00010000 INSTRUMENT_SHADER_OBJECTS — insert NOP(appHash, ucodeHash)
        std::string filename = "/pushbuffer-dump-%03d.xml";
        setenv("__GL_ac12fedf", filename.c_str(), 1);
        setenv("__GL_ac12fede", "0x10183", 1);
        printf("__GL_ac12fedf=%s\n", std::getenv("__GL_ac12fedf"));
        printf("__GL_ac12fede=%s\n", std::getenv("__GL_ac12fede"));
    }

    VK_device device;
    device.init(VK_config::args["device"].as<int>(), VK_QUEUE_TRANSFER_BIT, 0, 0);

    VK_TestCase_buffercopy test_b2b;
    VK_TestCase_imagebuffercopy test_i2b;

    test_b2b.run(device, "Test case: buffer(device_local) -> staging buffer(...)");
    test_i2b.run(device, "Test case:  image(device_local) -> staging buffer(...)");

    device.deinit();
    return 0;
}