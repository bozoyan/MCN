// 职责: 为宿主提供导演工作区、预览静帧及工程文件导入导出。
// 关联文件:
//   lib/shared/services/director/storage.dart
//   lib/shared/services/director/preview.dart
//   lib/shared/services/director/renderer.dart
//   lib/shared/services/director/session.dart
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import '../../models/director/document.dart';
import 'renderer.dart';
import 'preview.dart';
import 'session.dart';
import 'storage.dart';

class DirectorFileOutput {
  DirectorFileOutput(this.storage, this.session);
  final DirectorStorage storage;
  final DirectorSession session;
  bool _disposed = false;
  static final _previewWrites = <String, Future<void>>{};

  static Future<DirectorFileOutput> open(
    DirectorSession session,
    String scope, {
    required String novelId,
  }) async {
    return DirectorFileOutput(
      await workspace(scope, novelId: novelId),
      session,
    );
  }

  /// 调度的私有工作区：导出任务、预览静帧和工程文件都放在这里。
  static Future<DirectorStorage> workspace(
    String scope, {
    required String novelId,
  }) async {
    final base = await DirectorStorage.open(novelId);
    final root = _workspace(base, scope);
    await root.create(recursive: true);
    return DirectorStorage(root, base.temporary);
  }

  static Directory _workspace(DirectorStorage base, String scope) {
    if (!RegExp(r'^[\w-]+$').hasMatch(scope)) {
      throw ArgumentError.value(scope, 'scope');
    }
    return Directory('${base.root.path}/workspaces/$scope');
  }

  /// 读取上次生成的预览；尚未生成时返回空。
  static Future<Uint8List?> readPreview(
    String scope, {
    required String novelId,
  }) async => DirectorPreview(await workspace(scope, novelId: novelId)).read();

  static Stream<int> previewUpdates(String scope) =>
      DirectorPreview.updates(scope);

  /// 手动关闭与显式工具使用相同的切镜序列预览。
  Future<void> writePreview(DirectorDocument document) =>
      renderPreview(document, storage);

  /// 独立渲染切镜序列的第 0 帧。
  static Future<void> renderPreview(
    DirectorDocument document,
    DirectorStorage storage, {
    FrameRenderer? renderer,
  }) {
    final key = storage.root.path;
    final operation = (_previewWrites[key] ?? Future<void>.value()).then((
      _,
    ) async {
      final capture = renderer ?? DirectorRenderer();
      try {
        final bytes = await capture.capture(document, 0, document.cameraAt(0));
        await DirectorPreview(storage).write(bytes);
      } finally {
        capture.dispose();
      }
    });
    final settled = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    _previewWrites[key] = settled;
    settled.then((_) {
      if (identical(_previewWrites[key], settled)) {
        _previewWrites.remove(key);
      }
    });
    return operation;
  }

  Future<void> importDocument() async {
    final document = await storage.importDocument();
    if (document != null && !_disposed) {
      session.restore(document);
    }
  }

  Future<void> exportDocument() async {
    if (session.hasPendingInput) {
      throw const DocumentError('input', 'apply_pending');
    }
    final document = session.history.document;
    final file = File(
      '${storage.root.path}/exports/${document.id}_${DateTime.now().microsecondsSinceEpoch}.director.json',
    );
    await file.parent.create(recursive: true);
    await file.writeAsString(document.encode(), flush: true);
    await storage.offerFile(file, '${document.title}.director.json');
  }

  void dispose() {
    _disposed = true;
  }
}
