// 职责: Timeline 大纲编辑器 — 编辑 outline 主内容、横向/纵向 beats 展示（可展开覆盖正文）、章数刻度尺与拖拽重排。
// 关联文件:
//   lib/desktop/widgets/workspace/novel_workspace_panel.dart
//   lib/desktop/widgets/workspace/outline_architecture_view.dart
//   lib/desktop/widgets/workspace/outline_timeline_strip.dart
//   lib/shared/models/ai_shortcut_action.dart
//   lib/shared/models/outline.dart
//   lib/shared/providers/ai_shortcut_action_providers.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/workspace.json
//   assets/translations/zh-CN/workspace.json
//   assets/translations/en/agent_shortcut.json
//   assets/translations/zh-CN/agent_shortcut.json
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/hooks.md

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../shared/components/reveric_select.dart';
import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/models/ai_shortcut_action.dart';
import '../../../shared/models/outline.dart';
import '../../../shared/providers/ai_shortcut_action_providers.dart';
import '../../../shared/theme/theme.dart';
import '../../../shared/widgets/md/reveric_markdown_editor.dart';
import 'outline_architecture_view.dart';
import 'outline_beat_dialog.dart';
import 'outline_timeline_strip.dart';

class OutlineEditor extends HookConsumerWidget {
  const OutlineEditor({
    super.key,
    required this.draft,
    required this.onChanged,
    required this.onCreateFirstBeat,
    this.onRunShortcutAction,
    this.titleErrorText,
  });

  final OutlineDraft? draft;
  final ValueChanged<OutlineDraft> onChanged;
  final VoidCallback onCreateFirstBeat;
  final ValueChanged<AiShortcutActionDefinition>? onRunShortcutAction;

  /// 标题行下方内联展示的校验错误（如标题含 AI 路径结构字符），null 不展示。
  final String? titleErrorText;

  static const double _minimumMainPanelHeight = 380;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final outline = draft;
    if (outline == null) {
      return _EmptyOutlineState(onCreate: onCreateFirstBeat);
    }

    final beatsExpanded = useState(false);
    final timelineCollapsed = useState(false);
    final beatShortcutActions = ref.watch(
      enabledAiShortcutActionsForLocationProvider(
        AiShortcutActionLocation.outline_beat,
      ),
    );

    useEffect(() {
      beatsExpanded.value = false;
      timelineCollapsed.value = false;
      return null;
    }, [outline.documentId]);

    return LayoutBuilder(
      builder: (context, constraints) {
        // 预算只作上限：选能放下的最大密度档固有高度，避免面板高于内容留白。
        final maxBudget = math.max(
          0.0,
          constraints.maxHeight - _minimumMainPanelHeight - RevericSpacing.x3l,
        );
        final timelineExpandedHeight =
            OutlineTimelineStrip.resolveExpandedHeight(maxBudget);

        return Column(
          children: [
            Expanded(
              child: _OutlineMainPanel(
                draft: outline,
                onChanged: onChanged,
                beatsExpanded: beatsExpanded.value,
                beatShortcutActions: beatShortcutActions,
                onRunShortcutAction: onRunShortcutAction,
                titleErrorText: titleErrorText,
                onToggleBeatsExpanded: () {
                  beatsExpanded.value = !beatsExpanded.value;
                },
              ),
            ),
            if (!beatsExpanded.value)
              OutlineTimelineStrip(
                draft: outline,
                isCollapsed: timelineCollapsed.value,
                expandedHeight: timelineExpandedHeight,
                onAddBeat: () => _openOutlineBeatDialog(
                  context: context,
                  draft: outline,
                  onChanged: onChanged,
                ),
                onEditBeat: (beatIndex) => _openOutlineBeatDialog(
                  context: context,
                  draft: outline,
                  onChanged: onChanged,
                  beatIndex: beatIndex,
                ),
                onDeleteBeat: (beatIndex) => _deleteOutlineBeat(
                  draft: outline,
                  onChanged: onChanged,
                  beatIndex: beatIndex,
                ),
                beatShortcutActions: beatShortcutActions,
                onRunShortcutAction: onRunShortcutAction,
                onReorderBeats: (oldIndex, newIndex) => _reorderOutlineBeats(
                  draft: outline,
                  onChanged: onChanged,
                  oldIndex: oldIndex,
                  newIndex: newIndex,
                ),
                onToggleBeatsExpanded: () {
                  beatsExpanded.value = true;
                },
                onToggleCollapsed: () {
                  timelineCollapsed.value = !timelineCollapsed.value;
                },
              ),
          ],
        );
      },
    );
  }
}

