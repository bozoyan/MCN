// 职责: 伏笔编辑器 — 组织伏笔标题、状态、埋设与回收内容、关联位置编辑 UI。
// 关联文件:
//   lib/desktop/widgets/workspace/novel_workspace_panel.dart
//   lib/desktop/widgets/workspace/chapter_list_dropdown.dart
//   lib/shared/components/reveric_select.dart
//   lib/shared/components/reveric_text_field.dart
//   lib/shared/models/foreshadowing.dart
//   lib/shared/providers/novel_providers.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
//   assets/translations/en/workspace.json
//   assets/translations/zh-CN/workspace.json
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/hooks.md
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../shared/components/reveric_select.dart';
import '../../../shared/components/reveric_text_field.dart';
import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/widgets/foreshadowing/position_links.dart';
import '../../../shared/models/foreshadowing.dart';
import '../../../shared/theme/theme.dart';
import '../../../shared/widgets/md/reveric_markdown_editor.dart';

class ForeshadowingEditor extends HookConsumerWidget {
  const ForeshadowingEditor({
    super.key,
    required this.selectedItemId,
    this.isCreating = false,
    required this.foreshadowings,
    required this.titleController,
    required this.setupController,
    required this.payoffController,
    required this.titleFocusNode,
    required this.setupFocusNode,
    required this.payoffFocusNode,
    this.titleErrorText,
    required this.selectedStatus,
    required this.onStatusChanged,
    required this.positions,
    required this.onPositionsChanged,
    required this.onCreateForeshadowing,
    this.editorFontFamily = 'Georgia',
    this.editorFontSize = 16,
    this.databasePath,
    this.onNavigateToChapter,
    this.onNavigateToPosition,
  });

  final String? selectedItemId;
  final bool isCreating;
  final List<Foreshadowing> foreshadowings;
  final TextEditingController titleController;
  final TextEditingController setupController;
  final TextEditingController payoffController;
  final FocusNode titleFocusNode;
  final FocusNode setupFocusNode;
  final FocusNode payoffFocusNode;
  final String? titleErrorText;
  final String selectedStatus;
  final ValueChanged<String> onStatusChanged;
  final ForeshadowingPositionIds positions;
  final ValueChanged<ForeshadowingPositionIds> onPositionsChanged;
  final VoidCallback onCreateForeshadowing;
  final String editorFontFamily;
  final int editorFontSize;
  final String? databasePath;
  final ValueChanged<String>? onNavigateToChapter;
  final ValueChanged<ForeshadowingPositionTarget>? onNavigateToPosition;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pageScrollController = useScrollController();

    if (selectedItemId == null && !isCreating) {
      return _EmptyForeshadowingEditorState(
        hasForeshadowings: foreshadowings.isNotEmpty,
        onCreate: onCreateForeshadowing,
      );
    }

    Widget positionField(String position) => ForeshadowingPositionLinks(
      databasePath: databasePath!,
      value: positions,
      onChanged: onPositionsChanged,
      positions: [position],
      rowBuilder: (label, value) =>
          _ForeshadowingMetaLabeled(label: label, child: value),
      onNavigate:
          onNavigateToPosition ??
          (target) => onNavigateToChapter?.call(target.id),
    );

