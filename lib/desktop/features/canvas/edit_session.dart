// 职责: 等待画布编辑、拖拽与写入完成，阻止组词期或失败状态下开始排列及导出。
// 关联文件:
//   lib/desktop/features/canvas/widgets/canvas_region.dart
//   lib/desktop/features/canvas/widgets/canvas_board.dart
//   lib/desktop/features/canvas/widgets/canvas_sticky_editor.dart
//   lib/desktop/features/canvas/widgets/canvas_detail_layer.dart
// 遵循的 Rules:
//   .agents/rules/text-input-ime.md
//   .agents/rules/state-management.md
//   .agents/rules/error-handling.md

import 'dart:async';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import '../../../third/flow/vyuh_node_flow.dart' as flow;
import 'widgets/canvas_flow_adapter.dart';
import '../../../shared/models/canvas_layout.dart';
import '../../../shared/services/canvas_service.dart';

class CanvasEditSessionException implements Exception {
  const CanvasEditSessionException(this.code);
  final String code;
}

class CanvasEditorFlush {
  const CanvasEditorFlush({required this.isComposing, required this.flush});
  final bool Function() isComposing;
  final Future<void> Function() flush;
}

/// 会话由 CanvasRegion 拥有；作为 flow plugin 同时观察真实拖拽/缩放生命周期。
class CanvasEditSession extends flow.NodeFlowPlugin with ChangeNotifier {
  final _editors = <Object, CanvasEditorFlush>{};
  final _failures = <Object, Object>{};
  final _interactions = <String, int>{};
  int _interactionSequence = 0;
  Future<void> _writes = Future.value();
  Completer<void>? _idle;
  CanvasFlowController? _controller;
  bool _busy = false;
  bool _editingLocked = false;
  bool _disposed = false;
  int _editRevision = 0;

  Future<void> Function(String nodeId, Offset position, Size size)?
  saveGeometry;
  void Function(Object error)? onWriteError;

  bool get busy => _busy;
  bool get editingLocked => _editingLocked;
  bool get hasInteractions => _interactions.isNotEmpty;
  bool get isComposing => _editors.values.any((editor) => editor.isComposing());

  void register(Object key, CanvasEditorFlush editor) {
    _editors[key] = editor;
    _editRevision++;
  }

  void unregister(Object key) {
    _editors.remove(key);
    _editRevision++;
  }

  void markEdited() {
    _editRevision++;
  }

  Future<T> write<T>(Object key, Future<T> Function() action) {
    final task = _writes
        .then((_) => action())
        .then(
          (value) {
            _failures.remove(key);
            return value;
          },
          onError: (Object error, StackTrace stack) {
            _failures[key] = error;
            Error.throwWithStackTrace(error, stack);
          },
        );
    // 串行队列允许失败后的显式重试；原 task 仍向调用者抛错。
    _writes = task.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return task;
  }

  void writeInBackground(Object key, Future<void> Function() action) {
    unawaited(
      write(key, action).catchError((Object error) {
        onWriteError?.call(error);
      }),
    );
  }

  void beginInteraction(String id) {
    _interactions[id] = ++_interactionSequence;
    _idle ??= Completer<void>();
    if (!_disposed) {
      notifyListeners();
    }
  }

  void endInteraction(String id, [int? expectedSequence]) {
    if (expectedSequence != null && _interactions[id] != expectedSequence) {
      return;
    }
    final changed = _interactions.remove(id) != null;
    if (_interactions.isEmpty) {
      _idle?.complete();
      _idle = null;
    }
    if (changed && !_disposed) {
      notifyListeners();
    }
  }

  Future<void> flushAndWait() async {
    while (true) {
      if (isComposing) {
        throw const CanvasEditSessionException('input_composing');
      }
      while (_interactions.isNotEmpty) {
        await _idle!.future;
      }
      final revision = _editRevision;
      for (final entry in _editors.entries.toList()) {
        if (identical(_editors[entry.key], entry.value)) {
          try {
            await entry.value.flush();
          } on CanvasEditSessionException {
            rethrow;
          } catch (_) {
            throw const CanvasEditSessionException('save_failed');
          }
        }
      }
      while (true) {
        final pending = _writes;
        await pending;
        if (identical(pending, _writes)) {
          break;
        }
      }
      if (_failures.isNotEmpty) {
        throw const CanvasEditSessionException('save_failed');
      }
      if (isComposing) {
        throw const CanvasEditSessionException('input_composing');
      }
      if (_interactions.isEmpty && revision == _editRevision) {
        return;
      }
    }
  }

  /// UI 和 AI 共用的画布排列边界，shared 层只接收这个 Future 回调。
  Future<CanvasLayoutSaveResult> runLayout(
    Future<CanvasLayoutSaveResult> Function() action,
  ) async {
    try {
      return await runExclusive(action);
    } on CanvasEditSessionException catch (error) {
      throw CanvasServiceException(
        errorCode: error.code == 'save_failed'
            ? 'layout_save_failed'
            : 'layout_conflict',
        message: error.code == 'input_composing'
            ? 'Finish the current canvas text input before arranging.'
            : 'Canvas edits are not ready. Wait for them to finish before arranging.',
      );
    }
  }

  Future<T> runExclusive<T>(Future<T> Function() action) async {
    if (_disposed) {
      throw const CanvasEditSessionException('disposed');
    }
    if (_busy) {
      throw const CanvasEditSessionException('operation_in_progress');
    }
    _busy = true;
    notifyListeners();
    try {
      await flushAndWait();
      if (_disposed) {
        throw const CanvasEditSessionException('disposed');
      }
      _editingLocked = true;
      if (!_disposed) {
        notifyListeners();
      }
      return await action();
    } finally {
      _busy = false;
      _editingLocked = false;
      if (!_disposed) {
        notifyListeners();
      }
    }
  }

  @override
  String get id => 'canvas-edit-session';
  @override
  void attach(flow.NodeFlowController controller) {
    _controller = controller as CanvasFlowController;
  }

  @override
  void detach() {
    _controller = null;
    _interactions.clear();
    _idle?.complete();
    _idle = null;
  }

  void _save(String id) {
    final node = _controller?.getNode(id);
    final save = saveGeometry;
    final sequence = _interactions[id];
    if (node != null && save != null) {
      final position = node.position.value;
      final size = node.size.value;
      unawaited(
        write('geometry:$id', () => save(id, position, size)).then(
          (_) => endInteraction(id, sequence),
          onError: (Object error, StackTrace _) {
            onWriteError?.call(error);
            endInteraction(id, sequence);
          },
        ),
      );
    } else {
      endInteraction(id);
    }
  }

  @override
  void onEvent(flow.GraphEvent event) {
    switch (event) {
      case flow.NodeDragStarted(:final nodeIds):
        for (final id in nodeIds) {
          beginInteraction(id);
        }
      case flow.NodeDragEnded(:final nodeIds):
        for (final id in nodeIds) {
          _save(id);
        }
      case flow.ResizeStarted(:final nodeId):
        beginInteraction(nodeId);
      case flow.ResizeEnded(:final nodeId):
        _save(nodeId);
      default:
        break;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    detach();
    _editors.clear();
    super.dispose();
  }
}
