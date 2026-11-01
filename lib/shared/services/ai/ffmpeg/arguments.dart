// 职责: 按输入输出作用域解析媒体处理参数并记录文件、滤镜与多文件输出依赖。
// 关联文件:
//   lib/shared/services/ai/ffmpeg/command.dart
//   lib/shared/services/ai/ffmpeg/options.dart
//   lib/shared/services/ai/ffmpeg/filters.dart
//   lib/shared/services/ai/ffmpeg/inputs.dart
import 'dart:convert';
import 'package:path/path.dart' as p;
import '../../../models/tool_permission.dart';
import 'sequence.dart';
import 'filters.dart';
import 'options.dart';
export 'options.dart';

class FfmpegArguments {
  FfmpegArguments._({
    required this.args,
    required this.inputs,
    required this.outputs,
    required this.sequences,
    required this.inputFormats,
    required this.inputStarts,
    required this.graphs,
    required this.probe,
    required this.pass,
    required this.passLogIndex,
    required this.nullOutputs,
    required this.fileInputs,
  });
  final List<String> args;
  final Map<int, String> inputs, outputs;
  final Map<int, FfmpegSequence> sequences;
  final Map<int, String> inputFormats;
  final Map<int, int> inputStarts;
  final Map<int, FfmpegFilterGraph> graphs;
  final Set<int> nullOutputs;
  final Map<int, String> fileInputs;
  final bool probe;
  final int? pass, passLogIndex;

