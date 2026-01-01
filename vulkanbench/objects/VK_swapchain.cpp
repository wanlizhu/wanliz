#include "VK_swapchain.h"
#include "VK_device.h"
#include "VK_instance.h"
#include <stdexcept>

#ifdef _WIN32
static LRESULT CALLBACK WindowProc(HWND hwnd, UINT uMsg, WPARAM wParam, LPARAM lParam) {
    VK_swapchain* swapchain = reinterpret_cast<VK_swapchain*>(GetWindowLongPtrA(hwnd, GWLP_USERDATA));
    
    switch (uMsg) {
        case WM_SIZE:
            if (swapchain != nullptr && wParam != SIZE_MINIMIZED) {
                UINT width = LOWORD(lParam);
                UINT height = HIWORD(lParam);
                if (width > 0 && height > 0) {
                    swapchain->on_window_resized();
                }
            }
            return 0;
        case WM_SHOWWINDOW:
            if (swapchain != nullptr) {
                if (wParam == TRUE) {
                    swapchain->on_window_visible();
                } else {
                    swapchain->window_visible = false;
                }
            }
            return 0;
        case WM_CLOSE:
            if (swapchain != nullptr) {
                swapchain->on_window_closed();
            }
            return 0;
        case WM_DESTROY:
            PostQuitMessage(0);
            return 0;
        default:
            return DefWindowProcA(hwnd, uMsg, wParam, lParam);
    }
}
#endif

void VK_swapchain_process_events(VK_swapchain* swapchain) {
    if (swapchain == nullptr) {
        return;
    }

#ifdef _WIN32
    if (swapchain->win32_hwnd == nullptr) {
        return;
    }

    MSG msg;
    while (PeekMessageA(&msg, static_cast<HWND>(swapchain->win32_hwnd), 0, 0, PM_REMOVE)) {
        TranslateMessage(&msg);
        DispatchMessageA(&msg);
    }
#elif defined(__linux__)
    if (swapchain->x11_display == nullptr) {
        return;
    }

    Display* display = static_cast<Display*>(swapchain->x11_display);
    while (XPending(display)) {
        XEvent event;
        XNextEvent(display, &event);
        
        switch (event.type) {
            case ConfigureNotify: {
                XConfigureEvent xce = event.xconfigure;
                if (xce.width != static_cast<int>(swapchain->swapchainExtent.width) || 
                    xce.height != static_cast<int>(swapchain->swapchainExtent.height)) {
                    swapchain->swapchainExtent.width = static_cast<uint32_t>(xce.width);
                    swapchain->swapchainExtent.height = static_cast<uint32_t>(xce.height);
                    swapchain->on_window_resized();
                }
                break;
            }
            case MapNotify: {
                swapchain->on_window_visible();
                break;
            }
            case UnmapNotify: {
                swapchain->window_visible = false;
                break;
            }
            case ClientMessage: {
                if (event.xclient.data.l[0] == static_cast<long>(XInternAtom(display, "WM_DELETE_WINDOW", 0))) {
                    swapchain->on_window_closed();
                }
                break;
            }
        }
    }
#endif
}

