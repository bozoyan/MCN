// 职责: 备份恢复子页面 — 展示备份摘要并收集完整覆盖或小说级覆盖范围。
// 关联文件:
//   lib/shared/widgets/settings/backup_settings_section.dart
//   lib/shared/services/backup_service.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/settings.json
//   assets/translations/zh-CN/settings.json
// 遵循的 Rules:
//   .agents/rules/hooks.md
//   .agents/rules/design-system.md

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:intl/intl.dart';

import '../../components/reveric_button.dart';
import '../../localization/app_localization.dart';
import '../../localization/locale_keys.dart';
import '../../services/backup_service.dart';
import '../../theme/theme.dart';

/// 窗口太矮放不下整个列表时，列表至少保留的高度；再矮就退回整页滚动。
const double _minNovelListHeight = 120;

class BackupRestoreSelection {
  const BackupRestoreSelection({required this.mode, required this.novelIds});

  final RestoreMode mode;
  final Set<String> novelIds;
}

class BackupRestorePage extends HookWidget {
  const BackupRestorePage({
    super.key,
    required this.preview,
    required this.compact,
    required this.isRestoring,
    required this.onBack,
    required this.onRestore,
  });

  final BackupRestorePreview preview;
  final bool compact;
  final bool isRestoring;
  final VoidCallback onBack;
  final Future<void> Function(BackupRestoreSelection selection) onRestore;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final mode = useState(RestoreMode.selectedNovels);
    final selectedNovelIds = useState(const <String>{});
    final restorableNovels = preview.novels
        .where((novel) => novel.canRestore)
        .toList(growable: false);
    final canSubmit =
        mode.value == RestoreMode.fullReplacement ||
        selectedNovelIds.value.isNotEmpty;
    final confirmationKey = mode.value == RestoreMode.fullReplacement
        ? LocaleKeys.settingsBackupRestoreConfirmFull
        : LocaleKeys.settingsBackupRestoreConfirmMessage;
    final pagePadding = compact ? RevericSpacing.x3l : RevericSpacing.x4l;

