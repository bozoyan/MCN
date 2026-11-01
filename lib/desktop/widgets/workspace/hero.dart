// 职责: 桌面端小说概览页"继续写作" hero 卡片 — 上次写到的句子预览、继续写按钮、次要入口
// 关联文件:
//   lib/desktop/widgets/workspace/novel_overview.dart
//   lib/shared/models/novel_workspace.dart
//   lib/shared/database/novel_content_database.dart
//   lib/shared/utils/chapter_last_sentence.dart
//   lib/shared/components/reveric_surfaces.dart
//   lib/shared/theme/theme.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/workspace.json
//   assets/translations/zh-CN/workspace.json
import 'package:flutter/material.dart';

import '../../../shared/components/reveric_button.dart';
import '../../../shared/components/reveric_surfaces.dart';
import '../../../shared/database/novel_content_database.dart';
import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/models/novel_workspace.dart';
import '../../../shared/theme/theme.dart';
import '../../../shared/utils/chapter_last_sentence.dart';

class ContinueWritingHero extends StatelessWidget {
  const ContinueWritingHero({
    super.key,
    required this.chapters,
    this.lastWrittenChapter,
    required this.onSelectionChanged,
    required this.onContinueWriting,
  });

  final List<Chapter> chapters;
  final Chapter? lastWrittenChapter;
  final ValueSetter<WorkspaceSelection> onSelectionChanged;
  final ValueChanged<String> onContinueWriting;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final latest = _resolveLatestChapter(chapters);
    final lastWritten = lastWrittenChapter;
    final lastSentence = extractLastWrittenSentence(lastWritten?.content);
    final hasChapter = latest != null;
    final continueLabel = hasChapter
        ? context.t(
            LocaleKeys.workspaceContinueChapter,
            namedArgs: {'number': '${latest.chapterNum ?? "?"}'},
          )
        : context.t(LocaleKeys.workspaceStartFirstChapter);
    // 当"上次写到"来源章节不是当前要继续的最新章节时，
    // 在标题里提示用户句子来自更早的一章，避免误以为最新章已写过内容。
    final isLastFromOlderChapter =
        lastWritten != null && latest != null && lastWritten.id != latest.id;
    final lastWroteLabel = isLastFromOlderChapter
        ? context.t(
            LocaleKeys.workspaceLastWroteFromChapter,
            namedArgs: {'number': '${lastWritten.chapterNum ?? "?"}'},
          )
        : context.t(LocaleKeys.workspaceLastWroteText);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 600;
        final isWide = constraints.maxWidth > 900;

        return RevericElevatedCard(
          fallback: colors.surfaceContainerHigh,
          clipBehavior: Clip.antiAlias,
          gradientColors: (fill, active) => [
            fill,
            colors.accentWarm.withValues(alpha: active ? 0.06 : 0.08),
          ],
          child: Stack(
            children: [
              Positioned(
                right: isWide ? constraints.maxWidth * 0.15 : -40,
                top: isCompact ? -50 : -30,
                child: _DecorativeOrb(
                  size: isWide ? 280 : (isCompact ? 180 : 220),
                  color: colors.accentAmber.withValues(alpha: 0.18),
                ),
              ),
              Positioned(
                right: isWide ? constraints.maxWidth * 0.35 : 60,
                bottom: isCompact ? -40 : -60,
                child: _DecorativeOrb(
                  size: isWide ? 200 : (isCompact ? 120 : 160),
                  color: colors.accent.withValues(alpha: 0.10),
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  isCompact ? RevericSpacing.x2l : RevericSpacing.x4l,
                  isCompact ? RevericSpacing.x2l : RevericSpacing.x4l,
                  isCompact ? RevericSpacing.x2l : RevericSpacing.x4l,
                  isCompact ? RevericSpacing.x2l : RevericSpacing.x4l,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        RevericIcon(
                          RevericIcons.eco_outlined,
                          size: 18,
                          color: colors.accentWarm,
                        ),
                        const SizedBox(width: RevericSpacing.sm),
                        Text(
                          context.t(LocaleKeys.workspaceContinueWriting),
                          style: typo.uiSemibold.copyWith(
                            color: colors.accentWarm,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: RevericSpacing.x2l),
                    Text(
                      lastWroteLabel,
                      style: typo.uiSmall.copyWith(color: colors.textMuted),
                    ),
                    const SizedBox(height: RevericSpacing.md),
                    Text(
                      lastSentence ??
                          context.t(LocaleKeys.workspaceLastWroteEmpty),
                      style: typo.heading2.copyWith(
                        color: colors.textPrimary,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: RevericSpacing.md),
                    Text(
                      context.t(LocaleKeys.workspaceContinueWritingHint),
                      style: typo.uiSmall.copyWith(color: colors.textMuted),
                    ),
                    const SizedBox(height: RevericSpacing.x2l),
                    if (isCompact)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          RevericButton.primary(
                            onPressed: () => onContinueWriting(continueLabel),
                            icon: RevericIcons.create_outlined,
                            label: continueLabel,
                          ),
                          const SizedBox(height: RevericSpacing.lg),
                          Wrap(
                            spacing: RevericSpacing.sm,
                            runSpacing: RevericSpacing.sm,
                            children: [
                              RevericButton.secondary(
                                icon: RevericIcons.list_alt_outlined,
                                label: context.t(
                                  LocaleKeys.workspaceViewOutline,
                                ),
                                onPressed: () => onSelectionChanged(
                                  const WorkspaceSelection(
                                    section: NovelWorkspaceSection.outlines,
                                    isViewingAllOutlines: true,
                                  ),
                                ),
                              ),
                              RevericButton.secondary(
                                icon: RevericIcons.public_outlined,
                                label: context.t(
                                  LocaleKeys.workspaceBrowseSettings,
                                ),
                                onPressed: () => onSelectionChanged(
                                  const WorkspaceSelection(
                                    section: NovelWorkspaceSection.lore,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      )
                    else
                      Row(
                        children: [
                          RevericButton.primary(
                            onPressed: () => onContinueWriting(continueLabel),
                            icon: RevericIcons.create_outlined,
                            label: continueLabel,
                          ),
                          const SizedBox(width: RevericSpacing.x2l),
                          Expanded(
                            child: Wrap(
                              spacing: RevericSpacing.sm,
                              runSpacing: RevericSpacing.sm,
                              children: [
                                RevericButton.secondary(
                                  icon: RevericIcons.list_alt_outlined,
                                  label: context.t(
                                    LocaleKeys.workspaceViewOutline,
                                  ),
                                  onPressed: () => onSelectionChanged(
                                    const WorkspaceSelection(
                                      section: NovelWorkspaceSection.outlines,
                                      isViewingAllOutlines: true,
                                    ),
                                  ),
                                ),
                                RevericButton.secondary(
                                  icon: RevericIcons.public_outlined,
                                  label: context.t(
                                    LocaleKeys.workspaceBrowseSettings,
                                  ),
                                  onPressed: () => onSelectionChanged(
                                    const WorkspaceSelection(
                                      section: NovelWorkspaceSection.lore,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Chapter? _resolveLatestChapter(List<Chapter> chapters) {
    final filtered = chapters.where((c) => c.isNumberedChapter).toList();
    if (filtered.isEmpty) {
      return null;
    }
    filtered.sort((a, b) {
      final an = a.chapterNum ?? 0;
      final bn = b.chapterNum ?? 0;
      return bn.compareTo(an);
    });
    return filtered.first;
  }
}

class _DecorativeOrb extends StatelessWidget {
  const _DecorativeOrb({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
        ),
      ),
    );
  }
}
