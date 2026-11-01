// 职责: 加载并渲染 Prompt 模板，动态文本渲染失败时保留原文
// 关联文件:
//   lib/shared/services/ai/prompts/ai_prompt_service.dart
//   lib/shared/services/ai/prompts/prompt_registry.dart
//   lib/shared/services/ai/chat_prompt_builder.dart
//   lib/shared/providers/prompt_template_provider.dart
//   lib/shared/logger/app_logger.dart

import 'package:flutter/services.dart';
import 'package:mustache_template/mustache_template.dart';

import '../../logger/app_logger.dart';
import 'prompts/prompt_registry.dart';

final _log = AppLogger.forModule('PromptTemplate');

/// 与 agent/task prompt 分开存放、由 [PromptTemplateService.loadAll] 加载的片段路径。
abstract final class PromptFragmentPaths {
  static const coreRules = 'assets/prompts/fragments/core_rules';
  static const chapterReadingBoundary =
      'assets/prompts/fragments/chapter_reading_boundary';
  static const proseQualityBaseline =
      'assets/prompts/fragments/prose_quality_baseline';
  static const writingCraft = 'assets/prompts/fragments/writing_craft';
  static const sceneReadingBoundary =
      'assets/prompts/fragments/scene_reading_boundary';
  static const screenplayCraft = 'assets/prompts/fragments/screenplay_craft';
  static const all = [
    coreRules,
    chapterReadingBoundary,
    proseQualityBaseline,
    writingCraft,
    sceneReadingBoundary,
    screenplayCraft,
  ];
}

class PromptTemplateService {
  PromptTemplateService._();

  static PromptTemplateService? _instance;

  static PromptTemplateService get instance {
    if (_instance == null) {
      throw StateError(
        'PromptTemplateService not initialized. Call loadAll() first.',
      );
    }
    return _instance!;
  }

  static bool get isInitialized => _instance != null;

  final Map<String, Template> _templates = {};
  final Map<String, String> _rawContents = {};

  static Future<void> loadAll() async {
    final service = PromptTemplateService._();
    final assetPaths = [
      ...PromptRegistry.templateAssetPaths,
      ...PromptFragmentPaths.all,
    ];
    for (final name in assetPaths) {
      final path = '$name.md';
      final content = await rootBundle.loadString(path);
      service._rawContents[name] = content;
      service._templates[name] = Template(
        content,
        htmlEscapeValues: false,
        lenient: true,
      );
    }
    _instance = service;
  }

  String rawAsset(String name) {
    final content = _rawContents[name];
    if (content == null) {
      throw ArgumentError('Template not found: $name');
    }
    return content.trim();
  }

  String renderAsset(String name, [Map<String, dynamic> variables = const {}]) {
    final template = _templates[name];
    if (template == null) {
      throw ArgumentError('Template not found: $name');
    }
    return template.renderString(variables).trim();
  }

  static String renderString(
    String template, [
    Map<String, dynamic> variables = const {},
  ]) {
    try {
      final t = Template(template, htmlEscapeValues: false, lenient: true);
      return t.renderString(variables).trim();
    } catch (error, stackTrace) {
      _log.warning(
        'Prompt rendering failed (${error.runtimeType}); using original text.\n'
        '$stackTrace',
      );
      return template;
    }
  }
}