    return Scrollbar(
      controller: pageScrollController,
      thumbVisibility: true,
      child: CustomScrollView(
        controller: pageScrollController,
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              RevericSpacing.x6l,
              RevericSpacing.x4l,
              RevericSpacing.x6l,
              0,
            ),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ForeshadowingMetaGrid(
                    rows: [
                      [
                        _ForeshadowingMetaTextField(
                          label: context.t(LocaleKeys.commonTitle),
                          controller: titleController,
                          focusNode: titleFocusNode,
                          hintText: context.t(
                            LocaleKeys.workspaceEntryTitleHint,
                          ),
                          errorText: titleErrorText,
                        ),
                        _ForeshadowingMetaStatusField(
                          label: context.t(LocaleKeys.commonStatus),
                          value: selectedStatus,
                          options: foreshadowingStatuses,
                          optionLabels: {
                            for (final status in foreshadowingStatuses)
                              status: _statusLabel(context, status),
                          },
                          onChanged: onStatusChanged,
                        ),
                      ],
                      // 新建时同样可选位置，随「保存」一并创建。
                      if (databasePath != null)
                        [positionField('setup'), positionField('payoff')],
                    ],
                  ),
                  const SizedBox(height: RevericSpacing.x3l),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              RevericSpacing.x6l,
              0,
              RevericSpacing.x6l,
              RevericSpacing.x6l,
            ),
            sliver: SliverLayoutBuilder(
              builder: (context, sliverConstraints) {
                final remainingHeight =
                    sliverConstraints.viewportMainAxisExtent -
                    sliverConstraints.precedingScrollExtent -
                    RevericSpacing.x6l;
                final markdownHeight = math.max(360.0, remainingHeight);

                return SliverToBoxAdapter(
                  child: SizedBox(
                    height: markdownHeight,
                    child: _ForeshadowingMarkdownLayout(
                      setupLabel: context.t(LocaleKeys.commonSetup),
                      payoffLabel: context.t(LocaleKeys.commonPayoff),
                      setup: _ForeshadowingMarkdownSection(
                        label: context.t(LocaleKeys.commonSetup),
                        controller: setupController,
                        focusNode: setupFocusNode,
                        hintText: context.t(
                          LocaleKeys.workspaceForeshadowSetupHint,
                        ),
                        fontFamily: editorFontFamily,
                        fontSize: editorFontSize,
                        showLabel: false,
                      ),
                      payoff: _ForeshadowingMarkdownSection(
                        label: context.t(LocaleKeys.commonPayoff),
                        controller: payoffController,
                        focusNode: payoffFocusNode,
                        hintText: context.t(
                          LocaleKeys.workspaceForeshadowPayoffHint,
                        ),
                        fontFamily: editorFontFamily,
                        fontSize: editorFontSize,
                        showLabel: false,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyForeshadowingEditorState extends StatelessWidget {
  const _EmptyForeshadowingEditorState({
    required this.hasForeshadowings,
    required this.onCreate,
  });

  final bool hasForeshadowings;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(RevericSpacing.x6l),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RevericIcon(
              RevericIcons.alt_route_outlined,
              color: colors.textSubtle,
              size: 32,
            ),
            const SizedBox(height: RevericSpacing.lg),
            Text(
              context.t(
                LocaleKeys.workspaceNoEntrySelected,
                namedArgs: {
                  'type': context.t(LocaleKeys.workspaceForeshadowings),
                },
              ),
              style: typo.uiSemibold.copyWith(color: colors.textPrimary),
            ),
            const SizedBox(height: RevericSpacing.sm),
            Text(
              hasForeshadowings
                  ? context.t(
                      LocaleKeys.workspaceSelectEntryToEdit,
                      namedArgs: {
                        'type': context.t(LocaleKeys.workspaceForeshadowings),
                      },
                    )
                  : context.t(
                      LocaleKeys.workspaceCreateFirstEntry,
                      namedArgs: {
                        'type': context.t(LocaleKeys.workspaceForeshadowings),
                      },
                    ),
              style: typo.ui.copyWith(color: colors.textMuted),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: RevericSpacing.x2l),
            FilledButton(
              onPressed: onCreate,
              child: Text(context.t(LocaleKeys.workspaceNewForeshadowing)),
            ),
          ],
        ),
      ),
    );
  }
}

class _ForeshadowingMarkdownLayout extends StatelessWidget {
  const _ForeshadowingMarkdownLayout({
    required this.setupLabel,
    required this.payoffLabel,
    required this.setup,
    required this.payoff,
  });

  final String setupLabel;
  final String payoffLabel;
  final Widget setup;
  final Widget payoff;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Builder(
        builder: (context) {
          final controller = DefaultTabController.of(context);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ForeshadowingMarkdownTabs(
                controller: controller,
                setupLabel: setupLabel,
                payoffLabel: payoffLabel,
              ),
              const SizedBox(height: RevericSpacing.sm),
              Expanded(
                child: TabBarView(
                  controller: controller,
                  children: [setup, payoff],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ForeshadowingMarkdownTabs extends StatelessWidget {
  const _ForeshadowingMarkdownTabs({
    required this.controller,
    required this.setupLabel,
    required this.payoffLabel,
  });

  final TabController controller;
  final String setupLabel;
  final String payoffLabel;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);

    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceContainer,
        borderRadius: BorderRadius.circular(RevericRadius.button),
      ),
      padding: const EdgeInsets.all(RevericSpacing.xxs),
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          return Row(
            children: [
              Expanded(
                child: _ForeshadowingMarkdownTabButton(
                  label: setupLabel,
                  selected: controller.index == 0,
                  onTap: () => controller.animateTo(0),
                  colors: colors,
                  typo: typo,
                ),
              ),
              Expanded(
                child: _ForeshadowingMarkdownTabButton(
                  label: payoffLabel,
                  selected: controller.index == 1,
                  onTap: () => controller.animateTo(1),
                  colors: colors,
                  typo: typo,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ForeshadowingMarkdownTabButton extends StatelessWidget {
  const _ForeshadowingMarkdownTabButton({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.colors,
    required this.typo,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final RevericColors colors;
  final RevericTypography typo;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? colors.selected : colors.surfaceContainer,
      borderRadius: BorderRadius.circular(RevericRadius.capsule),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(RevericRadius.capsule),
        hoverColor: colors.hover,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: RevericSpacing.x2l,
            vertical: RevericSpacing.sm,
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: typo.uiSemibold.copyWith(
              color: selected ? colors.textPrimary : colors.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}

class _ForeshadowingMarkdownSection extends StatelessWidget {
  const _ForeshadowingMarkdownSection({
    required this.label,
    required this.controller,
    required this.focusNode,
    required this.hintText,
    required this.fontFamily,
    required this.fontSize,
    this.showLabel = true,
  });

  final String label;
  final TextEditingController controller;
  final FocusNode focusNode;
  final String hintText;
  final String fontFamily;
  final int fontSize;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showLabel) ...[
          Text(
            label,
            style: typo.uiSemibold.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: RevericSpacing.sm),
        ],
        Expanded(
          child: RevericMarkdownEditor(
            controller: controller,
            focusNode: focusNode,
            hintText: hintText,
            fontFamily: fontFamily,
            fontSize: fontSize,
          ),
        ),
      ],
    );
  }
}

/// 元信息字段网格：无外框，宽屏每行两列（列宽一致，上下行对齐），窄屏逐个竖排。
class _ForeshadowingMetaGrid extends StatelessWidget {
  const _ForeshadowingMetaGrid({required this.rows});

  final List<List<Widget>> rows;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final fields = [for (final row in rows) ...row];
        if (constraints.maxWidth < 560) {
          return Column(
            children: [
              for (var i = 0; i < fields.length; i++) ...[
                if (i > 0) const SizedBox(height: RevericSpacing.lg),
                fields[i],
              ],
            ],
          );
        }
        return Column(
          children: [
            for (var r = 0; r < rows.length; r++) ...[
              if (r > 0) const SizedBox(height: RevericSpacing.lg),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < rows[r].length; i++) ...[
                    if (i > 0) const SizedBox(width: RevericSpacing.x2l),
                    Expanded(child: rows[r][i]),
                  ],
                ],
              ),
            ],
          ],
        );
      },
    );
  }
}

/// 字段小标签 + 控件。
class _ForeshadowingMetaLabeled extends StatelessWidget {
  const _ForeshadowingMetaLabeled({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: typo.uiTinySemibold.copyWith(color: colors.textMuted),
        ),
        const SizedBox(height: RevericSpacing.xs),
        child,
      ],
    );
  }
}

class _ForeshadowingMetaTextField extends StatelessWidget {
  const _ForeshadowingMetaTextField({
    required this.label,
    required this.controller,
    required this.hintText,
    this.focusNode,
    this.errorText,
  });

