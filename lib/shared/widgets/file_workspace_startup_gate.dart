// 职责: 业务树挂载前校验文件工作区位置；设置页触发迁移时卸载业务树、复制并重新载入，失败时提供重试、取消与恢复默认位置。
// 关联文件:
//   lib/main.dart
//   lib/shared/services/file_workspace_orchestrator.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/settings.json
//   assets/translations/zh-CN/settings.json
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
// 遵循的 Rules:
//   .agents/rules/hooks.md
//   .agents/rules/error-handling.md

import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import '../components/reveric_button.dart';
import '../components/reveric_placeholder.dart';
import '../components/reveric_spinner.dart';
import '../localization/locale_keys.dart';
import '../services/file_workspace_orchestrator.dart';
import '../theme/theme.dart';

class FileWorkspaceStartupGate extends HookWidget {
  const FileWorkspaceStartupGate({
    super.key,
    required this.loading,
    required this.child,
  });

  final Widget loading;
  final Widget child;

  /// 卸载业务树后迁移到 [parent]，完成后重新挂载，确保迁移期间没有写入方。
  static void migrate(BuildContext context, String parent) {
    context
        .getInheritedWidgetOfExactType<_FileWorkspaceMigrationScope>()!
        .migrate(parent);
  }

  @override
  Widget build(BuildContext context) {
    final localization = EasyLocalization.of(context)!;
    final attempt = useState(0);
    final useDefault = useRef(false);
    // 迁移失败时保留目标，重试继续迁移，取消则回到当前位置。
    final target = useState<String?>(null);
    final operation = useMemoized(() async {
      await WidgetsBinding.instance.endOfFrame;
      await localization.delegate.load(localization.locale);
      if (Platform.isAndroid || Platform.isIOS) {
        return;
      }
      final orchestrator = FileWorkspaceOrchestrator();
      final recover = useDefault.value;
      useDefault.value = false;
      try {
        if (recover) {
          await orchestrator.useApplicationDirectory();
        }
        if (target.value case final parent?) {
          await orchestrator.migrate(parent);
          if (context.mounted) {
            target.value = null;
          }
          return;
        }
        await orchestrator.initialize();
      } catch (error, stack) {
        // Configuration decoding can fail before the orchestrator logs anything.
        logFileWorkspaceError('startup/migration', error, stack);
        rethrow;
      }
    }, [attempt.value]);
    final result = useFuture(operation);
    final migrating = target.value != null;
    if (result.connectionState != ConnectionState.done) {
      return migrating ? const _MigratingApp() : loading;
    }
    if (!result.hasError) {
      return _FileWorkspaceMigrationScope(
        migrate: (parent) {
          target.value = parent;
          attempt.value++;
        },
        child: child,
      );
    }
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: context.locale,
      supportedLocales: context.supportedLocales,
      localizationsDelegates: context.localizationDelegates,
      theme: RevericThemeData.classic.toThemeData(),
      home: RevericTheme(
        data: RevericThemeData.classic,
        child: Scaffold(
          body: Center(
            child: RevericPlaceholder.error(
              title: tr(
                migrating
                    ? LocaleKeys.settingsFileWorkspaceMigrationFailed
                    : LocaleKeys.settingsFileWorkspaceStartupFailed,
              ),
              description: migrating
                  ? tr(LocaleKeys.settingsFileWorkspaceMigrationFailedHint)
                  : '${tr(LocaleKeys.settingsFileWorkspaceStartupFailedHint)}\n\n'
                        '${tr(LocaleKeys.settingsFileWorkspaceRecoveryHint)}',
              action: Wrap(
                spacing: RevericSpacing.md,
                runSpacing: RevericSpacing.sm,
                children: [
                  RevericButton.primary(
                    label: tr(LocaleKeys.commonRetry),
                    onPressed: () => attempt.value++,
                  ),
                  if (migrating)
                    RevericButton.secondary(
                      label: tr(LocaleKeys.commonCancel),
                      onPressed: () {
                        target.value = null;
                        attempt.value++;
                      },
                    )
                  else
                    RevericButton.secondary(
                      label: tr(LocaleKeys.settingsFileWorkspaceUseDefault),
                      onPressed: () {
                        useDefault.value = true;
                        attempt.value++;
                      },
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FileWorkspaceMigrationScope extends InheritedWidget {
  const _FileWorkspaceMigrationScope({
    required this.migrate,
    required super.child,
  });

  final ValueChanged<String> migrate;

  @override
  bool updateShouldNotify(_FileWorkspaceMigrationScope oldWidget) => false;
}

class _MigratingApp extends StatelessWidget {
  const _MigratingApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: RevericThemeData.classic.toThemeData(),
      darkTheme: RevericThemeData.classicDark.toThemeData(),
      builder: (context, child) => RevericTheme(
        data: Theme.of(context).brightness == Brightness.dark
            ? RevericThemeData.classicDark
            : RevericThemeData.classic,
        child: child!,
      ),
      home: Builder(
        builder: (context) {
          final colors = RevericTheme.colorsOf(context);
          final typo = RevericTheme.typographyOf(context);
          return Scaffold(
            backgroundColor: colors.canvas,
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox.square(
                    dimension: RevericSizes.iconButtonIconSize,
                    child: RevericSpinner(color: colors.accent),
                  ),
                  const SizedBox(height: RevericSpacing.x2l),
                  Text(
                    tr(LocaleKeys.settingsFileWorkspaceMigrating),
                    style: typo.ui.copyWith(color: colors.textMuted),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
