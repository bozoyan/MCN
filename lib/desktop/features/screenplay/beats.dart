// 职责: 桌面剧本节拍区域 — 按幕分栏展示、编辑与重排节拍，并支持鼠标滚轮横向浏览。
// 关联文件:
//   lib/shared/components/reveric_dialog.dart
//   lib/shared/components/reveric_button.dart
//   lib/shared/widgets/confirm_dialog.dart
//   lib/desktop/widgets/workspace/novel_workspace_panel.dart
//   lib/shared/components/horizontal_wheel_scroll.dart
//   lib/shared/providers/screenplay_providers.dart
//   lib/shared/services/screenplay_service.dart
//   lib/shared/form/form.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/screenplay.json
//   assets/translations/zh-CN/screenplay.json
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
// 遵循的 Rules:
//   .agents/rules/form.md
//   .agents/rules/hooks.md
//   .agents/rules/state-management.md
//   .agents/rules/design-system.md

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../shared/components/dotted_border_box.dart';
import '../../../shared/components/horizontal_wheel_scroll.dart';
import '../../../shared/components/reveric_context_menu.dart';
import '../../../shared/components/reveric_icon_button.dart';
import '../../../shared/database/app_database.dart';
import '../../../shared/form/form.dart';
import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/models/screenplay.dart';
import '../../../shared/providers/novel_providers.dart';
import '../../../shared/providers/screenplay_providers.dart';
import '../../../shared/providers/screenplay_workspace_state_provider.dart';
import '../../../shared/theme/theme.dart';
import '../../../shared/widgets/confirm_dialog.dart';
import 'chips.dart';
import 'chrome.dart';
import '../../../shared/components/reveric_dialog.dart';
import '../../../shared/components/reveric_button.dart';

enum _BeatField<T> implements FieldSchema {
  act<String>(validators: [RequiredValidator<String>()]),
  title<String>(),
  description<String>();

  const _BeatField({this.validators});

  @override
  final List<Validator<dynamic>>? validators;
}

class ScreenplayBeatsRegion extends ConsumerWidget {
  const ScreenplayBeatsRegion({super.key, required this.novel});

  final Novel novel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final path = novel.contentDatabasePath!;
    final workspace = ref.watch(
      screenplayWorkspaceStateControllerProvider(novel.id, path),
    );
    final episodeId = workspace.episodeId;
    if (episodeId == null) {
      return ScreenplayEmptyState(
        title: context.t(LocaleKeys.screenplayNoBeats),
      );
    }
    final beats =
        ref.watch(screenplayBeatsProvider(path, episodeId)).value ??
        const <ScreenplayBeatSummary>[];
    final scenes =
        ref.watch(screenplayScenesProvider(path, episodeId)).value ??
        const <ScreenplaySceneSummary>[];
    final service = ref.read(
      screenplayServiceProvider(path, novelId: novel.id),
    );
    // 幕不是固定三栏 —— 幕数由这一集实际排出来的节拍决定，不设上限。
    // 一集还没有任何节拍时先给第一幕一个空栏，让「添加节拍」有地方落。
    final acts = beats.map((beat) => beat.actNumber).toSet().toList()..sort();
    if (acts.isEmpty) acts.add(1);

    Future<void> createBeat(int act) async {
      final result = await showRevericDialog<_BeatInput>(
        context: context,
        builder: (_) => _BeatDialog(initialAct: act),
      );
      if (result == null) return;
      final episode = await ref
          .read(novelContentDatabaseProvider(path))
          .screenplayDao
          .getEpisode(episodeId);
      if (episode == null) return;
      await service.createBeat(
        screenplayId: episode.screenplayId,
        episodeId: episodeId,
        actNumber: result.act,
        title: result.title,
        description: result.description,
      );
    }

