// 职责: Agent 提交制图草案后的跳转 — 记下草案所属地点，等这一轮说完再去那张地图：
//       从地图工作台进来的聊天页带着目标返回工作台，其余情况在当前页之上打开那张地图。
// 关联文件:
//   lib/mobile/pages/novel_chat_page.dart
//   lib/mobile/features/map/studio_page.dart
//   lib/shared/providers/map_agent_providers.dart
// 遵循的 Rules:
//   .agents/rules/hooks.md
import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

/// 返回待跳转的目标；调用方收到草案导航时写入地点 id。
///
/// 提交发生在一轮对话中途：这时离开聊天页会弹「暂停 / 后台运行」，Agent 也还要写总结，
/// 所以等 [processing] 落下再跳。[returnToCaller] 为 true 时关掉当前页（连同盖在上面的
/// sheet），把目标作为返回值交回调用方；否则调 [openMap]。
ValueNotifier<String?> useMapDraftNavigation(
  BuildContext context, {
  required bool processing,
  required bool returnToCaller,
  required ValueChanged<String> openMap,
}) {
  final pendingTarget = useState<String?>(null);
  final target = pendingTarget.value;
  useEffect(() {
    if (target == null || processing) {
      return null;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted || pendingTarget.value != target) {
        return;
      }
      pendingTarget.value = null;
      if (!returnToCaller) {
        openMap(target);
        return;
      }
      final navigator = Navigator.of(context);
      final route = ModalRoute.of(context);
      navigator.popUntil((item) => item == route);
      navigator.pop(target);
    });
    return null;
  }, [target, processing]);
  return pendingTarget;
}
