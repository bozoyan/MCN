// 职责: 全屏图片预览 — InteractiveViewer 缩放平移查看大图,点关闭或点击背景退出。
// 关联文件:
//   lib/shared/components/reveric_dialog.dart
//   lib/shared/theme/theme.dart
// 遵循的 Rules:
//   .agents/rules/design-system.md
import 'dart:io';

import 'package:flutter/material.dart';

import '../localization/locale_keys.dart';
import '../localization/app_localization.dart';
import '../theme/theme.dart';
import 'reveric_dialog.dart';

/// 以全屏弹层打开本地图片;双指缩放、拖动查看细节。
Future<void> showRevericImagePreview(
  BuildContext context, {
  required String imagePath,
  String? name,
}) {
  return showRevericDialog<void>(
    context: context,
    barrierColor: Colors.black87,
    builder: (context) {
      final typo = RevericTheme.typographyOf(context);
      return Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.all(RevericSpacing.x4l),
        child: Stack(
          children: [
            Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(RevericRadius.xl),
                child: InteractiveViewer(
                  child: Image.file(
                    File(imagePath),
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const RevericIcon(
                            RevericIcons.broken_image_outlined,
                            size: 64,
                          ),
                          const SizedBox(height: RevericSpacing.md),
                          Text(
                            context.t(LocaleKeys.mediaPreviewFailed),
                            style: typo.uiSmall.copyWith(
                              color: RevericTheme.colorsOf(
                                context,
                              ).textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (name != null && name.trim().isNotEmpty)
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: RevericSpacing.lg,
                      vertical: RevericSpacing.sm,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(RevericRadius.pill),
                    ),
                    child: Text(
                      name,
                      style: typo.uiSmall.copyWith(color: Colors.white),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
            Positioned(
              top: 0,
              right: 0,
              child: IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close, color: Colors.white, size: 26),
                tooltip: context.t(LocaleKeys.commonClose),
              ),
            ),
          ],
        ),
      );
    },
  );
}
