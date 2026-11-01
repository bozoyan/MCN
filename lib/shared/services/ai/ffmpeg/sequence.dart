// 职责: 校验图片或视频分段输出模板并按连续编号展开有界目标文件名。
// 关联文件:
//   lib/shared/services/ai/ffmpeg/arguments.dart
//   lib/shared/services/ai/ffmpeg/command.dart
//   lib/shared/services/ai/ffmpeg/options.dart
import 'package:path/path.dart' as p;
import 'options.dart';

class FfmpegSequence {
  const FfmpegSequence(
    this.pattern,
    this.placeholder,
    this.width,
    this.start,
    this.limit, {
    this.segment = false,
  });
  final String pattern, placeholder;
  final int width, start, limit;
  final bool segment;

  String at(int offset) => pattern.replaceFirst(
    placeholder,
    '${start + offset}'.padLeft(width, '0'),
  );

  static bool hasPlaceholder(String path) => RegExp(r'%[0-9]*d').hasMatch(path);

  static FfmpegSequence? parse(
    String path, {
    required int? frames,
    required int? start,
    required String? format,
  }) {
    final syntax = p.Context(
      style: path.contains('\\') ? p.Style.windows : p.Style.posix,
    );
    final matches = RegExp(r'%(?:0([1-9]))?d').allMatches(path).toList();
    final segment = format == 'segment';
    if (matches.isEmpty) {
      if (hasPlaceholder(path) || start != null || segment) {
        throw const FormatException(
          'Use one %d or %0Nd placeholder (N=1..9) in a sequence output filename.',
        );
      }
      return null;
    }
    if (matches.length != 1 ||
        hasPlaceholder(syntax.dirname(path)) ||
        hasPlaceholder(path.replaceFirst(matches.single.group(0)!, ''))) {
      throw const FormatException(
        'Use one %d or %0Nd placeholder (N=1..9) in the output filename, not its directory.',
      );
    }
    final extensions = segment
        ? ffmpegSegmentExtensions
        : ffmpegImageSequenceExtensions;
    if (!extensions.contains(syntax.extension(path).toLowerCase())) {
      throw FormatException(
        '${segment ? 'Segment' : 'Image sequence'} output requires one of these extensions: ${extensions.join(', ')}.',
      );
    }
    if (!segment && format != null && format != 'image2') {
      throw const FormatException(
        'Image sequence output requires format image2.',
      );
    }
    if (!segment &&
        (frames == null || frames < 1 || frames > ffmpegMaxSequenceFrames)) {
      throw const FormatException(
        'Each image sequence requires -frames:v between 1 and 240 before its output path.',
      );
    }
    final limit = segment ? ffmpegMaxSegments : frames!;
    final first = start ?? (segment ? 0 : 1);
    if (first < 0 || first > 2147483647 - limit) {
      throw const FormatException(
        'Sequence numbering exceeds the supported range.',
      );
    }
    return FfmpegSequence(
      path,
      matches.single.group(0)!,
      int.parse(matches.single.group(1) ?? '0'),
      first,
      limit,
      segment: segment,
    );
  }
}
