#pragma once 
#include "glwindow.h"
#include "window_tools.h"

// Resolve blit: DRAM -> L2(decompress) -> ROP resolve -> L2(compress) -> DRAM 
// Present blit: DRAM -> L2 -> ROP copy -> L2 -> DRAM  
// You don’t see L2 decompression on the present copy if the source is L2-resident or already uncompressed in memory
// You don’t see compression if the default framebuffer is allocated or treated as non-compressible for display/compositor reasons.

class GLWindow_IMPL : public GLWindow {
public:
    static const unsigned int TEXTURE_WIDTH = 3840;
    static const unsigned int TEXTURE_HEIGHT = 2160;
    static const unsigned int MSAA_SAMPLE_COUNT = 8;
    static const unsigned int MSAA_FORMAT = GL_RGBA8;

    void run();

private:
    void validate_framebuffer();
    void create_msaa_framebuffer();
    void draw_big_triangle();

private:
    GLuint m_msaaFramebuffer = UINT32_MAX;
    GLuint m_msaaColorTexture = UINT32_MAX;
    GLuint m_resolveFramebuffer = UINT32_MAX;
    GLuint m_resolveColorTexture = UINT32_MAX;
    GLuint m_shaderProgram = UINT32_MAX;
    GLuint m_uniformBuffer = UINT32_MAX;
    GLuint m_frameIndexLoc = UINT32_MAX;
    int m_frameIndex = 0;
    int m_actualMSAASamples = 0;
};
