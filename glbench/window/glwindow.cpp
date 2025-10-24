#include "glwindow.h"

int _sizeof_(GLenum color) {
    switch (color) {
        case GL_RGBA8:  return 4;
        case GL_RGBA16: return 8;
        case GL_RGBA32UI: return 16;
        case GL_RGBA32F: return 16;
        default: assert(false); return 0;
    }
}

const char* _str_(GLenum color) {
    switch (color) {
        case GL_RGBA8:  return "GL_RGBA8";
        case GL_RGBA16: return "GL_RGBA16";
        case GL_RGBA32UI: return "GL_RGBA32UI";
        case GL_RGBA32F: return "GL_RGBA32F";
        default: assert(false); return "";
    }
}

int _type_(GLenum color) {
    switch (color) {
        case GL_RGBA8:  return GL_UNSIGNED_BYTE;
        case GL_RGBA16: return GL_UNSIGNED_SHORT;
        case GL_RGBA32UI: return GL_UNSIGNED_INT;
        case GL_RGBA32F: return GL_FLOAT;
        default: assert(false); return 0;
    }
}

void glfw_error_callback(int error, const char* description) {
    std::cerr << "GLFW Error " << error << ": " << description << std::endl;
}

void GLWindow::open(
    const char* title, 
    int width, int height, 
    const std::map<int, int>& hints
) {
    glfwSetErrorCallback(glfw_error_callback);
    if (!glfwInit()) {
        throw std::runtime_error("Failed to initialize GLFW");
    }

    for (auto& [key, val] : hints) {
        glfwWindowHint(key, val);
    }

    m_window = glfwCreateWindow(width, height, title, nullptr, nullptr);
    if (!m_window) {
        glfwTerminate();
        throw std::runtime_error("Failed to create GLFW window");
    }

    glfwMakeContextCurrent(m_window);

    if (!gladLoaderLoadGL()) {
        glfwTerminate();
        throw std::runtime_error("Failed to call gladLoaderLoadGL");
    }

#ifdef __linux__
    Display* display = glfwGetX11Display();
    if (!gladLoaderLoadGLX(display, DefaultScreen(display))) {
        glfwTerminate();
        throw std::runtime_error("Failed to call gladLoaderLoadGLX");
    }
#else
    HWND hwnd = glfwGetWin32Window(m_window);
    HDC  hdc  = GetDC(hwnd);
    if (!gladLoaderLoadWGL(hdc)) {
        ReleaseDC(hwnd, hdc);
        glfwTerminate();
        throw std::runtime_error("Failed to call gladLoaderLoadWGL");
    }
#endif 

    glfwSwapInterval(0); // Disable Vsync

    const char* vendor = (const char*)glGetString(GL_VENDOR);
    const char* renderer = (const char*)glGetString(GL_RENDERER);
    const char* version = (const char*)glGetString(GL_VERSION);
    std::cout << "OpenGL Vendor: " << vendor << std::endl;
    std::cout << "OpenGL Renderer: " << renderer << std::endl;
    std::cout << "OpenGL Version: " << version << std::endl;

    glGenQueries(2, m_queries);
    m_timePoint = std::chrono::high_resolution_clock::now();

    std::cout << "Created Window \"" << title <<  "\" " << width << "x" << height << std::endl;
}

void GLWindow::close() {
    glDeleteQueries(2, m_queries);
    glfwDestroyWindow(m_window);
    glfwTerminate();
    std::cout << "Window Closed" << std::endl;
}

void GLWindow::gpu_timer_start() {
    glQueryCounter(m_queries[0], GL_TIMESTAMP);
}

void GLWindow::gpu_timer_end() {
    glQueryCounter(m_queries[1], GL_TIMESTAMP);
}

