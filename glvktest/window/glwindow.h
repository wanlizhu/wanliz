#pragma once
#include <cassert>
#include <iostream>
#include <vector>
#include <fstream>
#include <sstream>
#include <cstring>
#include <cstdlib>
#include <map>
#include <algorithm>
#include <string>
#include <stdexcept>
#include <filesystem>
#include <unordered_map>
#include <chrono>
#include <cstdio>
#include <cstdint>
#include <thread>
#include <ratio>
#ifdef __linux__
#include <unistd.h>
#include <X11/Xlib.h>  
#include "glad/gl.h"
#include "glad/glx.h" // X11
#include "glad/egl.h" // Wayland
#define GLFW_EXPOSE_NATIVE_X11
#define GLFW_EXPOSE_NATIVE_GLX
#include "GLFW/glfw3.h"
#include "GLFW/glfw3native.h"
#else 
#include "glad/gl.h"
#include "glad/wgl.h"
#define GLFW_EXPOSE_NATIVE_WIN32
#define GLFW_EXPOSE_NATIVE_WGL
#include "GLFW/glfw3.h"
#include "GLFW/glfw3native.h"
#endif 

int _sizeof_(GLenum color);
const char* _str_(GLenum color);
int _type_(GLenum color);

class GLWindow {
public:
    virtual ~GLWindow() {}

protected:
    void open(
        const char* title, 
        int width, int height, 
        const std::map<int, int>& hints
    );
    void close(); 
    void gpu_timer_start();
    void gpu_timer_end();
    std::chrono::nanoseconds gpu_timer_read();
    std::chrono::nanoseconds cpu_timer_read();
    std::chrono::nanoseconds cpu_timer_read_and_reset();
    GLuint compile_gpu_program(
        const std::string& vsfile, 
        const std::string& psfile
    );

protected:
    GLFWwindow* m_window = NULL;

private:
    GLuint m_queries[2] = {0, 0};
    std::chrono::high_resolution_clock::time_point m_timePoint;
};

