// 职责: 在无法确认旧实例唤起时显示独立提示窗口，不初始化业务数据库或托盘。
// 关联文件:
//   lib/main.dart
//   lib/shared/services/single_instance_service.dart
//   lib/shared/components/reveric_dialog.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/app.json
//   assets/translations/zh-CN/app.json
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
// 遵循的 Rules:
//   .agents/rules/hooks.md
//   .agents/rules/file-access.md

import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:window_manager/window_manager.dart';

import '../../shared/components/reveric_button.dart';
import '../../shared/components/reveric_dialog.dart';
import '../../shared/localization/locale_keys.dart';
import '../../shared/localization/merging_asset_loader.dart';
import '../../shared/logger/log_manager.dart';
import '../../shared/theme/theme.dart';

Future<void> showActivationFailureApp() async {
  await EasyLocalization.ensureInitialized();
  await windowManager.ensureInitialized();
  // 这是启动前的独立对话框，使用原生标题栏，不初始化依赖业务状态的桌面框架。
  await windowManager.waitUntilReadyToShow(
    const WindowOptions(
      size: Size(600, 360),
      center: true,
      titleBarStyle: TitleBarStyle.normal,
    ),
    () async {
      await windowManager.show();
      await windowManager.focus();
    },
  );
  runApp(
    EasyLocalization(
      supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
      path: 'assets/translations',
      assetLoader: const MergingAssetLoader(),
      fallbackLocale: const Locale('zh', 'CN'),
      startLocale: const Locale('zh', 'CN'),
      child: ActivationFailureApp(
        onClose: () => exit(1),
        onOpenLogs: _openLogs,
      ),
    ),
  );
}

Future<bool> _openLogs() async {
  try {
    final directory = LogManager.instance.logDirectory;
    if (directory == null || !await Directory(directory).exists()) {
      throw StateError('Startup log directory is unavailable');
    }
    final command = Platform.isWindows
        ? 'explorer'
        : Platform.isMacOS
        ? 'open'
        : 'xdg-open';
    final result = await Process.run(command, [
      directory,
    ]).timeout(const Duration(seconds: 3));
    // Explorer 复用已有窗口时也可能返回 1。
    return result.exitCode == 0 || (Platform.isWindows && result.exitCode == 1);
  } catch (error, stack) {
    LogManager.instance.error(
      'Failed to open startup logs',
      error: error,
      stackTrace: stack,
    );
    return false;
  }
}

class ActivationFailureApp extends HookWidget {
  const ActivationFailureApp({
    super.key,
    required this.onClose,
    required this.onOpenLogs,
  });

  final VoidCallback onClose;
  final Future<bool> Function() onOpenLogs;

  @override
  Widget build(BuildContext context) {
    final openingLogs = useState(false);
    final logsFailed = useState(false);
    final theme = RevericThemeData.classic;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      locale: context.locale,
      theme: theme.toThemeData(),
      home: RevericTheme(
        data: theme,
        child: Builder(
          builder: (context) => Material(
            color: RevericTheme.colorsOf(context).canvas,
            child: Center(
              child: RevericDialog(
                title: context.tr(LocaleKeys.appActivationUnconfirmedTitle),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.tr(LocaleKeys.appActivationUnconfirmedMessage),
                    ),
                    if (logsFailed.value) ...[
                      const SizedBox(height: RevericSpacing.md),
                      Text(
                        context.tr(LocaleKeys.appLogsOpenFailed),
                        style: RevericTheme.typographyOf(context).ui.copyWith(
                          color: RevericTheme.colorsOf(context).error,
                        ),
                      ),
                    ],
                  ],
                ),
                actions: [
                  RevericButton.secondary(
                    label: context.tr(LocaleKeys.appOpenLogs),
                    loading: openingLogs.value,
                    onPressed: () async {
                      openingLogs.value = true;
                      final opened = await onOpenLogs();
                      if (!context.mounted) {
                        return;
                      }
                      openingLogs.value = false;
                      logsFailed.value = !opened;
                    },
                  ),
                  RevericButton.primary(
                    label: context.tr(LocaleKeys.commonClose),
                    onPressed: onClose,
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