  final String label;
  final TextEditingController controller;
  final FocusNode? focusNode;
  final String hintText;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    return _ForeshadowingMetaLabeled(
      label: label,
      child: RevericTextField(
        controller: controller,
        focusNode: focusNode,
        hintText: hintText,
        errorText: errorText,
      ),
    );
  }
}

class _ForeshadowingMetaStatusField extends StatelessWidget {
  const _ForeshadowingMetaStatusField({
    required this.label,
    required this.value,
    required this.options,
    required this.optionLabels,
    required this.onChanged,
  });

  final String label;
  final String value;
  final List<String> options;
  final Map<String, String> optionLabels;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final currentValue = options.contains(value) ? value : options.first;
    return _ForeshadowingMetaLabeled(
      label: label,
      child: RevericSelect<String>(
        value: currentValue,
        items: [
          for (final option in options)
            RevericSelectItem<String>(
              value: option,
              label: optionLabels[option] ?? option,
              color: _statusColor(context, option),
            ),
        ],
        onChanged: onChanged,
      ),
    );
  }
}

String _statusLabel(BuildContext context, String status) {
  switch (status) {
    case foreshadowingStatusPending:
      return context.t(LocaleKeys.foreshadowingStatusPending);
    case foreshadowingStatusPlanted:
      return context.t(LocaleKeys.foreshadowingStatusPlanted);
    case foreshadowingStatusPayoff:
      return context.t(LocaleKeys.foreshadowingStatusPayoff);
    case foreshadowingStatusAbandoned:
      return context.t(LocaleKeys.foreshadowingStatusAbandoned);
    default:
      return status;
  }
}

Color _statusColor(BuildContext context, String status) {
  final colors = RevericTheme.colorsOf(context);
  return switch (status) {
    foreshadowingStatusPlanted => colors.accentAmber,
    foreshadowingStatusPayoff => colors.accent,
    foreshadowingStatusAbandoned => colors.textMuted,
    _ => colors.textSubtle,
  };
}
