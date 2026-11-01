// 职责: 移动端 AgentSkill 安装 call_name 冲突 dialog — 显示冲突名 + 三选项(覆盖/重命名/取消),
//   并提供重命名输入子 dialog;同时导出目录技能安装冲突与升级编排。
// 关联文件:
//   lib/shared/components/reveric_dialog.dart
//   lib/shared/components/reveric_button.dart
//   lib/shared/localization/locale_keys.dart
//   lib/shared/localization/app_localization.dart
//   lib/shared/theme/theme.dart
//   lib/shared/widgets/confirm_dialog.dart
//   lib/shared/providers/novel_agent_skill_providers.dart
//   lib/shared/models/official_agent_skill.dart
//   assets/translations/en/agent_skill.json
//   assets/translations/zh-CN/agent_skill.json
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
// 遵循的 Rules:
//   .agents/rules/i18n.md
//   .agents/rules/design-system.md
//   .agents/rules/icons.md
//   .agents/rules/error-handling.md
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/logger/app_logger.dart';
import '../../../shared/providers/novel_agent_skill_providers.dart';
import '../../../shared/theme/theme.dart';
import '../../../shared/components/reveric_dialog.dart';
import '../../../shared/components/reveric_button.dart';

final _log = AppLogger.forModule('MobileInstallConflict');

/// 用户在 [showInstallConflictDialog] 中可选的解决方式。
enum InstallConflictAction { overwrite, rename, cancel }

/// 弹出 call_name 冲突 dialog,返回用户选择的解决方式。
///
/// 重命名时,本函数只返回 [InstallConflictAction.rename];
/// 调用方需自行调用 [promptNewCallName] 拿到新 call_name 后再重试安装。
Future<InstallConflictAction> showInstallConflictDialog(
  BuildContext context, {
  required String conflictCallName,
}) async {
  final colors = RevericTheme.colorsOf(context);
  final typo = RevericTheme.typographyOf(context);

  final result = await showRevericDialog<InstallConflictAction>(
    context: context,
    builder: (dialogContext) {
      return RevericDialog(
        title: dialogContext.t(LocaleKeys.agentSkillConflictTitle),
        leading: ExcludeSemantics(
          child: Container(
            padding: const EdgeInsets.all(RevericSpacing.md),
            decoration: BoxDecoration(
              color: colors.warningBg,
              borderRadius: BorderRadius.circular(RevericRadius.large),
            ),
            child: RevericIcon(
              RevericIcons.warning_circle,
              size: RevericSizes.iconButtonIconSize,
              color: colors.warningText,
            ),
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              dialogContext.t(
                LocaleKeys.agentSkillConflictSub,
                namedArgs: {'call_name': conflictCallName},
              ),
              style: typo.ui.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: RevericSpacing.sm),
            Text(
              dialogContext.t(LocaleKeys.agentSkillConflictNote),
              style: typo.uiSmall.copyWith(color: colors.textMuted),
            ),
          ],
        ),
        actions: [
          RevericButton.secondary(
            label: dialogContext.t(LocaleKeys.commonCancel),
            onPressed: () =>
                Navigator.of(dialogContext).pop(InstallConflictAction.cancel),
          ),
          RevericButton.text(
            label: dialogContext.t(LocaleKeys.agentSkillRenameInstall),
            onPressed: () =>
                Navigator.of(dialogContext).pop(InstallConflictAction.rename),
          ),
          RevericButton.danger(
            label: dialogContext.t(LocaleKeys.agentSkillOverwrite),
            onPressed: () => Navigator.of(
              dialogContext,
            ).pop(InstallConflictAction.overwrite),
          ),
        ],
      );
    },
  );
  return result ?? InstallConflictAction.cancel;
}

/// 弹出输入 dialog 让用户输入新的 call_name。取消返回 null。
Future<String?> promptNewCallName(
  BuildContext context, {
  required String defaultValue,
}) async {
  final controller = TextEditingController(text: defaultValue);

  final result = await showRevericDialog<String>(
    context: context,
    builder: (dialogContext) {
      return RevericDialog(
        title: dialogContext.t(LocaleKeys.agentSkillNewCallName),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: dialogContext.t(LocaleKeys.agentSkillCallNamePlaceholder),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(RevericRadius.large),
            ),
          ),
        ),
        actions: [
          RevericButton.secondary(
            label: dialogContext.t(LocaleKeys.commonCancel),
            onPressed: () => Navigator.of(dialogContext).pop(null),
          ),
          RevericButton.primary(
            label: dialogContext.t(LocaleKeys.commonConfirm),
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
          ),
        ],
      );
    },
  );
  controller.dispose();
  return result;
}

