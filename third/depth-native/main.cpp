#include "depth.h"
#include <cstdlib>
#include <iostream>
#include <thread>
#include <charconv>
#include <cstring>
#include <string>
#include <vector>
#ifdef _WIN32
#include <windows.h>
#endif

int execute(int argc, char** argv) {
    const bool job = argc == 10 && std::string(argv[1]) == "--job";
    if (job) {
        --argc;
        ++argv;
        // The pipe is owned by the host. EOF also terminates inference when the
        // host crashes or exits, so a model process cannot outlive the app.
        std::thread([] {
            std::string command;
            std::getline(std::cin, command);
            std::_Exit(130);
        }).detach();
    }
    if (argc != 9) {
        std::cerr << "Usage: reveric-depth-native MODEL RGB FLOATS GRAY WIDTH HEIGHT FRAMES PROVIDER\n";
        return 2;
    }
    char error[4096]{};
    int values[4]{};
    for (int i = 0; i < 4; ++i) {
        const char* end = argv[5 + i] + std::strlen(argv[5 + i]);
        const auto parsed = std::from_chars(argv[5 + i], end, values[i]);
        if (parsed.ec != std::errc{} || parsed.ptr != end || (job && i == 3 && values[i] != 0)) {
            std::cout << "{\"error\":\"invalid_arguments\"}" << std::endl;
            return 2;
        }
    }
    int result = depth_run(argv[1], argv[2], argv[3], argv[4], values[0],
                          values[1], values[2], values[3], error, sizeof error);
    if (result) std::cerr << error << '\n';
    if (job) std::cout << (result ? "{\"error\":\"inference_failed\"}" : "{\"stage\":\"complete\",\"progress\":1}") << std::endl;
    return result;
}

#ifdef _WIN32
int wmain(int argc, wchar_t** argv) {
    std::vector<std::string> utf8;
    for (int i = 0; i < argc; ++i) {
        int size = WideCharToMultiByte(CP_UTF8, 0, argv[i], -1, nullptr, 0, nullptr, nullptr);
        std::string value(size, '\0');
        WideCharToMultiByte(CP_UTF8, 0, argv[i], -1, value.data(), size, nullptr, nullptr);
        value.pop_back();
        utf8.push_back(std::move(value));
    }
    std::vector<char*> arguments;
    for (auto& value : utf8) arguments.push_back(value.data());
    return execute(argc, arguments.data());
}
#else
int main(int argc, char** argv) { return execute(argc, argv); }
#endif
