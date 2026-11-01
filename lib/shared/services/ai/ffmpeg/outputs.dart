// 职责: 解析并检查输出路径，管理序列资源限额监控与取消的生命周期。
// 关联文件:
//   lib/shared/services/ai/ffmpeg/command.dart
//   lib/shared/services/ai/ffmpeg/arguments.dart
//   lib/shared/services/ai/ffmpeg/sequence.dart
//   lib/shared/services/ai/files/session_files.dart
import 'dart:async';
import 'dart:io';
import 'package:path/path.dart' as p;
import '../../../logger/app_logger.dart';
import '../../../models/tool_permission.dart';
import '../../production/ffmpeg_runner.dart';
import '../files/session_files.dart';
import '../files/command_paths.dart';
import 'arguments.dart';
import 'sequence.dart';

final _log = AppLogger.forModule('FFmpeg');

class FfmpegOutputs {
  FfmpegOutputs(this.files, this.sessionId, this.parsed, this.cancellation);
  final SessionFiles files;
  final String sessionId;
  final FfmpegArguments parsed;
  final MediaCancellation cancellation;
  final _targets = <File>[];
  final _ordinaryTargets = <String>[];
  final _sequences = <_SequenceOutput>[];
  Object? _failure;
  Timer? _timer;
  Future<void>? _inspection;
  String? defaultPassLog;

  void check() {
    if (cancellation.cancelled) {
      throw const ToolOperationException(
        'cancelled',
        'Media processing was cancelled.',
      );
    }
  }

  static Future<File> resolveTarget(
    SessionFiles files,
    String sessionId,
    String requested, {
    bool allowExisting = false,
  }) async {
    FfmpegArguments.localPath(requested);
    final paths = CommandPaths(files);
    final file = File(paths.absolute(requested, write: true));
    if (!p.isWithin(paths.root, file.path)) {
      throw const FormatException(
        'Output must be a file within the current work.',
      );
    }
    await paths.checkRelative(requested);
    final resolved = file;
    final type = await FileSystemEntity.type(file.path, followLinks: false);
    if (type == FileSystemEntityType.link ||
        type == FileSystemEntityType.directory ||
        (!allowExisting && type != FileSystemEntityType.notFound)) {
      throw ToolOperationException(
        'already_exists',
        'The output path already exists: ${paths.reference(resolved)}',
        hint: type == FileSystemEntityType.file
            ? 'Inspect the conflicting path with Run files list. If it is a disposable output from an earlier failed attempt and removal is authorized, use Run files remove to clean it up; otherwise choose a new output path. Confirm the output path is available before retrying.'
            : 'Choose a new output path.',
      );
    }
    return resolved;
  }

  Future<void> prepare(List<String> actual) async {
    final names = <String>{};
    for (final entry in parsed.outputs.entries) {
      final sequence = parsed.sequences[entry.key];
      File? first;
      for (var i = 0; i < (sequence?.limit ?? 1); i++) {
        check();
        final target = await resolveTarget(
          files,
          sessionId,
          sequence?.at(i) ?? entry.value,
        );
        final canonical = p.normalize(target.path);
        if (!names.add(
          Platform.isWindows || Platform.isMacOS
              ? canonical.toLowerCase()
              : canonical,
        )) {
          throw const FormatException(
            'Output filenames overlap after sequence expansion.',
          );
        }
        first ??= target;
        _targets.add(target);
      }
      if (sequence == null) {
        actual[entry.key] = first!.path;
        _ordinaryTargets.add(first.path);
      } else {
        final output = _SequenceOutput(sequence, first!.parent);
        _sequences.add(output);
        actual[entry.key] = output.template;
      }
      await first.parent.create(recursive: true);
    }
    for (final output in _sequences) {
      await output.excludeExisting(_ordinaryTargets);
    }
    if (parsed.pass != null) {
      final prefix = parsed.passLogIndex == null
          ? 'ffmpeg2pass'
          : actual[parsed.passLogIndex!];
      final target = await resolveTarget(
        files,
        sessionId,
        prefix,
        allowExisting: true,
      );
      await target.parent.create(recursive: true);
      final pattern = RegExp(
        '^${RegExp.escape(p.basename(target.path))}-[0-9]+\\.log(?:\\.mbtree)?(?:\\.temp)?'
        r'$',
        caseSensitive: !(Platform.isWindows || Platform.isMacOS),
      );
      await for (final entry in target.parent.list(followLinks: false)) {
        if (pattern.hasMatch(p.basename(entry.path)) && entry is! File) {
          throw const ToolOperationException(
            'invalid_argument',
            'Pass log paths must be regular files.',
          );
        }
      }
      if (parsed.passLogIndex case final index?) {
        actual[index] = target.path;
      } else {
        defaultPassLog = target.path;
      }
    }
  }

