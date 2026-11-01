// 职责: 移动端地图制图师抽屉 — 全部出图参数与提示词，底部挂共享生成脚。
// 关联文件:
//   lib/mobile/features/map/studio_page.dart
//   lib/shared/hooks/use_map_generate_form.dart
//   lib/shared/widgets/map/map_generate_fields.dart
//   lib/shared/widgets/map/map_generate_footer.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/map_editor.json
//   assets/translations/zh-CN/map_editor.json
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/text-input-ime.md
//   .agents/rules/i18n.md
import 'package:flutter/material.dart';

import '../../../shared/hooks/use_map_generate_form.dart';
import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/theme/theme.dart';
import '../../../shared/widgets/map/map_generate_fields.dart';

/// 拉起制图师抽屉。
///
/// [form] 归页面所有 —— 抽屉是另一条 route，但捕获的是同一组 notifier 与
/// controller，关掉抽屉再打开，参数和改了一半的提示词都还在。
Future<void> openMobileMapDesignerSheet(
  BuildContext context, {
  required MapGenerateForm form,
  required String databasePath,
  required String rootId,
  required String rootName,
  required bool busy,
  required Widget Function(VoidCallback onGenerate) buildFooter,
  required VoidCallback onGenerate,
  required MapAgentHandoffCallback onAskAgent,
}) {
  final colors = RevericTheme.colorsOf(context);
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: colors.surface,
    isScrollControlled: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(RevericRadius.x2l),
      ),
    ),
    builder: (sheetContext) => _DesignerSheet(
      form: form,
      databasePath: databasePath,
      rootId: rootId,
      rootName: rootName,
      busy: busy,
      buildFooter: buildFooter,
      // 抽屉挡着画布；先关抽屉再发起，作者能立刻看到进度条亮起来。
      onGenerate: () {
        if (!form.validateCustomStyle()) {
          return;
        }
        Navigator.of(sheetContext).pop();
        onGenerate();
      },
      // 聊天是另一整页；先收起抽屉，回来时再由页面按草稿决定要不要拉起。
      onAskAgent: ({required styleId, required styleWord}) {
        Navigator.of(sheetContext).pop();
        onAskAgent(styleId: styleId, styleWord: styleWord);
      },
    ),
  );
}

class _DesignerSheet extends StatelessWidget {
  const _DesignerSheet({
    required this.form,
    required this.databasePath,
    required this.rootId,
    required this.rootName,
    required this.busy,
    required this.buildFooter,
    required this.onGenerate,
    required this.onAskAgent,
  });

  final MapGenerateForm form;
  final String databasePath;
  final String rootId;
  final String rootName;
  final bool busy;
  final Widget Function(VoidCallback onGenerate) buildFooter;
  final VoidCallback onGenerate;
  final MapAgentHandoffCallback onAskAgent;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final media = MediaQuery.of(context);
    return Padding(
      // 键盘顶起整个抽屉，生成脚不被盖住。
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: media.size.height * 0.88),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                RevericSpacing.x2l,
                0,
                RevericSpacing.x2l,
                RevericSpacing.md,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.t(LocaleKeys.mapEditorStudioTitle),
                    style: typo.heading2,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    rootName,
                    style: typo.uiSmall.copyWith(color: colors.textMuted),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: colors.borderSubtle),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  RevericSpacing.x2l,
                  RevericSpacing.lg,
                  RevericSpacing.x2l,
                  RevericSpacing.lg,
                ),
                child: MapGenerateFields(
                  form: form,
                  databasePath: databasePath,
                  rootId: rootId,
                  rootName: rootName,
                  busy: busy,
                  onAskAgent: onAskAgent,
                  showTarget: false,
                  touchTargets: true,
                ),
              ),
            ),
            Container(
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: colors.borderSubtle)),
              ),
              padding: EdgeInsets.fromLTRB(
                RevericSpacing.x2l,
                RevericSpacing.md,
                RevericSpacing.x2l,
                RevericSpacing.md + media.padding.bottom,
              ),
              // 参数一变预估就要跟着变：抽屉这棵树不会随页面重建，自己听表单。
              child: ListenableBuilder(
                listenable: form.listenable,
                builder: (context, _) => buildFooter(onGenerate),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
