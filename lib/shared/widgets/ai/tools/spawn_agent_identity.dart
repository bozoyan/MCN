// 职责: SpawnAgent 行的身份呈现 — 拆出本次委派的笔名与子 Agent 职能，并渲染带状态环的头像与职能 chip
// 关联文件:
//   lib/shared/widgets/ai/tool_activity_group.dart
//   lib/shared/widgets/agent_avatar.dart
//   lib/shared/providers/subagent_providers.dart
//   lib/shared/services/ai/tools_subagent.dart
//   lib/shared/models/subagent.dart
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/icons.md
//   .agents/rules/state-management.md
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:reveric/shared/components/reveric_spinner.dart';
import 'package:reveric/shared/models/ai_message_block.dart';
import 'package:reveric/shared/models/subagent.dart';
import 'package:reveric/shared/providers/subagent_providers.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:reveric/shared/widgets/agent_avatar.dart';

const String _spawnAgentToolName = 'SpawnAgent';

/// 笔名在步骤行里的最大宽度：超出后省略，保证右侧职能 chip 始终有位置。
const double _penNameMaxWidth = 132;

/// 一次 SpawnAgent 调用的身份。
///
/// 新协议里 `agent` 是子 Agent 职能（「正文写手」），`name` 是编排者为本次委派
/// 起的笔名（「唐家三少」）。
class SpawnAgentIdentity {
  const SpawnAgentIdentity({required this.typeName, required this.penName});

  final String typeName;
  final String? penName;

  bool get hasPersona => (penName ?? '').isNotEmpty;
}

SpawnAgentIdentity spawnAgentIdentity(AiToolCallBlock block) {
  final agent = _arg(block, 'agent');
  final name = _arg(block, 'name');
  return SpawnAgentIdentity(
    typeName: agent,
    penName: name.isEmpty ? null : name,
  );
}

/// 本次委派的笔名；非 SpawnAgent 块或未提供笔名时返回 null。
String? spawnAgentPenName(AiToolCallBlock block) {
  if (block.toolName != _spawnAgentToolName) {
    return null;
  }
  return spawnAgentIdentity(block).penName;
}

/// 职能 chip 的文案：子 Agent 名称，配置了自定义模型时并入同一枚 chip，
/// 与改动前 `toolRowTarget` 的「名称 · 模型」信息量一致。
String spawnAgentRoleLabel(AiToolCallBlock block) {
  final typeName = spawnAgentIdentity(block).typeName;
  final model = (block.metadata?['sub_agent_model'] as String? ?? '').trim();
  if (typeName.isEmpty) {
    return model;
  }
  return model.isEmpty ? typeName : '$typeName · $model';
}

String _arg(AiToolCallBlock block, String key) =>
    (block.arguments[key] as String? ?? '').trim();

/// 委派行的头像：按 `agent` 匹配到子 Agent 后取其画像，外圈用颜色环表达状态，
/// 运行中是绕头像转的进度弧，终态是静止的色环 + 右下角角标。
class SpawnAgentAvatar extends ConsumerWidget {
  const SpawnAgentAvatar({
    super.key,
    required this.block,
    required this.status,
    this.novelId,
    this.size = 18,
  });

  final AiToolCallBlock block;
  final AiToolCallStatus status;
  final String? novelId;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = RevericTheme.colorsOf(context);
    final identity = spawnAgentIdentity(block);
    // 子 Agent 列表首帧可能还没就绪，此时 AgentAvatar 落到 emoji 兜底再自行重建。
    final agent = _matchByName(
      ref.watch(mergedSubAgentsProvider),
      identity.typeName,
    );
    final ringColor = _ringColor(colors, status);
    final isRunning = status == AiToolCallStatus.running;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          AgentAvatar(
            size: size,
            slug: agent?.slug,
            avatarPath: agent?.avatarPath,
            avatarEmoji: agent?.avatarEmoji,
            border: isRunning ? null : Border.all(color: ringColor, width: 1.5),
          ),
          if (isRunning)
            SizedBox(
              width: size,
              height: size,
              child: RevericSpinner(strokeWidth: 1.5, color: ringColor),
            ),
          if (_badgeIcon(status) case final String asset)
            Positioned(
              right: -2,
              bottom: -2,
              child: _StatusBadge(asset: asset, color: ringColor),
            ),
        ],
      ),
    );
  }

  SubAgent? _matchByName(List<SubAgent> agents, String name) {
    if (name.isEmpty) {
      return null;
    }
    final lower = name.toLowerCase();
    for (final agent in agents) {
      if (agent.name.toLowerCase() == lower) {
        return agent;
      }
    }
    return null;
  }

  Color _ringColor(RevericColors colors, AiToolCallStatus status) {
    return switch (status) {
      AiToolCallStatus.running => colors.accent,
      AiToolCallStatus.success => colors.additionBorder,
      AiToolCallStatus.error => colors.deletionBorder,
      AiToolCallStatus.pending ||
      AiToolCallStatus.rejected ||
      AiToolCallStatus.cancelled => colors.borderSubtle,
    };
  }

  String? _badgeIcon(AiToolCallStatus status) {
    return switch (status) {
      AiToolCallStatus.success => RevericIcons.check_rounded,
      AiToolCallStatus.error => RevericIcons.error_outline_rounded,
      AiToolCallStatus.cancelled => RevericIcons.close_rounded,
      AiToolCallStatus.pending ||
      AiToolCallStatus.running ||
      AiToolCallStatus.rejected => null,
    };
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.asset, required this.color});

  final String asset;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    // 实心角标 + 卡片色描边：在 18px 的头像边缘才读得出是徽章，而不是缺了一块。
    return Container(
      width: 11,
      height: 11,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        border: Border.all(color: colors.surfaceContainerHigh, width: 1),
      ),
      child: Center(
        child: RevericIcon(asset, size: 8, color: colors.surfaceContainerHigh),
      ),
    );
  }
}

/// 笔名后面的职能标签（「正文写手」），配置了自定义模型时并入同一枚 chip。
class SpawnAgentRoleChip extends StatelessWidget {
  const SpawnAgentRoleChip({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: RevericSpacing.xs,
        vertical: 1,
      ),
      decoration: BoxDecoration(
        color: colors.surfaceDim,
        borderRadius: BorderRadius.circular(RevericRadius.pill),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: typo.uiTiny.copyWith(color: colors.textMuted, height: 1.3),
      ),
    );
  }
}

/// 委派行第一行的「笔名 + 职能」内容区，外层负责放头像与展开箭头。
class SpawnAgentPersonaLabel extends StatelessWidget {
  const SpawnAgentPersonaLabel({
    super.key,
    required this.penName,
    required this.roleLabel,
  });

  final String penName;
  final String roleLabel;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return Row(
      children: [
        // 笔名是这一行的主语，限宽后省略；剩余空间全部留给职能 chip。
        Flexible(
          flex: 0,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _penNameMaxWidth),
            child: Text(
              penName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: typo.uiSemibold.copyWith(color: colors.textPrimary),
            ),
          ),
        ),
        if (roleLabel.isNotEmpty) ...[
          const SizedBox(width: RevericSpacing.xs),
          Flexible(child: SpawnAgentRoleChip(label: roleLabel)),
        ],
      ],
    );
  }
}