    // 分区名由工作区面包屑给出，这里不再铺一条只写着「节拍」的顶栏。
    return LayoutBuilder(
      builder: (context, constraints) {
        // 列宽对齐 mockup 的 flex: 1 0 260 —— 幕少时随窗口拉宽，
        // 但有上限：单列空状态摊满全宽会像一条横幅，所以夹在
        // 260 ~ 360 之间；幕多摊不出 260 就退回最小列宽横向滚。
        final usable = constraints.maxWidth.isFinite
            ? constraints.maxWidth -
                  RevericSpacing.x5l * 2 -
                  RevericSizes.screenplayAddActColumnWidth -
                  RevericSpacing.x2l * acts.length
            : 0.0;
        final columnWidth = usable <= 0
            ? RevericSizes.screenplayActColumnWidth
            : (usable / acts.length).clamp(
                RevericSizes.screenplayActColumnWidth,
                RevericSizes.screenplayActColumnMaxWidth,
              );
        // 纵向再包一层滚动：幕列高度交回内容决定，「新增一幕」只拉伸到
        // 最高幕列而不是被视口撑满；列高超出视口时也能继续往下滚。
        return SingleChildScrollView(
          child: HorizontalWheelScroll(
            builder: (context, controller) => SingleChildScrollView(
              controller: controller,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(
                RevericSpacing.x5l,
                RevericSpacing.x4l,
                RevericSpacing.x5l,
                64,
              ),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final act in acts) ...[
                      SizedBox(
                        width: columnWidth,
                        child: _ActColumn(
                          act: act,
                          beats: beats
                              .where((beat) => beat.actNumber == act)
                              .toList(),
                          scenes: scenes,
                          onAddBeat: () => unawaited(createBeat(act)),
                          onMoveUp: (beat, anchor) =>
                              service.moveBeatBefore(beat.id, anchor.id),
                          onMoveDown: (beat, anchor) =>
                              service.moveBeatAfter(beat.id, anchor.id),
                          onEdit: (beat) async {
                            final result = await showRevericDialog<_BeatInput>(
                              context: context,
                              builder: (_) => _BeatDialog(beat: beat),
                            );
                            if (result == null) return;
                            await service.updateBeat(
                              beatId: beat.id,
                              title: result.title,
                              description: result.description,
                            );
                            if (result.act != beat.actNumber) {
                              await service.moveBeatToActEnd(
                                beat.id,
                                result.act,
                              );
                            }
                          },
                          onDelete: (beat) async {
                            final confirmed = await showConfirmDialog(
                              context,
                              title: context.t(LocaleKeys.commonDelete),
                              message: context.t(
                                LocaleKeys.screenplayConfirmDelete,
                              ),
                              variant: ConfirmDialogVariant.warning,
                            );
                            if (confirmed) await service.deleteBeat(beat.id);
                          },
                        ),
                      ),
                      const SizedBox(width: RevericSpacing.x2l),
                    ],
                    _AddActColumn(
                      onTap: () => unawaited(createBeat(acts.last + 1)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ActColumn extends StatelessWidget {
  const _ActColumn({
    required this.act,
    required this.beats,
    required this.scenes,
    required this.onAddBeat,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onEdit,
    required this.onDelete,
  });

  final int act;
  final List<ScreenplayBeatSummary> beats;
  final List<ScreenplaySceneSummary> scenes;
  final VoidCallback onAddBeat;
  final Future<void> Function(
    ScreenplayBeatSummary beat,
    ScreenplayBeatSummary anchor,
  )
  onMoveUp;
  final Future<void> Function(
    ScreenplayBeatSummary beat,
    ScreenplayBeatSummary anchor,
  )
  onMoveDown;
  final Future<void> Function(ScreenplayBeatSummary beat) onEdit;
  final Future<void> Function(ScreenplayBeatSummary beat) onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return Container(
      padding: const EdgeInsets.all(RevericSpacing.lg),
      decoration: BoxDecoration(
        color: colors.surfaceDim,
        borderRadius: BorderRadius.circular(RevericRadius.x2l),
        border: Border.all(color: colors.borderSubtle),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              RevericSpacing.sm,
              RevericSpacing.xs,
              RevericSpacing.sm,
              RevericSpacing.lg,
            ),
            child: Row(
              children: [
                RevericIcon(
                  RevericIcons.alt_route_outlined,
                  size: 14,
                  color: colors.textMuted,
                ),
                const SizedBox(width: RevericSpacing.sm),
                Expanded(
                  child: Text(
                    context.t(
                      LocaleKeys.screenplayAct,
                      namedArgs: {'number': '$act'},
                    ),
                    // mockup .sp-act__title —— ui 字号的衬线粗体。
                    style: typo.bodySmall.copyWith(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: colors.textPrimary,
                    ),
                  ),
                ),
                Text(
                  '${beats.length}',
                  style: typo.mono.copyWith(
                    fontWeight: FontWeight.w500,
                    color: colors.textSubtle,
                  ),
                ),
              ],
            ),
          ),
          for (var index = 0; index < beats.length; index += 1)
            Padding(
              padding: const EdgeInsets.only(bottom: RevericSpacing.md),
              child: _BeatCard(
                beat: beats[index],
                sceneNumbers: [
                  for (final scene in scenes)
                    if (scene.beatId == beats[index].id) scene.sceneNumber,
                ],
                onEdit: () => unawaited(onEdit(beats[index])),
                onDelete: () => unawaited(onDelete(beats[index])),
                onMoveUp: index == 0
                    ? null
                    : () => unawaited(onMoveUp(beats[index], beats[index - 1])),
                onMoveDown: index + 1 == beats.length
                    ? null
                    : () =>
                          unawaited(onMoveDown(beats[index], beats[index + 1])),
              ),
            ),
          _AddBeatButton(onTap: onAddBeat),
        ],
      ),
    );
  }
}

/// mockup .sp-beat--ghost —— 幕列底部的虚线「添加节拍」入口。
class _AddBeatButton extends StatefulWidget {
  const _AddBeatButton({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_AddBeatButton> createState() => _AddBeatButtonState();
}

class _AddBeatButtonState extends State<_AddBeatButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(RevericRadius.large),
        child: DottedBorderBox(
          color: _hovered ? colors.accent : colors.borderInput,
          borderRadius: RevericRadius.large,
          child: Container(
            padding: const EdgeInsets.all(RevericSpacing.x2l),
            alignment: Alignment.center,
            child: Text(
              '+ ${context.t(LocaleKeys.screenplayAddBeat)}',
              style: typo.ui.copyWith(color: colors.textSubtle),
            ),
          ),
        ),
      ),
    );
  }
}

class _BeatCard extends StatefulWidget {
  const _BeatCard({
    required this.beat,
    required this.sceneNumbers,
    required this.onEdit,
    required this.onDelete,
    required this.onMoveUp,
    required this.onMoveDown,
  });