/// 处理本地官方目录的安装与冲突:
/// 1. 调用 `installFromOfficial`;
/// 2. 若返回冲突,弹 [showInstallConflictDialog];
/// 3. 覆盖 → 调用 `overwriteInstall`;重命名 → 弹
///    [promptNewCallName] 后用新 call_name 重试;取消 → 退出。
/// 4. 成功后 SnackBar 提示 `agent_skill.toast_installed`。
///
/// 返回 true 表示已成功安装(或覆盖完成),false 表示用户取消或失败。
Future<bool> resolveAndInstallCatalogSkill(
  BuildContext context,
  WidgetRef ref, {
  required InstallFromCatalogSource source,
}) async {
  final notifier = ref.read(installedAgentSkillsProvider.notifier);
  final sourceName = switch (source) {
    InstallFromOfficialSource(:final dto) => dto.name,
  };

  Future<bool> attemptInstall({String? overrideName}) async {
    final result = switch (source) {
      InstallFromOfficialSource(:final dto) =>
        await notifier.installFromOfficial(
          source: dto,
          overrideName: overrideName,
        ),
    };
    if (result is InstallFromCatalogSuccess) {
      return true;
    }
    if (result is InstallFromCatalogConflict) {
      final conflictCallName = result.conflictingName;
      final existingId = result.existingId;
      if (!context.mounted) {
        return false;
      }
      final action = await showInstallConflictDialog(
        context,
        conflictCallName: conflictCallName,
      );
      switch (action) {
        case InstallConflictAction.cancel:
          return false;
        case InstallConflictAction.overwrite:
          await notifier.overwriteInstall(
            existingNovelAgentSkillId: existingId,
            source: source,
          );
          return true;
        case InstallConflictAction.rename:
          if (!context.mounted) {
            return false;
          }
          final newName = await promptNewCallName(
            context,
            defaultValue: conflictCallName,
          );
          if (newName == null || newName.isEmpty) {
            return false;
          }
          return attemptInstall(overrideName: newName);
      }
    }
    return false;
  }

  try {
    final installed = await attemptInstall();
    if (installed && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.t(
              LocaleKeys.agentSkillToastInstalled,
              namedArgs: {'name': sourceName},
            ),
          ),
        ),
      );
    }
    return installed;
  } catch (error, stack) {
    _log.error(
      'install failed source=$sourceName',
      error: error,
      stackTrace: stack,
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.t(LocaleKeys.agentSkillLoadFailed))),
      );
    }
    return false;
  }
}

/// 升级同一目录来源的所有旧安装副本，并向用户反馈最终结果。
Future<bool> upgradeCatalogSkillInstallations(
  BuildContext context,
  WidgetRef ref, {
  required List<String> novelAgentSkillIds,
  required int latestVersion,
}) async {
  if (novelAgentSkillIds.isEmpty) {
    return false;
  }
  try {
    var upgraded = false;
    final notifier = ref.read(installedAgentSkillsProvider.notifier);
    for (final skillId in novelAgentSkillIds) {
      final result = await notifier.upgradeNovelAgentSkill(
        novelAgentSkillId: skillId,
      );
      if (result is UpgradeSuccess) {
        upgraded = true;
      }
    }
    if (!context.mounted) {
      return upgraded;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          upgraded
              ? context.t(
                  LocaleKeys.agentSkillToastUpgraded,
                  namedArgs: {'version': '$latestVersion'},
                )
              : context.t(LocaleKeys.agentSkillAlreadyLatest),
        ),
      ),
    );
    return upgraded;
  } catch (error, stack) {
    _log.error(
      'upgrade catalog installations failed',
      error: error,
      stackTrace: stack,
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.t(LocaleKeys.agentSkillLoadFailed))),
      );
    }
    return false;
  }
}
