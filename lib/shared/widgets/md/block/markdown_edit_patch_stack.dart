// 职责: Markdown 编辑器的全文级撤销栈 — 以可逆 patch 记录编辑，避免为长文保存整篇快照
// 关联文件:
//   lib/shared/widgets/md/block/markdown_block_document.dart
//   lib/shared/widgets/md/reveric_markdown_editor.dart
// 遵循的 Rules:
//   .agents/rules/code-style.md

/// 一次可逆编辑：把全文 [start] 起的 [removed] 换成了 [inserted]。
///
/// 48 万字符文档存整篇快照每条约 1MB，这里只存变化部分，一条通常几十字节。
class MarkdownEditPatch {
  const MarkdownEditPatch({
    required this.start,
    required this.removed,
    required this.inserted,
    required this.selectionBefore,
    required this.selectionAfter,
  });

  final int start;
  final String removed;
  final String inserted;

  /// 撤销后光标应回到的位置。
  final int selectionBefore;

  /// 重做后光标应回到的位置。
  final int selectionAfter;

  bool get isInsertion => removed.isEmpty && inserted.isNotEmpty;

  bool get isDeletion => inserted.isEmpty && removed.isNotEmpty;

  @override
  String toString() {
    return 'MarkdownEditPatch($start, -${removed.length}, +${inserted.length})';
  }
}

/// 编辑结果：撤销 / 重做后的全文与光标位置。
typedef MarkdownEditOutcome = ({String text, int selection});

/// 全文级撤销栈。
///
/// 连续输入会在 [mergeWindow] 内合并成一条，避免一个字一次撤销。
class MarkdownEditPatchStack {
  MarkdownEditPatchStack({
    this.mergeWindow = const Duration(milliseconds: 500),
    this.historyLimit = 500,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final Duration mergeWindow;
  final int historyLimit;
  final DateTime Function() _clock;

  final List<MarkdownEditPatch> _patches = [];

  /// 下一次 undo 要回退的 patch 下标；-1 表示已经退到底。
  int _index = -1;
  DateTime? _lastRecordedAt;

  bool get canUndo => _index >= 0;

  bool get canRedo => _index < _patches.length - 1;

  int get length => _patches.length;

  /// 记录一次编辑。[mergeable] 为 false 时（如外部整篇写入）不与上一条合并。
  void record(MarkdownEditPatch patch, {bool mergeable = true}) {
    if (patch.removed.isEmpty && patch.inserted.isEmpty) {
      return;
    }

    // 记录新编辑会丢弃 redo 分支。
    if (_index < _patches.length - 1) {
      _patches.removeRange(_index + 1, _patches.length);
    }

    final now = _clock();
    if (mergeable && _index >= 0 && _withinMergeWindow(now)) {
      final merged = _merge(_patches[_index], patch);
      if (merged != null) {
        _patches[_index] = merged;
        _lastRecordedAt = now;
        return;
      }
    }

    _patches.add(patch);
    _index = _patches.length - 1;
    _lastRecordedAt = mergeable ? now : null;

    if (_patches.length > historyLimit) {
      final overflow = _patches.length - historyLimit;
      _patches.removeRange(0, overflow);
      _index -= overflow;
    }
  }

  MarkdownEditOutcome? undo(String currentText) {
    if (!canUndo) {
      return null;
    }
    final patch = _patches[_index];
    final end = patch.start + patch.inserted.length;
    if (end > currentText.length) {
      // 全文与栈不同步（外部直接改写），放弃历史而不是产出错误文本。
      clear();
      return null;
    }
    _index -= 1;
    _lastRecordedAt = null;
    return (
      text: currentText.replaceRange(patch.start, end, patch.removed),
      selection: patch.selectionBefore,
    );
  }

  MarkdownEditOutcome? redo(String currentText) {
    if (!canRedo) {
      return null;
    }
    final patch = _patches[_index + 1];
    final end = patch.start + patch.removed.length;
    if (end > currentText.length) {
      clear();
      return null;
    }
    _index += 1;
    _lastRecordedAt = null;
    return (
      text: currentText.replaceRange(patch.start, end, patch.inserted),
      selection: patch.selectionAfter,
    );
  }

  void clear() {
    _patches.clear();
    _index = -1;
    _lastRecordedAt = null;
  }

  bool _withinMergeWindow(DateTime now) {
    final last = _lastRecordedAt;
    return last != null && now.difference(last) <= mergeWindow;
  }

  /// 只合并「同方向、首尾相接」的连续编辑；跨块或换行处不合并。
  MarkdownEditPatch? _merge(MarkdownEditPatch last, MarkdownEditPatch next) {
    if (last.isInsertion && next.isInsertion) {
      if (next.inserted.contains('\n') || last.inserted.contains('\n')) {
        return null;
      }
      if (next.start != last.start + last.inserted.length) {
        return null;
      }
      return MarkdownEditPatch(
        start: last.start,
        removed: '',
        inserted: last.inserted + next.inserted,
        selectionBefore: last.selectionBefore,
        selectionAfter: next.selectionAfter,
      );
    }

    if (last.isDeletion && next.isDeletion) {
      // 退格：新删除紧接在上一次删除之前。
      if (next.start + next.removed.length == last.start) {
        return MarkdownEditPatch(
          start: next.start,
          removed: next.removed + last.removed,
          inserted: '',
          selectionBefore: last.selectionBefore,
          selectionAfter: next.selectionAfter,
        );
      }
      // 前向删除：光标不动，反复吃掉后面的字符。
      if (next.start == last.start) {
        return MarkdownEditPatch(
          start: last.start,
          removed: last.removed + next.removed,
          inserted: '',
          selectionBefore: last.selectionBefore,
          selectionAfter: next.selectionAfter,
        );
      }
    }

    return null;
  }
}
