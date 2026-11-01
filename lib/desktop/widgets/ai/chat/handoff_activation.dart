// 职责: 等待聊天面板订阅目标会话后再消费开场请求，避免初始化状态被自动释放。
// 关联文件:
//   lib/desktop/widgets/ai/chat/panel.dart
//   lib/shared/providers/ai_providers.dart
// 遵循的 Rules:
//   .agents/rules/hooks.md
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

void useHandoffActivation({
  required String? requestId,
  required String? targetSessionId,
  required String? activeSessionId,
  required Future<void> Function(String?)? onSelectSession,
  required VoidCallback onReady,
}) {
  final consumed = useRef<String?>(null);
  final select = useRef(onSelectSession)..value = onSelectSession;
  final ready = useRef(onReady)..value = onReady;
  final context = useContext();
  useEffect(() {
    if (requestId == null || consumed.value == requestId) {
      return null;
    }
    var cancelled = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (cancelled || !context.mounted) {
        return;
      }
      if (activeSessionId != targetSessionId) {
        unawaited(select.value?.call(targetSessionId));
        return;
      }
      consumed.value = requestId;
      ready.value();
    });
    return () => cancelled = true;
  }, [requestId, targetSessionId, activeSessionId]);
}
