#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <string>
#include <windows.h>

#include "flutter_window.h"
#include "crash_handler.h"
#include "resource.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // 最先安装原生崩溃处理器：引擎 / Win32 层面的致命异常会绕过所有 Dart 错误
  // 处理，必须在这里把 minidump 与摘要落盘，下次启动才能看到崩溃现场。
  crash_handler::Install();

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");
  project.set_enable_flutter_gpu(true);
  project.set_impeller_switch(flutter::ImpellerSwitch::Enabled);

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  std::wstring app_title = L"Reveric";
  wchar_t title_buffer[128] = {};
  if (::LoadStringW(instance, IDS_APP_TITLE, title_buffer,
                    ARRAYSIZE(title_buffer)) > 0) {
    app_title = title_buffer;
  }
  if (!window.Create(app_title.c_str(), origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  // 能走到这里即为正常退出（窗口关闭驱动消息循环结束）：删除会话哨兵。
  // 崩溃 / 强杀不会执行到这里，marker 残留供下次启动识别异常终止。
  crash_handler::DeleteSessionMarker();

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
