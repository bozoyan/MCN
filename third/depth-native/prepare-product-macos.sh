#!/usr/bin/env bash
set -euo pipefail
depth_root=$(cd "$(dirname "$0")/../.." && pwd)
depth_work="$depth_root/build/depth-native"
mkdir -p "$depth_work"
depth_archive="$depth_work/onnxruntime-1.31.0.tgz"
if [ ! -f "$depth_archive" ]; then
  curl -fL --retry 2 --connect-timeout 30 --max-time 900 \
    https://github.com/microsoft/onnxruntime/releases/download/v1.31.0/onnxruntime-osx-arm64-1.31.0.tgz \
    -o "$depth_archive.part"
  printf '%s  %s\n' 1031b36dd3bdaa8d976a6130d9cf2a05e9be320b93ae804f8427b91dc3432afc "$depth_archive.part" | shasum -a 256 -c -
  mv "$depth_archive.part" "$depth_archive"
fi
printf '%s  %s\n' 1031b36dd3bdaa8d976a6130d9cf2a05e9be320b93ae804f8427b91dc3432afc "$depth_archive" | shasum -a 256 -c -
tar -xzf "$depth_archive" -C "$depth_work"
bash "$depth_root/third/depth-native/build-reduced-macos.sh"
python3 "$depth_root/third/depth-native/package_reduced.py" "$depth_work"
