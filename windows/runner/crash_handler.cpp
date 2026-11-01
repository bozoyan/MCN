#include "crash_handler.h"

#include <windows.h>

#include <dbghelp.h>
#include <process.h>
#include <shlobj.h>
#include <stdlib.h>

#include <atomic>
#include <cerrno>
#include <cstring>
#include <io.h>
#include <csignal>
#include <cstdio>
#include <string>
#include <vector>

namespace {

std::atomic<bool> g_crash_handled(false);
std::wstring g_crash_dump_dir;
std::wstring g_session_marker_path;
std::string g_session_token;
std::atomic<const char*> g_exit_source("none");
std::atomic<const char*> g_exit_phase("running");
std::atomic<unsigned long> g_dump_error(0);
std::atomic<unsigned long> g_summary_error(0);
std::atomic<unsigned long> g_marker_error(0);
std::atomic<unsigned long> g_exception_code(0);
std::atomic<const char*> g_dump_status("not_started");

bool OwnsSessionMarker() {
  if (g_session_marker_path.empty() || g_session_token.empty()) {
    return false;
  }
  HANDLE file = ::CreateFileW(g_session_marker_path.c_str(), GENERIC_READ,
      FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) {
    return false;
  }
  char data[4096] = {};
  DWORD read = 0;
  const bool ok = ::ReadFile(file, data, sizeof(data), &read, nullptr) != FALSE;
  ::CloseHandle(file);
  return ok && std::string(data, read).find(g_session_token) != std::string::npos;
}

// 独立快照避免在异常处理器中解析/重写 Dart marker；token 防止 PID 复用误关联。
void WriteNativeState() {
  if (!OwnsSessionMarker()) {
    return;
  }
  char data[1024] = {};
  const int length = snprintf(data, sizeof(data),
      "{\"pid\":%lu,\"session_token\":\"%s\",\"native_exit_source\":\"%s\","
      "\"native_exit_phase\":\"%s\",\"native_crash\":%s,\"dump_error\":%lu,\"summary_error\":%lu,\"marker_error\":%lu,\"dump_status\":\"%s\",\"exception_code\":\"0x%08lX\"}",
      ::GetCurrentProcessId(), g_session_token.c_str(), g_exit_source.load(), g_exit_phase.load(),
      g_crash_handled.load() ? "true" : "false", g_dump_error.load(), g_summary_error.load(), g_marker_error.load(), g_dump_status.load(), g_exception_code.load());
  if (length <= 0 || static_cast<size_t>(length) >= sizeof(data)) {
    return;
  }
  const std::wstring path = g_session_marker_path + L".native";
  HANDLE file = ::CreateFileW(path.c_str(), GENERIC_WRITE, FILE_SHARE_READ, nullptr, CREATE_ALWAYS,
      FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) {
    ::OutputDebugStringW(L"Reveric: cannot write native exit state\n");
    return;
  }
  DWORD written = 0;
  if (!::WriteFile(file, data, static_cast<DWORD>(length), &written, nullptr) ||
      written != static_cast<DWORD>(length) || !::FlushFileBuffers(file)) {
    ::OutputDebugStringW(L"Reveric: native exit state write/flush failed\n");
  }
  ::CloseHandle(file);
}

// 与 path_provider_windows 的 Application Support 目录算法保持一致：
// %APPDATA%\<ProductName>，ProductName 取自 exe 版本资源。
// 读取失败时回退 "Reveric"（与 Runner.rc 中的 ProductName 一致）。
std::wstring ReadProductName() {
  wchar_t module_path[MAX_PATH] = {};
  if (::GetModuleFileNameW(nullptr, module_path, MAX_PATH) == 0) {
    return L"Reveric";
  }
  DWORD handle = 0;
  const DWORD info_size = ::GetFileVersionInfoSizeW(module_path, &handle);
  if (info_size == 0) {
    return L"Reveric";
  }
  std::vector<BYTE> info(info_size);
  if (!::GetFileVersionInfoW(module_path, handle, info_size, info.data())) {
    return L"Reveric";
  }

  std::vector<DWORD> lang_codes;
  DWORD* translations = nullptr;
  UINT translations_size = 0;
  if (::VerQueryValueW(info.data(), L"\\VarFileInfo\\Translation",
                       reinterpret_cast<LPVOID*>(&translations),
                       &translations_size) &&
      translations != nullptr) {
    const UINT count = translations_size / sizeof(DWORD);
    for (UINT i = 0; i < count; ++i) {
      lang_codes.push_back(translations[i]);
    }
  }
  // 常见回退：en-US Unicode / en-US CP1252。
  lang_codes.push_back(0x040904B0);
  lang_codes.push_back(0x040904E4);

  for (const DWORD lang_code : lang_codes) {
    wchar_t sub_block[64] = {};
    swprintf(sub_block, 64, L"\\StringFileInfo\\%08lX\\ProductName", lang_code);
    wchar_t* value = nullptr;
    UINT value_size = 0;
    if (::VerQueryValueW(info.data(), sub_block,
                         reinterpret_cast<LPVOID*>(&value), &value_size) &&
        value != nullptr && value_size > 0) {
      return value;
    }
  }
  return L"Reveric";
}

std::wstring ResolveCrashDumpDirectory() {
  std::wstring base;
  PWSTR roaming = nullptr;
  if (SUCCEEDED(::SHGetKnownFolderPath(FOLDERID_RoamingAppData, KF_FLAG_DEFAULT,
                                       nullptr, &roaming)) &&
      roaming != nullptr) {
    base = roaming;
    ::CoTaskMemFree(roaming);
  } else {
    wchar_t temp_path[MAX_PATH] = {};
    const DWORD length = ::GetTempPathW(MAX_PATH, temp_path);
    base = length > 0 ? temp_path : L".";
  }
  return base + L"\\" + ReadProductName() + L"\\crashes";
}

// 把 minidump 与摘要 txt 写入崩溃目录。在崩溃 handler 内运行，只做最必要的
// 工作；重复进入（如 abort 级联）时只写第一份。
void WriteCrashReport(EXCEPTION_POINTERS* exception_pointers,
                      const char* kind) {
  if (g_crash_handled.exchange(true)) {
    return;
  }

  g_exception_code = exception_pointers != nullptr && exception_pointers->ExceptionRecord != nullptr
      ? exception_pointers->ExceptionRecord->ExceptionCode : 0;
  g_exit_phase = "crash_handler";
  WriteNativeState();

  const std::wstring dir =
      g_crash_dump_dir.empty() ? std::wstring(L".") : g_crash_dump_dir;

  SYSTEMTIME st = {};
  ::GetLocalTime(&st);
  wchar_t base_path[MAX_PATH] = {};
  swprintf(base_path, MAX_PATH, L"%ls\\crash_%04d%02d%02d_%02d%02d%02d_pid%lu",
           dir.c_str(), st.wYear, st.wMonth, st.wDay, st.wHour, st.wMinute,
           st.wSecond, ::GetCurrentProcessId());

  unsigned long exception_code = 0;
  void* exception_address = nullptr;
  std::wstring module_path;
  if (exception_pointers != nullptr &&
      exception_pointers->ExceptionRecord != nullptr) {
    exception_code = exception_pointers->ExceptionRecord->ExceptionCode;
    exception_address = exception_pointers->ExceptionRecord->ExceptionAddress;
    HMODULE module = nullptr;
    if (::GetModuleHandleExW(
            GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS |
                GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
            reinterpret_cast<LPCWSTR>(exception_address), &module) &&
        module != nullptr) {
      wchar_t path[MAX_PATH] = {};
      if (::GetModuleFileNameW(module, path, MAX_PATH) > 0) {
        module_path = path;
      }
    }
  }

  // 摘要 txt 采用 "key: value" 行格式（UTF-8），由 Dart 侧解析上报。
  const std::wstring txt_path = std::wstring(base_path) + L".txt";
  FILE* txt_file = nullptr;
  const int summary_error = _wfopen_s(&txt_file, txt_path.c_str(), L"w, ccs=UTF-8");
  g_summary_error = static_cast<unsigned long>(summary_error);
  if (summary_error == 0 && txt_file != nullptr) {
    fwprintf(txt_file, L"kind: %hs\n", kind);
    fwprintf(txt_file, L"timestamp: %04d-%02d-%02dT%02d:%02d:%02d (local)\n",
             st.wYear, st.wMonth, st.wDay, st.wHour, st.wMinute, st.wSecond);
    fwprintf(txt_file, L"pid: %lu\n", ::GetCurrentProcessId());
    fwprintf(txt_file, L"exception_code: 0x%08lX\n", exception_code);
    fwprintf(txt_file, L"exception_address: 0x%p\n", exception_address);
    fwprintf(txt_file, L"module: %ls\n",
             module_path.empty() ? L"" : module_path.c_str());
    // 先落最小异常摘要；即使后续 dump 写入卡住，仍保留异常码与模块。
    if (fflush(txt_file) != 0 || ferror(txt_file) || _commit(_fileno(txt_file)) != 0) {
      g_summary_error = static_cast<unsigned long>(errno);
    }
  }
  WriteNativeState();
  g_dump_status = "writing";
  WriteNativeState();
  const std::wstring dump_path = std::wstring(base_path) + L".dmp";
  bool dump_written = false;
  HANDLE dump_file =
      ::CreateFileW(dump_path.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_ALWAYS,
                    FILE_ATTRIBUTE_NORMAL, nullptr);
  if (dump_file != INVALID_HANDLE_VALUE) {
    MINIDUMP_EXCEPTION_INFORMATION exception_info = {};
    exception_info.ThreadId = ::GetCurrentThreadId();
    exception_info.ExceptionPointers = exception_pointers;
    exception_info.ClientPointers = FALSE;
    dump_written =
        ::MiniDumpWriteDump(
            ::GetCurrentProcess(), ::GetCurrentProcessId(), dump_file,
            static_cast<MINIDUMP_TYPE>(MiniDumpNormal | MiniDumpWithThreadInfo |
                                       MiniDumpWithUnloadedModules),
            exception_pointers != nullptr ? &exception_info : nullptr, nullptr,
            nullptr) != FALSE;
    if (!dump_written) {
      g_dump_error = ::GetLastError();
    }
    ::CloseHandle(dump_file);
  }
  if (dump_file == INVALID_HANDLE_VALUE) {
    g_dump_error = ::GetLastError();
  }
  g_dump_status = dump_written ? "written" : "failed";
  if (!dump_written) {
    // 避免留下 0 字节 dump 干扰 Dart 侧扫描。
    ::DeleteFileW(dump_path.c_str());
  }

  if (txt_file != nullptr) {
    fwprintf(txt_file, L"dump_file: %ls\n", dump_written ? dump_path.c_str() : L"");
    fwprintf(txt_file, L"dump_error: %lu\n", g_dump_error.load());
    if (fclose(txt_file) != 0) {
      g_summary_error = static_cast<unsigned long>(errno);
    }
  }
  WriteNativeState();
}

LONG WINAPI RevericUnhandledExceptionFilter(
    EXCEPTION_POINTERS* exception_pointers) {
  WriteCrashReport(exception_pointers, "unhandled_exception");
  return EXCEPTION_EXECUTE_HANDLER;
}

void RevericAbortHandler(int) {
  WriteCrashReport(nullptr, "abort");
  ::_exit(134);
}

}  // namespace

