// 职责: 封面档案小节 — 未读 / 读取中 / 已读 / 已读但过时 四态，以及「重新读一遍」。
// 关联文件:
//   lib/shared/services/ai/cover_brief_service.dart
//   lib/shared/providers/cover_providers.dart
//   lib/shared/models/cover_brief.dart
//   lib/shared/services/cover_prompt_builder.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/editor.json
//   assets/translations/zh-CN/editor.json
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/i18n.md

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../localization/app_localization.dart';
import '../../localization/locale_keys.dart';
import '../../models/cover_brief.dart';
import '../../providers/cover_providers.dart';
import '../../services/ai/cover_brief_service.dart';
import '../../services/cover_prompt_builder.dart';
import '../../theme/theme.dart';
import 'chips.dart';

class CoverBriefSection extends ConsumerWidget {
  const CoverBriefSection({
    super.key,
    required this.databasePath,
    required this.onRead,
    required this.onAppend,
  });

  final String databasePath;
  final VoidCallback onRead;
  final ValueChanged<String> onAppend;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref
        .watch(coverBriefStateProvider(databasePath))
        .asData
        ?.value;
    final stale =
        ref.watch(coverBriefStaleProvider(databasePath)).asData?.value ?? false;
    final brief = state?.brief;
    final reading = state?.reading ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CoverSectionHead(
          icon: RevericIcons.lightbulb_outline,
          label: context.t(LocaleKeys.editorCoverBrief),
          trailing: brief != null && !reading
              ? TextButton(
                  onPressed: onRead,
                  child: Text(context.t(LocaleKeys.editorCoverBriefReread)),
                )
              : null,
        ),
        if (reading)
          _Reading()
        else if (brief == null)
          _Blank(onRead: onRead)
        else ...[
          if (stale) ...[
            CoverAlert(context.t(LocaleKeys.editorCoverBriefStale)),
            const SizedBox(height: RevericSpacing.sm),
          ],
          Text(
            context.t(LocaleKeys.editorCoverAppendHint),
            style: RevericTheme.typographyOf(
              context,
            ).uiTiny.copyWith(color: RevericTheme.colorsOf(context).textMuted),
          ),
          const SizedBox(height: RevericSpacing.sm),
          _BriefBody(brief: brief, onAppend: onAppend),
        ],
      ],
    );
  }
}

/// 读取中用不确定进度：只读开头三章、只发一次调用，逐章百分比是假的。
class _Reading extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: RevericSpacing.lg,
        vertical: RevericSpacing.md,
      ),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHigh,
        border: Border.all(color: colors.borderSubtle),
        borderRadius: BorderRadius.circular(RevericRadius.large),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LinearProgressIndicator(
            color: colors.accent,
            backgroundColor: colors.borderSubtle,
          ),
          const SizedBox(height: RevericSpacing.md),
          Text(
            context.t(
              LocaleKeys.editorCoverBriefReading,
              namedArgs: {'count': '$coverBriefChapterCount'},
            ),
            style: typo.uiTiny.copyWith(color: colors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _Blank extends StatelessWidget {
  const _Blank({required this.onRead});

  final VoidCallback onRead;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: RevericSpacing.lg,
        vertical: RevericSpacing.md,
      ),
      decoration: BoxDecoration(
        color: colors.surfaceContainer,
        border: Border.all(color: colors.borderSubtle),
        borderRadius: BorderRadius.circular(RevericRadius.large),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.t(LocaleKeys.editorCoverBriefBlankNote),
            style: typo.uiTiny.copyWith(color: colors.textMuted),
          ),
          const SizedBox(height: RevericSpacing.md),
          OutlinedButton.icon(
            onPressed: onRead,
            icon: const RevericIcon(RevericIcons.book, size: 14),
            label: Text(context.t(LocaleKeys.editorCoverBriefRead)),
          ),
        ],
      ),
    );
  }
}

class _BriefBody extends StatelessWidget {
  const _BriefBody({required this.brief, required this.onAppend});

