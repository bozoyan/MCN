#include "depth_io.h"
#include <filesystem>
#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <fstream>
#include <limits>
#include <stdexcept>
#include <vector>

namespace {
static_assert(sizeof(float) == 4 && std::numeric_limits<float>::is_iec559);
constexpr std::size_t chunk_values = 65536;
using Histogram = std::vector<std::uint64_t>;

template <class F> void scan(const char* path, std::size_t count, F consume) {
    std::ifstream input(std::filesystem::u8path(path), std::ios::binary | std::ios::ate);
    if (count == 0 || !input || input.tellg() != static_cast<std::streamoff>(count * sizeof(float))) {
        throw std::runtime_error("Depth file size differs from the expected value count");
    }
    input.seekg(0);
    std::vector<float> buffer(std::min(count, chunk_values));
    for (std::size_t offset = 0; offset < count; offset += buffer.size()) {
        const std::size_t size = std::min(buffer.size(), count - offset);
        if (!input.read(reinterpret_cast<char*>(buffer.data()), size * sizeof(float))) {
            throw std::runtime_error("Cannot read depth file");
        }
        consume(buffer.data(), size);
    }
}

std::uint32_t key(float value) {
    if (!std::isfinite(value) || value < 0) {
        throw std::runtime_error("Depth output must be finite and non-negative");
    }
    // Non-negative IEEE float bit patterns sort in numerical order.
    // Canonicalize negative zero so it does not sort after positive values.
    if (value == 0) {
        return 0;
    }
    std::uint32_t bits;
    std::memcpy(&bits, &value, sizeof bits);
    return bits;
}

std::size_t bucket(const Histogram& histogram, std::uint64_t& rank) {
    for (std::size_t i = 0; i < histogram.size(); ++i) {
        if (rank < histogram[i]) {
            return i;
        }
        rank -= histogram[i];
    }
    throw std::runtime_error("Percentile rank is outside the depth file");
}

std::array<float, 2> percentiles(const char* path, std::size_t count) {
    if (count == 0) {
        throw std::runtime_error("Cannot normalize an empty depth file");
    }
    const double low = (count - 1) * .02, high = (count - 1) * .98;
    std::array<std::uint64_t, 4> ranks{
        static_cast<std::uint64_t>(low), static_cast<std::uint64_t>(std::ceil(low)),
        static_cast<std::uint64_t>(high), static_cast<std::uint64_t>(std::ceil(high))};
    Histogram upper_counts(65536);
    scan(path, count, [&](const float* values, std::size_t size) {
        for (std::size_t i = 0; i < size; ++i) {
            ++upper_counts[key(values[i]) >> 16];
        }
    });
    std::array<std::size_t, 4> upper{};
    std::array<Histogram, 4> lower_counts;
    for (std::size_t i = 0; i < upper.size(); ++i) {
        upper[i] = bucket(upper_counts, ranks[i]);
        lower_counts[i].resize(65536);
    }
    // Two radix passes recover the exact four order statistics, including
    // duplicates. Histogram sizes are independent of the number of frames.
    scan(path, count, [&](const float* values, std::size_t size) {
        for (std::size_t p = 0; p < size; ++p) {
            const auto bits = key(values[p]);
            for (std::size_t i = 0; i < upper.size(); ++i) {
                if ((bits >> 16) == upper[i]) {
                    ++lower_counts[i][bits & 65535];
                }
            }
        }
    });
    std::array<float, 4> selected{};
    for (std::size_t i = 0; i < selected.size(); ++i) {
        const std::uint32_t bits = static_cast<std::uint32_t>((upper[i] << 16) | bucket(lower_counts[i], ranks[i]));
        std::memcpy(&selected[i], &bits, sizeof bits);
    }
    return {
        static_cast<float>(selected[0] + (selected[1] - selected[0]) * (low - std::floor(low))),
        static_cast<float>(selected[2] + (selected[3] - selected[2]) * (high - std::floor(high)))};
}
}

void depth_write_gray(const char* floats, const char* gray, std::size_t count) {
    const auto limits = percentiles(floats, count);
    std::ofstream output(std::filesystem::u8path(gray), std::ios::binary | std::ios::trunc);
    if (!output) {
        throw std::runtime_error("Cannot open gray output");
    }
    std::vector<unsigned char> buffer(std::min(count, chunk_values));
    scan(floats, count, [&](const float* values, std::size_t size) {
        for (std::size_t i = 0; i < size; ++i) {
            const float normalized = limits[1] > limits[0]
                ? std::clamp((values[i] - limits[0]) / (limits[1] - limits[0]), 0.f, 1.f) : 0;
            buffer[i] = static_cast<unsigned char>(std::nearbyint(std::pow(normalized, 1.25f) * 255.f));
        }
        if (!output.write(reinterpret_cast<const char*>(buffer.data()), size)) {
            throw std::runtime_error("Cannot write gray output");
        }
    });
    output.close();
    if (!output) {
        throw std::runtime_error("Cannot finish gray output");
    }
}
