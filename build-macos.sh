#!/usr/bin/env bash
#
# build-macos.sh — 本地构建 Reveric macOS 安装包 (DMG + ZIP)
#
# 镜像 CI (.github/workflows/build.yaml) 的 macOS 打包流程：
#   1. 安装 appdmg (npm)
#   2. 禁用 pubspec.yaml sqlite3 hooks
#   3. fvm flutter pub get
#   4. 构建 FJS runtime (fjs.xcframework)
#   5. fastforge 构建 dmg 安装包 + zip 归档
#   6. 还原 pubspec.yaml
#
# 用法:
#   ./build-macos.sh
#   ./build-macos.sh 1.2.3+42
#   ./build-macos.sh --skip-install-tools
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BACKUP="$SCRIPT_DIR/pubspec.yaml.bak"
VERSION="${1:-}"
SKIP_INSTALL=false
FASTFORGE_VERSION="0.6.6"

if [[ "${1:-}" == "--skip-install-tools" ]]; then
  SKIP_INSTALL=true
  VERSION="${2:-}"
fi

cd "$SCRIPT_DIR"

info()  { echo -e "\n==> $*" >&2; }
ok()    { echo "==> $*" >&2; }
err()   { echo "==> ERROR: $*" >&2; exit 1; }

cleanup() {
  if [[ -f "$BACKUP" ]]; then
    info "还原 pubspec.yaml..."
    mv "$BACKUP" "$SCRIPT_DIR/pubspec.yaml"
    ok "pubspec.yaml 已还原"
  fi
}
trap cleanup EXIT

# ----- 前置检查 -----
info "检查前置依赖..."

command -v fvm     >/dev/null 2>&1 || err "未找到 fvm，请先安装 FVM 以使用项目 .fvmrc 固定的 Flutter SDK"
command -v python3 >/dev/null 2>&1 || err "未找到 python3"
command -v npm     >/dev/null 2>&1 || err "未找到 npm"

# 所有本地构建都通过 FVM 解析 .fvmrc，避免误用 PATH 中的其他 Flutter 版本。
FLUTTER=(fvm flutter)
DART=(fvm dart)
"${FLUTTER[@]}" --version >/dev/null

# 与 CI 一样重新解析固定 Fastforge 版本的传递依赖，避免复用旧的
# flutter_app_builder（0.6.0 会向新版 Flutter 传入保留 dart-define）。
info "安装/刷新 fastforge $FASTFORGE_VERSION..."
"${DART[@]}" pub global deactivate fastforge >/dev/null 2>&1 || true
"${DART[@]}" pub global activate fastforge "$FASTFORGE_VERSION"

# ----- 安装打包工具 (macOS) -----
if [[ "$SKIP_INSTALL" == false ]]; then
  info "安装/检查 appdmg..."
  if ! command -v appdmg >/dev/null 2>&1; then
    npm install -g appdmg
  else
    ok "appdmg 已安装"
  fi
else
  info "跳过工具安装"
fi

# ----- 备份 pubspec.yaml -----
info "备份 pubspec.yaml..."
cp "$SCRIPT_DIR/pubspec.yaml" "$BACKUP"

# ----- 设置版本号 -----
if [[ -n "$VERSION" ]]; then
  info "设置版本号为 $VERSION ..."
  python3 <<EOF
import re
with open('pubspec.yaml', 'r', encoding='utf-8') as f:
    content = f.read()
content = re.sub(r'^version:.*', 'version: $VERSION', content, flags=re.MULTILINE)
with open('pubspec.yaml', 'w', encoding='utf-8') as f:
    f.write(content)
print(f'Version set to $VERSION')
EOF
fi

# ----- 禁用 sqlite3 hooks -----
info "禁用 pubspec.yaml 中的 sqlite3 hooks..."
python3 <<EOF
with open('pubspec.yaml', 'r', encoding='utf-8') as f:
    lines = f.readlines()
in_hooks = False
with open('pubspec.yaml', 'w', encoding='utf-8') as f:
    for line in lines:
        if line.startswith('hooks:'):
            in_hooks = True
            f.write('# ' + line)
        elif in_hooks and (line.startswith('  ') or line.startswith('    ')):
            f.write('# ' + line)
        else:
            in_hooks = False
            f.write(line)
print('sqlite3 hooks disabled')
EOF

# ----- 清除 sqlite3 hook 缓存 -----
info "清除 sqlite3 hook 缓存..."
HOOK_CACHE="$SCRIPT_DIR/.dart_tool/hooks_runner/sqlite3"
if [[ -d "$HOOK_CACHE" ]]; then
  rm -rf "$HOOK_CACHE"
  ok "sqlite3 hook 缓存已清除"
fi

# ----- fvm flutter pub get -----
info "fvm flutter pub get..."
"${FLUTTER[@]}" pub get

# ----- 构建 FJS runtime -----
info "构建 FJS runtime (fjs.xcframework)..."
bash "$SCRIPT_DIR/third/fjs/tool/build_runtime.sh"
bash "$SCRIPT_DIR/third/fvp/macos/setup.sh"
bash "$SCRIPT_DIR/third/depth-native/prepare-product-macos.sh"

# ----- 清理旧产物 -----
info "清理旧 DMG 产物..."
find "$SCRIPT_DIR/dist" -name "*.dmg" -delete 2>/dev/null || true

# ----- 构建 DMG 安装包 -----
info "构建 macOS DMG 安装包 (fastforge macos-dmg)..."
fvm exec fastforge release --name release --jobs macos-dmg --skip-clean

# ----- 清理旧 ZIP 产物 -----
info "清理旧 ZIP 产物..."
find "$SCRIPT_DIR/dist" -name "*.zip" -delete 2>/dev/null || true

# ----- 构建 ZIP 归档 -----
info "构建 macOS ZIP 归档 (fastforge macos-zip)..."
fvm exec fastforge release --name release --jobs macos-zip --skip-clean

# ----- 输出 -----
echo ""
ok "macOS 安装包构建完成！"
echo ""
echo -e "\033[32m产物目录: dist/\033[0m"
if [[ -d "$SCRIPT_DIR/dist" ]]; then
  find "$SCRIPT_DIR/dist" \( -name "*.dmg" -o -name "*.zip" \) -exec echo "  {}" \;
fi
