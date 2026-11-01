// 职责: 复用移动端技能来源选择、候选确认和本地导入流程。
// 关联文件:
//   lib/mobile/features/agent_skills/novel_agent_skill_manage_page.dart
//   lib/mobile/features/agent_skills/marketplace_tab.dart
//   lib/shared/widgets/agent_skill_import_source_form.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/agent_skill.json
//   assets/translations/zh-CN/agent_skill.json
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/logger/app_logger.dart';
import '../../../shared/models/agent_skill_reference.dart';
import '../../../shared/models/novel_agent_skill.dart';
import '../../../shared/providers/novel_agent_skill_providers.dart';
import '../../../shared/services/agent_skill_transfer.dart';
import '../../../shared/theme/theme.dart';
import '../../../shared/widgets/agent_skill_import_dialog.dart';
import '../../../shared/widgets/agent_skill_import_source_form.dart';
import '../../services/android_saf_directory_import.dart';
import '../../widgets/sheet.dart';

final _log = AppLogger.forModule('MobileSkillImport');
Future<void> importMobileAgentSkills(
  BuildContext context,
  WidgetRef ref, {
  String initialUrl = '',
}) async {
  final existing =
      ref.read(installedAgentSkillsProvider).value ??
      const <NovelAgentSkillModel>[];
  const transfer = AgentSkillTransferService();
  try {
    final candidates = await showMobileSheet<List<AgentSkillImportCandidate>>(
      context: context,
      builder: (sheetContext) => MobileSheetScaffold(
        header: MobileSheetHeader.closable(
          title: sheetContext.t(LocaleKeys.agentSkillImport),
          onClose: () => Navigator.of(sheetContext).pop(),
        ),
        child: AgentSkillImportSourceForm(
          initialUrl: initialUrl,
          existingNames: existing.map((skill) => skill.name.trim()).toSet(),
          pickDirectory: !agentSkillSupportsDirectoryImport()
              ? null
              : () async {
                  if (defaultTargetPlatform == TargetPlatform.android) {
                    final result = await pickAndCopyAndroidDirectory(
                      extensions: AgentSkillReferences.allowedExtensions,
                    );
                    if (result == null) {
                      return null;
                    }
                    try {
                      return transfer.discoverInDirectory(
                        dirPath: result.directoryPath,
                        existing: existing,
                      );
                    } finally {
                      await deleteAndroidDirectoryImport(result.directoryPath);
                    }
                  }
                  final path = await getDirectoryPath();
                  return path == null
                      ? null
                      : transfer.discoverInDirectory(
                          dirPath: path,
                          existing: existing,
                        );
                },
          pickFiles: () async {
            final files = await openFiles(
              acceptedTypeGroups: const [agentSkillMarkdownTypeGroup],
            );
            if (files.isEmpty) {
              return null;
            }
            return [
              for (final file in files)
                transfer.parseSelectedMarkdown(
                  content: await file.readAsString(),
                  fileName: file.path,
                  existing: existing,
                ),
            ];
          },
          onDiscovered: (items) => Navigator.of(sheetContext).pop(items),
          padding: const EdgeInsets.fromLTRB(
            RevericSpacing.lg,
            RevericSpacing.lg,
            RevericSpacing.lg,
            RevericSpacing.x2l,
          ),
        ),
      ),
    );
    if (!context.mounted || candidates == null) {
      return;
    }

    final selected = await showAgentSkillImportDialog(
      context,
      candidates: candidates,
    );
    if (selected == null || !context.mounted) {
      return;
    }

    final result = await transfer.importCandidates(
      candidates: selected,
      notifier: ref.read(installedAgentSkillsProvider.notifier),
      existing: existing,
    );
    if (!context.mounted) {
      return;
    }
    _showTransferMessage(
      context,
      result.failed > 0 || result.skipped > 0
          ? context.t(
              LocaleKeys.agentSkillImportPartial,
              namedArgs: {
                'imported': '${result.imported}',
                'skipped': '${result.skipped}',
                'failed': '${result.failed}',
              },
            )
          : context.t(
              LocaleKeys.agentSkillImportSuccess,
              namedArgs: {'imported': '${result.imported}'},
            ),
    );
  } catch (error, stackTrace) {
    _log.error(
      'Import installed skills failed',
      error: error,
      stackTrace: stackTrace,
    );
    if (context.mounted) {
      _showTransferMessage(
        context,
        context.t(LocaleKeys.agentSkillImportFailed),
      );
    }
  }
}

void _showTransferMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}
