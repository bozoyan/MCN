# FFmpegKit desktop integration

Source: https://pub.dev/packages/ffmpeg_kit_flutter_new/versions/4.6.7.
The upstream license is retained in `ffmpeg_kit_flutter_new/LICENSE`.

The Dart API and native Windows/macOS implementations are unchanged. The local pubspec registers only Windows and macOS, so Android/iOS do not build or bundle the production codecs. Native FFmpeg remains the upstream 8.1.2 Full-GPL build; no codec/filter trimming is applied.

FVP uses these same libraries for desktop playback. When upgrading, update/check the ABI map in `runtime.dart` and run native playback/encoding tests plus the packaging audit. Keep native artifacts in build caches, not source control.

Windows callback-thread behavior was checked against `windows/src/FFmpegKitConfig.cpp` in https://github.com/sk3llo/ffmpeg-kit/tree/windows-8.1.2, the exact source named in the native bundle NOTICE. The Windows DLL does not export the callback function used by Apple.
