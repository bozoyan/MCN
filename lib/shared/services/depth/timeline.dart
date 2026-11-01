// 职责: 从解码帧时间戳建立深度输出时间线，保留可变帧率与显示方向。
// 关联文件:
//   lib/shared/services/depth/orchestrator.dart
//   lib/shared/services/depth/model.dart
import 'model.dart';

class DepthTimeline {
  const DepthTimeline(
    this.width,
    this.height,
    this.timestamps,
    this.durationUs,
  );
  final int width, height, durationUs;
  final List<int> timestamps;
  int get frames => timestamps.length;
  int get lastDurationUs => durationUs - timestamps.last;

  factory DepthTimeline.fromProbe(Map<String, dynamic> json) {
    Never invalid() => throw const DepthException(DepthFailure.invalid_video);
    final streams = (json['streams'] as List?)?.cast<Map<String, dynamic>>();
    final frames = (json['frames'] as List?)?.cast<Map<String, dynamic>>();
    if (streams == null ||
        streams.isEmpty ||
        frames == null ||
        frames.isEmpty) {
      invalid();
    }
    final video = streams.first;
    var width = video['width'] as int? ?? 0;
    var height = video['height'] as int? ?? 0;
    if (width <= 0 || height <= 0) {
      invalid();
    }
    // FFmpegKit's probe may expose the display matrix on decoded frames rather
    // than the deprecated AVStream side-data fields.
    final side = [
      ...((video['side_data_list'] as List?) ?? []),
      ...((frames.first['side_data_list'] as List?) ?? []),
    ];
    final rotation = side
        .cast<Map>()
        .where((value) => value.containsKey('rotation'))
        .firstOrNull?['rotation'];
    final angle =
        (rotation as num?)?.round() ??
        int.tryParse('${(video['tags'] as Map?)?['rotate']}') ??
        0;
    if (angle % 90 != 0) {
      invalid();
    }
    if (angle.abs() % 180 == 90) {
      final old = width;
      width = height;
      height = old;
    }
    final raw = <int>[];
    for (final frame in frames) {
      final value = double.tryParse('${frame['best_effort_timestamp_time']}');
      if (value == null || !value.isFinite) {
        invalid();
      }
      final us = (value * 1000000).round();
      if (raw.isNotEmpty && us <= raw.last) {
        invalid();
      }
      raw.add(us);
    }
    final start = raw.first;
    final times = raw.map((time) => time - start).toList(growable: false);
    final last = frames.last;
    final packet = double.tryParse(
      '${last['duration_time'] ?? last['pkt_duration_time']}',
    );
    final streamDuration = double.tryParse('${video['duration']}');
    final streamStart = double.tryParse('${video['start_time']}');
    var tail = packet != null && packet > 0 ? (packet * 1000000).round() : 0;
    if (streamDuration != null && streamStart != null) {
      final end = ((streamStart + streamDuration) * 1000000).round() - start;
      if (end > times.last) {
        tail = end - times.last;
      }
    }
    if (tail <= 0) {
      if (times.length < 2) {
        invalid();
      }
      tail = times.last - times[times.length - 2];
    }
    return DepthTimeline(width, height, times, times.last + tail);
  }
}
