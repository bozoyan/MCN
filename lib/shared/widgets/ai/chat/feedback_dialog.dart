// 职责: AI 聊天反馈弹窗 — 跳转公开 GitHub Issue，并在本机导出诊断文件供邮件私下发送
// 关联文件:
//   lib/shared/components/reveric_dialog.dart
//   lib/shared/components/reveric_button.dart
//   lib/shared/providers/ai_providers.dart
//   lib/shared/providers/novel_providers.dart
//   lib/shared/services/diagnostics_export_orchestrator.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/ai.json
//   assets/translations/zh-CN/ai.json
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
// 遵循的 Rules:
//   .agents/rules/i18n.md
//   .agents/rules/error-handling.md
//   .agents/rules/file-access.md
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:reveric/shared/app_config.dart'
    show appVersion, revericFeedbackEmail, revericGitHubRepoUrl;
import 'package:reveric/shared/localization/app_localization.dart';
import 'package:reveric/shared/localization/locale_keys.dart';
import 'package:reveric/shared/logger/app_logger.dart';
import 'package:reveric/shared/logger/log_manager.dart';
import 'package:reveric/shared/providers/ai_providers.dart';
import 'package:reveric/shared/providers/novel_providers.dart';
import 'package:reveric/shared/services/diagnostics_export_orchestrator.dart';
import 'package:reveric/shared/theme/theme.dart';
import '../../../components/dialog_feedback.dart';
import '../../../components/reveric_dialog.dart';
import '../../../components/reveric_button.dart';
import '../../../components/reveric_text_field.dart';

final _log = AppLogger.forModule('AiChatFeedback');

Future<void> showAiChatFeedbackDialog({
  required BuildContext context,
  required WidgetRef ref,
  required AiChatSessionState sessionState,
  required String? novelId,
  required String? databasePath,
}) async {
  final colors = RevericTheme.colorsOf(context);
  final typo = RevericTheme.typographyOf(context);

  final dialogWidth = MediaQuery.sizeOf(context).width.clamp(280.0, 400.0) - 48;

  await showRevericDialog<void>(
    context: context,
    builder: (dialogContext) {
      return _AiChatFeedbackDialog(
        dialogContext: dialogContext,
        colors: colors,
        typo: typo,
        dialogWidth: dialogWidth,
        loadContext: () => _loadFeedbackContext(
          ref: ref,
          sessionState: sessionState,
          novelId: novelId,
          databasePath: databasePath,
        ),
        sessionState: sessionState,
      );
    },
  );
}

class _AiChatFeedbackDialog extends StatefulWidget {
  const _AiChatFeedbackDialog({
    required this.dialogContext,
    required this.colors,
    required this.typo,
    required this.dialogWidth,
    required this.loadContext,
    required this.sessionState,
  });

  final BuildContext dialogContext;
  final RevericColors colors;
  final RevericTypography typo;
  final double dialogWidth;
  final Future<Map<String, dynamic>> Function() loadContext;
  final AiChatSessionState sessionState;

  @override
  State<_AiChatFeedbackDialog> createState() => _AiChatFeedbackDialogState();
}

class _AiChatFeedbackDialogState extends State<_AiChatFeedbackDialog> {
  late final TextEditingController _descriptionController;
  bool _isExporting = false;

  @override
  void initState() {
    super.initState();
    _descriptionController = TextEditingController();
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  Map<String, String> _environmentArgs() => {
    'description': _descriptionController.text.trim(),
    'version': appVersion,
    'platform': Platform.operatingSystem,
    'model': widget.sessionState.model ?? '-',
  };

  /// 公开 Issue 只带用户描述与环境信息，不带会话标题和消息。
  Future<void> _openIssue() async {
    final description = _descriptionController.text.trim();
    final summary = description.split('\n').first;
    final uri = Uri.parse('$revericGitHubRepoUrl/issues/new').replace(
      queryParameters: {
        'title': context.t(
          LocaleKeys.aiFeedbackIssueTitle,
          namedArgs: {
            'summary': summary.length > 60
                ? '${summary.substring(0, 60)}…'
                : summary,
          },
        ),
        'body': context.t(
          LocaleKeys.aiFeedbackIssueBody,
          namedArgs: _environmentArgs(),
        ),
      },
    );
    await _launch(uri, LocaleKeys.aiFeedbackOpenIssueFailed);
  }

  Future<void> _openEmail() async {
    // mailto 的 query 需按 RFC 6068 百分号编码；queryParameters 会把空格编成 `+`。
    final subject = Uri.encodeComponent(
      context.t(LocaleKeys.aiFeedbackEmailSubject),
    );
    final body = Uri.encodeComponent(
      context.t(LocaleKeys.aiFeedbackEmailBody, namedArgs: _environmentArgs()),
    );
    final uri = Uri.parse(
      'mailto:$revericFeedbackEmail?subject=$subject&body=$body',
    );
    await _launch(
      uri,
      LocaleKeys.aiFeedbackOpenEmailFailed,
      failureArgs: {'email': revericFeedbackEmail},
    );
  }

  Future<void> _launch(
    Uri uri,
    String failureKey, {
    Map<String, String>? failureArgs,
  }) async {
    try {
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        return;
      }
      _log.warning('launch returned false scheme=${uri.scheme}');
    } catch (error, stackTrace) {
      _log.error(
        'launch failed scheme=${uri.scheme}',
        error: error,
        stackTrace: stackTrace,
      );
    }
    if (mounted) {
      _showToast(
        context.t(failureKey, namedArgs: failureArgs),
        DialogToastVariant.error,
      );
    }
  }

