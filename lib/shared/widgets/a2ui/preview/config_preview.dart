// 职责: 调试预览中的插件配置表单 — 用示例 settings 渲染表单，保存写入内存并展示保存结果（凭据只显示是否已设置）。
// 关联文件:
//   lib/shared/widgets/settings/plugins/config_form.dart
//   lib/shared/models/plugin/setting_field.dart
//   lib/shared/widgets/a2ui/preview/preview_layout.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/a2ui.json
//   assets/translations/zh-CN/a2ui.json
// 遵循的 Rules:
//   .agents/rules/hooks.md
//   .agents/rules/design-system.md

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import '../../../localization/app_localization.dart';
import '../../../localization/locale_keys.dart';
import '../../../models/plugin/setting_field.dart';
import '../../../theme/theme.dart';
import '../../settings/plugins/config_form.dart';
import '../../settings/plugins/config_surface.dart';
import 'preview_layout.dart';

/// 模拟联网检索插件清单中的 settings；示例内容不参与本地化。
final List<PluginSettingField> _sampleFields = parsePluginSettingFields({
  'apiKey': {
    'type': 'secret',
    'title': 'API Key',
    'required': true,
    'description': '在服务商控制台创建，保存后不再显示原文。',
  },
  'endpoint': {
    'type': 'string',
    'title': '接口地址',
    'default': 'https://api.example.com',
    'maxLength': 120,
  },
  'maxResults': {
    'type': 'integer',
    'title': '默认结果数量',
    'default': 5,
    'min': 1,
    'max': 20,
  },
  'temperature': {'type': 'number', 'title': '摘要温度', 'min': 0, 'max': 2},
  'safeSearch': {'type': 'boolean', 'title': '安全搜索', 'default': true},
  'region': {
    'type': 'select',
    'title': '检索地区',
    'default': 'cn',
    'options': [
      {'value': 'cn', 'label': '中国大陆'},
      {'value': 'global', 'label': '全球'},
    ],
  },
  'extraPrompt': {
    'type': 'text',
    'title': '附加说明',
    'description': '会附在每次检索的请求里。',
  },
});

class A2uiConfigPreview extends HookWidget {
  const A2uiConfigPreview({super.key});

  @override
  Widget build(BuildContext context) {
    final values = useState<Map<String, Object?>>(const {});
    final savedSecrets = useState<Set<String>>(const {});
    final log = useState<List<String>>(const []);

    Future<void> save(PluginConfigSubmission submission) async {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      values.value = submission.settings;
      savedSecrets.value =
          {
            ...savedSecrets.value,
            for (final MapEntry(:key, :value) in submission.secrets.entries)
              if (value != null) key,
          }..removeAll([
            for (final MapEntry(:key, :value) in submission.secrets.entries)
              if (value == null) key,
          ]);
      log.value = [
        jsonEncode({
          'settings': submission.settings,
          // 凭据不进入日志，只记录变更类型。
          'secrets': {
            for (final MapEntry(:key, :value) in submission.secrets.entries)
              key: value == null ? 'cleared' : 'replaced',
          },
        }),
        ...log.value,
      ];
    }

    final stored = const JsonEncoder.withIndent('  ').convert({
      'settings': values.value,
      'secrets': {for (final key in savedSecrets.value) key: 'set'},
    });

    return A2uiPreviewSplit(
      preview: SingleChildScrollView(
        padding: const EdgeInsets.all(RevericSpacing.x2l),
        child: PluginConfigForm(
          fields: _sampleFields,
          values: values.value,
          savedSecrets: savedSecrets.value,
          onSave: save,
        ),
      ),
      inspector: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: A2uiInspectorSection(
              title: context.t(LocaleKeys.a2uiPreviewStored),
              child: A2uiInspectorText(stored),
            ),
          ),
          const SizedBox(height: RevericSpacing.lg),
          Expanded(
            child: A2uiInspectorSection(
              title: context.t(LocaleKeys.a2uiPreviewSubmissions),
              child: A2uiInspectorText(
                log.value.join('\n\n'),
                emptyText: context.t(LocaleKeys.a2uiPreviewNoSubmissions),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
