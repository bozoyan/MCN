#pragma once
#include <cstddef>

// Preserve whole-clip 2/98 percentile normalization without loading the clip.
// The file contains finite, non-negative float32 relative depths.
void depth_write_gray(const char* floats, const char* gray, std::size_t values);
