// 职责: AI 模式单条发言的「…」菜单 — 重说、删除之后的内容、删除本条，小剧场与议会的桌面面板、移动页共用。
// 关联文件:
//   lib/shared/components/reveric_more_menu_button.dart
//   lib/shared/widgets/ai/agent_message_card.dart
//   lib/desktop/features/theater/line_card.dart
//   lib/shared/widgets/ai/council/message_card.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/ai.json
//   assets/translations/zh-CN/ai.json
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
import 'package:flutter/material.dart';

import '../../components/reveric_context_menu.dart';
import '../../components/reveric_more_menu_button.dart';
import '../../localization/app_localization.dart';
import '../../localization/locale_keys.dart';
import '../../theme/theme.dart';

class AgentMessageMenu extends StatelessWidget {
  const AgentMessageMenu({
    super.key,
    this.onRegenerate,
    this.regenerateLabel,
    this.onRewindAfter,
    this.onRemove,
  }) : assert(onRegenerate == null || regenerateLabel != null);

  final VoidCallback? onRegenerate;

  /// 「重说」的文案随模式而定（这句台词 / 这条发言）。
  final String? regenerateLabel;
  final VoidCallback? onRewindAfter;
  final VoidCallback? onRemove;

  bool get hasEntries =>
      onRegenerate != null || onRewindAfter != null || onRemove != null;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    return RevericMoreMenuButton(
      iconSize: 16,
      entries: () => [
        if (onRegenerate != null)
          RevericMenuItem(
            label: regenerateLabel!,
            icon: RevericIcons.redo,
            onTap: onRegenerate,
          ),
        if (onRewindAfter != null)
          RevericMenuItem(
            label: context.t(LocaleKeys.aiMessageRewindAfter),
            icon: RevericIcons.delete_outline,
            iconColor: colors.error,
            labelColor: colors.error,
            onTap: onRewindAfter,
          ),
        if (onRemove != null)
          RevericMenuItem(
            label: context.t(LocaleKeys.commonDelete),
            icon: RevericIcons.delete_outline,
            iconColor: colors.error,
            labelColor: colors.error,
            onTap: onRemove,
          ),
      ],
    );
  }
}
