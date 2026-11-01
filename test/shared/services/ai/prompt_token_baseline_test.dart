// 职责: 为 orchestrator system prompt 与默认工具集的 prompt 体积建立可回归的 token 基准
// 关联文件:
//   lib/shared/services/ai/prompts/use_cases/chat_prompt_use_case.dart
//   lib/shared/services/ai/tools.dart
//   lib/shared/agent/agent_tool_dispatcher.dart
//   lib/shared/agent/token_estimator.dart

import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/agent/token_estimator.dart'
    show estimateTextTokens;
import 'package:reveric/shared/database/app_database.dart';
import 'package:reveric/shared/database/novel_content_database.dart';
import 'package:reveric/shared/models/ai_chat_models.dart'
    show AiSessionContext;
import 'package:reveric/shared/models/ai_session_mode.dart';
import 'package:reveric/shared/services/ai/prompt_template.dart';
import 'package:reveric/shared/services/ai/prompts/ai_prompt_service.dart';
import 'package:reveric/shared/services/ai/prompts/use_cases/chat_prompt_use_case.dart';
import 'package:reveric/shared/services/ai/tools.dart';
import 'package:reveric/shared/services/novel_actions.dart';
import 'package:reveric/shared/services/novel_content.dart';
import 'package:reveric/shared/services/working_overlay.dart';

/// 基准值 —— 每轮 prompt 瘦身后按实测输出更新。默认只下调；确有质量收益时才允许
/// 上调，且必须在下方水位注释里写清楚这些 token 换来了什么。
///
/// 单位是 [estimateTextTokens] 的估算 token（CJK 1:1、其余 ÷4，刻意高估），
/// 与运行时上下文预算用的是同一把尺子，所以这里的数字可以直接和 context window
/// 预算对比。
///
/// **超基准只打印 `[WARN]`，不再让测试失败。** 基准是观测水位，不是发布门槛 ——
/// 涨了要看得见，但不该卡住一次正常的功能改动。判断涨得值不值由人看输出决定，
/// 见 [_reportBaseline]。测试本身仍然断言「测得到、非零」，防止指标静默失灵。
/// 基线取自 2026-08-19 瘦身后的实测值（见 `reports the current ...` 用例的打印输出）。
///
/// 上一轮水位：orchestrator 3211 / floor 6273 / tools 7191 / combined 13464。
/// 本轮 floor 与 combined 各上调 362，是这份基准第一次向上调整。换来的是：writer 的
/// 「写作直觉」抽成 `writing_craft` fragment 由 orchestrator 与 writer 共用，
/// orchestrator 亲自写正文时不再拿只剩 4 条抽象表述的弱化副本——仓库里没有内置的
/// 正文写作 AgentSkill 能兜这个底。同批还把大纲章节推算语义收进 beats 的
/// `chapter_count` 字段说明（原先散在三份 prompt/skill 里各写一版）。
/// orchestrator.md 自身降到 2941：内容移进 fragment 后不再计入未渲染的模板，
/// 按惯例一并下调锁住。
///
/// 同轮再上调 172（floor 6635 → 6807）：补两组此前裸列在字段表里、没有任何解释的
/// 字段。`characters` 的 name、role、identity、motivation、arc —— name 必填、
/// identity 又是身份的唯一去处，缺说明时模型会把头衔和职务直接写进 name。
/// `chapters` 的 outline、brief、content —— 三个相邻文本字段，DB 里写明了
/// 「outline 写前规划、brief 写后总结、不被覆盖」，但这层语义之前没传给模型，
/// 而 outline 是可编辑字段，写错等于覆盖写前规划。
/// 字段表在 `e0e1e04e4` 才开始渲进 system prompt，在那之前模型必须先 Read 一条
/// 已有记录才知道有哪些字段，等于有个「照着现有数据模仿」的隐性护栏；字段表
/// 暴露后那个护栏没了，说明必须写在 schema 里。gender / age / title 语义自明，
/// 不写；六个集合共用的 category 暂缓。
///
/// 同轮再上调 61（floor 6807 → 6868）：`prose_quality_baseline` 增加正文全角标点
/// 要求。客户端的 `punctuation_replace.dart` 只在章节复制时做半角转全角，入库文本、
/// 编辑器显示和后续章节承接读到的都还是原样，所以这层要在写入前就管住。引号取 “”
/// 与该文件 `defaultPunctuationReplaceRules` 的 `'"' → '“”'` 对齐，避免同一本书里
/// 「」和 “” 混用；英文与数字原文整体豁免，留给外语台词、叙事内代码面板和 5'6"
/// 这类计量写法。
/// floor 从 6868 上调到 6902（+34）：来自 `6018d632a`（path schema 的 readonly
/// flag），换来的是字段表能标出只读字段。tools 从 7191 下调到 7068（-66 + 前轮余量）：
/// Edit 的 outline 专用 `beats` 参数移到 `Write /outlines/{name}/beats`，Edit 431→332、
/// Write 370→403。combined 随两者同步到 13970。
/// floor 从 6902 下调到 6822（-80）：path schema 去重。「路径获取方式」五条整块是
/// 上面「Hypermedia 导航」的复述（字段路径拼法、`_links.subresources`、Glob 发现
/// 都是逐字重复）；「可用集合」的集合清单与 `pathSchemaFieldNotes()` 渲出的字段字典
/// 表头是同一份，连分组都一样，只留字典里没有的 novel 路径语法与 hidden 的
/// relations / canvas；`pathSchemaBlock()` 开头那句前言又是导航第一条的摘要。
/// 工具描述未动，tools 与 combined 基准不变。
const int _orchestratorInstructionBaselineTokens = 2941;
const int _systemPromptFloorBaselineTokens = 6822;
const int _defaultToolDefsBaselineTokens = 7068;
const int _combinedBaselineTokens = 13970;

