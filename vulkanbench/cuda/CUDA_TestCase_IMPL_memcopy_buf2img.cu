#include <cuda_runtime.h>
#include <cstdio>
#include <cstdlib>
#include <cmath>

static const int SIZE_IN_MB = 1024;
static const int PROFILE_ITERATIONS = 1;
static const int BYTES_PER_PIXEL = 16;

#define CUDA_CHECK(call) do { \
    cudaError_t err = call; \
    if (err != cudaSuccess) { \
        fprintf(stderr, "CUDA error at %s:%d: %s\n", __FILE__, __LINE__, cudaGetErrorString(err)); \
        exit(EXIT_FAILURE); \
    } \
} while(0)

int main() {
    CUDA_CHECK(cudaSetDevice(0));

    cudaDeviceProp prop;
    CUDA_CHECK(cudaGetDeviceProperties(&prop, 0));
    printf("Using GPU: %s\n", prop.name);

    size_t sizeInBytes = (size_t)SIZE_IN_MB * 1024 * 1024;
    int imageWidth = (int)ceil(sqrt((double)sizeInBytes / BYTES_PER_PIXEL));
    int imageHeight = imageWidth;

    printf("Buffer size: %zu bytes (%d MB)\n", sizeInBytes, SIZE_IN_MB);
    printf("Image dimensions: %d x %d (RGBA32F)\n", imageWidth, imageHeight);

    void* srcBuffer;
    void* dstImage;
    size_t dstPitch;

    CUDA_CHECK(cudaMalloc(&srcBuffer, sizeInBytes));
    CUDA_CHECK(cudaMallocPitch(&dstImage, &dstPitch, imageWidth * BYTES_PER_PIXEL, imageHeight));

    printf("Image pitch: %zu bytes\n", dstPitch);

    cudaStream_t stream;
    cudaEvent_t start, stop;
    CUDA_CHECK(cudaStreamCreate(&stream));
    CUDA_CHECK(cudaEventCreate(&start));
    CUDA_CHECK(cudaEventCreate(&stop));

    printf("\nRunning buffer->image for %d times ...\n", PROFILE_ITERATIONS);

    double totalTimeMs = 0;
    for (int i = 0; i < PROFILE_ITERATIONS; i++) {
        CUDA_CHECK(cudaEventRecord(start, stream));
        CUDA_CHECK(cudaMemcpy2DAsync(
            dstImage, dstPitch,
            srcBuffer, imageWidth * BYTES_PER_PIXEL,
            imageWidth * BYTES_PER_PIXEL, imageHeight,
            cudaMemcpyDeviceToDevice, stream
        ));
        CUDA_CHECK(cudaEventRecord(stop, stream));
        CUDA_CHECK(cudaStreamSynchronize(stream));

        float ms;
        CUDA_CHECK(cudaEventElapsedTime(&ms, start, stop));
        totalTimeMs += ms;
    }

    double avgTimeMs = totalTimeMs / PROFILE_ITERATIONS;
    double gbPerSec = ((double)sizeInBytes / (1024.0 * 1024.0 * 1024.0)) / (avgTimeMs / 1000.0);

    printf("\nbuffer->image | %d MB | GPU = %7.3f (GB/s)\n", SIZE_IN_MB, gbPerSec);
    printf("Average copy time: %.3f ms\n", avgTimeMs);

    CUDA_CHECK(cudaEventDestroy(stop));
    CUDA_CHECK(cudaEventDestroy(start));
    CUDA_CHECK(cudaStreamDestroy(stream));
    CUDA_CHECK(cudaFree(dstImage));
    CUDA_CHECK(cudaFree(srcBuffer));

    return 0;
}
