// 职责: 桌面端独白会话区 — 议题头、独白消息流，以及生成中（暂停/取消）与生成后（继续/转写作）的底栏。
// 关联文件:
//   lib/desktop/features/monologue/panel.dart
//   lib/desktop/features/monologue/message_list.dart
//   lib/shared/hooks/use_monologue_run.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/monologue.json
//   assets/translations/zh-CN/monologue.json
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
import 'package:flutter/material.dart';

import '../../../shared/hooks/use_monologue_run.dart';
import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/models/monologue_models.dart';
import '../../../shared/theme/theme.dart';
import 'message_list.dart';

class MonologueSessionSection extends StatelessWidget {
  const MonologueSessionSection({
    super.key,
    required this.run,
    required this.session,
    required this.modelSelector,
    required this.onOpenActiveRunDetail,
    this.onSwitchToWriteMode,
  });

  final MonologueRun run;
  final MonologueSession session;
  final Widget modelSelector;
  final Future<void> Function(String title) onOpenActiveRunDetail;
  final Future<void> Function()? onSwitchToWriteMode;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final isGenerating = session.phase == MonologuePhase.generating;
    // 议题可能很长：header 是 Column 的固定 child，必须给议题文本限高，
    // 否则长议题会把 Expanded 消息列表压到 0 高度，无法滚动查看生成内容。
    // LayoutBuilder 必须包在 Column 外层：Column 给非 flex 子节点的高度约束
    // 无界（maxHeight = infinity），包在里面算出的比例限高不会生效。
    return LayoutBuilder(
      builder: (context, constraints) {
        final topicMaxHeight = constraints.maxHeight * 0.3;
        return Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: RevericSpacing.x2l,
                vertical: RevericSpacing.md,
              ),
              color: colors.surface,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.t(LocaleKeys.monologueTopic),
                    style: typo.uiSmall.copyWith(color: colors.textMuted),
                  ),
                  const SizedBox(height: RevericSpacing.xxs),
                  ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: topicMaxHeight),
                    // Column 的 start 对齐给的是宽松宽度，滚动视口会缩到最长行
                    // 宽，滚动条悬浮在文字中间；必须显式撑满宽度。
                    // shrinkWrap 让短议题按内容收缩，不会始终占满上限高度。
                    child: SizedBox(
                      width: double.infinity,
                      child: ListView(
                        shrinkWrap: true,
                        padding: EdgeInsets.zero,
                        children: [
                          Text(
                            session.topic,
                            style: typo.uiSemibold.copyWith(
                              color: colors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: colors.border),
            Expanded(
              child: MonologueMessageList(
                session: session,
                activeRun: run.activeRun,
                runHistory: run.runHistory,
                onOpenActiveRunDetail: onOpenActiveRunDetail,
              ),
            ),
            _BottomBar(
              padding: isGenerating
                  ? const EdgeInsets.symmetric(
                      horizontal: RevericSpacing.x2l,
                      vertical: RevericSpacing.md,
                    )
                  : const EdgeInsets.all(RevericSpacing.lg),
              modelSelector: modelSelector,
              child: isGenerating
                  ? _ActiveActions(
                      run: run,
                      characterName: session.character.name,
                    )
                  : _CompletedActions(
                      run: run,
                      onSwitchToWriteMode: onSwitchToWriteMode,
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.padding,
    required this.modelSelector,
    required this.child,
  });

  final EdgeInsets padding;
  final Widget modelSelector;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(top: BorderSide(color: colors.border)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(alignment: Alignment.centerLeft, child: modelSelector),
            const SizedBox(height: RevericSpacing.sm),
            child,
          ],
        ),
      ),
    );
  }
}

class _ActiveActions extends StatelessWidget {
  const _ActiveActions({required this.run, required this.characterName});

  final MonologueRun run;
  final String characterName;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final buttonStyle = typo.uiSmall.copyWith(color: colors.textMuted);
    return Row(
      children: [
        SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: colors.accent,
          ),
        ),
        const SizedBox(width: RevericSpacing.sm),
        Expanded(
          child: Text(
            context.t(
              LocaleKeys.monologueThinkingFmt,
              namedArgs: {'name': characterName},
            ),
            style: typo.uiSmall.copyWith(color: colors.textMuted),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        TextButton(
          onPressed: run.pause,
          child: Text(context.t(LocaleKeys.commonPause), style: buttonStyle),
        ),
        TextButton(
          onPressed: run.cancel,
          child: Text(context.t(LocaleKeys.commonCancel), style: buttonStyle),
        ),
      ],
    );
  }
}

class _CompletedActions extends StatelessWidget {
  const _CompletedActions({required this.run, this.onSwitchToWriteMode});

  final MonologueRun run;
  final Future<void> Function()? onSwitchToWriteMode;

  @override
  Widget build(BuildContext context) {
    final switchToWrite = onSwitchToWriteMode;
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: run.isRunning ? null : run.continueRun,
            icon: RevericIcon(RevericIcons.add_rounded, size: 16),
            label: Text(context.t(LocaleKeys.monologueContinue)),
          ),
        ),
        const SizedBox(width: RevericSpacing.sm),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: run.isRunning || switchToWrite == null
                ? null
                : switchToWrite,
            icon: RevericIcon(RevericIcons.edit_note_outlined, size: 16),
            label: Text(context.t(LocaleKeys.aiSwitchToWriteMode)),
          ),
        ),
      ],
    );
  }
}