/// 单个工具的上限 —— 防止总量达标但某个描述失控膨胀。当前最大的是 Read（1190）。
const int _singleToolDefBaselineTokens = 1190;

/// 与基准比对并打印一行，超了标 `[WARN]`，不抛断言。
void _reportBaseline(String label, int actual, int baseline, String note) {
  final delta = actual - baseline;
  // ignore: avoid_print
  print(
    delta > 0
        ? '[WARN] $label：$actual tok，超基准 $baseline（+$delta）。$note'
        : '[ok]   $label：$actual tok，基准 $baseline（$delta）。',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late NovelContentDatabase db;
  late AppDatabase appDb;
  late AiToolManager toolManager;
  late AiPromptService promptService;

  setUpAll(PromptTemplateService.loadAll);

  setUp(() {
    db = NovelContentDatabase.forTest(NativeDatabase.memory());
    appDb = AppDatabase.forTest(NativeDatabase.memory());
    final contentService = NovelContentService(db);
    final overlay = WorkingOverlayService(
      db,
      contentService,
      novelActionsService: NovelActionsService(appDb),
    );
    // skillLoader / suggestNextActionCallback 决定 AgentSkill 与 SuggestNextAction
    // 是否下发 ToolDef，桌面正常会话两者都挂着，基准必须包含它们。
    toolManager = AiToolManager(
      contentService,
      workingOverlayService: overlay,
      skillLoader: (_) async => null,
      skillNamesProvider: () => const <String>[],
      suggestNextActionCallback: (_, _) {},
    )..registerAllTools();
    promptService = AiPromptService.fromInitializedTemplates();
  });

  tearDown(() async {
    await db.close();
    await appDb.close();
  });

  /// 默认会话下真正下发给模型的工具定义。
  List<ToolDef> defaultToolDefs() =>
      toolManager.toolDefsForNames(defaultAgentToolNames());

  /// 一个 ToolDef 在 wire 上的实际体积：名字 + 描述 + 序列化后的 input schema。
  int toolDefTokens(ToolDef def) =>
      estimateTextTokens(def.name) +
      estimateTextTokens(def.description) +
      estimateTextTokens(jsonEncode(def.inputSchema));

  String systemPromptFloor() => promptService.chatPanel.system(
    ChatPanelPromptInput(
      context: const AiSessionContext(),
      mode: AiSessionMode.chat,
      systemInstruction: promptService.chatPanel.orchestratorInstruction(),
    ),
  );

  test('reports the current orchestrator + tools prompt budget', () {
    final orchestrator = promptService.chatPanel.orchestratorInstruction();
    final floor = systemPromptFloor();
    final defs = defaultToolDefs();

    final orchestratorTokens = estimateTextTokens(orchestrator);
    final floorTokens = estimateTextTokens(floor);
    final toolTokens = defs.fold<int>(0, (sum, d) => sum + toolDefTokens(d));

    final rows =
        defs
            .map(
              (d) => (
                name: d.name,
                description: estimateTextTokens(d.description),
                schema: estimateTextTokens(jsonEncode(d.inputSchema)),
                total: toolDefTokens(d),
              ),
            )
            .toList()
          ..sort((a, b) => b.total.compareTo(a.total));

    final buffer = StringBuffer()
      ..writeln('')
      ..writeln('===== AI prompt token baseline =====')
      ..writeln('estimator: estimateTextTokens (CJK 1:1, other ~/4)')
      ..writeln('')
      ..writeln('-- system prompt --')
      ..writeln(
        'orchestrator.md           '
        '${orchestrator.length.toString().padLeft(7)} chars '
        '${orchestratorTokens.toString().padLeft(6)} tok',
      )
      ..writeln(
        'system prompt (floor)     '
        '${floor.length.toString().padLeft(7)} chars '
        '${floorTokens.toString().padLeft(6)} tok',
      )
      ..writeln('')
      ..writeln('-- default tool defs (${defs.length} tools) --')
      ..writeln('tool                          desc  schema   total');
    for (final row in rows) {
      buffer.writeln(
        '${row.name.padRight(26)}'
        '${row.description.toString().padLeft(6)}'
        '${row.schema.toString().padLeft(8)}'
        '${row.total.toString().padLeft(8)}',
      );
    }
    buffer
      ..writeln('${'TOTAL'.padRight(26)}${toolTokens.toString().padLeft(22)}')
      ..writeln('')
      ..writeln(
        'COMBINED (system floor + tool defs): ${floorTokens + toolTokens} tok',
      )
      ..writeln('====================================');
    // ignore: avoid_print
    print(buffer);

    // 报告不断言体积，只保证测量对象非空 —— 真正的门槛在下面的基准用例里。
    expect(defs, isNotEmpty);
    expect(orchestratorTokens, greaterThan(0));
  });

  test('reports orchestrator instruction against baseline', () {
    final tokens = estimateTextTokens(
      promptService.chatPanel.orchestratorInstruction(),
    );
    _reportBaseline(
      'orchestrator.md',
      tokens,
      _orchestratorInstructionBaselineTokens,
      '先削减别处，或显式上调基准。',
    );
    expect(tokens, greaterThan(0));
  });

  test('reports minimal system prompt against baseline', () {
    final tokens = estimateTextTokens(systemPromptFloor());
    _reportBaseline(
      '空上下文 system prompt',
      tokens,
      _systemPromptFloorBaselineTokens,
      '这是每轮都要付的固定成本。',
    );
    expect(tokens, greaterThan(0));
  });

  test('reports default tool defs against baseline', () {
    final defs = defaultToolDefs();
    final tokens = defs.fold<int>(0, (sum, d) => sum + toolDefTokens(d));
    _reportBaseline(
      '默认工具集（${defs.length} 个工具）',
      tokens,
      _defaultToolDefsBaselineTokens,
      '看看是哪个工具涨的。',
    );
    expect(defs, isNotEmpty);
    expect(tokens, greaterThan(0));
  });

  test('reports per-tool defs against baseline', () {
    for (final def in defaultToolDefs()) {
      final tokens = toolDefTokens(def);
      if (tokens > _singleToolDefBaselineTokens) {
        _reportBaseline(
          '单工具 ${def.name}',
          tokens,
          _singleToolDefBaselineTokens,
          '总量达标也不代表单个描述没失控。',
        );
      }
      expect(tokens, greaterThan(0));
    }
  });

  test('reports combined system prompt + tool defs against baseline', () {
    final tokens =
        estimateTextTokens(systemPromptFloor()) +
        defaultToolDefs().fold<int>(0, (sum, d) => sum + toolDefTokens(d));
    _reportBaseline('每轮固定开销合计', tokens, _combinedBaselineTokens, '');
    expect(tokens, greaterThan(0));
  });
}