  Future<void> _export() async {
    if (_isExporting) {
      return;
    }
    setState(() => _isExporting = true);
    final savedMessage = context.t(LocaleKeys.aiFeedbackExportSaved);
    final failedMessage = context.t(LocaleKeys.aiFeedbackExportFailed);
    final sessionId = widget.sessionState.sessionId;
    try {
      final feedback = {
        ...await widget.loadContext(),
        'description': _descriptionController.text.trim(),
        'app_version': appVersion,
        'platform': Platform.operatingSystem,
      };
      final stamp = DateTime.now()
          .toUtc()
          .toIso8601String()
          .replaceAll(RegExp(r'[^0-9]'), '')
          .substring(0, 14);
      final status = await DiagnosticsExportOrchestrator().export(
        feedback: feedback,
        logPath: LogManager.instance.logFilePath,
        fileName: 'reveric_diagnostics_$stamp.zip',
      );
      if (mounted && status == DiagnosticsExportStatus.saved) {
        _showToast(savedMessage, DialogToastVariant.success);
      }
    } catch (error, stackTrace) {
      _log.error(
        'collect or export feedback failed sessionId=$sessionId',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) {
        _showToast(failedMessage, DialogToastVariant.error);
      }
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      }
    }
  }

  void _showToast(String message, DialogToastVariant variant) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: DialogToast(variant: variant, child: Text(message)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    final typo = widget.typo;

    return RevericDialog.panel(
      title: Text(context.t(LocaleKeys.aiFeedbackTitle)),
      content: SizedBox(
        width: widget.dialogWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.t(LocaleKeys.aiFeedbackDescription),
              style: typo.body.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: RevericSpacing.lg),
            RevericTextField(
              controller: _descriptionController,
              multiline: true,
              minLines: 3,
              maxLines: 6,
              hintText: context.t(LocaleKeys.aiFeedbackPlaceholder),
            ),
            const SizedBox(height: RevericSpacing.xl),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(RevericSpacing.lg),
              decoration: BoxDecoration(
                color: colors.surfaceDim,
                borderRadius: BorderRadius.circular(RevericRadius.medium),
                border: Border.all(color: colors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.t(LocaleKeys.aiFeedbackDiagnosticsTitle),
                    style: typo.uiSemibold.copyWith(color: colors.textPrimary),
                  ),
                  const SizedBox(height: RevericSpacing.xxs),
                  Text(
                    context.t(LocaleKeys.aiFeedbackDiagnosticsDescription),
                    style: typo.uiSmall.copyWith(color: colors.textMuted),
                  ),
                  const SizedBox(height: RevericSpacing.md),
                  Wrap(
                    spacing: RevericSpacing.md,
                    runSpacing: RevericSpacing.sm,
                    children: [
                      RevericButton.secondary(
                        label: context.t(
                          _isExporting
                              ? LocaleKeys.aiFeedbackExporting
                              : LocaleKeys.aiFeedbackExport,
                        ),
                        loading: _isExporting,
                        onPressed: _export,
                        size: RevericButtonSize.compact,
                      ),
                      RevericButton.text(
                        label: context.t(LocaleKeys.aiFeedbackSendEmail),
                        onPressed: _openEmail,
                        size: RevericButtonSize.compact,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      width: widget.dialogWidth + RevericSpacing.x4l * 2,
      actions: [
        RevericButton.secondary(
          label: context.t(LocaleKeys.commonClose),
          onPressed: () => Navigator.of(widget.dialogContext).pop(),
        ),
        RevericButton.primary(
          label: context.t(LocaleKeys.aiFeedbackSubmitIssue),
          onPressed: _openIssue,
        ),
      ],
    );
  }
}

Future<Map<String, dynamic>> _loadFeedbackContext({
  required WidgetRef ref,
  required AiChatSessionState sessionState,
  required String? novelId,
  required String? databasePath,
}) async {
  final sessionId = sessionState.sessionId;
  if (sessionId == null ||
      sessionId.isEmpty ||
      isTemporaryAiChatSessionId(sessionId)) {
    return {
      'format_version': 2,
      'captured_at': DateTime.now().toUtc().toIso8601String(),
      'message_source': 'memory',
      'session_id': sessionId,
      'title': sessionState.title,
      'model': sessionState.model,
      'message_count': sessionState.messages.length,
      'messages': sessionState.messages
          .map((message) => message.toJson())
          .toList(),
      'sub_sessions': <Map<String, dynamic>>[],
      'session_count': 1,
      'total_message_count': sessionState.messages.length,
    };
  }
  if (novelId == null ||
      novelId.isEmpty ||
      databasePath == null ||
      databasePath.isEmpty) {
    throw StateError('Persisted feedback requires a work and database.');
  }
  final persistence = ref.read(
    aiSessionPersistenceServiceProvider(
      novelId: novelId,
      databasePath: databasePath,
    ),
  );
  final novelDatabase = ref.read(novelContentDatabaseProvider(databasePath));
  return persistence.loadFeedbackContext(
    sessionId: sessionId,
    novelDatabase: novelDatabase,
  );
}
