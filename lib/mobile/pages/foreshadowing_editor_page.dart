// 职责: 移动端伏笔编辑页 — 标题/状态/铺垫/兑现 markdown 编辑（防抖自动保存）、关联位置选择（即时保存）。
// 关联文件:
//   lib/mobile/widgets/foreshadowings_panel.dart
//   lib/shared/widgets/foreshadowing/position_links.dart
//   lib/shared/widgets/md/reveric_markdown_editor.dart
//   lib/shared/providers/novel_providers.dart
//   lib/shared/services/novel_content.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/workspace.json
//   assets/translations/zh-CN/workspace.json
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
//   assets/translations/en/mobile.json
//   assets/translations/zh-CN/mobile.json
// 遵循的 Rules:
//   .agents/rules/hooks.md
//   .agents/rules/design-system.md
//   .agents/rules/icons.md
//   .agents/rules/i18n.md
//   .agents/rules/error-handling.md
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../shared/components/reveric_select.dart';
import '../../shared/localization/app_localization.dart';
import '../../shared/localization/locale_keys.dart';
import '../../shared/widgets/foreshadowing/position_links.dart';
import '../features/screenplay/scene_editor.dart';
import 'chapter_editor_page.dart';
import '../../shared/models/foreshadowing.dart';
import '../../shared/providers/novel_providers.dart';
import '../../shared/theme/theme.dart';
import '../../shared/widgets/md/reveric_markdown_editor.dart';
import '../widgets/detail_scaffold.dart';
import '../widgets/editor_app_bar.dart';
import '../widgets/segmented_tab_switcher.dart';

/// 伏笔编辑页（按 id 加载）：从伏笔列表按 id 取条目后渲染编辑主体。
/// 拆 loader 让条目跳转/列表打开统一「只传 id」，主体同步拿到具体对象不变。
class MobileForeshadowingEditorPage extends ConsumerWidget {
  const MobileForeshadowingEditorPage({
    super.key,
    required this.novelId,
    required this.databasePath,
    required this.foreshadowingId,
  });

  final String novelId;
  final String databasePath;
  final String foreshadowingId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(foreshadowingsProvider(databasePath)).value;
    final foreshadowing = list?.cast<Foreshadowing?>().firstWhere(
      (f) => f?.id == foreshadowingId,
      orElse: () => null,
    );
    if (foreshadowing == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return _ForeshadowingEditorBody(
      key: ValueKey(foreshadowing.id),
      novelId: novelId,
      databasePath: databasePath,
      foreshadowing: foreshadowing,
    );
  }
}

class _ForeshadowingEditorBody extends HookConsumerWidget {
  const _ForeshadowingEditorBody({
    super.key,
    required this.novelId,
    required this.databasePath,
    required this.foreshadowing,
  });

  final String novelId;
  final String databasePath;
  final Foreshadowing foreshadowing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = RevericTheme.colorsOf(context);

    final titleController = useTextEditingController(text: foreshadowing.title);
    final setupController = useTextEditingController(text: foreshadowing.setup);
    final payoffController = useTextEditingController(
      text: foreshadowing.payoff,
    );
    final setupFocusNode = useFocusNode();
    final payoffFocusNode = useFocusNode();
    final scrollController = useScrollController();
    final editorSectionKey = useMemoized(GlobalKey.new);
    // 共享 undo/redo 控制器：标题/铺垫/兑现同页，按钮作用于当前焦点字段。
    final undoController = useMemoized(UndoHistoryController.new);
    useEffect(() => undoController.dispose, const []);
    final status = useState<String>(foreshadowing.normalizedStatus);
    final positions = useState(foreshadowingPositionIdsOf(foreshadowing));
    // 最近一次落库的位置；未变时不重复校验/写入。
    final savedPositions = useRef(foreshadowingPositionIdsOf(foreshadowing));
    final dirty = useRef(false);
    final autoSaveTimer = useRef<Timer?>(null);
    final saveState = useState<(bool, DateTime?)>((
      false,
      foreshadowing.updatedAt,
    ));

    final service = ref.watch(novelContentServiceProvider(databasePath));
    // 位置跳转要用它构造目标页。这里必须 watch：只在回调里 read(...future) 时
    // 没有监听者，autoDispose provider 会在 loading 中被释放，future 抛异常，
    // 点击表现为毫无反应。
    final work = ref.watch(novelProvider(novelId)).value;

    Future<void> write() async {
      await service.updateForeshadowing(
        entryId: foreshadowing.id,
        title: titleController.text.trim(),
        setup: setupController.text,
        payoff: payoffController.text,
        status: status.value,
      );
      final nextPositions = positions.value;
      if (nextPositions != savedPositions.value) {
        await service.updateForeshadowingPositions(
          entryId: foreshadowing.id,
          fields: foreshadowingPositionFields(nextPositions),
        );
        savedPositions.value = nextPositions;
      }
    }

