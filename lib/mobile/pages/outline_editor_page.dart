// 职责: 移动端大纲编辑页 — 标题/状态/正文 markdown 编辑（防抖自动保存）、节奏点列表（增/改/左滑删/拖拽排序）。
// 关联文件:
//   lib/mobile/widgets/outlines_panel.dart
//   lib/mobile/pages/outline_beat_editor_page.dart
//   lib/mobile/widgets/segmented_tab_switcher.dart
//   lib/shared/components/reveric_select.dart
//   lib/shared/components/reveric_slidable_delete.dart
//   lib/shared/widgets/md/reveric_markdown_editor.dart
//   lib/shared/providers/novel_providers.dart
//   lib/shared/services/novel_content.dart
//   lib/shared/models/outline.dart
//   lib/shared/theme/theme.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/workspace.json
//   assets/translations/zh-CN/workspace.json
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
//   assets/translations/en/mobile.json
//   assets/translations/zh-CN/mobile.json
// 遵循的 Rules:
//   .agents/rules/hooks.md
//   .agents/rules/state-management.md
//   .agents/rules/design-system.md
//   .agents/rules/icons.md
//   .agents/rules/i18n.md
//   .agents/rules/error-handling.md
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../shared/components/reveric_select.dart';
import '../../shared/components/reveric_slidable_delete.dart';
import '../../shared/localization/app_localization.dart';
import '../../shared/localization/locale_keys.dart';
import '../../shared/models/outline.dart';
import '../../shared/providers/novel_providers.dart';
import '../../shared/theme/theme.dart';
import '../../shared/widgets/md/reveric_markdown_editor.dart';
import '../widgets/detail_scaffold.dart';
import '../widgets/editor_app_bar.dart';
import '../widgets/segmented_tab_switcher.dart';
import 'outline_beat_editor_page.dart';

/// 大纲编辑页（按 id 加载）：从大纲列表按 documentId 取草稿后渲染编辑主体。
/// 拆出 loader 是为了让条目跳转/列表打开统一「只传 id」，主体逻辑（controller 灌值/
/// 自动保存）保持同步拿到具体 draft 不变。
class MobileOutlineEditorPage extends ConsumerWidget {
  const MobileOutlineEditorPage({
    super.key,
    required this.databasePath,
    required this.outlineId,
  });

  final String databasePath;
  final String outlineId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(outlinesProvider(databasePath)).asData?.value;
    final draft = list?.cast<OutlineDraft?>().firstWhere(
      (d) => d?.documentId == outlineId,
      orElse: () => null,
    );
    if (draft == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return _OutlineEditorBody(
      key: ValueKey(draft.documentId),
      databasePath: databasePath,
      draft: draft,
    );
  }
}

class _OutlineEditorBody extends HookConsumerWidget {
  const _OutlineEditorBody({
    super.key,
    required this.databasePath,
    required this.draft,
  });

