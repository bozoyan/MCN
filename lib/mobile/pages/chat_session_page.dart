// 职责: 移动端单个 AI 对话的历史查看页 — 加载并渲染该会话的历史消息，打开时贴底展示最新消息，可把生成图片应用到角色 / 物品。
// 关联文件:
//   lib/shared/widgets/novel_open_boundary.dart
//   lib/mobile/providers/chat_providers.dart
//   lib/shared/widgets/ai/chat/auto_scroll_hook.dart
//   lib/shared/widgets/ai/chat/chat_message_view.dart
//   lib/mobile/widgets/chat_image_actions.dart
//   lib/shared/theme/theme.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/mobile.json
//   assets/translations/zh-CN/mobile.json
// 遵循的 Rules:
//   .agents/rules/hooks.md
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../shared/widgets/novel_open_boundary.dart';
import '../../shared/database/app_database.dart' show AiChatSession;
import '../../shared/localization/app_localization.dart';
import '../../shared/localization/locale_keys.dart';
import '../../shared/theme/theme.dart';
import 'package:reveric/shared/widgets/ai/chat/auto_scroll_hook.dart';
import 'package:reveric/shared/widgets/ai/chat/chat_message_view.dart';
import 'package:reveric/shared/widgets/ai/chat/ui_message.dart';

import '../providers/chat_providers.dart';
import '../widgets/chat_image_actions.dart';
import 'agent_model_settings_page.dart';

class MobileChatSessionPage extends HookConsumerWidget {
  const MobileChatSessionPage({
    super.key,
    required this.session,
    required this.displayTitle,
    required this.databasePath,
  });

  final AiChatSession session;
  final String displayTitle;
  final String? databasePath;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return NovelOpenBoundary(
      novelId: session.novelId,
      child: HookConsumer(
        builder: (context, ref, _) => _buildContent(context, ref),
      ),
    );
  }

  Widget _buildContent(BuildContext context, WidgetRef ref) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final messagesAsync = ref.watch(
      mobileSessionMessagesProvider((
        sessionId: session.id,
        novelId: session.novelId,
        databasePath: databasePath,
      )),
    );
    // 提前算出 uiMessages 供 hook 无条件调用（loading 时为空，hook 自动跳过）。
    final messages = messagesAsync.asData?.value ?? const [];
    final uiMessages = groupMessagesForUi(messages);
    final userScrolledUp = useRef(false);
    final scrollController = useChatAutoScroll(
      uiMessages: uiMessages,
      userScrolledUp: userScrolledUp,
      sessionId: session.id,
    );

    return Scaffold(
      backgroundColor: colors.canvas,
      appBar: AppBar(
        backgroundColor: colors.canvas,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: RevericIcon(
            RevericIcons.chevron_left,
            size: 24,
            color: colors.textSecondary,
          ),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(
          displayTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: typo.uiSemibold.copyWith(color: colors.textPrimary),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, thickness: 1, color: colors.borderSubtle),
        ),
      ),
      body: messagesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) =>
            _CenteredHint(text: context.t(LocaleKeys.mobileChatLoadFailed)),
        data: (messages) {
          if (messages.isEmpty) {
            return _CenteredHint(
              text: context.t(LocaleKeys.mobileChatEmptyConversation),
            );
          }
          final path = databasePath;
          return ListView.separated(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(
              RevericSpacing.lg,
              RevericSpacing.lg,
              RevericSpacing.lg,
              RevericSpacing.x3l,
            ),
            itemCount: uiMessages.length,
            separatorBuilder: (_, _) =>
                const SizedBox(height: RevericSpacing.lg),
            itemBuilder: (context, index) => ChatMessageView(
              message: uiMessages[index],
              activeSessionId: session.id,
              onConfigureImageModel: () =>
                  openMobileAgentModelSettingsPage(context),
              onSetAsAvatar: path == null
                  ? null
                  : (assetId, characterId) => setGeneratedImageAsAvatar(
                      context,
                      ref,
                      databasePath: path,
                      assetId: assetId,
                      characterId: characterId,
                    ),
              onAddPhoto: path == null
                  ? null
                  : (assetId, {characterId, itemId}) =>
                        addGeneratedImageAsPhoto(
                          context,
                          ref,
                          databasePath: path,
                          assetId: assetId,
                          characterId: characterId,
                          itemId: itemId,
                        ),
              databasePath: databasePath,
              novelId: session.novelId,
            ),
          );
        },
      ),
    );
  }
}

class _CenteredHint extends StatelessWidget {
  const _CenteredHint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(RevericSpacing.x3l),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: typo.uiSmall.copyWith(color: colors.textMuted),
        ),
      ),
    );
  }
}
