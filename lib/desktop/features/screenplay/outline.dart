// 职责: 桌面剧本大纲区域 — 编辑当前集大纲正文（Logline/Synopsis/Theme/Arcs），下方只读列出结构节拍。
// 关联文件:
//   lib/desktop/widgets/workspace/novel_workspace_panel.dart
//   lib/shared/services/document_save_coordinator.dart
//   lib/shared/services/screenplay_outline_save.dart
//   lib/shared/providers/screenplay_providers.dart
//   lib/shared/providers/screenplay_workspace_state_provider.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/screenplay.json
//   assets/translations/zh-CN/screenplay.json
// 遵循的 Rules:
//   .agents/rules/hooks.md
//   .agents/rules/state-management.md
//   .agents/rules/design-system.md

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../shared/database/app_database.dart';
import '../../../shared/database/novel_content_database.dart'
    show ScreenplayEpisodeRow;
import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/models/novel_workspace.dart';
import '../../../shared/models/screenplay.dart';
import '../../../shared/providers/screenplay_providers.dart';
import '../../../shared/providers/screenplay_workspace_state_provider.dart';
import '../../../shared/providers/workspace_navigation_provider.dart';
import '../../../shared/providers/novel_providers.dart';
import '../../../shared/services/document_save_coordinator.dart';
import '../../../shared/services/screenplay_outline_save.dart';
import '../../../shared/theme/theme.dart';
import '../../../shared/widgets/md/reveric_markdown_editor.dart';
import 'chips.dart';
import 'chrome.dart';

class ScreenplayOutlineRegion extends HookConsumerWidget {
  const ScreenplayOutlineRegion({
    super.key,
    required this.novel,
    required this.registerFlush,
  });

  final Novel novel;

  /// 大纲编辑器挂载时交回它的落盘函数，宿主页在切走前调用；卸载时传 null。
  final ValueChanged<Future<void> Function()?> registerFlush;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final path = novel.contentDatabasePath!;
    final workspace = ref.watch(
      screenplayWorkspaceStateControllerProvider(novel.id, path),
    );
    final episodeId = workspace.episodeId;

    // 没有选中集时编辑器不挂载，确保宿主页拿不到过期的 flush。
    final registerFlushRef = useRef(registerFlush);
    registerFlushRef.value = registerFlush;
    useEffect(() {
      if (episodeId == null) {
        registerFlushRef.value(null);
      }
      return null;
    }, [episodeId]);

    if (episodeId == null) {
      return ScreenplayEmptyState(
        title: context.t(LocaleKeys.screenplayNoOutline),
      );
    }
    final episode = ref.watch(screenplayEpisodeProvider(path, episodeId)).value;
    final beats =
        ref.watch(screenplayBeatsProvider(path, episodeId)).value ??
        const <ScreenplayBeatSummary>[];
    final scenes =
        ref.watch(screenplayScenesProvider(path, episodeId)).value ??
        const <ScreenplaySceneSummary>[];
    // 行还没读出来时先留白，不闪空编辑器。
    if (episode == null) {
      return const SizedBox.shrink();
    }

