// 职责: 移动端剧本节拍 — 按幕纵向展示节拍卡，提供分幕新增、编辑、排序与确认删除。
// 关联文件:
//   lib/shared/components/reveric_dialog.dart
//   lib/shared/components/reveric_button.dart
//   lib/shared/widgets/confirm_dialog.dart
//   lib/mobile/features/screenplay/editor_page.dart
//   lib/shared/providers/screenplay_providers.dart
//   lib/shared/services/screenplay_service.dart
//   lib/shared/theme/theme.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/zh-CN/common.json
//   assets/translations/en/common.json
//   assets/translations/en/screenplay.json
//   assets/translations/zh-CN/screenplay.json
// 遵循的 Rules:
//   .agents/rules/hooks.md
//   .agents/rules/state-management.md
//   .agents/rules/design-system.md

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
import '../../../shared/widgets/screenplay/chips.dart';
import 'support.dart';
import '../../../shared/components/reveric_dialog.dart';
import '../../../shared/components/reveric_button.dart';

enum _BeatEditField<T> implements FieldSchema {
  act<String>(validators: [RequiredValidator<String>()]),
  title<String>(),
  description<String>();

  const _BeatEditField({this.validators});

  @override
  final List<Validator<dynamic>>? validators;
}

class MobileScreenplayBeatsPage extends ConsumerWidget {
  const MobileScreenplayBeatsPage({super.key, required this.novel});

  final Novel novel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final path = novel.contentDatabasePath!;
    final workspace = ref.watch(
      screenplayWorkspaceStateControllerProvider(novel.id, path),
    );
    final beats = workspace.episodeId == null
        ? const <ScreenplayBeatSummary>[]
        : ref
                  .watch(screenplayBeatsProvider(path, workspace.episodeId!))
                  .value ??
              const <ScreenplayBeatSummary>[];
    final service = ref.read(
      screenplayServiceProvider(path, novelId: novel.id),
    );
    final acts = beats.map((beat) => beat.actNumber).toSet().toList()..sort();

    Future<void> add(int act) async {
      final episodeId = workspace.episodeId;
      if (episodeId == null) return;
      final episode = await ref
          .read(novelContentDatabaseProvider(path))
          .screenplayDao
          .getEpisode(episodeId);
      if (episode == null || !context.mounted) return;
      final result = await showRevericDialog<_BeatEditResult>(
        context: context,
        builder: (_) => _BeatEditDialog(initialAct: act),
      );
      if (result == null) return;
      await service.createBeat(
        screenplayId: episode.screenplayId,
        episodeId: episodeId,
        actNumber: result.act,
        title: result.title,
        description: result.description,
      );
    }

    Future<void> edit(ScreenplayBeatSummary beat) async {
      final result = await showRevericDialog<_BeatEditResult>(
        context: context,
        builder: (_) => _BeatEditDialog(beat: beat),
      );
      if (result == null) return;
      await service.updateBeat(
        beatId: beat.id,
        title: result.title,
        description: result.description,
      );
      if (result.act != beat.actNumber) {
        await service.moveBeatToActEnd(beat.id, result.act);
      }
    }

