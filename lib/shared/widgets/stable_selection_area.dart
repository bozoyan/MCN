// 职责: 内容流式增长期间禁用文本选区的 SelectionArea 替身，规避框架选区索引失稳崩溃。
// 关联文件:
//   lib/shared/widgets/ai/chat/chat_message_view.dart
//   lib/shared/widgets/ai/chat/chat_message_parts.dart
//   lib/shared/widgets/ai/thinking_card.dart
import 'package:flutter/material.dart';

/// [SelectionArea] 的安全封装。
///
/// Flutter 框架的 SelectableRegion 在选区内内容持续变更时会索引失稳，
/// 抛 ConcurrentModificationError / RangeError（flutter/flutter#111821，
/// 2022 年起仍未修复）。将 [selectable] 置为 false 时改用
/// [SelectionContainer.disabled]，让流式增长的文本不注册选区，
/// 内容稳定后再恢复可选。
class StableSelectionArea extends StatelessWidget {
  const StableSelectionArea({
    super.key,
    required this.child,
    this.selectable = true,
  });

  final Widget child;

  /// false 期间文本不可选中（用于内容仍在增长的流式阶段）。
  final bool selectable;

  @override
  Widget build(BuildContext context) {
    if (selectable) {
      return SelectionArea(child: child);
    }
    return SelectionContainer.disabled(child: child);
  }
}
