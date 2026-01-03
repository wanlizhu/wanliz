#pragma once
#include "VK_common.h"
#include "VK_image.h"

struct VK_sc_backingstore {
    uint32_t index = UINT32_MAX;
    VkImage image = NULL;
    VkImageView imageView_color0 = NULL;
    VkImageView imageView_depthstencil = NULL;
    VkFramebuffer framebuffer = NULL;
};

struct VK_swapchain {
#ifdef _WIN32
    void* win32_hwnd = nullptr;
#elif defined(__linux__)
    void* x11_display = nullptr;
    unsigned long x11_window = 0;
#endif
    bool window_visible = false;

    VK_device* device_ptr = nullptr;
    VkSwapchainKHR handle = NULL;
    VkSurfaceKHR surface = NULL;
    VkRenderPass defaultRenderPass = NULL;
    VK_image depthstencilImage;
    std::vector<VK_sc_backingstore> backingstores;
    
    VkFormat swapchainFormat = VK_FORMAT_UNDEFINED;
    VkFormat depthstencilFormat = VK_FORMAT_UNDEFINED;
    VkExtent2D swapchainExtent = {};
    VkFence imageAvailableFence = NULL;
    uint32_t currentImageIndex = UINT32_MAX;

    inline operator VkSwapchainKHR() const { return handle; }
    void init(VK_device* device_ptr, int window_width, int window_height);
    void deinit();

    void on_window_visible();
    void on_window_closed();
    void on_window_resized();
    void acquire_next_image();
    void present();
    
private:
    bool create_window();
    bool create_surface();
    bool create_swapchain();
    bool create_backingstores();
    void delete_swapchain_resources();
};