    Future<void> persist() async {
      autoSaveTimer.value?.cancel();
      if (!dirty.value) return;
      saveState.value = (true, saveState.value.$2);
      try {
        await write();
        dirty.value = false;
        saveState.value = (false, DateTime.now());
      } catch (_) {
        // service 已记录 [DB] 日志；UI 仅回到非保存中状态。
        saveState.value = (false, saveState.value.$2);
      }
    }

    void scheduleSave() {
      dirty.value = true;
      autoSaveTimer.value?.cancel();
      autoSaveTimer.value = Timer(const Duration(milliseconds: 800), persist);
    }

    // markdown 编辑器无 onChanged，借助 controller 监听触发自动保存。
    useEffect(() {
      void listener() => scheduleSave();
      setupController.addListener(listener);
      payoffController.addListener(listener);
      return () {
        setupController.removeListener(listener);
        payoffController.removeListener(listener);
      };
    }, const []);

    // 键盘弹出时把编辑区滚入可视区域，避免上半表单项占满压缩后的视口。
    useEffect(() {
      void scrollEditorIntoView() {
        if (!setupFocusNode.hasFocus && !payoffFocusNode.hasFocus) {
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

      setupFocusNode.addListener(scrollEditorIntoView);
      payoffFocusNode.addListener(scrollEditorIntoView);
      return () {
        setupFocusNode.removeListener(scrollEditorIntoView);
        payoffFocusNode.removeListener(scrollEditorIntoView);
      };
    }, const []);

    // 退出时冲刷未落盘改动。
    useEffect(
      () => () {
        autoSaveTimer.value?.cancel();
        if (dirty.value) {
          // 页面已销毁，失败无处提示；service 已记录 [DB] 日志。
          unawaited(write().catchError((Object _) {}));
        }
      },
      const [],
    );

    useListenable(titleController);

    final displayTitle = titleController.text.trim().isEmpty
        ? context.t(LocaleKeys.commonUntitled)
        : titleController.text.trim();

    Future<void> openPosition(ForeshadowingPositionTarget target) async {
      await persist();
      final novel = work;
      if (novel == null || !context.mounted) {
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => target.scene == null
              ? MobileChapterEditorPage(
                  novel: novel,
                  databasePath: databasePath,
                  initialChapterId: target.id,
                )
              : MobileScreenplaySceneEditorPage(
                  novel: novel,
                  scene: target.scene!,
                ),
        ),
      );
    }

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
              onBack: () => Navigator.of(context).maybePop(),
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
                            hintText: context.t(
                              LocaleKeys.workspaceEntryTitleHint,
                            ),
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
                                    for (final s in foreshadowingStatuses)
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
                              ForeshadowingPositionLinks(
                                databasePath: databasePath,
                                mobile: true,
                                value: positions.value,
                                onChanged: (next) {
                                  positions.value = next;
                                  scheduleSave();
                                },
                                positions: const ['setup'],
                                rowBuilder: (label, value) =>
                                    MobileDetailFieldRow(
                                      label: label,
                                      child: value,
                                    ),
                                onNavigate: openPosition,
                              ),
                              ForeshadowingPositionLinks(
                                databasePath: databasePath,
                                mobile: true,
                                value: positions.value,
                                onChanged: (next) {
                                  positions.value = next;
                                  scheduleSave();
                                },
                                positions: const ['payoff'],
                                rowBuilder: (label, value) =>
                                    MobileDetailFieldRow(
                                      label: label,
                                      child: value,
                                    ),
                                onNavigate: openPosition,
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
                                      context.t(LocaleKeys.commonSetup),
                                      context.t(LocaleKeys.commonPayoff),
                                    ],
                                    children: [
                                      RevericMarkdownEditor(
                                        controller: setupController,
                                        focusNode: setupFocusNode,
                                        undoController: undoController,
                                        hintText: context.t(
                                          LocaleKeys
                                              .workspaceForeshadowSetupHint,
                                        ),
                                      ),
                                      RevericMarkdownEditor(
                                        controller: payoffController,
                                        focusNode: payoffFocusNode,
                                        undoController: undoController,
                                        hintText: context.t(
                                          LocaleKeys
                                              .workspaceForeshadowPayoffHint,
                                        ),
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

Color _statusColor(String status, RevericColors colors) {
  return switch (status) {
    foreshadowingStatusPlanted => colors.accentAmber,
    foreshadowingStatusPayoff => colors.accent,
    foreshadowingStatusAbandoned => colors.textMuted,
    _ => colors.textSubtle,
  };
}

String _statusLabel(BuildContext context, String status) {
  return switch (status) {
    foreshadowingStatusPending => context.t(
      LocaleKeys.foreshadowingStatusPending,
    ),
    foreshadowingStatusPlanted => context.t(
      LocaleKeys.foreshadowingStatusPlanted,
    ),
    foreshadowingStatusPayoff => context.t(
      LocaleKeys.foreshadowingStatusPayoff,
    ),
    foreshadowingStatusAbandoned => context.t(
      LocaleKeys.foreshadowingStatusAbandoned,
    ),
    _ => status,
  };
}