  factory FfmpegArguments.parse(Object? raw, {required bool probe}) {
    if (raw is! List ||
        raw.isEmpty ||
        raw.length > ffmpegMaxArguments ||
        raw.any((v) => v is! String)) {
      throw const FormatException('args must contain 1..4096 strings');
    }
    final args = raw.cast<String>().toList();
    if (args.any((v) => v.contains('\u0000')) ||
        utf8.encode(args.join()).length > ffmpegMaxArgumentBytes) {
      throw const FormatException('args exceeds 256 KiB or contains NUL');
    }
    final inputs = <int, String>{}, outputs = <int, String>{};
    final inputFormats = <int, String>{};
    final inputStarts = <int, int>{}, graphs = <int, FfmpegFilterGraph>{};
    final sequences = <int, FfmpegSequence>{}, nullOutputs = <int>{};
    final fileInputs = <int, String>{};
    int? pass, passLogIndex;
    var passCount = 0;
    int? frames, startNumber, segmentStart;
    String? format, videoCodec;
    for (var index = 0; index < args.length; index++) {
      final token = args[index];
      if (token.isEmpty) {
        throw const FormatException('Missing argument name or output path.');
      }
      if (!token.startsWith('-') || token == '-') {
        if (probe) {
          localPath(token);
          inputs[index] = token;
          if (format != null) {
            inputFormats[index] = format;
          }
        } else if (format == 'null') {
          if (token != '-') {
            throw const FormatException(
              'Use -f null - for analysis without output.',
            );
          }
          nullOutputs.add(index);
        } else {
          localPath(token);
          if (!ffmpegOutputExtensions.contains(
            p.extension(token).toLowerCase(),
          )) {
            unsupported(token);
          }
          final sequence = FfmpegSequence.parse(
            token,
            frames: frames,
            start: format == 'segment' ? segmentStart : startNumber,
            format: format,
          );
          if (sequence != null) {
            sequences[index] = sequence;
          }
          outputs[index] = token;
        }
        frames = null;
        startNumber = null;
        segmentStart = null;
        format = null;
        continue;
      }
      final base = ffmpegOptionBase(token);
      if (probe
          ? ffmpegProbeFlags.contains(token)
          : ffmpegFlags.contains(token)) {
        continue;
      }
      if (probe
          ? !ffmpegProbeOptions.contains(base)
          : token != '-i' && !ffmpegValueOptions.contains(base)) {
        unsupported(token);
      }
      if (!RegExp(
        r'^-[A-Za-z0-9_-]+(?::[A-Za-z0-9_:+.?-]+)*$',
      ).hasMatch(token)) {
        unsupported(token);
      }
      if (++index >= args.length) {
        throw FormatException('Missing value for $token');
      }
      final value = args[index];
      if (value.isEmpty && base != '-metadata') {
        throw FormatException('Missing value for $token');
      }
      if (token == '-i') {
        localPath(value);
        inputs[index] = value;
        if (startNumber != null && !FfmpegSequence.hasPlaceholder(value)) {
          throw const FormatException(
            '-start_number requires an image sequence.',
          );
        }
        if (format != null) {
          inputFormats[index] = format;
        }
        if (startNumber != null) {
          inputStarts[index] = startNumber;
        }
        frames = null;
        startNumber = null;
        format = null;
      } else if (base == '-attach') {
        localPath(value);
        fileInputs[index] = value;
      } else if (base == '-dump_attachment') {
        localPath(value);
        if (FfmpegSequence.hasPlaceholder(value) ||
            p.extension(value).isEmpty) {
          throw const FormatException(
            'Attachment output requires a single filename with extension.',
          );
        }
        outputs[index] = value;
      } else if (base == '-frames' &&
          (token == '-frames:v' || token == '-frames:v:0')) {
        frames = int.tryParse(value);
        if (frames == null || frames < 1) {
          throw const FormatException('-frames:v must be a positive integer.');
        }
      } else if (base == '-start_number' || base == '-segment_start_number') {
        final start = int.tryParse(value);
        if (start == null || start < 0 || start > 2147483647) {
          throw const FormatException(
            'Start number must be a nonnegative 32-bit integer.',
          );
        }
        if (base == '-start_number') {
          startNumber = start;
        } else {
          segmentStart = start;
        }
      } else if (base == '-q') {
        final quality = double.tryParse(value);
        if (quality == null || !quality.isFinite) {
          throw const FormatException('Quality must be a finite number.');
        }
      } else if (base == '-fps_mode') {
        if (!ffmpegFpsModes.contains(value)) {
          throw const FormatException('Unsupported -fps_mode.');
        }
      } else if ({'-vf', '-af', '-filter', '-filter_complex'}.contains(base)) {
        graphs[index] = FfmpegFilterGraph(value);
      } else if (base == '-f' || base == '-segment_format') {
        if (!ffmpegFormats.contains(value)) {
          unsupported('$token $value');
        }
        if (base == '-f') {
          format = value;
        } else if ({'concat', 'segment', 'image2', 'null'}.contains(value)) {
          unsupported('$token $value');
        }
      } else if ({'-of', '-print_format'}.contains(base) && value != 'json') {
        unsupported('$token $value');
      } else if ({'-loglevel', '-v'}.contains(base)) {
        if (!{
          'quiet',
          'error',
          'warning',
          'info',
          'verbose',
          'debug',
        }.contains(value)) {
          unsupported('$token $value');
        }
      } else if ({'-c', '-codec'}.contains(base)) {
        if (!RegExp(r'^[A-Za-z0-9_]+$').hasMatch(value)) {
          unsupported(value);
        }
        if (token == '-c:v' || token == '-codec:v') {
          videoCodec = value;
        }
      } else if (base == '-pass') {
        passCount++;
        if (!{'1', '2'}.contains(value) ||
            (token != '-pass' && token != '-pass:v')) {
          throw const FormatException('Use -pass 1 or -pass 2.');
        }
        pass = int.parse(value);
      } else if (base == '-passlogfile') {
        localPath(value);
        if (token != '-passlogfile' ||
            passLogIndex != null ||
            FfmpegSequence.hasPlaceholder(value)) {
          throw const FormatException(
            'Use one pass log prefix without placeholders.',
          );
        }
        passLogIndex = index;
      } else if (base == '-map') {
        if (!RegExp(
          r'^(?:-?\d+(?::[A-Za-z0-9_:.-]+)*\??|\[[A-Za-z0-9_]+\])$',
        ).hasMatch(value)) {
          unsupported('$token $value');
        }
      } else if (base == '-x264-params' || base == '-x265-params') {
        _codecOptions(value);
      } else if (base == '-bsf') {
        _bitstreamFilters(value);
      } else if (base == '-pattern_type' && value != 'sequence') {
        unsupported('$token $value');
      } else if (base == '-safe' && !{'0', '1'}.contains(value)) {
        unsupported('$token $value');
      } else if (base == '-init_hw_device') {
        if (!RegExp(
          r'^(cuda|qsv|d3d11va|dxva2|videotoolbox|opencl|vulkan)(=[A-Za-z0-9_]+)?(?::[0-9.]+)?(@[A-Za-z0-9_]+)?$',
        ).hasMatch(value)) {
          unsupported('$token $value');
        }
      } else if ({'-hwaccel_device', '-filter_hw_device'}.contains(base)) {
        if (!RegExp(r'^[A-Za-z0-9_.-]+$').hasMatch(value)) {
          unsupported('$token $value');
        }
      } else if (value.contains('://') || value.startsWith('@/')) {
        unsupported(value);
      }
    }
    if ((probe && inputs.length != 1) ||
        inputs.isEmpty ||
        inputs.length > ffmpegMaxInputs ||
        (!probe && outputs.isEmpty && nullOutputs.isEmpty) ||
        outputs.length + nullOutputs.length > ffmpegMaxOutputs ||
        outputs.values.toSet().length != outputs.length ||
        outputs.values.any(inputs.values.contains)) {
      throw const FormatException(
        'Use up to 32 inputs and 16 distinct outputs; probe takes one file.',
      );
    }
    if (probe &&
        inputFormats.values.any(
          (v) => {'concat', 'segment', 'null'}.contains(v),
        )) {
      unsupported('probe input format');
    }
    if (sequences.values
            .where((s) => !s.segment)
            .fold<int>(0, (sum, s) => sum + s.limit) >
        ffmpegMaxSequenceFrames) {
      throw const FormatException(
        'Image sequences may request at most 240 images in total.',
      );
    }
    if (pass != null &&
        (passCount != 1 ||
            outputs.length + nullOutputs.length != 1 ||
            sequences.isNotEmpty ||
            videoCodec != 'libx264')) {
      throw const FormatException(
        'Pass encoding requires one libx264 output or null sink.',
      );
    }
    if (passLogIndex != null && pass == null) {
      throw const FormatException('-passlogfile requires -pass 1 or -pass 2.');
    }
    for (final graph in graphs.values) {
      for (final path in graph.dependencies) {
        localPath(path);
        if (FfmpegSequence.hasPlaceholder(path)) {
          unsupported('Filter dependencies must be individual files.');
        }
      }
    }
    return FfmpegArguments._(
      args: List.unmodifiable(args),
      inputs: Map.unmodifiable(inputs),
      outputs: Map.unmodifiable(outputs),
      sequences: Map.unmodifiable(sequences),
      inputFormats: Map.unmodifiable(inputFormats),
      inputStarts: Map.unmodifiable(inputStarts),
      graphs: Map.unmodifiable(graphs),
      probe: probe,
      pass: pass,
      passLogIndex: passLogIndex,
      nullOutputs: Set.unmodifiable(nullOutputs),
      fileInputs: Map.unmodifiable(fileInputs),
    );
  }

