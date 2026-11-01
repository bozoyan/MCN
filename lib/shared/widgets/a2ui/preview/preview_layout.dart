// 职责: A2UI 调试预览的共用排版 — 预览区与检查栏的宽窄屏分栏，以及带标题的检查框。
// 关联文件:
//   lib/shared/widgets/a2ui/preview/preview_panel.dart
//   lib/shared/widgets/a2ui/preview/config_preview.dart
// 遵循的 Rules:
//   .agents/rules/design-system.md

import 'package:flutter/material.dart';

import '../../../theme/theme.dart';

/// 宽屏左右分栏，窄屏上下分栏。
class A2uiPreviewSplit extends StatelessWidget {
  const A2uiPreviewSplit({
    super.key,
    required this.preview,
    required this.inspector,
  });

  final Widget preview;
  final Widget inspector;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final previewBox = DecoratedBox(
      decoration: BoxDecoration(
        color: colors.canvas,
        borderRadius: BorderRadius.circular(RevericRadius.large),
        border: Border.all(color: colors.borderSubtle),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(RevericRadius.large),
        child: preview,
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 720) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: previewBox),
              const SizedBox(width: RevericSpacing.lg),
              SizedBox(width: 300, child: inspector),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(flex: 3, child: previewBox),
            const SizedBox(height: RevericSpacing.lg),
            Expanded(flex: 2, child: inspector),
          ],
        );
      },
    );
  }
}

/// 检查栏中带标题、可滚动的一块内容。
class A2uiInspectorSection extends StatelessWidget {
  const A2uiInspectorSection({
    super.key,
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: typo.uiSmallSemibold.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: RevericSpacing.xs),
        Expanded(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colors.surfaceContainer,
              borderRadius: BorderRadius.circular(RevericRadius.large),
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(RevericSpacing.md),
              child: SizedBox(width: double.infinity, child: child),
            ),
          ),
        ),
      ],
    );
  }
}

/// 检查栏中的等宽文本；为空时显示 [emptyText]。
class A2uiInspectorText extends StatelessWidget {
  const A2uiInspectorText(this.text, {super.key, this.emptyText});

  final String text;
  final String? emptyText;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    if (text.isEmpty && emptyText != null) {
      return Text(
        emptyText!,
        style: typo.uiSmall.copyWith(color: colors.textMuted),
      );
    }
    return SelectableText(
      text,
      style: typo.mono.copyWith(color: colors.textPrimary),
    );
  }
}
