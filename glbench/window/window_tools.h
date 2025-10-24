#pragma once
#include <stdio.h>
#include <stdlib.h>

inline const char* _size_(uint64_t size) {
    static char buffer[32];
    if (size >= 1024ULL * 1024 * 1024) {
        double gb = size / (1024.0 * 1024.0 * 1024.0);
        snprintf(buffer, sizeof(buffer), "%.2f GB", gb);
    } else if (size >= 1024ULL * 1024) {
        double mb = size / (1024.0 * 1024.0);
        snprintf(buffer, sizeof(buffer), "%.2f MB", mb);
    } else if (size >= 1024ULL) {
        double kb = size / 1024.0;
        snprintf(buffer, sizeof(buffer), "%.2f KB", kb);
    } else {
        snprintf(buffer, sizeof(buffer), "%llu B", (unsigned long long)size);
    }
    return buffer;
}
