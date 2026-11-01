// Window selection and alignment follow Video Depth Anything, Apache-2.0:
// https://github.com/DepthAnything/Video-Depth-Anything/tree/4f5ae23172ba60fd7bc11ef671cca678842c7072
#include "depth.h"
#include "depth_io.h"
#include <onnxruntime_cxx_api.h>
#include <algorithm>
#include <array>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>
#include <unordered_map>

namespace {
constexpr int window = 32, overlap = 10, step = 22, blend = 8;
constexpr std::array<int, overlap> keys{0, 12, 24, 25, 26, 27, 28, 29, 30, 31};
using Frame = std::vector<float>;

void run(const char* model_path, const char* rgb_path, const char* float_path,
         const char* gray_path, int width, int height, int count, int provider) {
    if (!model_path || !rgb_path || !float_path || !gray_path || width <= 0 || height <= 0 ||
        width > 960 || height > 960 || width * height > 141120 || width % 14 || height % 14 || count < 1 || count > 10000000)
        throw std::runtime_error("Invalid arguments: dimensions must be multiples of 14 within 141120 pixels; frames 1..10000000");
    if (provider != 0 && provider != 1) throw std::runtime_error("Unknown execution provider");
    // Avoid accidental overwrite through the validation interface.
    const std::array<std::filesystem::path, 4> paths{std::filesystem::u8path(model_path), std::filesystem::u8path(rgb_path), std::filesystem::u8path(float_path), std::filesystem::u8path(gray_path)};
    for (size_t i = 0; i < paths.size(); ++i)
        for (size_t j = i + 1; j < paths.size(); ++j)
            if (std::filesystem::weakly_canonical(paths[i]) == std::filesystem::weakly_canonical(paths[j]))
                throw std::runtime_error("Model, input and outputs must be different files");
    const auto started = std::chrono::steady_clock::now();
    const size_t pixels = static_cast<size_t>(width) * height;
    const size_t frame_values = pixels * 3;
    std::ifstream input(std::filesystem::u8path(rgb_path), std::ios::binary | std::ios::ate);
    if (!input || input.tellg() != static_cast<std::streamoff>(count * frame_values))
        throw std::runtime_error("RGB file size does not match dimensions and frame count");
    std::vector<unsigned char> rgb(frame_values);
    std::ofstream float_output(std::filesystem::u8path(float_path), std::ios::binary | std::ios::trunc);
    if (!float_output) {
        throw std::runtime_error("Cannot open depth output");
    }

    Ort::Env env(ORT_LOGGING_LEVEL_WARNING, "reveric-depth-native");
    Ort::SessionOptions options;
    options.SetIntraOpNumThreads(4);
    options.SetGraphOptimizationLevel(GraphOptimizationLevel::ORT_ENABLE_ALL);
    const char* profile = std::getenv("DEPTH_PROFILE");
    if (profile && *profile) {
        options.EnableProfiling(std::filesystem::path(profile).c_str());
    }
    if (provider == 1) {
        std::unordered_map<std::string, std::string> coreml{
            {"ModelFormat", "MLProgram"}, {"MLComputeUnits", "ALL"},
            {"RequireStaticInputShapes", "1"}};
        if (const char* cache = std::getenv("DEPTH_COREML_CACHE"); cache && *cache) {
            coreml["ModelCacheDirectory"] = cache;
        }
        if (const char* units = std::getenv("DEPTH_COREML_COMPUTE"); units && *units) {
            coreml["MLComputeUnits"] = units;
        }
        if (std::getenv("DEPTH_COREML_PLAN")) {
            coreml["ProfileComputePlan"] = "1";
            options.SetLogSeverityLevel(0);
        }
        options.AppendExecutionProvider("CoreML", coreml);
    }
    const auto session_started = std::chrono::steady_clock::now();
    std::cout << "{\"stage\":\"inference\",\"progress\":0}" << std::endl;
    Ort::Session session(env, std::filesystem::u8path(model_path).c_str(), options);
    const double session_seconds = std::chrono::duration<double>(std::chrono::steady_clock::now() - session_started).count();
    std::cerr << "session ready seconds=" << session_seconds << '\n';
    const std::array<int64_t, 5> shape{1, window, 3, height, width};
    const auto model_shape = session.GetInputTypeInfo(0).GetTensorTypeAndShapeInfo().GetShape();
    if (model_shape.size() != shape.size())
        throw std::runtime_error("Model input shape differs from the supplied RGB profile");
    for (size_t i = 0; i < shape.size(); ++i) {
        if (model_shape[i] != shape[i] && !(i >= 3 && model_shape[i] == -1))
            throw std::runtime_error("Model input shape differs from the supplied RGB profile");
    }
    auto memory = Ort::MemoryInfo::CreateCpu(OrtArenaAllocator, OrtMemTypeDefault);
    Frame tensor(window * frame_values), previous(overlap * frame_values);
    bool have_previous = false;
    std::vector<Frame> aligned;
    std::array<Frame, 2> reference;
    const std::array<float, 3> mean{.485f, .456f, .406f}, stddev{.229f, .224f, .225f};
    const char* inputs[]{"frames"};
    const char* outputs[]{"depth"};
    double first_run_seconds = 0, inference_seconds = 0;
    int written = 0;
    auto emit = [&](const Frame& frame) {
        if (written == count) {
            return;
        }
        if (!float_output.write(reinterpret_cast<const char*>(frame.data()), frame.size() * sizeof(float))) {
            throw std::runtime_error("Cannot write depth output");
        }
        ++written;
    };
    for (int start = 0; start < count; start += step) {
        for (int t = 0; t < window; ++t) {
            if (have_previous && t < overlap) {
                std::copy_n(previous.data() + t * frame_values, frame_values, tensor.data() + t * frame_values);
                continue;
            }
            const auto source = std::min(start + t, count - 1) * frame_values;
            input.seekg(static_cast<std::streamoff>(source));
            if (!input.read(reinterpret_cast<char*>(rgb.data()), rgb.size())) {
                throw std::runtime_error("Cannot read RGB input frame");
            }
            for (int c = 0; c < 3; ++c)
                for (size_t p = 0; p < pixels; ++p)
                    tensor[t * frame_values + c * pixels + p] = (rgb[p * 3 + c] / 255.f - mean[c]) / stddev[c];
        }
        auto value = Ort::Value::CreateTensor<float>(memory, tensor.data(), tensor.size(), shape.data(), shape.size());
        const auto run_started = std::chrono::steady_clock::now();
        auto result = session.Run(Ort::RunOptions{nullptr}, inputs, &value, 1, outputs, 1);
        const double run_seconds = std::chrono::duration<double>(std::chrono::steady_clock::now() - run_started).count();
        inference_seconds += run_seconds;
        if (start == 0) {
            first_run_seconds = run_seconds;
        }
        if (result[0].GetTensorTypeAndShapeInfo().GetShape() != std::vector<int64_t>{1, window, height, width})
            throw std::runtime_error("Unexpected model output shape");
        const float* raw = result[0].GetTensorData<float>();
        std::vector<Frame> depths;
        for (int t = 0; t < window; ++t) depths.emplace_back(raw + t * pixels, raw + (t + 1) * pixels);
        if (!have_previous) {
            reference = {depths[0], depths[12]};
            aligned = std::move(depths);
        } else {
            // Fit scale/shift using the two anchor frames. Double accumulation
            // avoids cancellation in the normal equations; outputs remain float32.
            double aa = 0, a = 0, ab = 0, b = 0, n = 2 * pixels;
            for (int k = 0; k < 2; ++k)
                for (size_t p = 0; p < pixels; ++p) {
                    double x = depths[k][p], y = reference[k][p];
                    aa += x * x; a += x; ab += x * y; b += y;
                }
            const double det = aa * n - a * a;
            const float scale = det != 0 ? static_cast<float>((n * ab - a * b) / det) : 1;
            const float shift = det != 0 ? static_cast<float>((aa * b - a * ab) / det) : 0;
            for (auto& frame : depths)
                for (float& value : frame) value = std::max(0.f, value * scale + shift);
            for (int k = 0; k < blend; ++k) {
                const float weight = k / static_cast<float>(blend - 1);
                auto& before = aligned[aligned.size() - blend + k];
                for (size_t p = 0; p < pixels; ++p) before[p] = before[p] * (1 - weight) + depths[k + 2][p] * weight;
            }
            reference[1] = depths[12];
            for (int k = overlap; k < window; ++k) {
                aligned.push_back(std::move(depths[k]));
            }
        }
        // Only the final eight predictions can change in the next window.
        const auto ready = aligned.size() - blend;
        for (size_t i = 0; i < ready; ++i) {
            emit(aligned[i]);
        }
        aligned.erase(aligned.begin(), aligned.begin() + ready);
        for (int t = 0; t < overlap; ++t) {
            std::copy_n(tensor.data() + keys[t] * frame_values, frame_values, previous.data() + t * frame_values);
        }
        have_previous = true;
        std::cerr << "window " << start / step + 1 << '/' << (count + step - 1) / step << " seconds=" << run_seconds << '\n';
        std::cout << "{\"stage\":\"inference\",\"progress\":"
                  << static_cast<double>(start / step + 1) / ((count + step - 1) / step) << "}" << std::endl;
    }
    for (const auto& frame : aligned) {
        emit(frame);
    }
    float_output.close();
    if (!float_output || written != count) {
        throw std::runtime_error("Depth output is incomplete");
    }
    if (profile && *profile) {
        Ort::AllocatorWithDefaultOptions allocator;
        auto path = session.EndProfilingAllocated(allocator);
        std::cerr << "profile=" << path.get() << '\n';
    }
    session = Ort::Session{nullptr};
    Frame().swap(tensor);
    Frame().swap(previous);
    std::vector<Frame>().swap(aligned);
    reference = {};
    std::cout << "{\"stage\":\"mapping\",\"progress\":0}" << std::endl;
    depth_write_gray(float_path, gray_path, static_cast<size_t>(count) * pixels);
    const auto seconds = std::chrono::duration<double>(std::chrono::steady_clock::now() - started).count();
    std::cout << "{\"frames\":" << count << ",\"seconds\":" << seconds
              << ",\"session_seconds\":" << session_seconds
              << ",\"inference_seconds\":" << inference_seconds
              << ",\"first_run_seconds\":" << first_run_seconds
              << ",\"provider\":" << provider << ",\"streaming\":true}\n";
}
}

int depth_run(const char* model, const char* rgb, const char* floats, const char* gray,
              int width, int height, int frames, int provider, char* error, size_t capacity) {
    if (error && capacity) error[0] = 0;
    try {
        run(model, rgb, floats, gray, width, height, frames, provider);
        return 0;
    } catch (const std::exception& failure) {
        if (error && capacity) std::snprintf(error, capacity, "%s", failure.what());
        return 1;
    } catch (...) {
        if (error && capacity) std::snprintf(error, capacity, "Unknown native failure");
        return 2;
    }
}