bool VK_swapchain::create_window() {
#ifdef _WIN32
    WNDCLASSEXA wc = {};
    wc.cbSize = sizeof(WNDCLASSEXA);
    wc.style = CS_HREDRAW | CS_VREDRAW;
    wc.lpfnWndProc = WindowProc;
    wc.hInstance = GetModuleHandle(nullptr);
    wc.hCursor = LoadCursor(nullptr, IDC_ARROW);
    wc.lpszClassName = "VulkanWindowClass";
    RegisterClassExA(&wc);

    HWND hwnd = CreateWindowExA(
        0,
        "VulkanWindowClass",
        "Vulkan Stress Test",
        WS_OVERLAPPEDWINDOW | WS_VISIBLE,
        CW_USEDEFAULT, CW_USEDEFAULT,
        static_cast<int>(swapchainExtent.width),
        static_cast<int>(swapchainExtent.height),
        nullptr,
        nullptr,
        GetModuleHandle(nullptr),
        nullptr
    );

    if (!hwnd) {
        std::cerr << "Failed to create window" << std::endl;
        return false;
    }

    SetWindowLongPtrA(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(this));
    
    ShowWindow(hwnd, SW_SHOW);
    UpdateWindow(hwnd);
    win32_hwnd = hwnd;

#elif defined(__linux__)
    Display* display = XOpenDisplay(nullptr);
    if (!display) {
        std::cerr << "Failed to open X11 display" << std::endl;
        return false;
    }

    x11_display = display;

    int screen = DefaultScreen(display);
    Window rootWindow = RootWindow(display, screen);

    XSetWindowAttributes windowAttribs = {};
    windowAttribs.event_mask = StructureNotifyMask | ExposureMask | KeyPressMask;
    windowAttribs.background_pixel = BlackPixel(display, screen);

    Window window = XCreateWindow(
        display,
        rootWindow,
        0, 0,
        swapchainExtent.width,
        swapchainExtent.height,
        0,
        CopyFromParent,
        InputOutput,
        CopyFromParent,
        CWBackPixel | CWEventMask,
        &windowAttribs
    );

    if (!window) {
        std::cerr << "Failed to create X11 window" << std::endl;
        return false;
    }

    XStoreName(display, window, "Vulkan Stress Test");
    
    Atom wmDeleteMessage = XInternAtom(display, "WM_DELETE_WINDOW", 0);
    XSetWMProtocols(display, window, &wmDeleteMessage, 1);
    
    XMapWindow(display, window);
    XFlush(display);
    x11_window = window;
#endif

    return true;
}

bool VK_swapchain::create_surface() {
#ifdef _WIN32
    if (win32_hwnd == nullptr) {
        std::cerr << "Window not created" << std::endl;
        return false;
    }

    VkWin32SurfaceCreateInfoKHR createInfo = {};
    createInfo.sType = VK_STRUCTURE_TYPE_WIN32_SURFACE_CREATE_INFO_KHR;
    createInfo.hinstance = GetModuleHandle(nullptr);
    createInfo.hwnd = static_cast<HWND>(win32_hwnd);

    auto vkCreateWin32SurfaceKHR = reinterpret_cast<PFN_vkCreateWin32SurfaceKHR>(vkGetInstanceProcAddr(VK_instance::GET().handle, "vkCreateWin32SurfaceKHR"));
    if (!vkCreateWin32SurfaceKHR) {
        std::cerr << "Failed to load vkCreateWin32SurfaceKHR" << std::endl;
        return false;
    }

    VkResult result = vkCreateWin32SurfaceKHR(VK_instance::GET().handle, &createInfo, nullptr, &surface);
    if (result != VK_SUCCESS) {
        std::cerr << "Failed to create Win32 surface" << std::endl;
        return false;
    }

#elif defined(__linux__)
    if (x11_display == nullptr || x11_window == 0) {
        std::cerr << "Window not created" << std::endl;
        return false;
    }

    VkXlibSurfaceCreateInfoKHR createInfo = {};
    createInfo.sType = VK_STRUCTURE_TYPE_XLIB_SURFACE_CREATE_INFO_KHR;
    createInfo.dpy = static_cast<Display*>(x11_display);
    createInfo.window = x11_window;

    auto vkCreateXlibSurfaceKHR = reinterpret_cast<PFN_vkCreateXlibSurfaceKHR>(vkGetInstanceProcAddr(VK_instance::GET().handle, "vkCreateXlibSurfaceKHR"));
    if (!vkCreateXlibSurfaceKHR) {
        std::cerr << "Failed to load vkCreateXlibSurfaceKHR" << std::endl;
        return false;
    }

    VkResult result = vkCreateXlibSurfaceKHR(VK_instance::GET().handle, &createInfo, nullptr, &surface);
    if (result != VK_SUCCESS) {
        std::cerr << "Failed to create Xlib surface" << std::endl;
        return false;
    }

#else
    std::cerr << "Unsupported platform for surface creation" << std::endl;
    return false;
#endif

    return true;
}

