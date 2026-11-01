#!/usr/bin/env bash
#
# release.sh — 更新本地版本并创建 tag（可选创建 GitHub Release）
#
# 用法:
#   ./release.sh 1.2.3                            本地 commit + tag
#   ./release.sh 1.2.3 --github-release           push + 创建 GitHub Release
#   ./release.sh 1.2.3 --skip-tag                 本地 commit，不创建/检查 tag
#   ./release.sh 1.2.3+42 --dry-run
#   ./release.sh 1.2.3+42 --github-release --dry-run
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VERSION=""
DRY_RUN=""
GITHUB_RELEASE=false
SKIP_TAG=false

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN="--dry-run" ;;
    --github-release) GITHUB_RELEASE=true ;;
    --gh-release) GITHUB_RELEASE=true ;;
    --skip-tag) SKIP_TAG=true ;;
    --no-tag) SKIP_TAG=true ;;
    *) VERSION="$arg" ;;
  esac
done

if [[ -z "$VERSION" ]]; then
  echo "用法: $0 <version> [--github-release] [--skip-tag] [--dry-run]"
  echo "示例: $0 1.2.3+42"
  echo "      $0 1.2.3+42 --github-release"
  echo "      $0 1.2.3+42 --skip-tag"
  exit 1
fi

VERSION="${VERSION#v}"
TAG_VERSION="${VERSION%%+*}"
TAG="v$TAG_VERSION"

if [[ "$SKIP_TAG" == true && "$GITHUB_RELEASE" == true ]]; then
  echo "ERROR: --skip-tag 不能与 --github-release 同时使用。GitHub Release 必须绑定 tag。"
  exit 1
fi

run() {
  local desc="$1" cmd="$2"
  echo -e "\n==> $desc"
  echo "    $cmd"
  if [[ "$DRY_RUN" != "--dry-run" ]]; then
    eval "$cmd"
  fi
}

pushd "$SCRIPT_DIR" >/dev/null

existing_tag_target() {
  git rev-list -n 1 "$TAG" 2>/dev/null || true
}

# 检查分支
BRANCH="$(git rev-parse --abbrev-ref HEAD)"
if [[ "$BRANCH" != "unstable" ]]; then
  echo "WARNING: 当前在 '$BRANCH' 分支。release 应该从 unstable 创建。"
  read -r -p "继续? (y/N) " reply
  [[ "$reply" != "y" ]] && exit 1
fi

if [[ "$SKIP_TAG" != true ]]; then
  EXISTING_TAG_TARGET="$(existing_tag_target)"
  if [[ -n "$EXISTING_TAG_TARGET" ]]; then
    HEAD_COMMIT="$(git rev-parse HEAD)"
    if [[ "$EXISTING_TAG_TARGET" != "$HEAD_COMMIT" ]]; then
      echo "ERROR: tag ${TAG} 已存在，但不指向当前 HEAD。"
      echo "       ${TAG} -> $EXISTING_TAG_TARGET"
      echo "       HEAD -> $HEAD_COMMIT"
      exit 1
    fi
  fi
fi

run "更新 pubspec.yaml version 为 $VERSION" \
  "python3 -c \"
import re
with open('pubspec.yaml', 'r', encoding='utf-8') as f:
    c = f.read()
c = re.sub(r'^version:.*', 'version: $VERSION', c, flags=re.MULTILINE)
with open('pubspec.yaml', 'w', encoding='utf-8') as f:
    f.write(c)
print('Version set to $VERSION')
\""

run "更新 app_config.dart appVersion 为 $VERSION" \
  "sed -i '' \"s/const appVersion = '[^']*'/const appVersion = '$VERSION'/\" lib/shared/app_config.dart"

if [[ "$DRY_RUN" == "--dry-run" ]]; then
  run "git commit pubspec.yaml + app_config.dart" \
    "git add pubspec.yaml lib/shared/app_config.dart && git commit -m 'chore: bump version to $VERSION'"
else
  if git diff --quiet -- pubspec.yaml lib/shared/app_config.dart; then
    echo -e "\n==> pubspec.yaml + app_config.dart 已是 ${VERSION}，跳过 commit"
  else
    run "git commit pubspec.yaml + app_config.dart" \
      "git add pubspec.yaml lib/shared/app_config.dart && git commit -m 'chore: bump version to $VERSION'"
  fi
fi

if [[ "$SKIP_TAG" == true ]]; then
  echo -e "\n==> 已启用 --skip-tag，跳过 tag ${TAG} 检查与创建"
elif [[ "$DRY_RUN" == "--dry-run" ]]; then
  run "git tag $TAG" \
    "git tag $TAG"
else
  EXISTING_TAG_TARGET="$(existing_tag_target)"
  if [[ -n "$EXISTING_TAG_TARGET" ]]; then
    HEAD_COMMIT="$(git rev-parse HEAD)"
    if [[ "$EXISTING_TAG_TARGET" == "$HEAD_COMMIT" ]]; then
      echo -e "\n==> tag ${TAG} 已存在且指向当前 HEAD，跳过创建"
    else
      echo "ERROR: tag ${TAG} 已存在，但不指向当前 HEAD。"
      echo "       ${TAG} -> $EXISTING_TAG_TARGET"
      echo "       HEAD -> $HEAD_COMMIT"
      exit 1
    fi
  else
    run "git tag $TAG" \
      "git tag $TAG"
  fi
fi

if [[ "$GITHUB_RELEASE" == true ]]; then
  command -v gh >/dev/null 2>&1 || { echo "ERROR: 未找到 gh CLI (https://cli.github.com/)"; exit 1; }

  run "git push origin $BRANCH" \
    "git push origin $BRANCH"

  run "git push origin $TAG" \
    "git push origin $TAG"

  run "创建 GitHub Release ${TAG}" \
    "gh release create $TAG --title '$TAG' --generate-notes --verify-tag"
fi

popd >/dev/null
if [[ "$GITHUB_RELEASE" == true ]]; then
  echo -e "\n==> 完成！Release ${TAG} 已创建，CI 将自动打包。"
elif [[ "$SKIP_TAG" == true ]]; then
  echo -e "\n==> 完成！本地已 commit，已跳过 tag ${TAG}。"
else
  echo -e "\n==> 完成！本地已 commit 并创建 tag ${TAG}。用 --github-release 推送并创建 Release:"
  echo "    $0 $VERSION --github-release"
fi