  final String databasePath;
  final OutlineDraft draft;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);

    final titleController = useTextEditingController(text: draft.title);
    final contentController = useTextEditingController(text: draft.content);
    final contentFocusNode = useFocusNode();
    final scrollController = useScrollController();
    final editorSectionKey = useMemoized(GlobalKey.new);
    // 共享 undo/redo 控制器：标题与正文 markdown 同页，按钮作用于当前焦点字段。
    final undoController = useMemoized(UndoHistoryController.new);
    useEffect(() => undoController.dispose, const []);
    final status = useState<String>(draft.status);
    final startChapterNum = useState<int>(
      draft.startChapterNum < 1 ? 1 : draft.startChapterNum,
    );
    // 本地 beats 镜像：beats 是 outline draft 的子列表，编辑后整体回写。
    final beats = useState<List<OutlineBeatDraft>>(draft.beats.toList());

    final dirty = useRef(false);
    final autoSaveTimer = useRef<Timer?>(null);
    final saveState = useState<(bool, DateTime?)>((false, draft.updatedAt));

    final service = ref.watch(novelContentServiceProvider(databasePath));

    final saveChain = useRef(Future<void>.value());
    final revision = useRef(0);
    final pendingDraft = useRef(draft);

    Future<void> persist({bool notify = true}) {
      autoSaveTimer.value?.cancel();
      if (!dirty.value) {
        return saveChain.value;
      }
      final snapshot = pendingDraft.value;
      final savingRevision = revision.value;
      if (notify && context.mounted) {
        saveState.value = (true, saveState.value.$2);
      }
      final next = saveChain.value.then((_) async {
        try {
          await service.outlineService.saveOutline(snapshot);
          if (revision.value == savingRevision) {
            dirty.value = false;
          }
          if (notify && context.mounted) {
            saveState.value = (false, DateTime.now());
          }
        } catch (_) {
          // The service logs the failure. Retain dirty state for retry.
          if (notify && context.mounted) {
            saveState.value = (false, saveState.value.$2);
          }
        }
      });
      saveChain.value = next;
      return next;
    }

    void scheduleSave() {
      dirty.value = true;
      revision.value++;
      pendingDraft.value = draft.copyWith(
        title: titleController.text.trim(),
        content: contentController.text,
        status: status.value,
        startChapterNum: startChapterNum.value,
        beats: List.unmodifiable(beats.value),
      );
      autoSaveTimer.value?.cancel();
      autoSaveTimer.value = Timer(const Duration(milliseconds: 800), persist);
    }

    useOnListenableChange(contentController, scheduleSave);

    // 键盘弹出时把编辑区滚入可视区域，避免上半表单项占满压缩后的视口。
    useEffect(() {
      void scrollEditorIntoView() {
        if (!contentFocusNode.hasFocus) {
          return;
        }
        final target = editorSectionKey.currentContext;
        if (target == null) {
          return;
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!target.mounted) {
            return;
          }
          Scrollable.ensureVisible(
            target,
            alignment: 0,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
          );
        });
      }

      contentFocusNode.addListener(scrollEditorIntoView);
      return () {
        contentFocusNode.removeListener(scrollEditorIntoView);
      };
    }, const []);

    // Freeze drafts on input, so disposal never reads disposed controllers.
    final flushSave = useRef<Future<void> Function()>(
      () => persist(notify: false),
    );
    flushSave.value = () => persist(notify: false);
    useEffect(
      () => () {
        autoSaveTimer.value?.cancel();
        unawaited(flushSave.value());
      },
      const [],
    );

    Future<void> openBeatEditor([OutlineBeatDraft? existing]) async {
      final result = await Navigator.of(context).push<OutlineBeatDraft>(
        MaterialPageRoute<OutlineBeatDraft>(
          builder: (_) => MobileOutlineBeatEditorPage(beat: existing),
        ),
      );
      if (!context.mounted || result == null) {
        return;
      }
      final next = [...beats.value];
      if (existing == null) {
        next.add(result.copyWith(sortOrder: next.length));
      } else {
        final index = next.indexWhere((b) => b.id == existing.id);
        if (index >= 0) {
          next[index] = result.copyWith(sortOrder: index);
        }
      }
      beats.value = next;
      scheduleSave();
    }

    void deleteBeat(int index) {
      if (index < 0 || index >= beats.value.length) {
        return;
      }
      final next = [...beats.value]..removeAt(index);
      beats.value = [
        for (var i = 0; i < next.length; i++) next[i].copyWith(sortOrder: i),
      ];
      scheduleSave();
    }

    void reorderBeats(int oldIndex, int newIndex) {
      if (oldIndex == newIndex) {
        return;
      }
      final next = [...beats.value];
      final moved = next.removeAt(oldIndex);
      next.insert(newIndex.clamp(0, next.length), moved);
      beats.value = [
        for (var i = 0; i < next.length; i++) next[i].copyWith(sortOrder: i),
      ];
      scheduleSave();
    }

    useListenable(titleController);

    final displayTitle = titleController.text.trim().isEmpty
        ? context.t(LocaleKeys.commonUntitled)
        : titleController.text.trim();

    return Scaffold(
      backgroundColor: colors.canvas,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            MobileEditorAppBar(
              title: displayTitle,
              subtitle: _statusLabel(context, status.value),
              saving: saveState.value.$1,
              savedAt: saveState.value.$2,
              onBack: () async {
                await persist();
                if (context.mounted && !dirty.value) {
                  Navigator.of(context).pop();
                }
              },
              undoController: undoController,
            ),
            Expanded(
              child: CustomScrollView(
                controller: scrollController,
                slivers: [
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      mobileDetailBodyPadding.left,
                      mobileDetailBodyPadding.top,
                      mobileDetailBodyPadding.right,
                      0,
                    ),
                    sliver: SliverToBoxAdapter(
                      child: Column(
                        children: [
                          MobileDetailTitleField(
                            controller: titleController,
                            undoController: undoController,
                            hintText: context.t(LocaleKeys.workspaceOutlines),
                            onChanged: (_) => scheduleSave(),
                          ),
                          const SizedBox(height: RevericSpacing.xl),
                          MobileDetailFieldList(
                            children: [
                              MobileDetailFieldRow(
                                label: context.t(LocaleKeys.commonStatus),
                                child: MobileDetailSelect<String>(
                                  value: status.value,
                                  items: [
                                    for (final s in outlineStatuses)
                                      RevericSelectItem<String>(
                                        value: s,
                                        label: _statusLabel(context, s),
                                        color: _statusColor(s, colors),
                                      ),
                                  ],
                                  onChanged: (next) {
                                    status.value = next;
                                    scheduleSave();
                                  },
                                ),
                              ),
                              MobileDetailFieldRow(
                                label: context.t(
                                  LocaleKeys.workspaceOutlineStartChapter,
                                ),
                                child: SizedBox(
                                  width: 96,
                                  child: TextFormField(
                                    key: ValueKey(
                                      'outline-start-chapter-${draft.documentId}',
                                    ),
                                    initialValue: '${startChapterNum.value}',
                                    keyboardType: TextInputType.number,
                                    inputFormatters: [
                                      FilteringTextInputFormatter.digitsOnly,
                                    ],
                                    textAlign: TextAlign.end,
                                    onChanged: (value) {
                                      final next = int.tryParse(value);
                                      if (next == null ||
                                          next < 1 ||
                                          next == startChapterNum.value) {
                                        return;
                                      }
                                      startChapterNum.value = next;
                                      scheduleSave();
                                    },
                                    // 与行内选择器同样式：无边框、值靠右。
                                    style: typo.uiSmallSemibold.copyWith(
                                      color: colors.textPrimary,
                                    ),
                                    decoration: const InputDecoration(
                                      isDense: true,
                                      border: InputBorder.none,
                                      enabledBorder: InputBorder.none,
                                      focusedBorder: InputBorder.none,
                                      contentPadding: EdgeInsets.zero,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(
                      RevericSpacing.x4l,
                      RevericSpacing.lg,
                      RevericSpacing.x4l,
                      RevericSpacing.x4l,
                    ),
                    sliver: SliverLayoutBuilder(
                      builder: (context, sliverConstraints) {
                        const sectionLabelHeight =
                            RevericSpacing.lg + RevericSpacing.sm;
                        final remainingHeight =
                            sliverConstraints.viewportMainAxisExtent -
                            sliverConstraints.precedingScrollExtent -
                            RevericSpacing.x4l;
                        final editorHeight = math.max(
                          360.0,
                          remainingHeight - sectionLabelHeight,
                        );

                        return SliverToBoxAdapter(
                          child: KeyedSubtree(
                            key: editorSectionKey,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                MobileDetailSectionLabel(
                                  text: context.t(LocaleKeys.commonContent),
                                ),
                                SizedBox(
                                  height: editorHeight,
                                  child: MobileSegmentedTabSwitcher(
                                    tabs: [
                                      context.t(LocaleKeys.commonContent),
                                      context.t(
                                        LocaleKeys
                                            .workspaceOutlineBeatChapterCountValue,
                                        namedArgs: {
                                          'count': '${beats.value.length}',
                                        },
                                      ),
                                    ],
                                    children: [
                                      RevericMarkdownEditor(
                                        controller: contentController,
                                        focusNode: contentFocusNode,
                                        undoController: undoController,
                                        hintText: context.t(
                                          LocaleKeys
                                              .workspaceOutlineContentHint,
                                        ),
                                      ),
                                      _BeatsList(
                                        beats: beats.value,
                                        onAdd: () => openBeatEditor(),
                                        onEdit: (index) =>
                                            openBeatEditor(beats.value[index]),
                                        onDelete: deleteBeat,
                                        onReorder: reorderBeats,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BeatsList extends StatelessWidget {
  const _BeatsList({
    required this.beats,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
    required this.onReorder,
  });

  final List<OutlineBeatDraft> beats;
  final VoidCallback onAdd;
  final ValueChanged<int> onEdit;
  final ValueChanged<int> onDelete;
  final ReorderCallback onReorder;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);

    if (beats.isEmpty) {
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
                context.t(LocaleKeys.workspaceOutlineTimelineEmptyTitle),
                style: typo.uiSemibold.copyWith(color: colors.textPrimary),
              ),
              const SizedBox(height: RevericSpacing.sm),
              Text(
                context.t(LocaleKeys.workspaceOutlineTimelineEmptyHint),
                textAlign: TextAlign.center,
                style: typo.uiSmall.copyWith(color: colors.textMuted),
              ),
              const SizedBox(height: RevericSpacing.x2l),
              FilledButton.icon(
                onPressed: onAdd,
                icon: RevericIcon(RevericIcons.add, size: 16),
                label: Text(context.t(LocaleKeys.workspaceOutlineAddBeat)),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.only(bottom: RevericSpacing.sm),
            child: InkWell(
              onTap: onAdd,
              borderRadius: BorderRadius.circular(RevericRadius.pill),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: RevericSpacing.lg,
                  vertical: RevericSpacing.sm,
                ),
                decoration: BoxDecoration(
                  color: colors.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(RevericRadius.pill),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    RevericIcon(
                      RevericIcons.add,
                      size: 16,
                      color: colors.accent,
                    ),
                    const SizedBox(width: RevericSpacing.xs),
                    Text(
                      context.t(LocaleKeys.workspaceOutlineAddBeat),
                      style: typo.uiSmallSemibold.copyWith(
                        color: colors.accent,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        Expanded(
          child: ReorderableListView.builder(
            buildDefaultDragHandles: false,
            itemCount: beats.length,
            onReorderItem: onReorder,
            padding: const EdgeInsets.only(bottom: RevericSpacing.x5l),
            itemBuilder: (context, index) {
              final beat = beats[index];
              return _BeatCard(
                key: ValueKey(beat.id),
                index: index,
                beat: beat,
                onEdit: () => onEdit(index),
                onDelete: () => onDelete(index),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _BeatCard extends StatelessWidget {
  const _BeatCard({
    super.key,
    required this.index,
    required this.beat,
    required this.onEdit,
    required this.onDelete,
  });

  final int index;
  final OutlineBeatDraft beat;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final title = beat.title.trim().isEmpty
        ? context.t(LocaleKeys.workspaceOutlineUntitledBeat)
        : shortOutlineBeatTitle(beat.title);
    final statusColor = _statusColor(beat.status, colors);
    final preview = beat.content.trim();

    return Padding(
      padding: const EdgeInsets.only(bottom: RevericSpacing.sm),
      child: RevericSlidableDelete(
        borderRadius: BorderRadius.circular(RevericRadius.large),
        deleteLabel: context.t(LocaleKeys.commonDelete),
        onDelete: onDelete,
        childBuilder: (context, borderRadius) => Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onEdit,
            borderRadius: borderRadius,
            child: Container(
              padding: const EdgeInsets.all(RevericSpacing.lg),
              decoration: BoxDecoration(
                color: colors.surfaceContainer,
                borderRadius: borderRadius,
                border: Border.all(color: colors.border),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ReorderableDragStartListener(
                    index: index,
                    child: Padding(
                      padding: const EdgeInsets.only(
                        top: 2,
                        right: RevericSpacing.sm,
                      ),
                      child: RevericIcon(
                        RevericIcons.swap_horiz_rounded,
                        size: 18,
                        color: colors.textSubtle,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              '${index + 1}.',
                              style: typo.uiSmallSemibold.copyWith(
                                color: colors.textSubtle,
                              ),
                            ),
                            const SizedBox(width: RevericSpacing.xs),
                            Expanded(
                              child: Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: typo.uiSemibold.copyWith(
                                  color: colors.textPrimary,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: RevericSpacing.xxs),
                        Row(
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: statusColor,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: RevericSpacing.xs),
                            Text(
                              context.t(
                                LocaleKeys
                                    .workspaceOutlineBeatChapterCountValue,
                                namedArgs: {'count': '${beat.chapterCount}'},
                              ),
                              style: typo.uiTiny.copyWith(
                                color: colors.textMuted,
                              ),
                            ),
                          ],
                        ),
                        if (preview.isNotEmpty) ...[
                          const SizedBox(height: RevericSpacing.xs),
                          Text(
                            preview,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: typo.uiSmall.copyWith(
                              color: colors.textMuted,
                              height: 1.45,
                            ),
                          ),
                        ],
                      ],
                    ),
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

Color _statusColor(String status, RevericColors colors) {
  return switch (status) {
    outlineStatusInProgress => colors.accent,
    outlineStatusFinished => colors.accentWarm,
    _ => colors.warningText,
  };
}

String _statusLabel(BuildContext context, String status) {
  return switch (status) {
    outlineStatusInProgress => context.t(
      LocaleKeys.workspaceOutlineStatusInProgress,
    ),
    outlineStatusFinished => context.t(
      LocaleKeys.workspaceOutlineStatusFinished,
    ),
    _ => context.t(LocaleKeys.workspaceOutlineStatusPending),
  };
}
