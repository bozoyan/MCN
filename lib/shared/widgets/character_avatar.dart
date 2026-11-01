// 职责: 角色头像展示组件 — 优先显示角色头像图片资产，回退到名字首字母圆形。
// 关联文件:
//   lib/shared/models/character_profile.dart
//   lib/shared/widgets/agent_avatar.dart
//   lib/shared/widgets/media_asset_image.dart
import 'package:flutter/material.dart';

import '../models/character_profile.dart';
import 'media_asset_image.dart';

class CharacterAvatar extends StatelessWidget {
  const CharacterAvatar({
    super.key,
    this.character,
    this.avatarAssetId,
    this.fallbackName,
    this.fallbackMaxChars = 1,
    this.size = 32,
    this.backgroundColor,
    this.textColor,
  });

  final CharacterProfile? character;
  final String? avatarAssetId;
  final String? fallbackName;
  final int fallbackMaxChars;
  final double size;
  final Color? backgroundColor;
  final Color? textColor;

  String? get _resolvedAssetId => avatarAssetId ?? character?.avatarAssetId;

  String get _resolvedName => fallbackName ?? character?.name ?? '?';

  String _avatarFallbackText(String name, int maxChars) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      return '?';
    }
    final limit = maxChars < 1 ? 1 : maxChars;
    return trimmed.characters.take(limit).string;
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = backgroundColor ?? Colors.grey.withValues(alpha: 0.15);
    final fallback = _fallback(bgColor);
    final assetId = _resolvedAssetId;
    if (assetId == null || assetId.isEmpty) {
      return fallback;
    }
    return SizedBox(
      width: size,
      height: size,
      child: ClipOval(
        child: MediaAssetImage(
          assetId: assetId,
          cacheWidth: (size * 2).toInt(),
          placeholder: fallback,
        ),
      ),
    );
  }

  Widget _fallback(Color bgColor) {
    final txtColor = textColor ?? Colors.white;
    final fallbackText = _avatarFallbackText(_resolvedName, fallbackMaxChars);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: bgColor),
      child: Center(
        child: Text(
          fallbackText,
          style: TextStyle(
            fontSize: size * (fallbackText.characters.length > 1 ? 0.36 : 0.45),
            fontWeight: FontWeight.w600,
            color: txtColor,
          ),
        ),
      ),
    );
  }
}