bool VK_swapchain::create_swapchain() {
    VkSurfaceCapabilitiesKHR capabilities;
    vkGetPhysicalDeviceSurfaceCapabilitiesKHR(device_ptr->physdev.handle, surface, &capabilities);

    VkExtent2D desiredExtent = swapchainExtent;
    swapchainExtent = capabilities.currentExtent;
    if (swapchainExtent.width == UINT32_MAX) {
        swapchainExtent.width = std::max(
            capabilities.minImageExtent.width,
            std::min(capabilities.maxImageExtent.width, desiredExtent.width));
        swapchainExtent.height = std::max(
            capabilities.minImageExtent.height,
            std::min(capabilities.maxImageExtent.height, desiredExtent.height));
    }

    uint32_t formatCount;
    vkGetPhysicalDeviceSurfaceFormatsKHR(device_ptr->physdev.handle, surface, &formatCount, nullptr);
    if (formatCount == 0) {
        std::cerr << "No surface formats available" << std::endl;
        return false;
    }

    std::vector<VkSurfaceFormatKHR> formats(formatCount);
    vkGetPhysicalDeviceSurfaceFormatsKHR(device_ptr->physdev.handle, surface, &formatCount, formats.data());

    VkSurfaceFormatKHR selectedFormat = formats[0];
    for (const auto& format : formats) {
        if (format.format == VK_FORMAT_B8G8R8A8_SRGB && format.colorSpace == VK_COLOR_SPACE_SRGB_NONLINEAR_KHR) {
            selectedFormat = format;
            break;
        }
    }
    swapchainFormat = selectedFormat.format;

    VkPresentModeKHR presentMode = VK_PRESENT_MODE_FIFO_KHR;

    uint32_t imageCount = capabilities.minImageCount + 1;
    if (capabilities.maxImageCount > 0 && imageCount > capabilities.maxImageCount) {
        imageCount = capabilities.maxImageCount;
    }

    VkSwapchainCreateInfoKHR createInfo = {};
    createInfo.sType = VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR;
    createInfo.surface = surface;
    createInfo.minImageCount = imageCount;
    createInfo.imageFormat = swapchainFormat;
    createInfo.imageColorSpace = selectedFormat.colorSpace;
    createInfo.imageExtent = swapchainExtent;
    createInfo.imageArrayLayers = 1;
    createInfo.imageUsage = VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT | VK_IMAGE_USAGE_TRANSFER_DST_BIT;
    createInfo.imageSharingMode = VK_SHARING_MODE_EXCLUSIVE;
    createInfo.preTransform = capabilities.currentTransform;
    createInfo.compositeAlpha = VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR;
    createInfo.presentMode = presentMode;
    createInfo.clipped = VK_TRUE;
    createInfo.oldSwapchain = VK_NULL_HANDLE;

    VkResult result = vkCreateSwapchainKHR(device_ptr->handle, &createInfo, nullptr, &handle);
    if (result != VK_SUCCESS) {
        std::cerr << "Failed to create swapchain" << std::endl;
        return false;
    }

    return true;
}

