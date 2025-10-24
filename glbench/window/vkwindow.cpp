#include "vkwindow.h"

void VKWindow::open(
    const char* title,
    int width, int height,
    const std::map<int, int>& hints
) {
    
}

void VKWindow::close() {

}

void VKWindow::gpu_timer_start() {

}

void VKWindow::gpu_timer_end() {

}

std::chrono::nanoseconds VKWindow::gpu_timer_read() {
    return std::chrono::nanoseconds(0);
}

std::chrono::nanoseconds VKWindow::cpu_timer_read() {
    return std::chrono::nanoseconds(0);
}

std::chrono::nanoseconds VKWindow::cpu_timer_read_and_reset() {
    return std::chrono::nanoseconds(0);
}