class _EmptyOutlineState extends StatelessWidget {
  const _EmptyOutlineState({required this.onCreate});

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
              RevericIcons.timeline_outlined,
              size: 32,
              color: colors.textSubtle,
            ),
            const SizedBox(height: RevericSpacing.lg),
            Text(
              context.t(
                LocaleKeys.workspaceNoEntrySelected,
                namedArgs: {'type': context.t(LocaleKeys.workspaceOutlines)},
              ),
              style: typo.uiSemibold.copyWith(color: colors.textPrimary),
            ),
            const SizedBox(height: RevericSpacing.sm),
            Text(
              context.t(LocaleKeys.workspaceOutlineEditorEmptyHint),
              style: typo.ui.copyWith(color: colors.textMuted),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: RevericSpacing.x2l),
            FilledButton.icon(
              onPressed: onCreate,
              icon: const RevericIcon(RevericIcons.add, size: 16),
              label: Text(context.t(LocaleKeys.workspaceNewOutline)),
            ),
          ],
        ),
      ),
    );
  }
}

class _OutlineMainPanel extends HookWidget {
  const _OutlineMainPanel({
    required this.draft,
    required this.onChanged,
    required this.beatsExpanded,
    required this.beatShortcutActions,
    this.onRunShortcutAction,
    required this.onToggleBeatsExpanded,
    this.titleErrorText,
  });

  final OutlineDraft draft;
  final ValueChanged<OutlineDraft> onChanged;
  final bool beatsExpanded;
  final List<AiShortcutActionDefinition> beatShortcutActions;
  final ValueChanged<AiShortcutActionDefinition>? onRunShortcutAction;
  final VoidCallback onToggleBeatsExpanded;
  final String? titleErrorText;

  @override
  Widget build(BuildContext context) {
    final controller = useTextEditingController(text: draft.content);
    final focusNode = useFocusNode();
    final draftRef = useRef(draft);
    draftRef.value = draft;

    useEffect(() {
      if (controller.text != draft.content) {
        controller.text = draft.content;
      }
      return null;
    }, [draft.documentId, draft.content]);

    useEffect(() {
      void listener() {
        final text = controller.text;
        if (text != draftRef.value.content) {
          onChanged(draftRef.value.copyWith(content: text));
        }
      }

      controller.addListener(listener);
      return () => controller.removeListener(listener);
    }, [controller, onChanged]);

    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontalPadding = constraints.maxWidth < 900
            ? RevericSpacing.x4l
            : RevericSpacing.x6l;
        return Padding(
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            RevericSpacing.x4l,
            horizontalPadding,
            RevericSpacing.x3l,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _OutlineTitleRow(
                draft: draft,
                onChanged: onChanged,
                errorText: titleErrorText,
              ),
              const SizedBox(height: RevericSpacing.x3l),
              Expanded(
                child: beatsExpanded
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          OutlineTimelineBeatsToolbar(
                            beatsExpanded: true,
                            onToggleBeatsExpanded: onToggleBeatsExpanded,
                            onAddBeat: () => _openOutlineBeatDialog(
                              context: context,
                              draft: draft,
                              onChanged: onChanged,
                            ),
                          ),
                          const SizedBox(height: RevericSpacing.lg),
                          Expanded(
                            child: OutlineArchitectureView(
                              draft: draft,
                              onAddBeat: () => _openOutlineBeatDialog(
                                context: context,
                                draft: draft,
                                onChanged: onChanged,
                              ),
                              onEditBeat: (beatIndex) => _openOutlineBeatDialog(
                                context: context,
                                draft: draft,
                                onChanged: onChanged,
                                beatIndex: beatIndex,
                              ),
                              onDeleteBeat: (beatIndex) => _deleteOutlineBeat(
                                draft: draft,
                                onChanged: onChanged,
                                beatIndex: beatIndex,
                              ),
                              beatShortcutActions: beatShortcutActions,
                              onRunShortcutAction: onRunShortcutAction,
                              onReorderBeats: (oldIndex, newIndex) =>
                                  _reorderOutlineBeats(
                                    draft: draft,
                                    onChanged: onChanged,
                                    oldIndex: oldIndex,
                                    newIndex: newIndex,
                                  ),
                            ),
                          ),
                        ],
                      )
                    : RevericMarkdownEditor(
                        controller: controller,
                        focusNode: focusNode,
                        hintText: context.t(
                          LocaleKeys.workspaceOutlineContentHint,
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _OutlineTitleRow extends StatelessWidget {
  const _OutlineTitleRow({
    required this.draft,
    required this.onChanged,
    this.errorText,
  });

  final OutlineDraft draft;
  final ValueChanged<OutlineDraft> onChanged;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: TextFormField(
                key: ValueKey('outline-title-${draft.documentId}'),
                initialValue: draft.title,
                onChanged: (value) => onChanged(draft.copyWith(title: value)),
                style: typo.display.copyWith(color: colors.textPrimary),
                decoration: InputDecoration(
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                  hintText: context.t(LocaleKeys.workspaceOutlines),
                  hintStyle: typo.display.copyWith(color: colors.textSubtle),
                ),
              ),
            ),
            const SizedBox(width: RevericSpacing.x2l),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: RevericSpacing.lg,
                vertical: RevericSpacing.sm,
              ),
              decoration: BoxDecoration(
                color: colors.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(RevericRadius.pill),
                border: Border.all(color: colors.borderSubtle),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    context.t(LocaleKeys.workspaceOutlineStartChapter),
                    style: typo.ui.copyWith(color: colors.textSecondary),
                  ),
                  const SizedBox(width: RevericSpacing.sm),
                  SizedBox(
                    width: 36,
                    child: TextFormField(
                      key: ValueKey(
                        'outline-start-chapter-${draft.documentId}',
                      ),
                      initialValue: '${draft.startChapterNum}',
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      textAlign: TextAlign.center,
                      onChanged: (value) {
                        final startChapterNum = int.tryParse(value);
                        if (startChapterNum == null ||
                            startChapterNum < 1 ||
                            startChapterNum == draft.startChapterNum) {
                          return;
                        }
                        onChanged(
                          draft.copyWith(startChapterNum: startChapterNum),
                        );
                      },
                      style: typo.uiSemibold.copyWith(
                        color: colors.textPrimary,
                      ),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: RevericSpacing.lg),
            _StatusPill(
              value: draft.status,
              onChanged: (status) => onChanged(draft.copyWith(status: status)),
            ),
          ],
        ),
        if (errorText != null) ...[
          const SizedBox(height: RevericSpacing.xs),
          Text(
            errorText!,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: typo.uiSmall.copyWith(color: colors.error),
          ),
        ],
      ],
    );
  }
}

