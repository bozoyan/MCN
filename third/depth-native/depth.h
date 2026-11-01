#pragma once
#include <stddef.h>

#if defined(_WIN32)
#if defined(DEPTH_BUILD)
#define DEPTH_API __declspec(dllexport)
#else
#define DEPTH_API __declspec(dllimport)
#endif
#else
#define DEPTH_API __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

// Synchronous core; the product invokes it in an isolated task process. RGB must
// match the exported model resolution. Output files must belong to the caller.
// provider: 0 = CPU, 1 = CoreML (macOS); errors are returned, never thrown over FFI.
DEPTH_API int depth_run(const char* model, const char* rgb, const char* floats,
                        const char* gray, int width, int height, int frames,
                        int provider, char* error, size_t error_capacity);

#ifdef __cplusplus
}
#endif
