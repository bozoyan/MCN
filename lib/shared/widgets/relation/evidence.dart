// 职责: 展示有效章节或场次证据，并阻止跳转已失效的位置。
// 关联文件:
//   lib/shared/services/entity_relations_service.dart
//   lib/shared/widgets/relation/providers.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/relation.json
//   assets/translations/zh-CN/relation.json
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
// 遵循的 Rules:
//   .agents/rules/hooks.md
//   .agents/rules/design-system.md
//   .agents/rules/state-management.md
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../components/reveric_button.dart';
import '../../localization/app_localization.dart';
import '../../localization/locale_keys.dart';
import '../../theme/theme.dart';
import 'providers.dart';

String evidenceChoiceLabel(
  BuildContext context,
  RelationEvidenceChoice choice,
) => context.t(
  choice.kind == 'chapter'
      ? LocaleKeys.relationEvidenceChapter
      : LocaleKeys.relationEvidenceScene,
  namedArgs: {
    'title': choice.title.isEmpty
        ? context.t(LocaleKeys.commonUntitled)
        : choice.title,
  },
);

class RelationEvidence extends ConsumerWidget {
  const RelationEvidence({
    super.key,
    required this.databasePath,
    this.chapterId,
    this.sceneId,
    this.onOpen,
  });
  final String databasePath;
  final String? chapterId;
  final String? sceneId;
  final RelationEvidenceNavigation? onOpen;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final typo = RevericTheme.typographyOf(context);
    final colors = RevericTheme.colorsOf(context);
    if (chapterId == null && sceneId == null) {
      return Text(
        context.t(LocaleKeys.relationSettingEvidence),
        style: typo.uiSmall.copyWith(color: colors.textMuted),
      );
    }
    final choices = ref.watch(relationEvidenceChoicesProvider(databasePath));
    return choices.when(
      loading: () => const LinearProgressIndicator(),
      error: (_, _) => Text(
        context.t(LocaleKeys.relationSaveFailed),
        style: typo.uiSmall.copyWith(color: colors.warningText),
      ),
      data: (options) {
        final kind = chapterId != null ? 'chapter' : 'scene';
        final id = chapterId ?? sceneId!;
        final choice = options
            .where((e) => e.kind == kind && e.id == id)
            .firstOrNull;
        if (choice == null) {
          return Text(
            context.t(LocaleKeys.relationEvidenceDeleted),
            style: typo.uiSmall.copyWith(color: colors.textMuted),
          );
        }
        return Align(
          alignment: AlignmentDirectional.centerStart,
          child: RevericButton.text(
            size: RevericButtonSize.compact,
            icon: RevericIcons.menu_book_outlined,
            label: evidenceChoiceLabel(context, choice),
            onPressed: onOpen == null ? null : () => onOpen!(kind, id),
          ),
        );
      },
    );
  }
}
