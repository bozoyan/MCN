#ifndef RUNNER_CRASH_HANDLER_H_
#define RUNNER_CRASH_HANDLER_H_

#include <string>

// 原生崩溃捕获：Dart 层的 FlutterError / PlatformDispatcher 无法感知引擎与
// Win32 层面的致命异常，进程直接消失且无任何日志。这里在 wWinMain 最前面安装
// 未处理异常过滤器与 SIGABRT handler，把 minidump 与可读摘要写入崩溃目录，
// 供下次启动时由 Dart 侧扫描上报；同时在进程正常退出时清理 Dart 写入的
// 会话哨兵文件（崩溃哨兵方案的原生侧兜底）。
namespace crash_handler {

// 解析崩溃转储目录（%APPDATA%\<ProductName>\crashes，与 Dart path_provider 的
// Application Support 目录算法一致），创建目录并安装崩溃处理器。
// 必须在创建任何窗口 / 引擎之前调用。
void Install();

// 返回崩溃转储目录（Install 之后有效）。
std::wstring GetCrashDumpDirectory();

// 记录 Dart 侧会话哨兵文件路径，供正常退出时删除。
void SetSessionMarkerPath(const std::wstring& path, const std::string& session_token);

// 仅记录诊断，不改变窗口关闭或关机的处理结果。
void RecordExitRequested(const char* source);
void CancelSystemExit();

// 删除会话哨兵文件；仅在正常退出路径（消息循环结束）调用。
// 只清理当前会话；删除失败保留错误码供下次启动诊断，不在退出路径抛错。
void DeleteSessionMarker();

}  // namespace crash_handler

#endif  // RUNNER_CRASH_HANDLER_H_
