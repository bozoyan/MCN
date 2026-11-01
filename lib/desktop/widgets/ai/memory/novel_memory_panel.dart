// 职责: 小说级记忆面板 — 主内容区独立页面，展示当前小说的记忆条目列表与 CRUD 操作
// 关联文件:
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
//   lib/shared/providers/memory_providers.dart
//   lib/desktop/widgets/ai/memory/memory_list.dart
//   lib/desktop/widgets/ai/memory/memory_edit_dialog.dart
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../shared/localization/app_localization.dart';
import '../../../../shared/localization/locale_keys.dart';
import '../../../../shared/theme/theme.dart';
import 'memory_edit_dialog.dart';
import 'memory_list.dart';

class NovelMemoryPanel extends ConsumerWidget {
  const NovelMemoryPanel({super.key, required this.novelId});

  final String novelId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(RevericSpacing.x4l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                context.t(LocaleKeys.memoryTitle),
                style: typo.heading2.copyWith(color: colors.textPrimary),
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (_) => MemoryEditDialog(novelId: novelId),
                  );
                },
                icon: const RevericIcon(RevericIcons.add, size: 16),
                label: Text(context.t(LocaleKeys.commonCreate)),
              ),
            ],
          ),
          const SizedBox(height: RevericSpacing.xs),
          Text(
            context.t(LocaleKeys.memoryDescription),
            style: typo.uiSmall.copyWith(color: colors.textMuted),
          ),
          const SizedBox(height: RevericSpacing.x4l),
          SizedBox(
            height: 600,
            child: MemoryList(novelId: novelId, showHeader: false),
          ),
        ],
      ),
    );
  }
}