std::chrono::nanoseconds GLWindow::gpu_timer_read() {
    GLint available[2] = {0, 0};
    int retries = 0;
    do {
        glGetQueryObjectiv(m_queries[0], GL_QUERY_RESULT_AVAILABLE, &available[0]);
        glGetQueryObjectiv(m_queries[1], GL_QUERY_RESULT_AVAILABLE, &available[1]);
        if (++retries > 1) {
            std::this_thread::sleep_for(std::chrono::microseconds(100));
        }
    } while (!(available[0] && available[1]));
    assert(available[0] && available[1]);
    
    GLuint64 startTime = 0, endTime = 0;
    glGetQueryObjectui64v(m_queries[0], GL_QUERY_RESULT, &startTime);
    glGetQueryObjectui64v(m_queries[1], GL_QUERY_RESULT, &endTime);
    assert(endTime >= startTime);

    return std::chrono::nanoseconds(endTime - startTime);
}

std::chrono::nanoseconds GLWindow::cpu_timer_read() {
    return std::chrono::duration_cast<std::chrono::nanoseconds>(std::chrono::high_resolution_clock::now() - m_timePoint);
}

std::chrono::nanoseconds GLWindow::cpu_timer_read_and_reset() {
    auto ns = cpu_timer_read();
    m_timePoint = std::chrono::high_resolution_clock::now();
    return ns;
}

GLuint compile_glsl_shader_from_file(GLenum stage, const std::string& filename) {
    const char* source = nullptr;
    std::string fileContent;
    std::filesystem::path parent = std::filesystem::current_path().parent_path();
    std::string filepath;

    if (std::filesystem::exists(std::filesystem::current_path() / filename)) {
        filepath = (std::filesystem::current_path() / filename).string();
    } else if (std::filesystem::exists(parent / filename)) {
        filepath = (parent / filename).string();
    } else {
        std::cerr << "File doesn't exist: " << filename << std::endl;
        throw std::runtime_error("File doesn't exist");
    }

    std::cout << "Load shader from file: \"" << filepath << "\"" << std::endl;
    std::ifstream file(filepath);
    if (!file.is_open()) {
        std::cerr << "Cannot open file: " << filename << std::endl;
        throw std::runtime_error("Cannot open file");
    }

    std::stringstream buffer;
    buffer << file.rdbuf();
    fileContent = buffer.str();
    source = fileContent.c_str();

    GLuint shader = glCreateShader(stage);
    glShaderSource(shader, 1, &source, nullptr);
    glCompileShader(shader);

    int result = 0, length = 0;
    char* message = nullptr;
    glGetShaderiv(shader, GL_COMPILE_STATUS, &result);
    if (result == GL_FALSE) {
        glGetShaderiv(shader, GL_INFO_LOG_LENGTH, &length);
        message = (char*)alloca(length * sizeof(char));
        glGetShaderInfoLog(shader, length, &length, message);
        glDeleteShader(shader);

        std::cerr << "Failed to compile " << (stage == GL_VERTEX_SHADER ? "vertex" : "fragment") << " shader: " << message << std::endl;
        throw std::runtime_error("Failed to compile shader");
    }

    return shader;
}

GLuint GLWindow::compile_gpu_program(
    const std::string& vsfile, 
    const std::string& psfile 
) {
    GLuint vs = compile_glsl_shader_from_file(GL_VERTEX_SHADER, vsfile);
    GLuint ps = compile_glsl_shader_from_file(GL_FRAGMENT_SHADER, psfile);

    GLuint program = glCreateProgram();
    glAttachShader(program, vs);
    glAttachShader(program, ps);
    glLinkProgram(program);

    int result = 0, length = 0;
    char* message = nullptr;
    glGetProgramiv(program, GL_LINK_STATUS, &result);
    if (result == GL_FALSE) {
        glGetProgramiv(program, GL_INFO_LOG_LENGTH, &length);
        message = (char*)alloca(length * sizeof(char));
        glGetProgramInfoLog(program, length, &length, message);
        glDeleteProgram(program);

        std::cerr << "Failed to link program: " << message << std::endl;
        throw std::runtime_error("Failed to link program");
    }

    glDeleteShader(vs);
    glDeleteShader(ps);
    std::cout << "Linked program (ID: " << program << ") with " << vsfile << " and " << psfile << std::endl;

    return program;
}