    void openBeatsBoard() {
      ref
          .read(workspaceNavigationProvider.notifier)
          .request(
            WorkspaceNavigationRequest(
              section: NovelWorkspaceSection.screenplay_beats,
            ),
          );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        RevericSpacing.x5l,
        RevericSpacing.x4l,
        RevericSpacing.x5l,
        64,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: RevericSizes.screenplayOutlineMaxWidth,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _OutlineDocEditor(
                key: ValueKey(episode.id),
                novel: novel,
                episode: episode,
                registerFlush: registerFlush,
              ),
              const SizedBox(height: RevericSpacing.x6l),
              _OutlineBeatsSection(
                beats: beats,
                scenes: scenes,
                onOpenBoard: openBeatsBoard,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 当前集大纲正文的编辑区 —— 整段 markdown，debounce 自动保存，
/// 切集 / 切分区前由宿主页 flush。
class _OutlineDocEditor extends HookConsumerWidget {
  const _OutlineDocEditor({
    super.key,
    required this.novel,
    required this.episode,
    required this.registerFlush,
  });

  final Novel novel;
  final ScreenplayEpisodeRow episode;
  final ValueChanged<Future<void> Function()?> registerFlush;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final path = novel.contentDatabasePath!;
    final overlay = ref.read(workingOverlayServiceProvider(path));
    final database = ref.read(novelContentDatabaseProvider(path));
    final controller = useTextEditingController(text: episode.outline);
    final focusNode = useFocusNode();
    final coordinator = useMemoized(
      // 走 overlay 而不是直接 updateEpisodeOutline：手动保存要进修改历史，
      // 并顺带提交同一集上仍待审阅的 AI 改动。列写入由 apply-on-stage 完成。
      () => DocumentSaveCoordinator<String>(
        save: (text) => commitEpisodeOutlineManualSave(
          overlay,
          database,
          episodeId: episode.id,
          newOutline: text,
        ),
      ),
      [episode.id],
    );
    // 卸载前把 debounce 里的尾巴写掉；正常切换由宿主页的 flush 提前兜住。
    useEffect(() {
      return () {
        unawaited(coordinator.flush().onError((_, _) {}));
        coordinator.dispose();
      };
    }, [coordinator]);
    // 先更新基线，外部同步触发 controller listener 时才不会被当作手动输入。
    final outlineRef = useRef(episode.outline);
    outlineRef.value = episode.outline;
    // 本地有未落盘的编辑或正在组词时不接受外部值：AI 的写入落在 debounce 中间
    // 会盖掉正在输入的内容。用户这次保存会把 AI 那条改动一起提交进历史，
    // 不会丢。
    useEffect(() {
      if (coordinator.isDirty ||
          coordinator.isSaving ||
          controller.value.composing.isValid) {
        return null;
      }
      if (controller.text != episode.outline) {
        controller.text = episode.outline;
      }
      return null;
    }, [episode.id, episode.outline]);

    useOnListenableChange(controller, () {
      if (controller.text != outlineRef.value) {
        coordinator.schedule(controller.text);
      }
    });

    final registerFlushRef = useRef(registerFlush);
    registerFlushRef.value = registerFlush;
    useEffect(() {
      registerFlushRef.value(coordinator.flush);
      return () => registerFlushRef.value(null);
    }, [coordinator]);

    return RevericMarkdownEditor(
      controller: controller,
      focusNode: focusNode,
      hintText: context.t(LocaleKeys.screenplayOutlineHint),
      autoHeight: true,
      minHeight: 480,
    );
  }
}

/// 只读结构节拍 —— 与节拍看板同一份数据，这里只做总览，编辑跳去看板。
class _OutlineBeatsSection extends StatelessWidget {
  const _OutlineBeatsSection({
    required this.beats,
    required this.scenes,
    required this.onOpenBoard,
  });

  final List<ScreenplayBeatSummary> beats;
  final List<ScreenplaySceneSummary> scenes;
  final VoidCallback onOpenBoard;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final acts = beats.map((beat) => beat.actNumber).toSet().toList()..sort();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            RevericIcon(
              RevericIcons.alt_route_outlined,
              size: 14,
              color: colors.textMuted,
            ),
            const SizedBox(width: RevericSpacing.sm),
            Expanded(
              child: Text(
                context.t(LocaleKeys.screenplayOutlineBeats),
                style: typo.uiSemibold.copyWith(color: colors.textPrimary),
              ),
            ),
            TextButton(
              onPressed: onOpenBoard,
              child: Text(context.t(LocaleKeys.screenplayOpenBeatsBoard)),
            ),
          ],
        ),
        const SizedBox(height: RevericSpacing.lg),
        if (beats.isEmpty)
          Text(
            context.t(LocaleKeys.screenplayNoBeats),
            style: typo.ui.copyWith(color: colors.textMuted),
          )
        else
          for (final act in acts) ...[
            Padding(
              padding: const EdgeInsets.only(
                top: RevericSpacing.lg,
                bottom: RevericSpacing.sm,
              ),
              child: Text(
                context.t(
                  LocaleKeys.screenplayAct,
                  namedArgs: {'number': '$act'},
                ),
                style: typo.uiSmallSemibold.copyWith(color: colors.textMuted),
              ),
            ),
            for (final beat in beats.where((beat) => beat.actNumber == act))
              _OutlineBeatRow(
                beat: beat,
                sceneNumbers: [
                  for (final scene in scenes)
                    if (scene.beatId == beat.id) scene.sceneNumber,
                ],
                onTap: onOpenBoard,
              ),
          ],
      ],
    );
  }
}

class _OutlineBeatRow extends StatelessWidget {
  const _OutlineBeatRow({
    required this.beat,
    required this.sceneNumbers,
    required this.onTap,
  });

  final ScreenplayBeatSummary beat;
  final List<int> sceneNumbers;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final description = beat.description.trim();
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: RevericSpacing.lg),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: colors.borderSubtle)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
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
                ScreenplayPagesText(
                  pageEighths: beat.pageEighths,
                  style: typo.mono.copyWith(color: colors.textSubtle),
                ),
              ],
            ),
            if (description.isNotEmpty) ...[
              const SizedBox(height: RevericSpacing.xs),
              Text(
                description,
                style: typo.bodySmall.copyWith(
                  fontSize: 13,
                  height: 1.7,
                  color: colors.textSecondary,
                ),
              ),
            ],
            if (sceneNumbers.isNotEmpty) ...[
              const SizedBox(height: RevericSpacing.sm),
              Wrap(
                spacing: RevericSpacing.xxs,
                runSpacing: RevericSpacing.xxs,
                children: [
                  for (final number in sceneNumbers)
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
    );
  }
}