bool VK_swapchain::create_backingstores() {
    uint32_t imageCount;
    vkGetSwapchainImagesKHR(device_ptr->handle, handle, &imageCount, nullptr);
    std::vector<VkImage> swapchainImages(imageCount);
    vkGetSwapchainImagesKHR(device_ptr->handle, handle, &imageCount, swapchainImages.data());

    backingstores.resize(imageCount);

    bool hasDepthStencil = (depthstencilFormat != VK_FORMAT_UNDEFINED);
    if (hasDepthStencil) {
        if (!depthstencilImage.init(
                device_ptr, depthstencilFormat, swapchainExtent,
                VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT,
                VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT
            )) {
            std::cerr << "Failed to create depth stencil image" << std::endl;
            return false;
        }
    }

    VkAttachmentDescription colorAttachment = {};
    colorAttachment.format = swapchainFormat;
    colorAttachment.samples = VK_SAMPLE_COUNT_1_BIT;
    colorAttachment.loadOp = VK_ATTACHMENT_LOAD_OP_CLEAR;
    colorAttachment.storeOp = VK_ATTACHMENT_STORE_OP_STORE;
    colorAttachment.stencilLoadOp = VK_ATTACHMENT_LOAD_OP_DONT_CARE;
    colorAttachment.stencilStoreOp = VK_ATTACHMENT_STORE_OP_DONT_CARE;
    colorAttachment.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED;
    colorAttachment.finalLayout = VK_IMAGE_LAYOUT_PRESENT_SRC_KHR;

    VkAttachmentReference colorAttachmentRef = {};
    colorAttachmentRef.attachment = 0;
    colorAttachmentRef.layout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;

    VkAttachmentDescription depthAttachment = {};
    VkAttachmentReference depthAttachmentRef = {};
    
    if (hasDepthStencil) {
        depthAttachment.format = depthstencilFormat;
        depthAttachment.samples = VK_SAMPLE_COUNT_1_BIT;
        depthAttachment.loadOp = VK_ATTACHMENT_LOAD_OP_CLEAR;
        depthAttachment.storeOp = VK_ATTACHMENT_STORE_OP_DONT_CARE;
        depthAttachment.stencilLoadOp = VK_ATTACHMENT_LOAD_OP_DONT_CARE;
        depthAttachment.stencilStoreOp = VK_ATTACHMENT_STORE_OP_DONT_CARE;
        depthAttachment.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED;
        depthAttachment.finalLayout = VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL;

        depthAttachmentRef.attachment = 1;
        depthAttachmentRef.layout = VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL;
    }

    VkSubpassDescription subpass = {};
    subpass.pipelineBindPoint = VK_PIPELINE_BIND_POINT_GRAPHICS;
    subpass.colorAttachmentCount = 1;
    subpass.pColorAttachments = &colorAttachmentRef;
    subpass.pDepthStencilAttachment = hasDepthStencil ? &depthAttachmentRef : nullptr;

    std::vector<VkAttachmentDescription> attachments = {colorAttachment};
    if (hasDepthStencil) {
        attachments.push_back(depthAttachment);
    }

    VkRenderPassCreateInfo renderPassInfo = {};
    renderPassInfo.sType = VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO;
    renderPassInfo.attachmentCount = static_cast<uint32_t>(attachments.size());
    renderPassInfo.pAttachments = attachments.data();
    renderPassInfo.subpassCount = 1;
    renderPassInfo.pSubpasses = &subpass;

    VkResult result = vkCreateRenderPass(device_ptr->handle, &renderPassInfo, nullptr, &defaultRenderPass);
    if (result != VK_SUCCESS) {
        std::cerr << "Failed to create render pass" << std::endl;
        return false;
    }

    for (size_t i = 0; i < backingstores.size(); i++) {
        backingstores[i].index = static_cast<uint32_t>(i);
        backingstores[i].image = swapchainImages[i];

        VkImageViewCreateInfo viewInfo = {};
        viewInfo.sType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO;
        viewInfo.image = backingstores[i].image;
        viewInfo.viewType = VK_IMAGE_VIEW_TYPE_2D;
        viewInfo.format = swapchainFormat;
        viewInfo.subresourceRange.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
        viewInfo.subresourceRange.baseMipLevel = 0;
        viewInfo.subresourceRange.levelCount = 1;
        viewInfo.subresourceRange.baseArrayLayer = 0;
        viewInfo.subresourceRange.layerCount = 1;

        result = vkCreateImageView(device_ptr->handle, &viewInfo, nullptr, &backingstores[i].imageView_color0);
        if (result != VK_SUCCESS) {
            std::cerr << "Failed to create color image view" << std::endl;
            return false;
        }

        if (hasDepthStencil) {
            backingstores[i].imageView_depthstencil = depthstencilImage.view;
        }

        std::vector<VkImageView> attachmentViews = {backingstores[i].imageView_color0};
        if (hasDepthStencil) {
            attachmentViews.push_back(backingstores[i].imageView_depthstencil);
        }

        VkFramebufferCreateInfo framebufferInfo = {};
        framebufferInfo.sType = VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO;
        framebufferInfo.renderPass = defaultRenderPass;
        framebufferInfo.attachmentCount = static_cast<uint32_t>(attachmentViews.size());
        framebufferInfo.pAttachments = attachmentViews.data();
        framebufferInfo.width = swapchainExtent.width;
        framebufferInfo.height = swapchainExtent.height;
        framebufferInfo.layers = 1;

        result = vkCreateFramebuffer(device_ptr->handle, &framebufferInfo, nullptr, &backingstores[i].framebuffer);
        if (result != VK_SUCCESS) {
            std::cerr << "Failed to create framebuffer" << std::endl;
            return false;
        }
    }

    return true;
}

