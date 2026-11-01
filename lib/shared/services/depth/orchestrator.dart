// 职责: 编排深度任务的媒体探测、解码、推理与保留时间线的灰度视频编码。
// 关联文件:
//   lib/shared/services/depth/native_runner.dart
//   lib/shared/services/depth/timeline.dart
//   lib/shared/services/production/ffmpeg_runner.dart
//   lib/shared/services/production/media_service.dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import '../editing/disk_space.dart';
import '../production/ffmpeg_runner.dart';
import '../production/media_service.dart';
import 'model.dart';
import 'native_runner.dart';
import 'timeline.dart';

class DepthOrchestrator {
  Future<EncodedMedia> run({
    required String input,
    required File model,
    required Directory workspace,
    required FfmpegRunner ffmpeg,
    required DepthNativeRunner native,
    required MediaCancellation token,
    required DepthProgress progress,
  }) async {
    checkDepthCancellation(token);
    progress(DepthStage.decoding, null);
    final probe = await ffmpeg.execute(
      [
        '-v',
        'error',
        '-select_streams',
        'v:0',
        '-show_frames',
        '-show_streams',
        '-show_entries',
        'frame=best_effort_timestamp_time,pkt_duration_time,duration_time:frame_side_data=rotation:stream=width,height,start_time,duration:stream_side_data=rotation:stream_tags=rotate',
        '-of',
        'json',
        input,
      ],
      probe: true,
      cancellation: token,
    );
    final timeline = DepthTimeline.fromProbe(
      jsonDecode(probe) as Map<String, dynamic>,
    );
    final profile = DepthProfile.forVideo(timeline.width, timeline.height);
    if (editingFreeBytes(workspace.path) <
        profile.requiredBytes(timeline.frames, await File(input).length())) {
      throw const DepthException(DepthFailure.insufficient_space);
    }
    final rgb = File(p.join(workspace.path, 'input.rgb'));
    token.onProgress = (time) => progress(
      DepthStage.decoding,
      (time.inMicroseconds / timeline.durationUs).clamp(0, 1),
    );
    await ffmpeg.execute(
      [
        '-v',
        'error',
        '-y',
        '-i',
        input,
        '-map',
        '0:v:0',
        '-an',
        '-vf',
        'scale=${profile.width}:${profile.height}:flags=bicubic,setsar=1',
        '-vsync',
        '0',
        '-pix_fmt',
        'rgb24',
        '-f',
        'rawvideo',
        rgb.path,
      ],
      probe: false,
      cancellation: token,
    );
    if (await rgb.length() != timeline.frames * profile.pixels * 3) {
      throw const DepthException(DepthFailure.invalid_video);
    }
    token.onProgress = null;
    await native.run(
      model: model.path,
      workspace: workspace,
      profile: profile,
      frames: timeline.frames,
      cancellation: token,
      progress: progress,
    );
    checkDepthCancellation(token);
    progress(DepthStage.encoding, 0);
    final gray = await File(p.join(workspace.path, 'depth.gray')).open();
    final concat = File(p.join(workspace.path, 'frames.ffconcat'));
    final list = concat.openWrite();
    list.writeln('ffconcat version 1.0');
    final buffer = Uint8List(profile.pixels);
    try {
      for (var i = 0; i < timeline.frames; i++) {
        checkDepthCancellation(token);
        var offset = 0;
        while (offset < buffer.length) {
          final read = await gray.readInto(buffer, offset);
          if (read == 0) {
            throw const DepthException(DepthFailure.native_failed);
          }
          offset += read;
        }
        final frame = await File(
          p.join(workspace.path, '$i.pgm'),
        ).open(mode: FileMode.write);
        try {
          await frame.writeFrom(
            ascii.encode('P5\n${profile.width} ${profile.height}\n255\n'),
          );
          await frame.writeFrom(buffer);
        } finally {
          await frame.close();
        }
        final duration = i + 1 < timeline.frames
            ? timeline.timestamps[i + 1] - timeline.timestamps[i]
            : timeline.lastDurationUs;
        list.writeln(
          "file '$i.pgm'\noption framerate 1000000\nduration ${(duration / 1000000).toStringAsFixed(6)}",
        );
      }
    } finally {
      await gray.close();
      await list.close();
    }
    final output = File(p.join(workspace.path, 'depth.mp4'));
    token.onProgress = (time) => progress(
      DepthStage.encoding,
      (time.inMicroseconds / timeline.durationUs).clamp(0, 1),
    );
    try {
      await ffmpeg.execute(
        [
          '-v',
          'error',
          '-y',
          '-f',
          'concat',
          '-safe',
          '0',
          '-i',
          concat.path,
          '-an',
          '-vf',
          'scale=${timeline.width}:${timeline.height}:flags=bicubic,setsar=1',
          '-c:v',
          'libx264',
          '-preset',
          'fast',
          '-crf',
          '18',
          '-bf',
          '0',
          '-pix_fmt',
          timeline.width.isEven && timeline.height.isEven
              ? 'yuv420p'
              : 'yuv444p',
          '-vsync',
          '0',
          '-enc_time_base',
          '1:1000000',
          '-bsf:v',
          "setts=duration='if(eq(N,${timeline.frames - 1}),${timeline.lastDurationUs},DURATION)'",
          '-video_track_timescale',
          '1000000',
          '-movflags',
          '+faststart',
          output.path,
        ],
        probe: false,
        cancellation: token,
      );
      final info = await MediaService(
        ffmpeg,
      ).probe(output.path, cancellation: token);
      if (info.hasAudio ||
          !info.hasVideo ||
          info.width != timeline.width ||
          info.height != timeline.height ||
          info.frameCount != timeline.frames ||
          (info.duration.inMicroseconds - timeline.durationUs).abs() > 2000) {
        throw const DepthException(DepthFailure.invalid_video);
      }
      return EncodedMedia(output, info, workspace);
    } finally {
      token.onProgress = null;
    }
  }
}