    Widget buildNovelList(double listMaxHeight) {
      return Container(
        constraints: BoxConstraints(maxHeight: listMaxHeight),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          border: Border.all(color: colors.borderSubtle),
          borderRadius: BorderRadius.circular(RevericRadius.medium),
        ),
        child: ListView.separated(
          shrinkWrap: true,
          itemCount: preview.novels.length,
          separatorBuilder: (_, _) =>
              Divider(height: 1, color: colors.borderSubtle),
          itemBuilder: (context, index) {
            final novel = preview.novels[index];
            final selected = selectedNovelIds.value.contains(novel.id);
            return CheckboxListTile(
              key: ValueKey('restore_novel_${novel.id}'),
              value: selected,
              onChanged: novel.canRestore && !isRestoring
                  ? (checked) {
                      final next = selectedNovelIds.value.toSet();
                      if (checked ?? false) {
                        next.add(novel.id);
                      } else {
                        next.remove(novel.id);
                      }
                      selectedNovelIds.value = next;
                    }
                  : null,
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: RevericSpacing.md,
              ),
              title: Text(
                novel.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: typo.ui.copyWith(color: colors.textPrimary),
              ),
              subtitle: Text(
                _novelStatus(context, novel),
                style: typo.uiSmall.copyWith(
                  color: _novelStatusColor(colors, novel),
                ),
              ),
            );
          },
        ),
      );
    }

    return Column(
      children: [
        Expanded(
          child: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  pagePadding,
                  pagePadding,
                  pagePadding,
                  0,
                ),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          IconButton(
                            key: const ValueKey('restore_back_button'),
                            onPressed: isRestoring ? null : onBack,
                            tooltip: context.t(
                              LocaleKeys.settingsBackupRestoreCancel,
                            ),
                            icon: const RevericIcon(
                              RevericIcons.arrow_back,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: RevericSpacing.xs),
                          Expanded(
                            child: Text(
                              context.t(
                                LocaleKeys.settingsBackupRestoreConfirmTitle,
                              ),
                              style: compact
                                  ? typo.uiSemibold.copyWith(
                                      color: colors.textPrimary,
                                    )
                                  : typo.heading2.copyWith(
                                      color: colors.textPrimary,
                                    ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: RevericSpacing.lg),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 680),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: RevericSpacing.x2l,
                              runSpacing: RevericSpacing.xs,
                              children: [
                                Text(
                                  context.t(
                                    LocaleKeys
                                        .settingsBackupRestorePreviewCreatedAt,
                                    namedArgs: {
                                      'date': DateFormat(
                                        'yyyy-MM-dd HH:mm',
                                      ).format(preview.createdAt.toLocal()),
                                    },
                                  ),
                                  style: typo.uiSmall.copyWith(
                                    color: colors.textMuted,
                                  ),
                                ),
                                Text(
                                  context.t(
                                    LocaleKeys
                                        .settingsBackupRestorePreviewNovels,
                                    namedArgs: {
                                      'count': preview.novels.length.toString(),
                                    },
                                  ),
                                  style: typo.uiSmall.copyWith(
                                    color: colors.textMuted,
                                  ),
                                ),
                              ],
                            ),
                            if (preview.warningCount > 0) ...[
                              const SizedBox(height: RevericSpacing.md),
                              _RestoreNotice(
                                icon: RevericIcons.warning_amber_rounded,
                                message: context.t(
                                  LocaleKeys
                                      .settingsBackupRestorePreviewWarnings,
                                  namedArgs: {
                                    'count': preview.warningCount.toString(),
                                  },
                                ),
                              ),
                            ],
                            const SizedBox(height: RevericSpacing.lg),
                            RadioGroup<RestoreMode>(
                              groupValue: mode.value,
                              onChanged: (value) {
                                if (!isRestoring && value != null) {
                                  mode.value = value;
                                }
                              },
                              child: Column(
                                children: [
                                  RadioListTile<RestoreMode>(
                                    key: const ValueKey('restore_mode_full'),
                                    value: RestoreMode.fullReplacement,
                                    enabled: !isRestoring,
                                    contentPadding: EdgeInsets.zero,
                                    title: Text(
                                      context.t(
                                        LocaleKeys
                                            .settingsBackupRestoreModeFull,
                                      ),
                                      style: typo.uiSemibold.copyWith(
                                        color: colors.textPrimary,
                                      ),
                                    ),
                                    subtitle: Text(
                                      context.t(
                                        LocaleKeys
                                            .settingsBackupRestoreModeFullDescription,
                                      ),
                                      style: typo.uiSmall.copyWith(
                                        color: colors.textMuted,
                                      ),
                                    ),
                                  ),
                                  RadioListTile<RestoreMode>(
                                    key: const ValueKey(
                                      'restore_mode_selected',
                                    ),
                                    value: RestoreMode.selectedNovels,
                                    enabled:
                                        !isRestoring &&
                                        restorableNovels.isNotEmpty,
                                    contentPadding: EdgeInsets.zero,
                                    title: Text(
                                      context.t(
                                        LocaleKeys
                                            .settingsBackupRestoreModeSelected,
                                      ),
                                      style: typo.uiSemibold.copyWith(
                                        color: colors.textPrimary,
                                      ),
                                    ),
                                    subtitle: Text(
                                      context.t(
                                        LocaleKeys
                                            .settingsBackupRestoreModeSelectedDescription,
                                      ),
                                      style: typo.uiSmall.copyWith(
                                        color: colors.textMuted,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (mode.value == RestoreMode.selectedNovels) ...[
                              const SizedBox(height: RevericSpacing.md),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Flexible(
                                    child: Text(
                                      context.t(
                                        LocaleKeys
                                            .settingsBackupRestoreSelectNovels,
                                      ),
                                      style: typo.uiSemibold.copyWith(
                                        color: colors.textPrimary,
                                      ),
                                    ),
                                  ),
                                  Flexible(
                                    child: TextButton(
                                      key: const ValueKey('restore_select_all'),
                                      onPressed: isRestoring
                                          ? null
                                          : () {
                                              final allSelected =
                                                  selectedNovelIds
                                                      .value
                                                      .length ==
                                                  restorableNovels.length;
                                              selectedNovelIds.value =
                                                  allSelected
                                                  ? const <String>{}
                                                  : restorableNovels
                                                        .map(
                                                          (novel) => novel.id,
                                                        )
                                                        .toSet();
                                            },
                                      child: Text(
                                        selectedNovelIds.value.length ==
                                                restorableNovels.length
                                            ? context.t(
                                                LocaleKeys
                                                    .settingsBackupRestoreClearAll,
                                              )
                                            : context.t(
                                                LocaleKeys
                                                    .settingsBackupRestoreSelectAll,
                                              ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  pagePadding,
                  0,
                  pagePadding,
                  RevericSpacing.lg,
                ),
                sliver: mode.value == RestoreMode.selectedNovels
                    ? SliverLayoutBuilder(
                        builder: (context, constraints) {
                          final remaining =
                              constraints.viewportMainAxisExtent -
                              constraints.precedingScrollExtent -
                              RevericSpacing.lg;
                          return SliverToBoxAdapter(
                            child: Align(
                              alignment: Alignment.topLeft,
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 680,
                                ),
                                child: buildNovelList(
                                  math.max(remaining, _minNovelListHeight),
                                ),
                              ),
                            ),
                          );
                        },
                      )
                    : const SliverToBoxAdapter(child: SizedBox.shrink()),
              ),
            ],
          ),
        ),
        _RestoreActionFooter(
          compact: compact,
          isRestoring: isRestoring,
          message: context.t(confirmationKey),
          onBack: onBack,
          onConfirm: canSubmit && !isRestoring
              ? () => onRestore(
                  BackupRestoreSelection(
                    mode: mode.value,
                    novelIds: Set<String>.unmodifiable(selectedNovelIds.value),
                  ),
                )
              : null,
        ),
      ],
    );
  }

  String _novelStatus(BuildContext context, BackupNovelSummary novel) {
    if (novel.hasTitleConflict) {
      return context.t(LocaleKeys.settingsBackupRestoreNovelConflict);
    }
    if (!novel.hasContentDatabase) {
      return context.t(LocaleKeys.settingsBackupRestoreNovelMissingContent);
    }
    return context.t(
      novel.existsInCurrentLibrary
          ? LocaleKeys.settingsBackupRestoreNovelOverwrite
          : LocaleKeys.settingsBackupRestoreNovelImport,
    );
  }

  Color _novelStatusColor(RevericColors colors, BackupNovelSummary novel) {
    if (!novel.canRestore || novel.existsInCurrentLibrary) {
      return colors.warningText;
    }
    return colors.additionBorder;
  }
}

class _RestoreActionFooter extends StatelessWidget {
  const _RestoreActionFooter({
    required this.compact,
    required this.isRestoring,
    required this.message,
    required this.onBack,
    required this.onConfirm,
  });

  final bool compact;
  final bool isRestoring;
  final String message;
  final VoidCallback onBack;
  final VoidCallback? onConfirm;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final horizontalPadding = compact ? RevericSpacing.x3l : RevericSpacing.x4l;
    final typo = RevericTheme.typographyOf(context);
    final notice = Row(
      key: const ValueKey('restore_confirmation_notice'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RevericIcon(
          RevericIcons.warning_amber_rounded,
          size: RevericSizes.buttonIconSize,
          color: colors.warningText,
        ),
        const SizedBox(width: RevericSpacing.sm),
        Expanded(
          child: Text(
            message,
            style: typo.uiSmall.copyWith(color: colors.textSecondary),
          ),
        ),
      ],
    );
    final actions = Wrap(
      alignment: WrapAlignment.end,
      spacing: RevericSpacing.md,
      runSpacing: RevericSpacing.sm,
      children: [
        RevericButton.secondary(
          onPressed: isRestoring ? null : onBack,
          label: context.t(LocaleKeys.settingsBackupRestoreCancel),
        ),
        RevericButton.danger(
          key: const ValueKey('restore_confirm_button'),
          onPressed: onConfirm,
          loading: isRestoring,
          icon: RevericIcons.upload,
          label: context.t(
            isRestoring
                ? LocaleKeys.settingsBackupRestoreInProgress
                : LocaleKeys.settingsBackupRestoreConfirmRestore,
          ),
        ),
      ],
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.canvas,
        border: Border(top: BorderSide(color: colors.borderSubtle)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            RevericSpacing.md,
            horizontalPadding,
            compact ? RevericSpacing.md : RevericSpacing.x2l,
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final textScale = MediaQuery.textScalerOf(context).scale(1);
                  if (!compact && constraints.maxWidth >= 600 * textScale) {
                    return Row(
                      children: [
                        Expanded(child: notice),
                        const SizedBox(width: RevericSpacing.x4l),
                        actions,
                      ],
                    );
                  }
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      notice,
                      const SizedBox(height: RevericSpacing.lg),
                      actions,
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RestoreNotice extends StatelessWidget {
  const _RestoreNotice({required this.icon, required this.message});

  final String icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return Container(
      padding: const EdgeInsets.all(RevericSpacing.md),
      decoration: BoxDecoration(
        color: colors.warningBg,
        borderRadius: BorderRadius.circular(RevericRadius.medium),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RevericIcon(icon, size: 18, color: colors.warningText),
          const SizedBox(width: RevericSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: typo.uiSmall.copyWith(color: colors.warningText),
            ),
          ),
        ],
      ),
    );
  }
}
