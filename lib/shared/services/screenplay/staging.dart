// 职责: 将导演台调度的当前版本和历史版本接到作品数据库，串行执行保存。
// 关联文件:
//   lib/shared/database/novel_content_daos/screenplay_dao.dart
//   lib/shared/services/director/session.dart
//   lib/shared/models/director/persistence.dart
import 'dart:async';
import 'package:uuid/uuid.dart';
import '../../database/novel_content_database.dart';
import 'staging_changes.dart';
import '../../logger/app_logger.dart';
import '../../database/novel_content_daos/screenplay_dao.dart';
import '../../models/director/document.dart';
import '../../models/director/persistence.dart';
import '../director/session.dart';

final _log = AppLogger.forModule('Director');

class VideoStagingBinding {
  VideoStagingBinding(this.dao, this.stagingId);
  final ScreenplayDao dao;
  final String stagingId;
  static final _opened = Expando<Map<String, VideoStagingBinding>>();
  static VideoStagingBinding? openFor(ScreenplayDao dao, String id) =>
      _opened[dao]?[id];
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    final render = updatePreview;
    if (render != null) {
      unawaited(_previewAfterClose(render));
    }
    if (identical(_opened[dao]?[stagingId], this)) {
      _opened[dao]!.remove(stagingId);
    }
  }

  Future<void> _previewAfterClose(
    Future<void> Function(DirectorDocument) render,
  ) async {
    try {
      await flush();
      if (_hasManualEdits) {
        await render(_persisted);
      }
    } catch (error, stack) {
      _log.error(
        'close preview failed stagingId=$stagingId',
        error: error,
        stackTrace: stack,
      );
    }
  }

  late final DirectorSession session;
  // 由宿主在手动关闭时生成预览；普通保存不会调用。
  Future<void> Function(DirectorDocument document)? updatePreview;
  int _version = 0;
  DateTime? _savedAt;
  Future<void> _writes = Future.value();
  final _checkpointId = const Uuid().v4();
  late DirectorDocument _observed, _persisted;
  final _pending = <(DirectorDocument, DirectorDocument)>[];
  bool _receiving = false, _disposed = false, _hasManualEdits = false;
  Object? _writeError;
  StackTrace? _writeStack;

  /// 版本号即历史条目身份；调度还没保存过时为 0。
  int get version => _version;

  Future<DirectorSession> load({
    required String camera,
    Future<List<Json>> Function(String?)? exportVersions,
  }) async {
    final stored = await dao.getStaging(stagingId);
    if (stored == null) {
      throw const DocumentError('staging', 'not_found');
    }
    _version = stored.version;
    _savedAt = stored.updatedAt;
    final initial = stored.document == null
        ? DirectorDocument.blank(stored.title, camera: camera)
        : DirectorDocument.fromJson(stored.document!);
    _observed = _persisted = initial;
    session = DirectorSession(
      initial,
      onChanged: _changed,
      onSave: (_) async {
        await _writes;
        if (_pending.isNotEmpty) {
          _enqueue(_pending.last);
        }
        await flush();
        return DirectorRevision(
          id: '$_version',
          savedAt: _savedAt!,
          savedDocument: _persisted,
        );
      },
      exportVersions: exportVersions,
      versions: DirectorHistory(list: _history, load: _snapshot),
    )..savedRevisionId = _version == 0 ? null : '$_version';
    (_opened[dao] ??= {})[stagingId] = this;
    return session;
  }

  void _changed(DirectorDocument document) {
    if (_receiving) {
      return;
    }
    final oldJson = _observed.toJson(), nextJson = document.toJson();
    if (oldJson['output']['aspect_mode'] == 'auto' &&
        nextJson['output']['aspect_mode'] == 'auto') {
      nextJson['output']['width'] = oldJson['output']['width'];
      nextJson['output']['height'] = oldJson['output']['height'];
      if (DirectorDocument.fromJson(nextJson).businessContent ==
          _observed.businessContent) {
        return;
      }
    }
    final change = (_observed, document);
    _observed = document;
    _pending.add(change);
    _enqueue(change);
  }

  void _enqueue((DirectorDocument, DirectorDocument) change) {
    final operation = dao.serializeStaging(stagingId, () async {
      final row = await dao.getStaging(stagingId);
      if (row == null) {
        throw const DocumentError('staging', 'not_found');
      }
      final current = row.document == null
          ? _persisted
          : DirectorDocument.fromJson(row.document!);
      final through = _pending.indexOf(change);
      final changes = _pending.take(through + 1).toList();
      var next = current;
      for (final pending in changes) {
        next = _applyPending(next, pending);
      }
      if (next.businessContent != current.businessContent) {
        await dao.saveStaging(
          stagingId,
          next.toJson(),
          title: next.title,
          savedAt: DateTime.now(),
          checkpointId: _checkpointId,
          initialDocument: current.toJson(),
        );
        _hasManualEdits = true;
      }
      for (final pending in changes) {
        _pending.remove(pending);
      }
      receive((await dao.getStaging(stagingId))!, local: true);
    });
    _writes = operation.then<void>(
      (_) {
        _writeError = null;
        _writeStack = null;
      },
      onError: (Object error, StackTrace stack) {
        _writeError = error;
        _writeStack = stack;
        if (!_disposed) {
          session.report(error, stack);
        }
      },
    );
  }

  DirectorDocument _applyPending(
    DirectorDocument current,
    (DirectorDocument, DirectorDocument) change,
  ) {
    try {
      return applyStagingChanges(current, change.$1, change.$2);
    } on DocumentError catch (error, stack) {
      // 先前的编辑可能已经删除本次操作的目标。只拒绝这次非法编辑；
      // 数据库写入失败仍保留在队列中，由显式保存重试。
      _pending.remove(change);
      if (!_disposed) {
        session.report(error, stack);
      }
      return current;
    }
  }

  /// 数据库写入完成后同步视图，尚在队列中的本地改动保持可见。
  void receive(VideoStagingRow row, {bool local = false}) {
    final stored = row.document == null
        ? _persisted
        : DirectorDocument.fromJson(row.document!);
    _persisted = stored;
    _version = row.version;
    _savedAt = row.updatedAt;
    if (_disposed) {
      return;
    }
    var visible = stored;
    for (final change in [..._pending]) {
      visible = _applyPending(visible, change);
    }
    _observed = visible;
    _receiving = true;
    try {
      session.savedRevisionId = '$_version';
      session.history.synchronize(visible, external: !local);
      session.history.markSaved(stored);
    } finally {
      _receiving = false;
    }
  }

  Future<void> flush() async {
    while (true) {
      final writes = _writes;
      await writes;
      if (identical(writes, _writes)) {
        break;
      }
    }
    if (_writeError != null) {
      Error.throwWithStackTrace(_writeError!, _writeStack!);
    }
  }

  Future<List<DirectorRevision>> _history() async => [
    if (_version > 0) DirectorRevision(id: '$_version', savedAt: _savedAt!),
    for (final entry in await dao.getStagingHistory(stagingId))
      DirectorRevision(id: '${entry.version}', savedAt: entry.savedAt),
  ];

  Future<DirectorDocument> _snapshot(String id) async {
    final version = int.tryParse(id);
    if (version == _version) {
      final stored = await dao.getStaging(stagingId);
      if (stored?.document != null) {
        return DirectorDocument.fromJson(stored!.document!);
      }
    }
    final entry = version == null
        ? null
        : await dao.getStagingRevision(stagingId, version);
    if (entry == null) {
      throw const DocumentError('history', 'invalid_pointer');
    }
    return DirectorDocument.fromJson(entry.value);
  }
}
