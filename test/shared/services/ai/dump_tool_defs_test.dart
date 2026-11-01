// 职责: 把 ChatPromptUseCase.system() 与默认工具定义落到本地，对照模型实际看到的全文
// 关联文件:
//   lib/shared/services/ai/prompts/use_cases/chat_prompt_use_case.dart
//   lib/shared/services/ai/tools.dart
//   lib/shared/services/bundled_control_skills.dart
//   test/shared/services/ai/prompt_token_baseline_test.dart
// 遵循的 Rules:
//   .agents/rules/testing.md

@Tags(['tool_dump'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/agent/token_estimator.dart'
    show estimateTextTokens;
import 'package:reveric/shared/database/app_database.dart';
import 'package:reveric/shared/database/novel_content_database.dart';
import 'package:reveric/shared/models/agent_skill.dart';
import 'package:reveric/shared/models/ai_chat_models.dart'
    show AiSessionContext;
import 'package:reveric/shared/models/app_settings_aggregate_data.dart'
    show defaultAiAgentIdentityText, defaultAiAgentSoulText;
import 'package:reveric/shared/models/ai_session_mode.dart';
import 'package:reveric/shared/services/ai/prompt_template.dart';
import 'package:reveric/shared/services/ai/prompts/ai_prompt_service.dart';
import 'package:reveric/shared/services/ai/prompts/use_cases/chat_prompt_use_case.dart';
import 'package:reveric/shared/services/ai/tools.dart';
import 'package:reveric/shared/services/bundled_control_skills.dart';
import 'package:reveric/shared/services/novel_actions.dart';
import 'package:reveric/shared/services/novel_content.dart';
import 'package:reveric/shared/services/working_overlay.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(PromptTemplateService.loadAll);

  test(
    'writes ChatPromptUseCase.system and default tools to TOOL_DUMP_DIR',
    () async {
      final db = NovelContentDatabase.forTest(NativeDatabase.memory());
      final appDb = AppDatabase.forTest(NativeDatabase.memory());
      addTearDown(() async {
        await db.close();
        await appDb.close();
      });

      final contentService = NovelContentService(db);
      final overlay = WorkingOverlayService(
        db,
        contentService,
        novelActionsService: NovelActionsService(appDb),
      );
      final toolManager = AiToolManager(
        contentService,
        workingOverlayService: overlay,
        skillLoader: (_) async => null,
        skillNamesProvider: () => const <String>[],
        suggestNextActionCallback: (_, _) {},
      )..registerAllTools();
      final promptService = AiPromptService.fromInitializedTemplates();

      final bundled = await const BundledControlSkillsLoader().loadAll(
        rootBundle,
      );
      final promptServiceChat = promptService.chatPanel;
      final system = promptServiceChat.system(
        ChatPanelPromptInput(
          context: const AiSessionContext(),
          mode: AiSessionMode.chat,
          systemInstruction: promptServiceChat.orchestratorInstruction(),
          identityPrompt: defaultAiAgentIdentityText,
          soulPrompt: defaultAiAgentSoulText,
          availableSkills: [
            for (final skill in bundled)
              AgentSkillSummary(
                name: skill.callName,
                whenToUse: skill.whenToUse,
                description: skill.description,
              ),
          ],
        ),
      );
      final defs = toolManager.toolDefsForNames(defaultAgentToolNames());

      final outDir = Directory(
        Platform.environment['TOOL_DUMP_DIR'] ??
            '${Directory.systemTemp.path}/reveric-tool-defs',
      )..createSync(recursive: true);
      final toolsDir = Directory('${outDir.path}/tools')..createSync();

      for (final leftover in [
        'orchestrator.txt',
        'path_schema.txt',
        'system_floor.txt',
      ]) {
        final file = File('${outDir.path}/$leftover');
        if (file.existsSync()) {
          file.deleteSync();
        }
      }

      File('${outDir.path}/chat_system.txt').writeAsStringSync(system);

      final rows = <_ToolRow>[];
      const pretty = JsonEncoder.withIndent('  ');
      for (final def in defs) {
        File(
          '${toolsDir.path}/${def.name}.txt',
        ).writeAsStringSync(def.description);
        File(
          '${toolsDir.path}/${def.name}.schema.json',
        ).writeAsStringSync(pretty.convert(def.inputSchema));
        rows.add(
          _ToolRow(
            name: def.name,
            descTok: estimateTextTokens(def.description),
            schemaTok: estimateTextTokens(jsonEncode(def.inputSchema)),
            totalTok:
                estimateTextTokens(def.name) +
                estimateTextTokens(def.description) +
                estimateTextTokens(jsonEncode(def.inputSchema)),
          ),
        );
      }
      rows.sort((a, b) => b.totalTok.compareTo(a.totalTok));

      final systemTok = estimateTextTokens(system);
      final toolTok = rows.fold<int>(0, (sum, row) => sum + row.totalTok);
      File('${outDir.path}/README.md').writeAsStringSync(
        _buildIndex(
          dumpDir: _relativeDumpDir(outDir),
          systemChars: system.length,
          systemTok: systemTok,
          toolCount: rows.length,
          toolTok: toolTok,
          rows: rows,
        ),
      );

      // ignore: avoid_print
      print('dumped chat system + ${defs.length} tools to ${outDir.path}');
      expect(system, contains('# 身份设定'));
      expect(system, contains('# 灵魂设定'));
      expect(system, contains('# 工作区资源路径规则'));
      expect(system, contains('# 可用 AgentSkills'));
      expect(File('${toolsDir.path}/Read.txt').lengthSync(), greaterThan(0));
    },
  );
}

class _ToolRow {
  const _ToolRow({
    required this.name,
    required this.descTok,
    required this.schemaTok,
    required this.totalTok,
  });

  final String name;
  final int descTok;
  final int schemaTok;
  final int totalTok;
}

String _relativeDumpDir(Directory outDir) {
  final cwd = Directory.current.path;
  final path = outDir.path;
  if (path == cwd || path.startsWith('$cwd/')) {
    return path.substring(cwd.length).replaceFirst(RegExp('^/'), '');
  }
  return path;
}

String _buildIndex({
  required String dumpDir,
  required int systemChars,
  required int systemTok,
  required int toolCount,
  required int toolTok,
  required List<_ToolRow> rows,
}) {
  final buffer = StringBuffer()
    ..writeln('# Chat use case + tools snapshot')
    ..writeln()
    ..writeln(
      '`chat_system.txt` 是 `ChatPromptUseCase.system()` 的完整输出'
      '（默认 identity/soul、bundled control skills 索引；无小说/记忆/用户规则）。'
      'token 用 `estimateTextTokens`（CJK 1:1，其余 ÷4）。',
    )
    ..writeln()
    ..writeln('重新生成：')
    ..writeln()
    ..writeln('```bash')
    ..writeln('TOOL_DUMP_DIR=$dumpDir \\')
    ..writeln('  fvm flutter test --tags tool_dump --run-skipped \\')
    ..writeln('  test/shared/services/ai/dump_tool_defs_test.dart')
    ..writeln('```')
    ..writeln()
    ..writeln('## 体积')
    ..writeln()
    ..writeln('| 项 | chars | tok |')
    ..writeln('|---|---:|---:|')
    ..writeln('| ChatPromptUseCase.system | $systemChars | $systemTok |')
    ..writeln('| default tools ($toolCount) |  | $toolTok |')
    ..writeln('| **combined** |  | **${systemTok + toolTok}** |')
    ..writeln()
    ..writeln('## 文件')
    ..writeln()
    ..writeln('| 文件 | 内容 |')
    ..writeln('|---|---|')
    ..writeln('| `chat_system.txt` | `ChatPromptUseCase.system()` |')
    ..writeln('| `tools/{Name}.txt` | 工具 description |')
    ..writeln('| `tools/{Name}.schema.json` | 工具 input schema |')
    ..writeln()
    ..writeln('## 工具')
    ..writeln()
    ..writeln('| tool | desc | schema | total |')
    ..writeln('|---|---:|---:|---:|');
  for (final row in rows) {
    buffer.writeln(
      '| ${row.name} | ${row.descTok} | ${row.schemaTok} | ${row.totalTok} |',
    );
  }
  buffer.writeln('| **TOTAL** |  |  | **$toolTok** |');
  buffer.writeln();
  return buffer.toString();
}