    final groups = acts.isEmpty ? [1] : acts;
    final scenes = workspace.episodeId == null
        ? const <ScreenplaySceneSummary>[]
        : ref
                  .watch(screenplayScenesProvider(path, workspace.episodeId!))
                  .value ??
              const <ScreenplaySceneSummary>[];
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    Future<void> actions(
      ScreenplayBeatSummary beat,
      List<ScreenplayBeatSummary> rows,
    ) async {
      final index = rows.indexOf(beat);
      final action = await showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        useSafeArea: true,
        builder: (context) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.only(bottom: RevericSpacing.x5l),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  title: Text(context.t(LocaleKeys.commonEdit)),
                  onTap: () => Navigator.pop(context, 'edit'),
                ),
                ListTile(
                  enabled: index > 0,
                  title: Text(context.t(LocaleKeys.screenplayMoveUp)),
                  onTap: () => Navigator.pop(context, 'up'),
                ),
                ListTile(
                  enabled: index + 1 < rows.length,
                  title: Text(context.t(LocaleKeys.screenplayMoveDown)),
                  onTap: () => Navigator.pop(context, 'down'),
                ),
              ],
            ),
          ),
        ),
      );
      if (action == 'edit') {
        await edit(beat);
      }
      if (action == 'up' && index > 0) {
        await service.moveBeatBefore(beat.id, rows[index - 1].id);
      }
      if (action == 'down' && index + 1 < rows.length) {
        await service.moveBeatAfter(beat.id, rows[index + 1].id);
      }
    }

    return ListView(
      key: PageStorageKey('beats-${workspace.episodeId}'),
      padding: const EdgeInsets.all(RevericSpacing.x2l),
      children: [
        for (final act in groups) ...[
          Row(
            children: [
              Expanded(
                child: Text(
                  context.t(
                    LocaleKeys.screenplayAct,
                    namedArgs: {'number': '$act'},
                  ),
                  style: typo.body.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              Text(
                '${beats.where((b) => b.actNumber == act).length}',
                style: typo.uiTiny.copyWith(color: colors.textMuted),
              ),
            ],
          ),
          const SizedBox(height: RevericSpacing.md),
          for (final beat in beats.where((b) => b.actNumber == act))
            Padding(
              padding: const EdgeInsets.only(bottom: RevericSpacing.md),
              child: Dismissible(
                key: ValueKey(beat.id),
                direction: DismissDirection.endToStart,
                confirmDismiss: (_) => showConfirmDialog(
                  context,
                  title: context.t(LocaleKeys.commonDelete),
                  message: context.t(LocaleKeys.screenplayConfirmDelete),
                  variant: ConfirmDialogVariant.warning,
                ),
                onDismissed: (_) => unawaited(service.deleteBeat(beat.id)),
                background: Container(color: colors.deletionBg),
                child: MobileScreenplayCard(
                  onTap: () => edit(beat),
                  onLongPress: () => actions(
                    beat,
                    beats.where((b) => b.actNumber == act).toList(),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              beat.title.trim().isEmpty
                                  ? context.t(LocaleKeys.screenplayUntitledBeat)
                                  : beat.title,
                              style: typo.body.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: RevericSpacing.sm),
                          ScreenplayPagesText(pageEighths: beat.pageEighths),
                        ],
                      ),
                      if (beat.description.isNotEmpty) ...[
                        const SizedBox(height: RevericSpacing.sm),
                        Text(
                          beat.description,
                          style: typo.bodySmall.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                      ],
                      const SizedBox(height: RevericSpacing.sm),
                      Wrap(
                        spacing: RevericSpacing.xs,
                        runSpacing: RevericSpacing.xs,
                        children: [
                          for (final scene in scenes.where(
                            (s) => s.beatId == beat.id,
                          ))
                            ScreenplayChip(
                              label: mobileSceneLabel(context, scene),
                              tone: ScreenplayChipTone.plain,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          OutlinedButton(
            onPressed: workspace.episodeId == null ? null : () => add(act),
            child: Text(context.t(LocaleKeys.screenplayAddBeat)),
          ),
          const SizedBox(height: RevericSpacing.x2l),
        ],
        OutlinedButton.icon(
          onPressed: workspace.episodeId == null
              ? null
              : () => add(groups.last + 1),
          icon: const RevericIcon(RevericIcons.add, size: 18),
          label: Text(context.t(LocaleKeys.screenplayAddAct)),
        ),
      ],
    );
  }
}

class _BeatEditResult {
  const _BeatEditResult({
    required this.act,
    required this.title,
    required this.description,
  });

  final int act;
  final String title;
  final String description;
}

class _BeatEditDialog extends HookWidget {
  const _BeatEditDialog({this.beat, this.initialAct = 1});

  final ScreenplayBeatSummary? beat;
  final int initialAct;

  @override
  Widget build(BuildContext context) {
    final form = useForm<_BeatEditField>(
      initialValues: {
        _BeatEditField.act: '${beat?.actNumber ?? initialAct}',
        _BeatEditField.title: beat?.title ?? '',
        _BeatEditField.description: beat?.description ?? '',
      },
    );
    void submit() {
      if (!form.validate()) return;
      final act = int.tryParse(form.getValue<String>(_BeatEditField.act) ?? '');
      if (act == null || act < 1) {
        form.setError(
          _BeatEditField.act,
          context.t(LocaleKeys.libraryPlannedEpisodeCountInvalid),
        );
        return;
      }
      Navigator.of(context).pop(
        _BeatEditResult(
          act: act,
          title: form.getValue<String>(_BeatEditField.title) ?? '',
          description: form.getValue<String>(_BeatEditField.description) ?? '',
        ),
      );
    }

    return RevericDialog(
      title: context.t(LocaleKeys.screenplayBeats),
      content: HookedForm<_BeatEditField>(
        form: form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            HookedTextFormField<_BeatEditField>(
              fieldHook: _BeatEditField.act,
              keyboardType: TextInputType.number,
              label: context.t(LocaleKeys.screenplayActNumber),
            ),
            const SizedBox(height: RevericSpacing.md),
            HookedTextFormField<_BeatEditField>(
              fieldHook: _BeatEditField.title,
              label: context.t(LocaleKeys.screenplayUntitledBeat),
            ),
            const SizedBox(height: RevericSpacing.md),
            HookedTextFormField<_BeatEditField>(
              fieldHook: _BeatEditField.description,
              multiline: true,
              minLines: 2,
              maxLines: 5,
              label: context.t(LocaleKeys.libraryDescription),
            ),
          ],
        ),
      ),
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