  final ScreenplayBeatSummary beat;
  final List<int> sceneNumbers;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;

  @override
  State<_BeatCard> createState() => _BeatCardState();
}

class _BeatCardState extends State<_BeatCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final beat = widget.beat;
    final description = beat.description.trim();
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onEdit,
        child: Container(
          padding: const EdgeInsets.all(RevericSpacing.lg),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(RevericRadius.large),
            border: Border.all(
              color: _hovered ? colors.accent : colors.borderInput,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      beat.title.trim().isEmpty
                          ? context.t(LocaleKeys.screenplayUntitledBeat)
                          : beat.title,
                      style: typo.bodySmall.copyWith(
                        fontWeight: FontWeight.w700,
                        height: 1.4,
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: RevericSpacing.sm),
                  if (_hovered)
                    _BeatCardMenu(
                      onEdit: widget.onEdit,
                      onDelete: widget.onDelete,
                      onMoveUp: widget.onMoveUp,
                      onMoveDown: widget.onMoveDown,
                    )
                  else
                    ScreenplayPagesText(
                      pageEighths: beat.pageEighths,
                      style: typo.mono.copyWith(color: colors.textSubtle),
                    ),
                ],
              ),
              if (description.isNotEmpty) ...[
                const SizedBox(height: RevericSpacing.sm),
                Text(
                  description,
                  // mockup .sp-beat__desc —— ui 字号的衬线正文。
                  style: typo.bodySmall.copyWith(
                    fontSize: 13,
                    height: 1.7,
                    color: colors.textSecondary,
                  ),
                ),
              ],
              if (widget.sceneNumbers.isNotEmpty) ...[
                const SizedBox(height: RevericSpacing.md),
                Wrap(
                  spacing: RevericSpacing.xxs,
                  runSpacing: RevericSpacing.xxs,
                  children: [
                    for (final number in widget.sceneNumbers)
                      ScreenplayChip(
                        tone: ScreenplayChipTone.plain,
                        label: context.t(
                          LocaleKeys.screenplayScene,
                          namedArgs: {'number': '$number'},
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _BeatCardMenu extends StatelessWidget {
  const _BeatCardMenu({
    required this.onEdit,
    required this.onDelete,
    required this.onMoveUp,
    required this.onMoveDown,
  });

  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    return Builder(
      builder: (buttonContext) => RevericIconButton(
        icon: RevericIcons.more_horiz,
        tooltip: context.t(LocaleKeys.commonMoreActions),
        onPressed: () {
          final box = buttonContext.findRenderObject()! as RenderBox;
          unawaited(
            showRevericContextMenu(
              context: context,
              position: box.localToGlobal(Offset(0, box.size.height)),
              entries: [
                RevericMenuItem(
                  icon: RevericIcons.edit_outlined,
                  label: context.t(LocaleKeys.commonEdit),
                  onTap: onEdit,
                ),
                RevericMenuItem(
                  icon: RevericIcons.expand_less_rounded,
                  label: context.t(LocaleKeys.screenplayMoveUp),
                  enabled: onMoveUp != null,
                  onTap: onMoveUp,
                ),
                RevericMenuItem(
                  icon: RevericIcons.caret_down,
                  label: context.t(LocaleKeys.screenplayMoveDown),
                  enabled: onMoveDown != null,
                  onTap: onMoveDown,
                ),
                const RevericMenuDivider(),
                RevericMenuItem(
                  icon: RevericIcons.delete_outline,
                  iconColor: colors.warningText,
                  labelColor: colors.warningText,
                  label: context.t(LocaleKeys.commonDelete),
                  onTap: onDelete,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _AddActColumn extends StatefulWidget {
  const _AddActColumn({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_AddActColumn> createState() => _AddActColumnState();
}

class _AddActColumnState extends State<_AddActColumn> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    // hover 对齐 mockup .sp-act--add:hover —— 描边转 accent，文字提一档。
    final foreground = _hovered ? colors.textSecondary : colors.textSubtle;
    return SizedBox(
      width: RevericSizes.screenplayAddActColumnWidth,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(RevericRadius.x2l),
          child: DottedBorderBox(
            color: _hovered ? colors.accent : colors.borderInput,
            borderRadius: RevericRadius.x2l,
            child: Container(
              constraints: const BoxConstraints(minHeight: 132),
              alignment: Alignment.center,
              padding: const EdgeInsets.all(RevericSpacing.lg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RevericIcon(RevericIcons.add, size: 14, color: foreground),
                  const SizedBox(height: RevericSpacing.sm),
                  Text(
                    context.t(LocaleKeys.screenplayAddAct),
                    textAlign: TextAlign.center,
                    style: typo.ui.copyWith(color: foreground),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BeatInput {
  const _BeatInput({
    required this.act,
    required this.title,
    required this.description,
  });

  final int act;
  final String title;
  final String description;
}

class _BeatDialog extends HookWidget {
  const _BeatDialog({this.beat, this.initialAct});

  final ScreenplayBeatSummary? beat;
  final int? initialAct;

  @override
  Widget build(BuildContext context) {
    final form = useForm<_BeatField>(
      initialValues: {
        _BeatField.act: '${beat?.actNumber ?? initialAct ?? 1}',
        _BeatField.title: beat?.title ?? '',
        _BeatField.description: beat?.description ?? '',
      },
      keys: [beat?.id],
    );
    void submit() {
      if (!form.validate()) return;
      final act = int.tryParse(form.getValue<String>(_BeatField.act) ?? '');
      if (act == null || act < 1) {
        form.setError(
          _BeatField.act,
          context.t(LocaleKeys.libraryPlannedEpisodeCountInvalid),
        );
        return;
      }
      Navigator.of(context).pop(
        _BeatInput(
          act: act,
          title: form.getValue<String>(_BeatField.title) ?? '',
          description: form.getValue<String>(_BeatField.description) ?? '',
        ),
      );
    }

    return RevericDialog.panel(
      title: Text(
        beat == null
            ? context.t(LocaleKeys.screenplayAddBeat)
            : context.t(LocaleKeys.commonEdit),
      ),
      content: SizedBox(
        width: 420,
        child: HookedForm<_BeatField>(
          form: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              HookedTextFormField<_BeatField>(
                fieldHook: _BeatField.act,
                keyboardType: TextInputType.number,
                label: context.t(LocaleKeys.screenplayActNumber),
              ),
              const SizedBox(height: RevericSpacing.md),
              HookedTextFormField<_BeatField>(
                fieldHook: _BeatField.title,
                label: context.t(LocaleKeys.screenplayUntitledBeat),
              ),
              const SizedBox(height: RevericSpacing.md),
              HookedTextFormField<_BeatField>(
                fieldHook: _BeatField.description,
                multiline: true,
                minLines: 3,
                maxLines: 5,
                label: context.t(LocaleKeys.libraryDescription),
              ),
            ],
          ),
        ),
      ),

      width: 420 + RevericSpacing.x4l * 2,

      actions: [
        RevericButton.secondary(
          label: context.t(LocaleKeys.commonCancel),
          onPressed: () => Navigator.of(context).pop(),
        ),
        RevericButton.primary(
          label: context.t(LocaleKeys.commonSave),
          onPressed: submit,
        ),
      ],
    );
  }
}