void VK_swapchain::delete_swapchain_resources() {
    vkDeviceWaitIdle(device_ptr->handle);

    for (auto& backingstore : backingstores) {
        if (backingstore.framebuffer != VK_NULL_HANDLE) {
            vkDestroyFramebuffer(device_ptr->handle, backingstore.framebuffer, nullptr);
            backingstore.framebuffer = VK_NULL_HANDLE;
        }
        if (backingstore.imageView_color0 != VK_NULL_HANDLE) {
            vkDestroyImageView(device_ptr->handle, backingstore.imageView_color0, nullptr);
            backingstore.imageView_color0 = VK_NULL_HANDLE;
        }
        backingstore.imageView_depthstencil = VK_NULL_HANDLE;
    }
    backingstores.clear();

    if (defaultRenderPass != VK_NULL_HANDLE) {
        vkDestroyRenderPass(device_ptr->handle, defaultRenderPass, nullptr);
        defaultRenderPass = VK_NULL_HANDLE;
    }

    depthstencilImage.deinit();

    if (handle != VK_NULL_HANDLE) {
        vkDestroySwapchainKHR(device_ptr->handle, handle, nullptr);
        handle = VK_NULL_HANDLE;
    }
}

bool VK_swapchain::init(VK_device* dev_ptr, int window_width, int window_height) {
    if (dev_ptr == nullptr) {
        std::cerr << "Invalid device pointer" << std::endl;
        return false;
    }

    device_ptr = dev_ptr;
    handle = VK_NULL_HANDLE;
    surface = VK_NULL_HANDLE;
    defaultRenderPass = VK_NULL_HANDLE;
    backingstores.clear();
    imageAvailableFence = VK_NULL_HANDLE;
    currentImageIndex = UINT32_MAX;
    depthstencilFormat = VK_FORMAT_D24_UNORM_S8_UINT;
    swapchainExtent.width = static_cast<uint32_t>(window_width);
    swapchainExtent.height = static_cast<uint32_t>(window_height);
    window_visible = false;

#ifdef _WIN32
    win32_hwnd = nullptr;
#elif defined(__linux__)
    x11_display = nullptr;
    x11_window = 0;
#endif

    if (!device_ptr->cmdqueue.supportPresenting) {
        std::cerr << "Command queue does not support presenting" << std::endl;
        return false;
    }

    if (!create_window()) {
        deinit();
        return false;
    }

    if (!create_surface()) {
        deinit();
        return false;
    }

    if (!create_swapchain()) {
        deinit();
        return false;
    }

    if (!create_backingstores()) {
        deinit();
        return false;
    }

    VkFenceCreateInfo fenceInfo = {};
    fenceInfo.sType = VK_STRUCTURE_TYPE_FENCE_CREATE_INFO;
    fenceInfo.flags = VK_FENCE_CREATE_SIGNALED_BIT;

    VkResult result = vkCreateFence(device_ptr->handle, &fenceInfo, nullptr, &imageAvailableFence);
    if (result != VK_SUCCESS) {
        std::cerr << "Failed to create image available fence" << std::endl;
        deinit();
        return false;
    }

    currentImageIndex = UINT32_MAX;

    return true;
}

