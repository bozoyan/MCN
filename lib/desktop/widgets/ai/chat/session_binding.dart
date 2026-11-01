// 职责: 在作品作用域内解析持久化 active 或稳定新草稿信号，保留刷新期间已绑定的会话。
// 关联文件:
//   lib/desktop/pages/novel_editor.dart
//   lib/shared/services/ai/session_persistence.dart
//   lib/shared/providers/novel_providers.dart
// 遵循的 Rules:
//   .agents/rules/hooks.md
//   .agents/rules/state-management.md
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../shared/services/ai/session_persistence.dart';

String? useResolvedChatSession({
  required String novelId,
  required String? databasePath,
  required bool ready,
  required String? selectedId,
  required AsyncValue<String?> persisted,
}) {
  // 换作品时 selectedId 仍是上一部作品的会话——复位它的 effect 要到本帧之后才跑。
  // 记下换作品前的选择并忽略它，否则 binding 会锁死在旧作品的会话上，聊天区空白。
  final lastSelectedId = useRef<String?>(null);
  final binding = useMemoized(() => _ChatBinding(lastSelectedId.value), [
    novelId,
    databasePath,
  ]);
  lastSelectedId.value = selectedId;
  if (!ready) {
    return null;
  }
  if (selectedId != null && selectedId != binding.staleSelection) {
    binding.resolved = selectedId;
  } else if (binding.resolved == null && persisted.hasValue) {
    binding.resolved = persisted.value ?? binding.newSignal;
  }
  return effectiveAiChatSessionId(novelId: novelId, activeId: binding.resolved);
}

class _ChatBinding {
  _ChatBinding(this.staleSelection);

  /// 换作品前一帧的选择。会话 ID 全局唯一且只属于一部作品，不会误伤新作品的选择。
  final String? staleSelection;
  final newSignal = '__new__${DateTime.now().microsecondsSinceEpoch}';
  String? resolved;
}