namespace crash_handler {

void Install() {
  g_crash_dump_dir = ResolveCrashDumpDirectory();
  ::SHCreateDirectoryExW(nullptr, g_crash_dump_dir.c_str(), nullptr);

  ::SetUnhandledExceptionFilter(&RevericUnhandledExceptionFilter);
  // 让 abort() 走我们的 SIGABRT handler 写 dump，而不是直接交给 WER。
  _set_abort_behavior(0, _WRITE_ABORT_MSG | _CALL_REPORTFAULT);
  std::signal(SIGABRT, &RevericAbortHandler);
}

std::wstring GetCrashDumpDirectory() { return g_crash_dump_dir; }

void SetSessionMarkerPath(const std::wstring& path, const std::string& session_token) {
  if (session_token.empty() ||
      session_token.find_first_not_of("0123456789-") != std::string::npos) {
    return;
  }
  g_session_marker_path = path;
  g_session_token = session_token;
  WriteNativeState();
}

void RecordExitRequested(const char* source) {
  if (std::strcmp(g_exit_source.load(), "system") == 0 &&
      std::strcmp(source, "window") == 0) {
    return;
  }
  g_exit_source = source;
  g_exit_phase = "requested";
  WriteNativeState();
}

void CancelSystemExit() {
  g_exit_source = "none";
  g_exit_phase = "running";
  WriteNativeState();
}

void DeleteSessionMarker() {
  if (!OwnsSessionMarker() || g_crash_handled.load()) {
    return;
  }
  g_exit_phase = "cleanup_completed";
  WriteNativeState();
  if (!::DeleteFileW(g_session_marker_path.c_str())) {
    g_exit_phase = "marker_delete_failed";
    g_marker_error = ::GetLastError();
    WriteNativeState();
  }
}

}  // namespace crash_handler