void VK_swapchain::deinit() {
    if (device_ptr == nullptr) {
        return;
    }

    vkDeviceWaitIdle(device_ptr->handle);

    if (imageAvailableFence != VK_NULL_HANDLE) {
        vkDestroyFence(device_ptr->handle, imageAvailableFence, nullptr);
        imageAvailableFence = VK_NULL_HANDLE;
    }

    delete_swapchain_resources();

    if (surface != VK_NULL_HANDLE) {
        vkDestroySurfaceKHR(VK_instance::GET().handle, surface, nullptr);
        surface = VK_NULL_HANDLE;
    }

#ifdef _WIN32
    if (win32_hwnd != nullptr) {
        DestroyWindow(static_cast<HWND>(win32_hwnd));
        win32_hwnd = nullptr;
    }
#elif defined(__linux__)
    if (x11_window != 0 && x11_display != nullptr) {
        XDestroyWindow(static_cast<Display*>(x11_display), x11_window);
        x11_window = 0;
    }
    if (x11_display != nullptr) {
        XCloseDisplay(static_cast<Display*>(x11_display));
        x11_display = nullptr;
    }
#endif

    device_ptr = nullptr;
}

void VK_swapchain::on_window_visible() {
    window_visible = true;
}

void VK_swapchain::on_window_closed() {
    window_visible = false;
}

void VK_swapchain::on_window_resized() {
    VkSurfaceCapabilitiesKHR capabilities;
    vkGetPhysicalDeviceSurfaceCapabilitiesKHR(device_ptr->physdev.handle, surface, &capabilities);

    delete_swapchain_resources();

    swapchainExtent = capabilities.currentExtent;

    if (!create_swapchain()) {
        throw std::runtime_error("Failed to resize swapchain");
    }

    if (!create_backingstores()) {
        throw std::runtime_error("Failed to create backingstore resources");
    }

    currentImageIndex = UINT32_MAX;
}

void VK_swapchain::acquire_next_image() {
    vkWaitForFences(device_ptr->handle, 1, &imageAvailableFence, VK_TRUE, UINT64_MAX);
    vkResetFences(device_ptr->handle, 1, &imageAvailableFence);

    VkResult result = vkAcquireNextImageKHR(
        device_ptr->handle,
        handle,
        UINT64_MAX,  // Blocking mode - wait forever
        VK_NULL_HANDLE,  // No semaphore
        imageAvailableFence,  // Use fence instead
        &currentImageIndex
    );

    if (result == VK_ERROR_OUT_OF_DATE_KHR || result == VK_SUBOPTIMAL_KHR) {
        on_window_resized();
        vkWaitForFences(device_ptr->handle, 1, &imageAvailableFence, VK_TRUE, UINT64_MAX);
        vkResetFences(device_ptr->handle, 1, &imageAvailableFence);
        result = vkAcquireNextImageKHR(
            device_ptr->handle,
            handle,
            UINT64_MAX,
            VK_NULL_HANDLE,
            imageAvailableFence,
            &currentImageIndex
        );
    }

    if (result != VK_SUCCESS && result != VK_SUBOPTIMAL_KHR) {
        throw std::runtime_error("Failed to acquire swapchain image");
    }

    vkWaitForFences(device_ptr->handle, 1, &imageAvailableFence, VK_TRUE, UINT64_MAX);
}

void VK_swapchain::present() {
    VkPresentInfoKHR presentInfo = {};
    presentInfo.sType = VK_STRUCTURE_TYPE_PRESENT_INFO_KHR;
    presentInfo.waitSemaphoreCount = 0;
    presentInfo.pWaitSemaphores = nullptr;
    presentInfo.swapchainCount = 1;
    presentInfo.pSwapchains = &handle;
    presentInfo.pImageIndices = &currentImageIndex;

    VkResult result = vkQueuePresentKHR(device_ptr->cmdqueue.handle, &presentInfo);
    if (result == VK_ERROR_OUT_OF_DATE_KHR || result == VK_SUBOPTIMAL_KHR) {
        on_window_resized();
    } else if (result != VK_SUCCESS) {
        std::cerr << "Failed to present swapchain image" << std::endl;
    }

    vkQueueWaitIdle(device_ptr->cmdqueue.handle);
}
