#!/usr/bin/env bash
set -euo pipefail
# This path needs only the native binary, ONNX model and FFmpeg. No Python.
if [ "$#" -ne 2 ] && [ "$#" -ne 5 ]; then
  echo 'Usage: DEPTH_MODEL=MODEL.onnx bash third/depth-native/run-native.sh WORK_DIR INPUT_VIDEO [WIDTH HEIGHT MAX_FRAMES]' >&2
  exit 2
fi
depth_root=$(cd "$(dirname "$0")/../.." && pwd)
depth_binary="${DEPTH_NATIVE_BIN:-$depth_root/build/depth-native/native-macos/reveric-depth-native}"
depth_model="${DEPTH_MODEL:?Set DEPTH_MODEL to the ONNX model path}"
mkdir -p "$1"
depth_work=$(cd "$1" && pwd)
depth_input="$2"
depth_width="${3:-280}"
depth_height="${4:-280}"
depth_limit="${5:-48}"
ffmpeg -hide_banner -loglevel error -y -i "$depth_input" \
  -vf "fps=24,scale=$depth_width:$depth_height:force_original_aspect_ratio=increase,crop=$depth_width:$depth_height" \
  -frames:v "$depth_limit" -pix_fmt rgb24 -f rawvideo "$depth_work/input.rgb"
depth_bytes=$(wc -c < "$depth_work/input.rgb")
depth_frames=$((depth_bytes / (depth_width * depth_height * 3)))
/usr/bin/time -l "$depth_binary" "$depth_model" \
  "$depth_work/input.rgb" "$depth_work/native.f32" "$depth_work/native.gray" \
  "$depth_width" "$depth_height" "$depth_frames" 0 > "$depth_work/run.log" 2>&1
ffmpeg -hide_banner -loglevel error -y -f rawvideo -pixel_format gray \
  -video_size "${depth_width}x${depth_height}" -framerate 24 -i "$depth_work/native.gray" \
  -c:v libx264 -crf 18 -pix_fmt yuv420p -movflags +faststart "$depth_work/depth-preview.mp4"
ffmpeg -hide_banner -loglevel error -y -f rawvideo -pixel_format rgb24 \
  -video_size "${depth_width}x${depth_height}" -framerate 24 -i "$depth_work/input.rgb" \
  -i "$depth_work/depth-preview.mp4" -filter_complex '[0:v][1:v]hstack=inputs=2[v]' \
  -map '[v]' -c:v libx264 -crf 18 -pix_fmt yuv420p "$depth_work/comparison.mp4"
ffprobe -v error -count_frames -select_streams v:0 \
  -show_entries stream=width,height,nb_read_frames,avg_frame_rate:format=duration \
  -of json "$depth_work/depth-preview.mp4"