  final CoverBrief brief;
  final ValueChanged<String> onAppend;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final rows = <({String uiLabel, String value, String fragment})>[
      (
        uiLabel: context.t(LocaleKeys.editorCoverBriefCategory),
        value: brief.category,
        fragment: coverBriefFieldSnippet('品类', brief.category),
      ),
      (
        uiLabel: context.t(LocaleKeys.editorCoverStyle),
        value: brief.style,
        fragment: coverBriefFieldSnippet('风格', brief.style),
      ),
      (
        uiLabel: context.t(LocaleKeys.editorCoverPalette),
        value: brief.palette,
        fragment: coverBriefFieldSnippet('色调', brief.palette),
      ),
      (
        uiLabel: context.t(LocaleKeys.editorCoverBriefTemperature),
        value: brief.temperature,
        fragment: coverBriefFieldSnippet('色温', brief.temperature),
      ),
      (
        uiLabel: context.t(LocaleKeys.editorCoverBriefFigure),
        value: brief.figure,
        fragment: coverBriefFieldSnippet('主角', brief.figure),
      ),
      (
        uiLabel: context.t(LocaleKeys.editorCoverBriefEra),
        value: brief.era,
        fragment: coverBriefFieldSnippet('时代', brief.era),
      ),
    ].where((row) => row.value.trim().isNotEmpty).toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
            horizontal: RevericSpacing.sm,
            vertical: RevericSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: colors.surfaceContainerHigh,
            border: Border.all(color: colors.borderSubtle),
            borderRadius: BorderRadius.circular(RevericRadius.large),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final row in rows)
                Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    onTap: () => onAppend(row.fragment),
                    borderRadius: BorderRadius.circular(RevericRadius.small),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: RevericSpacing.sm,
                        vertical: RevericSpacing.xs,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 32,
                            child: Text(
                              row.uiLabel,
                              style: typo.uiTiny.copyWith(
                                color: colors.textSubtle,
                                height: 1.7,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              row.value,
                              style: typo.uiTiny.copyWith(
                                color: colors.textSecondary,
                                height: 1.7,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: RevericSpacing.sm),
        // 「按哪一版稿子读的」—— 判断要不要重读全靠这一行。
        Row(
          children: [
            RevericIcon(
              RevericIcons.clock,
              size: 12,
              color: colors.textSubtle,
            ),
            const SizedBox(width: RevericSpacing.xxs),
            Expanded(
              child: Text(
                context.t(
                  LocaleKeys.editorCoverBriefFooter,
                  namedArgs: {
                    'when': _timeLabel(brief.readAt),
                    'chapters': '${brief.chapterCount}',
                    'words': '${brief.wordCount}',
                  },
                ),
                style: typo.uiTiny.copyWith(color: colors.textSubtle),
              ),
            ),
          ],
        ),
      ],
    );
  }

  String _timeLabel(DateTime readAt) {
    final local = readAt.toLocal();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '${local.month}/${local.day} $hh:$mm';
  }
}

/// 设计灵感：读稿抽出来的候选意象，点一下追加进提示词。
/// 从封面档案里拆出来单独成节 —— 它是「可以画什么」，不是档案的第五个字段。
class CoverInspirationSection extends ConsumerWidget {
  const CoverInspirationSection({
    super.key,
    required this.databasePath,
    required this.onAppend,
  });

  final String databasePath;
  final ValueChanged<String> onAppend;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final motifs =
        ref
            .watch(coverBriefStateProvider(databasePath))
            .asData
            ?.value
            .brief
            ?.motifs ??
        const <CoverBriefMotif>[];
    if (motifs.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CoverSectionHead(
          icon: RevericIcons.lightbulb_outline,
          label: context.t(LocaleKeys.editorCoverInspiration),
        ),
        Text(
          context.t(LocaleKeys.editorCoverAppendHint),
          style: typo.uiTiny.copyWith(color: colors.textMuted),
        ),
        const SizedBox(height: RevericSpacing.sm),
        for (final motif in motifs)
          Padding(
            padding: const EdgeInsets.only(bottom: RevericSpacing.xs),
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: () => onAppend(coverMotifSnippet(motif)),
                borderRadius: BorderRadius.circular(RevericRadius.small),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: RevericSpacing.xxs,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          '· ${motif.text}',
                          style: typo.uiTiny.copyWith(color: colors.textMuted),
                        ),
                      ),
                      if (motif.from.isNotEmpty) ...[
                        const SizedBox(width: RevericSpacing.sm),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: colors.surfaceContainer,
                            borderRadius: BorderRadius.circular(
                              RevericRadius.small,
                            ),
                          ),
                          child: Text(
                            motif.from,
                            style: typo.uiTiny.copyWith(
                              color: colors.textSubtle,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