  Future<void> validateInputs(Iterable<String> paths) async {
    for (final path in paths) {
      final source = await CommandPaths(files).resolve(path);
      if (_targets.any((target) => p.equals(source.path, target.path))) {
        throw const FormatException('Output cannot replace an input');
      }
    }
  }

  void startBudget() {
    if (_sequences.isEmpty) {
      return;
    }
    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (_inspection != null || _failure != null) {
        return;
      }
      _inspection = _poll();
    });
  }

  Future<void> _poll() async {
    try {
      await _verifyBudget();
    } catch (error, stack) {
      _failure = error;
      _log.error(
        'sequence output limit check failed',
        error: error,
        stackTrace: stack,
      );
      try {
        await cancellation.cancel();
      } catch (cancelError, cancelStack) {
        _log.error(
          'sequence cancellation failed',
          error: cancelError,
          stackTrace: cancelStack,
        );
      }
    } finally {
      _inspection = null;
    }
  }

  Future<void> _verifyBudget() async {
    if (_failure != null) {
      throw _failure!;
    }
    var imageCount = 0, segmentCount = 0;
    final seen = <String>{};
    for (final output in _sequences) {
      await for (final entry in output.entries()) {
        if (!seen.add(_SequenceOutput._key(entry.path))) {
          continue;
        }
        final owner = _sequences
            .where((candidate) => candidate.contains(entry.path))
            .firstOrNull;
        if (owner == null) {
          throw const ToolOperationException(
            'resource_exhausted',
            'Generated files exceed the requested output range.',
          );
        }
        if (entry is! File) {
          throw const ToolOperationException(
            'invalid_result',
            'Unexpected entry in sequence output.',
          );
        }
        if (owner.sequence.segment) {
          segmentCount++;
        } else {
          imageCount++;
        }
        if (imageCount > ffmpegMaxSequenceFrames ||
            segmentCount > ffmpegMaxSegments) {
          throw const ToolOperationException(
            'resource_exhausted',
            'Generated files exceed the output count limit.',
          );
        }
      }
    }
  }

  Future<void> dispose() async {
    _timer?.cancel();
    await _inspection;
  }

  Future<void> verifyBudget() async {
    await dispose();
    await _verifyBudget();
  }
}

class _SequenceOutput {
  _SequenceOutput(this.sequence, this.directory);
  final FfmpegSequence sequence;
  final Directory directory;
  final _excluded = <String>{};
  late final _parts = p.basename(template).split(sequence.placeholder);
  late final _pattern = RegExp(
    '^${RegExp.escape(_parts[0])}([0-9]+)${RegExp.escape(_parts[1])}'
    r'$',
    caseSensitive: !(Platform.isWindows || Platform.isMacOS),
  );
  String get template {
    final syntax = p.Context(
      style: sequence.pattern.contains(r'\') ? p.Style.windows : p.Style.posix,
    );
    return p.join(directory.path, syntax.basename(sequence.pattern));
  }

  static String _key(String path) {
    final normalized = p.normalize(path);
    return Platform.isWindows || Platform.isMacOS
        ? normalized.toLowerCase()
        : normalized;
  }

  int? _number(String path) {
    if (_key(p.dirname(path)) != _key(directory.path)) {
      return null;
    }
    final name = p.basename(template);
    final match = _pattern.firstMatch(p.basename(path));
    final number = match == null ? null : int.tryParse(match.group(1)!);
    if (number == null || number < sequence.start) {
      return null;
    }
    final canonical = name.replaceFirst(
      sequence.placeholder,
      '$number'.padLeft(sequence.width, '0'),
    );
    return _key(canonical) == _key(p.basename(path)) ? number : null;
  }

  bool contains(String path) {
    final number = _number(path);
    return number != null && number < sequence.start + sequence.limit;
  }

  Future<void> excludeExisting(Iterable<String> otherOutputs) async {
    _excluded.addAll(otherOutputs.map(_key));
    await for (final entry in directory.list(followLinks: false)) {
      // Target collisions are checked separately; older numbers do not belong to this run.
      if (_number(entry.path) != null && !contains(entry.path)) {
        _excluded.add(_key(entry.path));
      }
    }
  }

  Stream<FileSystemEntity> entries() {
    return directory
        .list(followLinks: false)
        .where(
          (entry) =>
              !_excluded.contains(_key(entry.path)) &&
              _number(entry.path) != null,
        );
  }
}
