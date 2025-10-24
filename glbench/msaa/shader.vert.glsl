#version 330 core
#if defined(VULKAN)
#define gl_VertexID gl_VertexIndex
#endif

out vec2 uv;

void main()
{
    // Simple fullscreen triangle generation
    // Vertex 0: (-1, -1, 0, 1)
    // Vertex 1: (-1,  3, 0, 1)  
    // Vertex 2: ( 3, -1, 0, 1)
    
    if (gl_VertexID == 0) {
        gl_Position = vec4(-1.0, -1.0, 0.0, 1.0);
        uv = vec2(0.0, 1.0);
    }
    else if (gl_VertexID == 1) {
        gl_Position = vec4(-1.0, 3.0, 0.0, 1.0);
        uv = vec2(0.0, -1.0);
    }
    else { // gl_VertexID == 2
        gl_Position = vec4(3.0, -1.0, 0.0, 1.0);
        uv = vec2(2.0, 1.0);
    }
}
