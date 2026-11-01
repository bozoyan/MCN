// 职责: 聊天会话的延续/删除动作菜单 — 判定可用性并弹出统一样式浮层
// 关联文件:
//   lib/desktop/widgets/ai/chat/session_list.dart
//   lib/desktop/widgets/ai/chat/session_switcher.dart
//   lib/shared/components/reveric_context_menu.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/ai.json
//   assets/translations/zh-CN/ai.json
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/error-handling.md
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../shared/components/reveric_context_menu.dart';
import '../../../../shared/localization/app_localization.dart';
import '../../../../shared/localization/locale_keys.dart';
import '../../../../shared/logger/app_logger.dart';
import '../../../../shared/models/ai_session_mode.dart';
import '../../../../shared/providers/ai_mode_processing.dart';
import '../../../../shared/providers/ai_providers.dart'
    show aiChatRuntimeProvider;
import '../../../../shared/providers/novel_providers.dart';
import '../../../../shared/theme/theme.dart';

final _log = AppLogger.forModule('ChatSessionContextMenu');

/// 在 [position] 弹出会话行右键菜单（延续 / 删除）。
Future<void> showChatSessionContextMenu({
  required BuildContext context,
  required WidgetRef ref,
  required Offset position,
  required String sessionId,
  String? databasePath,
  VoidCallback? onContinue,
  VoidCallback? onDelete,
}) async {
  final continuable =
      onContinue != null &&
      await _hasContinuableHistory(
        ref,
        sessionId: sessionId,
        databasePath: databasePath,
      );
  if (!context.mounted) {
    return;
  }

  final colors = RevericTheme.colorsOf(context);
  final busy = continuable && _isSessionBusy(ref, sessionId);
  final entries = <RevericMenuEntry>[
    if (continuable)
      RevericMenuItem(
        icon: RevericIcons.git_fork,
        label: context.t(LocaleKeys.aiChatContinue),
        tooltip: busy
            ? context.t(LocaleKeys.aiCancelFirst)
            : context.t(LocaleKeys.aiChatContinueHint),
        enabled: !busy,
        onTap: onContinue,
      ),
    if (continuable && onDelete != null) const RevericMenuDivider(),
    if (onDelete != null)
      RevericMenuItem(
        icon: RevericIcons.delete,
        iconColor: colors.warningText,
        labelColor: colors.warningText,
        label: context.t(LocaleKeys.commonDelete),
        onTap: onDelete,
      ),
  ];
  if (entries.isEmpty) {
    return;
  }

  await showRevericContextMenu(
    context: context,
    position: position,
    entries: entries,
  );
}

/// 会话是否已有落库消息，可以作为延续来源。
///
/// 查询放在菜单弹出时而不是每行 build 时，避免长列表为一个低频动作常驻查询。
/// 草稿会话（`__handoff_draft__` 等）还没有真实会话行，不能作为来源。
Future<bool> _hasContinuableHistory(
  WidgetRef ref, {
  required String sessionId,
  required String? databasePath,
}) async {
  if (databasePath == null || sessionId.startsWith('__')) {
    return false;
  }
  try {
    return await ref
        .read(novelContentDatabaseProvider(databasePath))
        .aiChatMessageDao
        .hasSavedMessages(sessionId);
  } catch (error, stackTrace) {
    _log.error(
      '[DB] table=ai_chat_messages operation=SELECT session=$sessionId '
      'error=$error',
      error: error,
      stackTrace: stackTrace,
    );
    return false;
  }
}

/// 来源会话正在跑请求或落库时不能延续。
bool _isSessionBusy(WidgetRef ref, String sessionId) {
  final runtime = ref.read(aiChatRuntimeProvider(sessionId));
  return runtime.isRequestInFlight ||
      runtime.isSessionMutationInFlight ||
      ref.read(
        aiSessionProcessingProvider(
          mode: AiSessionMode.chat,
          sessionId: sessionId,
        ),
      );
}
