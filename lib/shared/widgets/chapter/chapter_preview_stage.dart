// 职责: 章节阅读预览舞台 — 按设备画布（手机/平板）渲染章节标题与正文，供 desktop 预览弹窗与 mobile 预览页共用。
// 关联文件:
//   lib/desktop/widgets/workspace/chapter_preview_dialog.dart
//   lib/mobile/pages/chapter_preview_page.dart
//   lib/shared/localization/locale_keys.dart
//   lib/shared/theme/theme.dart
//   assets/translations/en/workspace.json
//   assets/translations/zh-CN/workspace.json
// 遵循的 Rules:
//   .agents/rules/design-system.md
import 'package:flutter/material.dart';

import '../../localization/app_localization.dart';
import '../../localization/locale_keys.dart';
import '../../theme/theme.dart';

/// 章节预览的模拟设备规格。
enum ChapterPreviewDevice {
  phone320(
    labelKey: LocaleKeys.workspacePreviewDevicePhoneSmall,
    width: 320,
    height: 568,
    frame: 10,
    radius: 34,
    screenRadius: 25,
    contentPadding: 24,
    statusBarHeight: 34,
  ),
  phone390(
    labelKey: LocaleKeys.workspacePreviewDevicePhone,
    width: 390,
    height: 844,
    frame: 12,
    radius: 38,
    screenRadius: 27,
    contentPadding: 32,
    statusBarHeight: 42,
  ),
  phone430(
    labelKey: LocaleKeys.workspacePreviewDevicePhoneLarge,
    width: 430,
    height: 932,
    frame: 12,
    radius: 42,
    screenRadius: 31,
    contentPadding: 36,
    statusBarHeight: 44,
  ),
  tablet768(
    labelKey: LocaleKeys.workspacePreviewDeviceTablet,
    width: 768,
    height: 1024,
    frame: 16,
    radius: 30,
    screenRadius: 18,
    contentPadding: 84,
    statusBarHeight: 40,
  );

  const ChapterPreviewDevice({
    required this.labelKey,
    required this.width,
    required this.height,
    required this.frame,
    required this.radius,
    required this.screenRadius,
    required this.contentPadding,
    required this.statusBarHeight,
  });

  final String labelKey;
  final double width;
  final double height;
  final double frame;
  final double radius;
  final double screenRadius;
  final double contentPadding;
  final double statusBarHeight;

  double get outerWidth => width + frame * 2;
  double get outerHeight => height + frame * 2;
}

/// 按设备画布渲染章节预览：设备外框 + 状态栏 + 标题 + 正文。
class ChapterPreviewStage extends StatelessWidget {
  const ChapterPreviewStage({
    super.key,
    required this.device,
    required this.title,
    required this.body,
    required this.fontFamily,
    required this.fontSize,
    required this.letterSpacing,
    required this.lineHeight,
  });

  final ChapterPreviewDevice device;
  final String title;
  final String body;
  final String fontFamily;
  final int fontSize;
  final double letterSpacing;
  final double lineHeight;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);

    return Center(
      child: FittedBox(
        fit: BoxFit.contain,
        child: SizedBox(
          width: device.outerWidth,
          height: device.outerHeight,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colors.textPrimary,
              borderRadius: BorderRadius.circular(device.radius),
              boxShadow: [
                BoxShadow(
                  color: colors.textPrimary.withValues(alpha: 0.18),
                  blurRadius: 28,
                  offset: const Offset(0, 16),
                ),
              ],
            ),
            child: Padding(
              padding: EdgeInsets.all(device.frame),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(device.screenRadius),
                child: ColoredBox(
                  color: colors.surface,
                  child: _ReadablePreview(
                    device: device,
                    title: title,
                    body: body,
                    fontFamily: fontFamily,
                    fontSize: fontSize,
                    letterSpacing: letterSpacing,
                    lineHeight: lineHeight,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ReadablePreview extends StatelessWidget {
  const _ReadablePreview({
    required this.device,
    required this.title,
    required this.body,
    required this.fontFamily,
    required this.fontSize,
    required this.letterSpacing,
    required this.lineHeight,
  });

  final ChapterPreviewDevice device;
  final String title;
  final String body;
  final String fontFamily;
  final int fontSize;
  final double letterSpacing;
  final double lineHeight;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final displayTitle = title.isEmpty
        ? context.t(LocaleKeys.workspaceChapterTitle)
        : title;
    final displayBody = body.isEmpty
        ? context.t(LocaleKeys.workspaceChapterBodyHint)
        : body;

    return Column(
      children: [
        SizedBox(
          height: device.statusBarHeight,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: device.contentPadding),
            child: Row(
              children: [
                Text(
                  '21:48',
                  style: typo.uiTinySemibold.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
                const Spacer(),
                Container(
                  width: 28,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.textPrimary,
                    borderRadius: BorderRadius.circular(RevericRadius.pill),
                  ),
                ),
                const Spacer(),
                Text(
                  '100%',
                  style: typo.uiTinySemibold.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              device.contentPadding,
              RevericSpacing.x3l,
              device.contentPadding,
              RevericSpacing.x6l,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayTitle,
                  style: typo.heading2.copyWith(
                    color: colors.textPrimary,
                    fontFamily: fontFamily,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: RevericSpacing.x4l),
                Text(
                  displayBody,
                  style: typo.body.copyWith(
                    color: body.isEmpty
                        ? colors.textSubtle
                        : colors.textPrimary,
                    fontFamily: fontFamily,
                    fontSize: fontSize.toDouble(),
                    letterSpacing: letterSpacing,
                    height: lineHeight,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
