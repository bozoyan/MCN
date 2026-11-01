#include "depth_io.h"
#include <algorithm>
#include <chrono>
#include <cmath>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <limits>
#include <random>
#include <stdexcept>
#include <vector>

namespace {
void save(const std::filesystem::path& path, const std::vector<float>& values) {
    std::ofstream out(path, std::ios::binary | std::ios::trunc);
    out.write(reinterpret_cast<const char*>(values.data()), values.size() * sizeof(float));
    if (!out) {
        throw std::runtime_error("Cannot create test input");
    }
}

void compare(const std::filesystem::path& directory, const std::vector<float>& values) {
    const auto input = directory / "input.f32", output = directory / "output.gray";
    save(input, values);
    depth_write_gray(input.string().c_str(), output.string().c_str(), values.size());
    auto sorted = values;
    std::sort(sorted.begin(), sorted.end());
    auto percentile = [&](double fraction) {
        const double index = (sorted.size() - 1) * fraction;
        const auto low = static_cast<std::size_t>(index), high = static_cast<std::size_t>(std::ceil(index));
        return static_cast<float>(sorted[low] + (sorted[high] - sorted[low]) * (index - low));
    };
    const float low = percentile(.02), high = percentile(.98);
    std::vector<unsigned char> actual(values.size());
    std::ifstream in(output, std::ios::binary);
    if (!in.read(reinterpret_cast<char*>(actual.data()), actual.size()) || in.peek() != EOF) {
        throw std::runtime_error("Wrong output size");
    }
    for (std::size_t i = 0; i < values.size(); ++i) {
        const float normalized = high > low ? std::clamp((values[i] - low) / (high - low), 0.f, 1.f) : 0;
        const auto expected = static_cast<unsigned char>(std::nearbyint(std::pow(normalized, 1.25f) * 255.f));
        if (actual[i] != expected) {
            throw std::runtime_error("Bounded-memory output differs from full-array percentile reference");
        }
    }
}

void rejects(const std::filesystem::path& directory, const std::vector<float>& values, std::size_t count) {
    const auto input = directory / "invalid.f32", output = directory / "invalid.gray";
    save(input, values);
    try {
        depth_write_gray(input.string().c_str(), output.string().c_str(), count);
    } catch (const std::runtime_error&) {
        return;
    }
    throw std::runtime_error("Invalid depth data was accepted");
}
}

int main() {
    const auto suffix = std::chrono::steady_clock::now().time_since_epoch().count();
    const auto directory = std::filesystem::temp_directory_path() / ("depth-io-test-" + std::to_string(suffix));
    if (!std::filesystem::create_directory(directory)) {
        return 1;
    }
    int result = 0;
    try {
        compare(directory, {0});
        compare(directory, {5});
        compare(directory, std::vector<float>(100, 3.f));
        compare(directory, {-0.f, 0.f, .001f, 1.f, 1000.f, std::numeric_limits<float>::denorm_min()});
        std::mt19937 random(4261);
        std::uniform_real_distribution<float> distribution(0.f, 100.f);
        std::vector<float> values(200003);
        for (auto& value : values) {
            value = distribution(random);
        }
        compare(directory, values);
        for (std::size_t i = 0; i < values.size(); ++i) {
            values[i] = static_cast<float>(i % 7);
        }
        compare(directory, values);
        rejects(directory, {}, 0);
        rejects(directory, {1, 2}, 3);
        rejects(directory, {1, -1}, 2);
        rejects(directory, {1, std::numeric_limits<float>::quiet_NaN()}, 2);
        rejects(directory, {1, std::numeric_limits<float>::infinity()}, 2);
        std::cout << "Exact normalization passed: constants, signed zero, subnormal, cross-chunk random/duplicates and malformed input\n";
    } catch (const std::exception& error) {
        std::cerr << error.what() << '\n';
        result = 1;
    }
    std::filesystem::remove_all(directory);
    return result;
}
