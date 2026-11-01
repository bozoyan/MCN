// 职责: 移动端聊天里把 AI 生成的图片应用到角色头像或角色 / 物品照片，失败时提示保存失败。
// 关联文件:
//   lib/shared/widgets/ai/chat/chat_message_view.dart
//   lib/shared/services/novel_content.dart
//   lib/mobile/pages/novel_chat_page.dart
//   lib/mobile/pages/chat_session_page.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
// 遵循的 Rules:
//   .agents/rules/file-access.md
//   .agents/rules/error-handling.md
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../shared/localization/app_localization.dart';
import '../../shared/localization/locale_keys.dart';
import '../../shared/logger/app_logger.dart';
import '../../shared/providers/novel_providers.dart';

final _log = AppLogger.forModule('MobileChatImageActions');

Future<void> setGeneratedImageAsAvatar(
  BuildContext context,
  WidgetRef ref, {
  required String databasePath,
  required String assetId,
  required String characterId,
}) => _apply(context, () async {
  final service = ref.read(novelContentServiceProvider(databasePath));
  await service.updateCharacterAvatarAndPhotos(
    entryId: characterId,
    avatarAssetId: assetId,
  );
});

Future<void> addGeneratedImageAsPhoto(
  BuildContext context,
  WidgetRef ref, {
  required String databasePath,
  required String assetId,
  String? characterId,
  String? itemId,
}) => _apply(context, () async {
  final service = ref.read(novelContentServiceProvider(databasePath));
  if (characterId != null && characterId.isNotEmpty) {
    await service.addCharacterPhotos(characterId, [assetId]);
  } else if (itemId != null && itemId.isNotEmpty) {
    await service.addItemPhotos(itemId, [assetId]);
  }
});

Future<void> _apply(
  BuildContext context,
  Future<void> Function() action,
) async {
  try {
    await action();
  } catch (error, stackTrace) {
    _log.error(
      'Apply generated image failed',
      error: error,
      stackTrace: stackTrace,
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.t(LocaleKeys.commonSaveFailed))),
      );
    }
  }
}
