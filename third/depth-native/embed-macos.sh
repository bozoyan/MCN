#!/usr/bin/env bash
set -euo pipefail
depth_root=$(cd "$(dirname "$0")/../.." && pwd)
depth_sdk="${DEPTH_ORT_ROOT:-$depth_root/build/depth-native/ort-reduced-1.31.0/dist}"
if [ ! -f "$depth_sdk/lib/libonnxruntime.dylib" ]; then
  echo 'Depth SDK missing. Run bash third/depth-native/prepare-product-macos.sh before building.' >&2
  exit 1
fi
depth_build="$depth_root/build/depth-native/native-macos"
depth_destination="${1:-${TARGET_BUILD_DIR:?}/${UNLOCALIZED_RESOURCES_FOLDER_PATH:?}/depth}"
# This standalone process must match its ONNX SDK, which can have fewer slices
# than the host app. CMake expects a semicolon-separated architecture list.
depth_archs=$(lipo -archs "$depth_sdk/lib/libonnxruntime.dylib")
cmake -S "$depth_root/third/depth-native" -B "$depth_build" \
  -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=OFF -DORT_ROOT="$depth_sdk" \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=12.0 -DCMAKE_OSX_ARCHITECTURES="${depth_archs// /;}"
cmake --build "$depth_build" --parallel 4
cmake --install "$depth_build" --prefix "$depth_destination"
depth_identity="${EXPANDED_CODE_SIGN_IDENTITY:--}"
if [ -z "$depth_identity" ]; then depth_identity=-; fi
depth_sign_options=()
if [ "$depth_identity" != - ]; then depth_sign_options=(--options runtime); fi
for depth_file in "$depth_destination"/lib/*.dylib "$depth_destination/bin/reveric-depth-native"; do
  if [ ! -L "$depth_file" ]; then
    codesign --force --sign "$depth_identity" "${depth_sign_options[@]}" "$depth_file"
    codesign --verify --strict "$depth_file"
  fi
done