Future<void> _openOutlineBeatDialog({
  required BuildContext context,
  required OutlineDraft draft,
  required ValueChanged<OutlineDraft> onChanged,
  int? beatIndex,
}) async {
  final beat =
      beatIndex == null || beatIndex < 0 || beatIndex >= draft.beats.length
      ? null
      : draft.beats[beatIndex];
  if (beatIndex != null && beat == null) {
    return;
  }
  final nextBeat = await showDialog<OutlineBeatDraft>(
    context: context,
    builder: (context) {
      return OutlineBeatDialog(beat: beat);
    },
  );
  if (nextBeat == null) {
    return;
  }
  if (beat == null) {
    onChanged(
      draft.copyWith(
        beats: [
          ...draft.beats,
          nextBeat.copyWith(sortOrder: draft.beats.length),
        ],
      ),
    );
    return;
  }
  onChanged(
    draft.copyWith(
      beats: [
        for (int i = 0; i < draft.beats.length; i++)
          if (i == beatIndex)
            nextBeat.copyWith(sortOrder: i)
          else
            draft.beats[i],
      ],
    ),
  );
}

void _deleteOutlineBeat({
  required OutlineDraft draft,
  required ValueChanged<OutlineDraft> onChanged,
  required int beatIndex,
}) {
  if (beatIndex < 0 || beatIndex >= draft.beats.length) {
    return;
  }
  final nextBeats = [...draft.beats]..removeAt(beatIndex);
  onChanged(
    draft.copyWith(
      beats: [
        for (int i = 0; i < nextBeats.length; i++)
          nextBeats[i].copyWith(sortOrder: i),
      ],
    ),
  );
}

void _reorderOutlineBeats({
  required OutlineDraft draft,
  required ValueChanged<OutlineDraft> onChanged,
  required int oldIndex,
  required int newIndex,
}) {
  if (oldIndex == newIndex) {
    return;
  }
  final next = [...draft.beats];
  final moved = next.removeAt(oldIndex);
  final insertAt = newIndex > oldIndex ? newIndex - 1 : newIndex;
  next.insert(insertAt.clamp(0, next.length), moved);
  final reindexed = <OutlineBeatDraft>[
    for (int i = 0; i < next.length; i++) next[i].copyWith(sortOrder: i),
  ];
  onChanged(draft.copyWith(beats: reindexed));
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final normalized = outlineStatuses.contains(value)
        ? value
        : outlineStatusPending;
    return SizedBox(
      width: 140,
      child: Tooltip(
        message: context.t(LocaleKeys.commonStatus),
        child: RevericSelect<String>(
          value: normalized,
          height: RevericSizes.buttonHeightSm,
          items: [
            for (final status in outlineStatuses)
              RevericSelectItem(
                value: status,
                label: statusLabel(context, status),
                color: statusColor(context, status),
              ),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }
}