  static void _codecOptions(String value) {
    const allowed = {
      'keyint',
      'min-keyint',
      'scenecut',
      'bframes',
      'b-adapt',
      'ref',
      'aq-mode',
      'aq-strength',
      'psy-rd',
      'psy-rdoq',
      'rc-lookahead',
      'deblock',
      'sao',
      'strong-intra-smoothing',
      'open-gop',
      'repeat-headers',
      'annexb',
      'aud',
      'level-idc',
      'vbv-maxrate',
      'vbv-bufsize',
      'crf',
      'qp',
      'qcomp',
      'merange',
      'me',
      'subme',
      'weightp',
      'weightb',
      '8x8dct',
      'trellis',
      'fast-pskip',
      'no-scenecut',
      'pools',
      'frame-threads',
      'wpp',
      'pmode',
      'pme',
      'lossless',
      'hdr10',
      'hdr10-opt',
      'colorprim',
      'transfer',
      'colormatrix',
    };
    for (final item in value.split(':')) {
      final equal = item.indexOf('=');
      if (equal < 1 ||
          !allowed.contains(item.substring(0, equal)) ||
          !RegExp(r'^[A-Za-z0-9_.+,-]+$').hasMatch(item.substring(equal + 1))) {
        unsupported(
          'Codec private option must be a supported processing option.',
        );
      }
    }
  }

  static void _bitstreamFilters(String value) {
    const allowed = {
      'aac_adtstoasc',
      'h264_mp4toannexb',
      'hevc_mp4toannexb',
      'av1_metadata',
      'h264_metadata',
      'hevc_metadata',
      'mpeg2_metadata',
      'vp9_metadata',
      'filter_units',
      'extract_extradata',
      'remove_extra',
      'dump_extra',
      'setts',
      'noise',
      'chomp',
      'null',
      'vp9_superframe',
      'vp9_superframe_split',
      'vp9_raw_reorder',
      'mpeg4_unpack_bframes',
      'opus_metadata',
      'dca_core',
      'truehd_core',
      'eac3_core',
    };
    for (final filter in ffmpegSplit(value, ',').asMap().entries) {
      if (filter.key.isEven &&
          !allowed.contains(filter.value.split('=').first)) {
        unsupported('Unsupported bitstream filter.');
      }
    }
  }

  static Never unsupported(String token) => throw ToolOperationException(
    'unsupported',
    'Unsupported FFmpeg token: $token',
  );

  static void localPath(String value) {
    if (value.isEmpty ||
        value == '-' ||
        value.contains('*') ||
        value.contains('?') ||
        value.contains('\u0000') ||
        (RegExp(r'^[A-Za-z][A-Za-z0-9+.-]*:').hasMatch(value) &&
            !RegExp(r'^[A-Za-z]:[\\/]').hasMatch(value))) {
      unsupported(value);
    }
  }
}
