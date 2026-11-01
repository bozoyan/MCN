# Video Player Dart API

Source: https://pub.dev/packages/video_player/versions/2.14.1 (BSD-3-Clause).
The Dart library is unchanged. The local pubspec removes endorsed platform plugin declarations and dependencies: playback is provided solely by the desktop FVP backend. This prevents unused Android/iOS players from entering the application through FVP's transitive dependency.

Keep the Dart sources/version synchronized on upgrade; retain the dependency boundary.
