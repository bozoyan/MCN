// 职责: 移动端把一张本地图落成作品封面 — 上传与 AI 出图共用的写入与结果提示。
// 关联文件:
//   lib/shared/services/novel_actions.dart
//   lib/mobile/pages/novel_editor_page.dart
//   lib/mobile/pages/novel_chat_page.dart
//   lib/mobile/features/cover_studio/studio_page.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
//   assets/translations/en/editor.json
//   assets/translations/zh-CN/editor.json
// 遵循的 Rules:
//   .agents/rules/error-handling.md
//   .agents/rules/i18n.md

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../shared/database/app_database.dart';
import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/providers/novel_providers.dart';

/// 写入封面并弹一条结果。
///
/// [successKey] 区分场景：手动上传说「已保存」，工作台应用说「已设为封面」。
/// 写入前重读一次作品：工作台停留期间标题/简介可能已经在别处改过。
Future<void> applyMobileNovelCover(
  BuildContext context,
  WidgetRef ref, {
  required Novel novel,

  /// 手动上传的本地文件；与 [assetId] 二选一。
  String? localFilePath,

  /// 封面工作台的生成结果。
  String? assetId,
  String successKey = LocaleKeys.editorGeneratedCoverApplied,
}) async {
  try {
    final currentNovel =
        ref.read(novelProvider(novel.id)).asData?.value ?? novel;
    await ref
        .read(novelActionsProvider)
        .updateNovel(
          novel: currentNovel,
          title: currentNovel.title,
          authorName: currentNovel.authorName,
          description: currentNovel.description,
          coverSourcePath: localFilePath,
          coverAssetId: assetId,
          removeCover: false,
          tags: currentNovel.tags,
          category: currentNovel.category,
          type: currentNovel.type,
        );
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(context.t(successKey))));
  } catch (error, stackTrace) {
    debugPrintStack(
      label: 'Failed to update novel cover',
      stackTrace: stackTrace,
    );
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.t(LocaleKeys.commonSaveFailed))),
    );
  }
}
