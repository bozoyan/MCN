// 职责: WebDAV 恢复子页面，枚举远端备份并下载所选文件。
// 关联文件:
//   lib/shared/widgets/settings/backup_settings_section.dart
//   lib/shared/services/webdav_backup_service.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/settings.json
//   assets/translations/zh-CN/settings.json
// 遵循的 Rules:
//   .agents/rules/hooks.md
//   .agents/rules/design-system.md

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import '../../localization/app_localization.dart';
import '../../localization/locale_keys.dart';
import '../../models/webdav_backup_config.dart';
import '../../services/webdav_backup_service.dart';
import '../../theme/theme.dart';

class WebDavRestorePage extends HookWidget {
  const WebDavRestorePage({
    super.key,
    required this.config,
    required this.service,
    required this.compact,
    required this.onBack,
    required this.onDownloaded,
  });

  final WebDavBackupConfig config;
  final WebDavBackupService service;
  final bool compact;
  final VoidCallback onBack;
  final Future<void> Function(String localPath) onDownloaded;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final refreshToken = useState(0);
    final downloadingName = useState<String?>(null);
    final downloadError = useState(false);
    final future = useMemoized(() => service.listBackups(config), <Object?>[
      config.serverUrl,
      config.remoteDirectory,
      refreshToken.value,
    ]);
    final snapshot = useFuture(future);
    final pagePadding = compact ? RevericSpacing.x3l : RevericSpacing.x4l;

    Future<void> download(WebDavBackupFile file) async {
      if (downloadingName.value != null) return;
      downloadingName.value = file.name;
      downloadError.value = false;
      try {
        final result = await service.downloadBackup(
          config: config,
          remoteFile: file,
        );
        final localPath = result.localPath;
        if (!context.mounted) {
          if (localPath != null) {
            await service.deleteDownloadedBackup(localPath);
          }
          return;
        }
        if (!result.success || localPath == null) {
          downloadError.value = true;
          return;
        }
        await onDownloaded(localPath);
      } finally {
        if (context.mounted) {
          downloadingName.value = null;
        }
      }
    }

    return Padding(
      padding: EdgeInsets.all(pagePadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                key: const ValueKey('webdav_restore_back_button'),
                onPressed: downloadingName.value == null ? onBack : null,
                tooltip: context.t(LocaleKeys.settingsBackupRestoreCancel),
                icon: const RevericIcon(RevericIcons.arrow_back, size: 20),
              ),
              const SizedBox(width: RevericSpacing.xs),
              Expanded(
                child: Text(
                  context.t(LocaleKeys.settingsWebDavRestoreTitle),
                  style: compact
                      ? typo.uiSemibold.copyWith(color: colors.textPrimary)
                      : typo.heading2.copyWith(color: colors.textPrimary),
                ),
              ),
            ],
          ),
          const SizedBox(height: RevericSpacing.sm),
          Text(
            context.t(LocaleKeys.settingsWebDavRestoreDescription),
            style: typo.ui.copyWith(color: colors.textMuted),
          ),
          const SizedBox(height: RevericSpacing.lg),
          Expanded(
            child: _body(
              context,
              snapshot: snapshot,
              downloadingName: downloadingName.value,
              onDownload: download,
              onRetry: () => refreshToken.value += 1,
            ),
          ),
          if (downloadError.value) ...[
            const SizedBox(height: RevericSpacing.md),
            Text(
              context.t(LocaleKeys.settingsWebDavRestoreFailed),
              style: typo.uiSmall.copyWith(color: colors.deletionBorder),
            ),
          ],
        ],
      ),
    );
  }

  Widget _body(
    BuildContext context, {
    required AsyncSnapshot<WebDavListResult> snapshot,
    required String? downloadingName,
    required ValueChanged<WebDavBackupFile> onDownload,
    required VoidCallback onRetry,
  }) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    if (snapshot.connectionState != ConnectionState.done) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(strokeWidth: 2),
            const SizedBox(height: RevericSpacing.md),
            Text(
              context.t(LocaleKeys.settingsWebDavRestoreLoading),
              style: typo.uiSmall.copyWith(color: colors.textMuted),
            ),
          ],
        ),
      );
    }
    final result = snapshot.data;
    if (snapshot.hasError || result == null || !result.success) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              context.t(LocaleKeys.settingsWebDavRestoreFailed),
              style: typo.ui.copyWith(color: colors.textMuted),
            ),
            const SizedBox(height: RevericSpacing.sm),
            OutlinedButton(
              onPressed: onRetry,
              child: Text(context.t(LocaleKeys.settingsWebDavRestoreRetry)),
            ),
          ],
        ),
      );
    }
    if (result.files.isEmpty) {
      return Center(
        child: Text(
          context.t(LocaleKeys.settingsWebDavRestoreEmpty),
          style: typo.ui.copyWith(color: colors.textMuted),
          textAlign: TextAlign.center,
        ),
      );
    }
    return ListView.separated(
      itemCount: result.files.length,
      separatorBuilder: (_, _) =>
          Divider(height: 1, color: colors.borderSubtle),
      itemBuilder: (context, index) {
        final file = result.files[index];
        final isDownloading = downloadingName == file.name;
        return ListTile(
          key: ValueKey('webdav_backup_${file.name}'),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: RevericSpacing.md,
            vertical: RevericSpacing.xs,
          ),
          leading: const RevericIcon(RevericIcons.folder_outlined, size: 20),
          title: Text(
            file.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: typo.uiSemibold.copyWith(color: colors.textPrimary),
          ),
          subtitle: Text(
            _fileDetails(context, file),
            style: typo.uiSmall.copyWith(color: colors.textMuted),
          ),
          trailing: TextButton.icon(
            onPressed: downloadingName == null ? () => onDownload(file) : null,
            icon: isDownloading
                ? const SizedBox.square(
                    dimension: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const RevericIcon(RevericIcons.download, size: 16),
            label: Text(
              context.t(
                isDownloading
                    ? LocaleKeys.settingsWebDavRestoreDownloading
                    : LocaleKeys.settingsWebDavRestoreDownload,
              ),
            ),
          ),
        );
      },
    );
  }
}

String _fileDetails(BuildContext context, WebDavBackupFile file) {
  final parts = <String>[];
  if (file.modifiedAt != null) {
    parts.add(
      DateFormat.yMd(
        context.locale.toString(),
      ).add_Hm().format(file.modifiedAt!),
    );
  }
  if (file.size != null) {
    final megabytes = file.size! / (1024 * 1024);
    parts.add('${megabytes.toStringAsFixed(megabytes >= 10 ? 0 : 1)} MB');
  }
  return parts.join(' · ');
}
