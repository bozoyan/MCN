// 职责: 角色扮演单条消息卡片 — 角色回应（生成中与生成后同一张 AgentMessageCard）与作者发言气泡，桌面面板与移动页共用。
// 关联文件:
//   lib/shared/widgets/ai/agent_message_card.dart
//   lib/shared/widgets/ai/agent_round_detail_dialog.dart
//   lib/shared/services/ai/roleplay_session_codec.dart
//   lib/shared/models/roleplay_models.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/council.json
//   assets/translations/zh-CN/council.json
import 'dart:io';

import 'package:flutter/material.dart';

import '../../agent/agent_run_state.dart';
import '../../localization/app_localization.dart';
import '../../localization/locale_keys.dart';
import '../../models/roleplay_models.dart';
import '../../services/ai/roleplay_session_codec.dart';
import '../../theme/theme.dart';
import '../../utils/storage_paths.dart';
import '../character_avatar.dart';
import 'agent_message_card.dart';
import 'agent_round_detail_dialog.dart';

/// 已落盘的一条消息：角色回应或作者发言。
class RoleplayMessageCard extends StatelessWidget {
  const RoleplayMessageCard({
    super.key,
    required this.message,
    required this.character,
    required this.density,
    required this.userName,
    required this.userAvatarPath,
    this.completedRun,
    this.databasePath,
    this.novelId,
  });

  final RoleplayMessage message;
  final RoleplayParticipant character;
  final AgentMessageDensity density;
  final String userName;
  final String userAvatarPath;
  final AgentRunState? completedRun;
  final String? databasePath;
  final String? novelId;

  @override
  Widget build(BuildContext context) {
    if (message.speakerId == roleplayUserSpeakerId) {
      return _UserMessageBubble(
        content: message.content,
        density: density,
        userName: userName,
        userAvatarPath: userAvatarPath,
      );
    }
    final detailRun =
        completedRun ??
        AgentRunState(
          agentId: message.speakerId,
          agentName: message.speakerName,
          round: 1,
          accumulatedText: message.content,
          isComplete: true,
        );
    return _CharacterCard(
      character: character,
      name: message.speakerName,
      density: density,
      thinking: completedRun?.accumulatedThinking ?? '',
      onOpenDetail: () => AgentRoundDetailDialog.show(
        context,
        runState: detailRun,
        title: message.speakerName,
        databasePath: databasePath,
        novelId: novelId,
      ),
      body: SelectionArea(
        child: Text(
          message.content,
          style: AgentMessageCard.bodyStyle(context, density),
        ),
      ),
    );
  }
}

/// 正在生成的角色回应：与 [RoleplayMessageCard] 同一外观，还没出字时显示跳动三点。
class RoleplayStreamingCard extends StatelessWidget {
  const RoleplayStreamingCard({
    super.key,
    required this.run,
    required this.character,
    required this.density,
    required this.onOpenDetail,
  });

  /// 还没收到首个 delta 时为 null。
  final AgentRunState? run;
  final RoleplayParticipant character;
  final AgentMessageDensity density;
  final VoidCallback onOpenDetail;

  @override
  Widget build(BuildContext context) {
    final run = this.run;
    final text = run?.accumulatedText ?? '';
    return _CharacterCard(
      character: character,
      name: character.name,
      density: density,
      thinking: run?.accumulatedThinking ?? '',
      streaming: true,
      onOpenDetail: run == null ? null : onOpenDetail,
      // 内容还在增长，不开选区。
      body: text.isEmpty
          ? null
          : Text(text, style: AgentMessageCard.bodyStyle(context, density)),
    );
  }
}

class _CharacterCard extends StatelessWidget {
  const _CharacterCard({
    required this.character,
    required this.name,
    required this.density,
    required this.thinking,
    required this.body,
    this.streaming = false,
    this.onOpenDetail,
  });

  final RoleplayParticipant character;
  final String name;
  final AgentMessageDensity density;
  final String thinking;
  final Widget? body;
  final bool streaming;
  final VoidCallback? onOpenDetail;

  @override
  Widget build(BuildContext context) {
    final accent = RevericTheme.colorsOf(context).accentWarm;
    return AgentMessageCard(
      avatar: CharacterAvatar(
        avatarAssetId: character.avatarAssetId,
        fallbackName: character.name,
        size: AgentMessageCard.avatarSize(density),
        backgroundColor: accent.withValues(alpha: 0.15),
      ),
      name: name,
      accentColor: accent,
      density: density,
      thinking: thinking,
      streaming: streaming,
      onOpenDetail: onOpenDetail,
      body: body,
    );
  }
}

/// 作者发言：靠右、头像在右。
class _UserMessageBubble extends StatelessWidget {
  const _UserMessageBubble({
    required this.content,
    required this.density,
    required this.userName,
    required this.userAvatarPath,
  });

  final String content;
  final AgentMessageDensity density;
  final String userName;
  final String userAvatarPath;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final mobile = density == AgentMessageDensity.mobile;
    final accent = colors.accent;
    final displayName = userName.isNotEmpty
        ? userName
        : context.t(LocaleKeys.councilUserSpeakerLabel);
    return Padding(
      padding: EdgeInsets.only(
        bottom: mobile ? RevericSpacing.lg : RevericSpacing.md,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  displayName,
                  style: typo.uiSmall.copyWith(
                    color: accent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(
                  height: mobile ? RevericSpacing.xs : RevericSpacing.xxs,
                ),
                Container(
                  padding: const EdgeInsets.all(RevericSpacing.md),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(
                      mobile ? RevericRadius.x2l : RevericRadius.xl,
                    ),
                  ),
                  child: SelectionArea(
                    child: Text(
                      content,
                      style: AgentMessageCard.bodyStyle(context, density),
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: mobile ? RevericSpacing.md : RevericSpacing.sm),
          _UserAvatar(
            path: userAvatarPath,
            fallback: CharacterAvatar(
              fallbackName: displayName,
              size: AgentMessageCard.avatarSize(density),
              backgroundColor: accent.withValues(alpha: 0.15),
            ),
            size: AgentMessageCard.avatarSize(density),
          ),
        ],
      ),
    );
  }
}

/// 用户头像来自设置里的本地图片，不属于作品资产；缺失时显示名字首字。
class _UserAvatar extends StatelessWidget {
  const _UserAvatar({
    required this.path,
    required this.fallback,
    required this.size,
  });
  final String path;
  final Widget fallback;
  final double size;

  @override
  Widget build(BuildContext context) {
    final resolved = RevericPaths.resolveStored(path.trim());
    if (resolved == null) {
      return fallback;
    }
    return ClipOval(
      child: Image.file(
        File(resolved),
        width: size,
        height: size,
        fit: BoxFit.cover,
        cacheWidth: (size * 2).toInt(),
        errorBuilder: (_, _, _) => fallback,
      ),
    );
  }
}
