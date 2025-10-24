#version 330 core
#if defined(VULKAN)
layout(std140) uniform params_t {
    uint frameIndex;
    uint padding[3];  
};
#else
uniform uint frameIndex;
#endif 

in vec2 uv;
out vec4 fragColor;

// Simple hash function for random generation
uint hash(uint x)
{
    x += (x << 10u);
    x ^= (x >> 6u);
    x += (x << 3u);
    x ^= (x >> 11u);
    x += (x << 15u);
    return x;
}

// Generate random float between 0 and 1
float random(uvec2 pixelCoord, uint frame)
{
    uint seed = pixelCoord.x + pixelCoord.y * 3840u + frame * 12345u;
    return float(hash(seed)) / 4294967296.0; // Divide by 2^32
}

void main()
{
    uvec2 pixelCoord = uvec2(gl_FragCoord.xy);
    float randValue = random(pixelCoord, frameIndex);
    
    // Generate 0 or 1 based on random value
    float result = randValue > 0.5 ? 1.0 : 0.0;
    
    fragColor = vec4(result, result, result, 1.0);
}
