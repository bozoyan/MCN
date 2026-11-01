// 职责: Agent 头像组件 — 支持用户上传图片、内置画像资源、emoji 三级回退
// 关联文件:
//   lib/shared/models/agent_profile.dart
//   lib/shared/models/subagent.dart
//   lib/shared/utils/storage_paths.dart
import 'dart:io';

import 'package:flutter/material.dart';

import '../theme/theme.dart';
import '../utils/storage_paths.dart';

const _agentAvatarAssetBase = 'assets/images/agent_avatars';

const _builtinAvatarAssetNames = {
  'orchestrator': 'viber.webp',
  'planner': 'planner.webp',
  'writer': 'writer.webp',
  'artist': 'designer.webp',
  'chronicler': 'chronicler.webp',
  'monologue_narrator': 'monologue_narrator.webp',
  'roleplay_master': 'roleplay_master.webp',
  'theater_actor': 'theater_director.webp',
  'review': 'review.webp',
  'style_polish': 'style_polish.webp',
  'plot_architect': 'plot_architect.webp',
  'character_analyst': 'character_analyst.webp',
  'world_builder': 'world_builder.webp',
  'pacing_expert': 'pacing_expert.webp',
  'conflict_designer': 'conflict_designer.webp',
  'theme_guardian': 'theme_guardian.webp',
  'explorer': 'explorer.webp',
};

String? builtinAvatarAssetForSlug(
  String slug, {
  Brightness brightness = Brightness.dark,
}) {
  final assetName = _builtinAvatarAssetNames[slug];
  if (assetName == null) {
    return null;
  }

  final variant = brightness == Brightness.dark ? 'dark' : 'light';
  return '$_agentAvatarAssetBase/$variant/$assetName';
}

class AgentAvatar extends StatelessWidget {
  const AgentAvatar({
    super.key,
    this.avatarPath,
    this.slug,
    this.avatarEmoji,
    this.size = 28,
    this.backgroundColor,
    this.border,
  });

  final String? avatarPath;
  final String? slug;
  final String? avatarEmoji;
  final double size;
  final Color? backgroundColor;
  final BoxBorder? border;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final bgColor = backgroundColor ?? colors.surfaceContainer;

    // 1) User-uploaded image
    // 存储值可能是相对路径或旧沙盒容器的绝对路径，统一过 resolveStored 兜底。
    final resolvedAvatar = RevericPaths.resolveStored(avatarPath);
    if (resolvedAvatar != null) {
      return _imageContainer(
        bgColor: bgColor,
        image: Image.file(
          File(resolvedAvatar),
          fit: BoxFit.cover,
          cacheWidth: 128,
          errorBuilder: (_, _, _) => _buildBuiltinOrEmoji(context, bgColor),
        ),
      );
    }

    return _buildBuiltinOrEmoji(context, bgColor);
  }

  Widget _buildBuiltinOrEmoji(BuildContext context, Color bgColor) {
    // 2) Built-in asset image
    if (slug != null) {
      final assetPath = builtinAvatarAssetForSlug(
        slug!,
        brightness: RevericTheme.colorsOf(context).brightness,
      );
      if (assetPath != null) {
        return _imageContainer(
          bgColor: bgColor,
          image: Image.asset(
            assetPath,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => _emojiFallback(bgColor),
          ),
        );
      }
    }

    return _emojiFallback(bgColor);
  }

  Widget _emojiFallback(Color bgColor) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: bgColor,
        border: border,
      ),
      child: Center(
        child: Text(
          avatarEmoji ?? '🤖',
          style: TextStyle(fontSize: size * 0.5),
        ),
      ),
    );
  }

  Widget _imageContainer({required Widget image, required Color bgColor}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: bgColor,
        border: border,
      ),
      child: ClipOval(child: image),
    );
  }
}
