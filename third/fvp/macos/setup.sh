#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
version=0.39.0
sha=cc5a820c848ecd637d8c38e5a444ae489bbe95315de4a71884f2a8e52d63fc73
prepare_framework() {
  if [[ -f Frameworks/mdk.framework/mdk && -f Frameworks/.mdk-version ]] && [[ "$(cat Frameworks/.mdk-version)" == "$version:$sha" ]]; then
    return
  fi
  mkdir -p .cache Frameworks
  archive=".cache/mdk-sdk-$version.tar.xz"
  if [[ ! -f "$archive" ]]; then
    curl --fail --location --retry 3 "https://github.com/wang-bin/mdk-sdk/releases/download/v$version/mdk-sdk-macOS.tar.xz" -o "$archive.part"
    mv "$archive.part" "$archive"
  fi
  echo "$sha  $archive" | shasum -a 256 -c -
  staging=$(mktemp -d "$PWD/.cache/mdk.XXXXXX")
  tar -xf "$archive" -C "$staging"
  # MDK weak-links its optional FFmpeg runtime. Only FFmpegKit supplies FFmpeg.
  rsync -a --delete --delete-excluded --exclude 'libffmpeg*' --exclude '_CodeSignature' \
    "$staging/mdk-sdk/lib/mdk.framework/" Frameworks/mdk.framework/
  printf '%s' "$version:$sha" > Frameworks/.mdk-version
}

staging=''
spm_staging=''
trap '[[ -z "$staging" ]] || rm -rf "$staging"; [[ -z "$spm_staging" ]] || rm -rf "$spm_staging"' EXIT
prepare_framework

# SwiftPM consumes the same trimmed framework as CocoaPods. Prepare it before
# package resolution (make targets and CI call this script before Flutter).
spm_dir=fvp/Binaries
spm_key="$version:$sha:$(shasum -a 256 setup.sh | awk '{print $1}')"
if [[ -f "$spm_dir/mdk.xcframework.zip" && -f "$spm_dir/.mdk-version" ]] && \
   [[ "$(cat "$spm_dir/.mdk-version")" == "$spm_key" ]]; then
  exit 0
fi
mkdir -p .cache "$spm_dir"
spm_staging=$(mktemp -d "$PWD/.cache/mdk-spm.XXXXXX")
xcrun xcodebuild -create-xcframework \
  -framework "$PWD/Frameworks/mdk.framework" \
  -output "$spm_staging/mdk.xcframework"
ditto -c -k --sequesterRsrc --keepParent \
  "$spm_staging/mdk.xcframework" "$spm_staging/mdk.xcframework.zip"
mv "$spm_staging/mdk.xcframework.zip" "$spm_dir/mdk.xcframework.zip"
printf '%s' "$spm_key" > "$spm_dir/.mdk-version"
