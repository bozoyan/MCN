// 职责: A2UI 调试预览面板 — 切换内置样例或插件配置表单，并实时展示页面数据与事件记录。
// 关联文件:
//   lib/shared/widgets/a2ui/preview/samples.dart
//   lib/shared/widgets/a2ui/preview/config_preview.dart
//   lib/shared/widgets/a2ui/surface_view.dart
//   lib/shared/widgets/settings/debug_settings_section.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/a2ui.json
//   assets/translations/zh-CN/a2ui.json
// 遵循的 Rules:
//   .agents/rules/hooks.md
//   .agents/rules/design-system.md
//   .agents/rules/performance.md

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import '../../../components/reveric_dialog.dart';
import '../../../components/reveric_segmented_control.dart';
import '../../../components/reveric_select.dart';
import '../../../localization/app_localization.dart';
import '../../../localization/locale_keys.dart';
import '../../../theme/theme.dart';
import '../session.dart';
import '../surface_view.dart';
import 'config_preview.dart';
import 'preview_layout.dart';
import 'samples.dart';

/// 打开预览：桌面端弹窗，移动端全屏页面。
Future<void> showA2uiPreview(BuildContext context) {
  final mobile = switch (Theme.of(context).platform) {
    TargetPlatform.android || TargetPlatform.iOS => true,
    _ => false,
  };
  if (mobile) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => Scaffold(
          appBar: AppBar(title: Text(context.t(LocaleKeys.a2uiPreviewTitle))),
          body: const SafeArea(top: false, child: A2uiPreviewPanel()),
        ),
      ),
    );
  }
  return showRevericDialog<void>(
    context: context,
    builder: (context) => RevericDialog.panel(
      width: 1040,
      title: Text(context.t(LocaleKeys.a2uiPreviewTitle)),
      content: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.72,
        child: const A2uiPreviewPanel(),
      ),
    ),
  );
}

enum _PreviewMode { samples, plugin_config }

class A2uiPreviewPanel extends HookWidget {
  const A2uiPreviewPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final mode = useState(_PreviewMode.samples);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: RevericSegmentedControl<_PreviewMode>(
            segments: [
              RevericSegment(
                value: _PreviewMode.samples,
                label: context.t(LocaleKeys.a2uiPreviewModeSamples),
              ),
              RevericSegment(
                value: _PreviewMode.plugin_config,
                label: context.t(LocaleKeys.a2uiPreviewModePluginConfig),
              ),
            ],
            selected: mode.value,
            onChanged: (next) => mode.value = next,
          ),
        ),
        const SizedBox(height: RevericSpacing.lg),
        Expanded(
          child: switch (mode.value) {
            _PreviewMode.samples => const _SamplePreview(),
            _PreviewMode.plugin_config => const A2uiConfigPreview(),
          },
        ),
      ],
    );
  }
}

typedef _LogEntry = ({String name, String source, String context});

class _SamplePreview extends HookWidget {
  const _SamplePreview();

  @override
  Widget build(BuildContext context) {
    final sample = useState(a2uiSamples.first);
    final log = useState<List<_LogEntry>>(const []);
    final session = useMemoized(
      () => A2uiSurfaceSession.load(
        surfaceId: 'preview-${sample.value.id}',
        messages: sample.value.messages,
        onAction: (event) async {
          log.value = [
            (
              name: event.name,
              source: event.sourceComponentId,
              context: jsonEncode(event.context),
            ),
            ...log.value,
          ];
          return sample.value.respond?.call(event) ?? const [];
        },
      ),
      [sample.value],
    );
    // 旧界面在本帧才卸载，会话推迟到帧末释放，保证晚于界面释放。
    useEffect(
      () =>
          () => WidgetsBinding.instance.addPostFrameCallback(
            (_) => session.dispose(),
          ),
      [session],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RevericSelect<A2uiSample>(
          label: context.t(LocaleKeys.a2uiPreviewSample),
          value: sample.value,
          items: [
            for (final item in a2uiSamples)
              RevericSelectItem(value: item, label: item.title),
          ],
          onChanged: (next) {
            log.value = const [];
            sample.value = next;
          },
        ),
        const SizedBox(height: RevericSpacing.lg),
        Expanded(
          child: A2uiPreviewSplit(
            preview: A2uiSurfaceView(
              key: ObjectKey(session),
              session: session,
              padding: const EdgeInsets.all(RevericSpacing.x2l),
              showErrorDetails: true,
            ),
            inspector: _Inspector(session: session, log: log.value),
          ),
        ),
      ],
    );
  }
}

class _Inspector extends HookWidget {
  const _Inspector({required this.session, required this.log});

  final A2uiSurfaceSession session;
  final List<_LogEntry> log;

  @override
  Widget build(BuildContext context) {
    final data = useState<Object?>(session.dataSnapshot());
    useEffect(() {
      data.value = session.dataSnapshot();
      final subscription = session.surface?.dataModel.subscribe<Object?>(
        '/',
        (_) => data.value = session.dataSnapshot(),
      );
      return subscription?.unsubscribe;
    }, [session]);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: A2uiInspectorSection(
            title: context.t(LocaleKeys.a2uiPreviewData),
            child: A2uiInspectorText(
              const JsonEncoder.withIndent('  ').convert(data.value),
            ),
          ),
        ),
        const SizedBox(height: RevericSpacing.lg),
        Expanded(
          child: A2uiInspectorSection(
            title: context.t(LocaleKeys.a2uiPreviewActions),
            child: A2uiInspectorText(
              [
                for (final entry in log)
                  '${entry.name} ← ${entry.source}\n${entry.context}',
              ].join('\n\n'),
              emptyText: context.t(LocaleKeys.a2uiPreviewNoActions),
            ),
          ),
        ),
      ],
    );
  }
}
