// 职责: 目录安装冲突对话框 —— 提示 call_name 冲突,让用户选择覆盖、重命名或取消,
//   返回 [InstallConflictResult] 供调用方决定下一步(installFrom* with override / overwriteInstall)。
// 关联文件:
//   lib/shared/components/reveric_dialog.dart
//   lib/shared/components/reveric_button.dart
//   lib/shared/components/reveric_text_field.dart
//   lib/desktop/features/agent_skills/official_catalog_tab.dart
//   lib/desktop/features/agent_skills/marketplace_catalog_tab.dart
//   lib/shared/localization/locale_keys.dart
//   lib/shared/theme/theme.dart
//   assets/translations/en/agent_skill.json
//   assets/translations/zh-CN/agent_skill.json
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/i18n.md
//   .agents/rules/icons.md
//   .agents/rules/code-style.md
import 'package:flutter/material.dart';

import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/theme/theme.dart';
import '../../../shared/components/reveric_dialog.dart';
import '../../../shared/components/reveric_button.dart';
import '../../../shared/components/reveric_text_field.dart';
import '../../../shared/components/reveric_icon_button.dart';

/// 用户在冲突对话框中的选择。
enum InstallConflictAction {
  /// 取消,放弃安装。
  cancel,

  /// 覆盖现有同名安装(保留 id/callName/enabled/sortOrder)。
  overwrite,

  /// 用新 call_name 安装(保留两条独立安装)。
  rename,
}

/// 冲突对话框返回结果。`newCallName` 仅在 [InstallConflictAction.rename] 时非 null。
class InstallConflictResult {
  const InstallConflictResult({required this.action, this.newCallName});

  final InstallConflictAction action;
  final String? newCallName;

  static const cancel = InstallConflictResult(
    action: InstallConflictAction.cancel,
  );
}

/// 弹出冲突对话框。返回用户选择;用户关闭对话框视为 [InstallConflictResult.cancel]。
///
/// 对话框内嵌「新 call_name」输入框:用户点击「重命名安装」时直接读取输入框内容,
/// 不再弹二次对话框。
///
/// 对话框内容由 [_InstallConflictDialog] StatefulWidget 持有,TextEditingController
/// 在 State.dispose 中释放 —— 该 dispose 发生在 dialog exit animation 完成后,
/// 避免 controller 在 exit animation 期间被提前 dispose 导致 rebuild 崩溃。
Future<InstallConflictResult> showInstallConflictDialog(
  BuildContext context, {
  required String conflictingName,
  required String sourceName,
}) async {
  final result = await showRevericDialog<InstallConflictResult>(
    context: context,
    builder: (dialogCtx) => _InstallConflictDialog(
      conflictingName: conflictingName,
      sourceName: sourceName,
    ),
  );
  return result ?? InstallConflictResult.cancel;
}

class _InstallConflictDialog extends StatefulWidget {
  const _InstallConflictDialog({
    required this.conflictingName,
    required this.sourceName,
  });

  final String conflictingName;
  final String sourceName;

  @override
  State<_InstallConflictDialog> createState() => _InstallConflictDialogState();
}

class _InstallConflictDialogState extends State<_InstallConflictDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    return RevericDialog.panel(
      scrollable: true,
      title: Row(
        children: [
          RevericIcon(RevericIcons.warning_circle, color: colors.warningText),
          const SizedBox(width: RevericSpacing.lg),
          Expanded(child: Text(context.t(LocaleKeys.agentSkillConflictTitle))),
          RevericIconButton(
            icon: RevericIcons.close,
            tooltip: context.t(LocaleKeys.commonCancel),
            onPressed: () =>
                Navigator.of(context).maybePop(InstallConflictResult.cancel),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            context.t(
              LocaleKeys.agentSkillConflictSub,
              namedArgs: {'call_name': widget.conflictingName},
            ),
          ),
          const SizedBox(height: RevericSpacing.lg),
          Text(context.t(LocaleKeys.agentSkillConflictNote)),
          const SizedBox(height: RevericSpacing.x2l),
          RevericTextField(
            controller: _controller,
            label: context.t(LocaleKeys.agentSkillNewCallName),
            hintText: context.t(LocaleKeys.agentSkillCallNameHint),
          ),
        ],
      ),
      actions: [
        RevericButton.secondary(
          label: context.t(LocaleKeys.commonCancel),
          onPressed: () =>
              Navigator.of(context).maybePop(InstallConflictResult.cancel),
        ),
        RevericButton.secondary(
          label: context.t(LocaleKeys.agentSkillOverwrite),
          onPressed: () => Navigator.of(context).maybePop(
            const InstallConflictResult(
              action: InstallConflictAction.overwrite,
            ),
          ),
        ),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _controller,
          builder: (vbCtx, value, _) {
            final trimmed = value.text.trim();
            final enabled =
                trimmed.isNotEmpty && trimmed != widget.conflictingName;
            return RevericButton.primary(
              label: vbCtx.t(LocaleKeys.agentSkillRenameInstall),
              onPressed: enabled
                  ? () => Navigator.of(vbCtx).maybePop(
                      InstallConflictResult(
                        action: InstallConflictAction.rename,
                        newCallName: trimmed,
                      ),
                    )
                  : null,
            );
          },
        ),
      ],
    );
  }
}
