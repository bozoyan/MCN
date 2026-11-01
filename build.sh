#!/usr/bin/env bash
# 串行构建当前宿主与工具链支持的平台；macOS / Android 复用现有打包流程。
# 用法: ./build.sh
# Linux / Web 可在 PLATFORMS 列表中取消注释启用。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

if [[ $# -ne 0 ]]; then
  echo "用法: ./build.sh（无需参数）" >&2
  exit 2
fi

command -v fvm >/dev/null 2>&1 || {
  echo "错误: 未找到 fvm，请先安装 FVM 和 .fvmrc 指定的 Flutter SDK。" >&2
  exit 1
}

case "$(uname -s)" in
  Darwin) HOST=macos ;;
  Linux) HOST=linux ;;
  MINGW*|MSYS*|CYGWIN*) HOST=windows ;;
  *) HOST=unknown ;;
esac

echo "==> 当前宿主: ${HOST}"

REASON=""
check_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    REASON="未找到 $1"
    return 1
  fi
}

check_platform() {
  local platform="$1"
  REASON=""
  case "$platform" in
    macos)
      [[ "$HOST" == macos ]] || { REASON="需要 macOS 宿主"; return 1; } ;;
    windows)
      [[ "$HOST" == windows ]] || { REASON="需要 Windows 宿主"; return 1; } ;;
    linux)
      [[ "$HOST" == linux ]] || { REASON="需要 Linux 宿主"; return 1; } ;;
  esac
  [[ -d "$platform" ]] || { REASON="缺少 $platform/ 项目目录"; return 1; }
  case "$platform" in
    macos)
      if ! xcodebuild -version >/dev/null 2>&1; then
        REASON="未找到可用的 Xcode"
        return 1
      fi
      check_command python3 || return 1
      check_command npm || return 1 ;;
    windows)
      check_command powershell.exe || return 1
      local program_files vswhere installation
      program_files="$(printenv 'ProgramFiles(x86)' || true)"
      vswhere="${program_files}/Microsoft Visual Studio/Installer/vswhere.exe"
      if [[ ! -f "$vswhere" ]]; then
        REASON="未找到 Visual Studio Installer 的 vswhere.exe"
        return 1
      fi
      installation="$("$vswhere" -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath)"
      if [[ -z "$installation" ]]; then
        REASON="未找到 Visual Studio C++ 构建工具"
        return 1
      fi ;;
    linux)
      local tool
      for tool in clang++ cmake ninja pkg-config; do
        check_command "$tool" || return 1
      done
      if ! pkg-config --exists gtk+-3.0; then
        REASON="未找到 GTK 3 开发库"
        return 1
      fi ;;
    android)
      check_command python3 || return 1
      local sdk local_sdk
      local_sdk=""
      if [[ -f android/local.properties ]]; then
        local_sdk="$(sed -n 's/^sdk\.dir=//p' android/local.properties | tr -d '\r')"
        local_sdk="${local_sdk//\\:/:}"
        local_sdk="${local_sdk//\\\\/\\}"
      fi
      # 只检查本地 SDK，不调用 sdkmanager 检查许可证或访问网络。
      for sdk in "${ANDROID_HOME:-}" "${ANDROID_SDK_ROOT:-}" "$local_sdk" \
        "$HOME/Library/Android/sdk" "$HOME/Android/Sdk" "${LOCALAPPDATA:-}/Android/Sdk"; do
        if [[ -n "$sdk" && -d "$sdk/platforms" && -d "$sdk/build-tools" ]]; then
          return 0
        fi
      done
      REASON="未找到 Android SDK 的 platforms / build-tools；请配置 ANDROID_HOME"
      return 1 ;;
    web)
      # Web 编译无需安装 Chrome；以 SDK 是否提供 web 构建命令为准。
      if ! fvm flutter build web --help >/dev/null 2>&1; then
        REASON="Flutter 未启用 Web 构建"
        return 1
      fi ;;
  esac
}

build_windows() {
  powershell.exe -NoProfile -ExecutionPolicy Bypass \
    -File "$SCRIPT_DIR/third/depth-native/prepare-product-windows.ps1" || return $?
  fvm flutter build windows --release
}

SUCCEEDED=0
SKIPPED=0
FAILED=0
PLATFORMS=(
  macos
  windows
  # linux
  android
  # web
)
for platform in "${PLATFORMS[@]}"; do
  if ! check_platform "$platform"; then
    echo "[跳过] $platform: $REASON"
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  case "$platform" in
    macos) COMMAND=(bash "$SCRIPT_DIR/build-macos.sh") ;;
    windows) COMMAND=(build_windows) ;;
    android) COMMAND=(bash "$SCRIPT_DIR/build-android.sh") ;;
    *) COMMAND=(fvm flutter build "$platform" --release) ;;
  esac
  printf '\n==> %s:' "$platform"
  printf ' %q' "${COMMAND[@]}"
  printf '\n'
  if "${COMMAND[@]}"; then
    echo "[成功] $platform"
    SUCCEEDED=$((SUCCEEDED + 1))
  else
    status=$?
    echo "[失败] $platform: 退出码 $status" >&2
    FAILED=$((FAILED + 1))
  fi
done

printf '\n'
echo "构建完成: 成功 ${SUCCEEDED}，跳过 ${SKIPPED}，失败 ${FAILED}。"
[[ "$FAILED" -eq 0 && "$SUCCEEDED" -gt 0 ]]
