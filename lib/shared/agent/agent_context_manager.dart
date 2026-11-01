// 职责: Agent context manager — 对话历史存储、构建、压缩（usage 驱动 + 显式 compact 步骤）
// 关联文件:
//   lib/shared/agent/agent.dart
//   lib/shared/agent/agent_event.dart
//   lib/shared/agent/token_estimator.dart
//   lib/shared/agent/message.dart
//   lib/shared/services/ai/ai_chat_service.dart
//   lib/shared/services/ai/session_persistence.dart

import 'dart:math';

import 'token_estimator.dart';
import 'agent_tool_dispatcher.dart' show AgentCancellationToken;
import 'message.dart';
import 'client.dart' show AiUsage;

const _compressedUserMessagesHeader = '[原始用户消息]';
const _compressedUserMessagesMaxTokens = 2048;

/// 未知模型没有上下文限制时使用的保守默认窗口。
const defaultContextTokenLimit = 200000;

/// 返回在模型上下文窗口使用到 80% 时触发压缩的 token 阈值。
///
/// 此处只描述压缩时机；单轮输出预算由 Agent 的固定上限负责。
int compactThresholdForContextLimit(int contextTokens) =>
    (contextTokens * 0.8).floor();

/// Context manager 运行时快照，供 fork 或持久化使用。
class AgentContextSnapshot {
  const AgentContextSnapshot({
    required this.messages,
    this.summary,
    this.compactionCount = 0,
    this.roundIndex = 0,
    this.lastCompactionTokensBefore,
    this.lastCompactionTokensAfter,
    this.lastCompactionMessageCount,
  });

  final List<AgentMessage> messages;
  final String? summary;
  final int compactionCount;
  final int roundIndex;

  /// 最近一次压缩的 token 前后值，供落库写进 compact_summary 消息 metadata。
  final int? lastCompactionTokensBefore;
  final int? lastCompactionTokensAfter;

  /// 最近一次压缩完成时 [messages] 的长度：此下标及之后的消息产生于压缩之后，
  /// 供 UI / 落库把摘要放在压缩实际发生的位置。
  final int? lastCompactionMessageCount;

  AgentContextSnapshot copyWith({
    List<AgentMessage>? messages,
    String? summary,
    int? compactionCount,
    int? roundIndex,
    int? lastCompactionTokensBefore,
    int? lastCompactionTokensAfter,
    int? lastCompactionMessageCount,
  }) {
    return AgentContextSnapshot(
      messages: messages ?? List.of(this.messages),
      summary: summary ?? this.summary,
      compactionCount: compactionCount ?? this.compactionCount,
      roundIndex: roundIndex ?? this.roundIndex,
      lastCompactionTokensBefore:
          lastCompactionTokensBefore ?? this.lastCompactionTokensBefore,
      lastCompactionTokensAfter:
          lastCompactionTokensAfter ?? this.lastCompactionTokensAfter,
      lastCompactionMessageCount:
          lastCompactionMessageCount ?? this.lastCompactionMessageCount,
    );
  }
}

/// 压缩切点类型。
enum CompactionCutKind {
  /// 切点落在 turn 边界（user text 消息）。
  turnBoundary,

  /// 单 turn 超大，fallback 到 assistant 边界。
  intraTurn,

  /// 无需压缩（overflow 为空）。
  skipped,
}

/// 压缩结果。
class CompactionOutcome {
  const CompactionOutcome({
    required this.cutKind,
    required this.tokensBefore,
    required this.tokensAfterEstimate,
    required this.overflowCount,
  });

  final CompactionCutKind cutKind;

  /// 触发时的评估 token 数。
  final int tokensBefore;

  /// 压缩后 retained + summary 的估算 token 数。
  final int tokensAfterEstimate;

  /// 被压缩的消息数。
  final int overflowCount;

  bool get skipped => cutKind == CompactionCutKind.skipped;
}

/// Agent 对话历史的抽象。
///
/// Agent 不直接持 [List<AgentMessage>]，而是通过 context manager 读写。
/// - [SimpleAgentContextManager]：纯内存，无压缩（isolated / subagent / council 用）
/// - [SmartAgentContextManager]：装饰器，加 token 感知压缩（Chat Panel 用）
abstract class AgentContextManager {
  /// 追加消息到对话历史末尾。
  void addMessages(List<AgentMessage> msgs);

  /// 整体替换对话历史。
  void setMessages(List<AgentMessage> msgs);

  /// 当前对话历史（不含 system prompt）。
  List<AgentMessage> get messages;

  /// 清空对话历史。
  void clearMessages();

  /// 构建送给 LLM 的消息列表。
  /// 简单实现直接返回 messages；Smart 实现前置注入摘要（压缩由 Agent 显式调用）。
  Future<List<AgentMessage>> buildMessages();

  /// 返回运行时快照，供 fork 或持久化。
  AgentContextSnapshot snapshot();

  /// 当前轮次索引（由 Agent 维护，context manager 存储）。
  int get roundIndex;
  set roundIndex(int value);

  /// 压缩次数。
  int get compactionCount;
}

/// 纯内存 context manager，无压缩。
///
/// 用于 isolated agent（SubAgent/Council/Theater/Monologue）。
class SimpleAgentContextManager implements AgentContextManager {
  SimpleAgentContextManager({
    List<AgentMessage>? initialMessages,
    int initialRoundIndex = 0,
  }) : _msgs = List.of(initialMessages ?? const <AgentMessage>[]) {
    _roundIndex = initialRoundIndex;
  }

  List<AgentMessage> _msgs;
  int _roundIndex = 0;
  int _compactionCount = 0;

  @override
  void addMessages(List<AgentMessage> msgs) => _msgs.addAll(msgs);

  @override
  void setMessages(List<AgentMessage> msgs) => _msgs = List.of(msgs);

  @override
  List<AgentMessage> get messages => List.unmodifiable(_msgs);

  @override
  void clearMessages() {
    _msgs = [];
    _roundIndex = 0;
    _compactionCount = 0;
  }

  @override
  Future<List<AgentMessage>> buildMessages() async => List.of(_msgs);

  @override
  AgentContextSnapshot snapshot() => AgentContextSnapshot(
    messages: List.of(_msgs),
    compactionCount: _compactionCount,
    roundIndex: _roundIndex,
  );

  @override
  int get roundIndex => _roundIndex;

  @override
  set roundIndex(int v) => _roundIndex = v;

  @override
  int get compactionCount => _compactionCount;
}

/// LLM 摘要回调。接收当前完整消息历史与既有摘要，返回合并后的摘要文本。
///
/// 完整历史同时包含将被压缩的溢出部分与压缩后保留的最近消息（Codex 式
/// 全量交接），摘要模型可结合最新进度判断早期细节的去留。
typedef AgentSummarizer =
    Future<String> Function({
      required List<AgentMessage> messages,
      String? previousSummary,
      AgentCancellationToken? cancellationToken,
    });

/// 压缩成功时派生的结构化上下文，由代码追加到摘要末尾。
typedef AgentContextSupplementProvider = Future<List<AgentMessage>> Function();

/// 装饰器 context manager，在 token 超限时触发 LLM 压缩。
///
/// 装饰 [AgentContextManager]（通常是 [SimpleAgentContextManager]）。
/// 压缩由 Agent 循环显式调用 [shouldCompact] + [compact] 触发，
/// [buildMessages] 仅做摘要前置注入。
class SmartAgentContextManager implements AgentContextManager {
  SmartAgentContextManager({
    AgentContextManager? inner,
    this.compactThreshold = 180000,
    this.contextTokens = 200000,
    this.outputFloor = 16000,
    this.summaryMaxChars = 8000,
    this.contextSupplementProvider,
  }) : _inner = inner ?? SimpleAgentContextManager();

  factory SmartAgentContextManager.fromSnapshot({
    required AgentContextSnapshot snapshot,
    int compactThreshold = 180000,
    int contextTokens = 200000,
    int outputFloor = 16000,
    int summaryMaxChars = 8000,
    AgentSummarizer? summarizer,
    AgentContextSupplementProvider? contextSupplementProvider,
  }) {
    final manager = SmartAgentContextManager(
      inner: SimpleAgentContextManager(
        initialMessages: snapshot.messages,
        initialRoundIndex: snapshot.roundIndex,
      ),
      compactThreshold: compactThreshold,
      contextTokens: contextTokens,
      outputFloor: outputFloor,
      summaryMaxChars: summaryMaxChars,
      contextSupplementProvider: contextSupplementProvider,
    );
    manager.summarizer = summarizer;
    manager._summary = snapshot.summary;
    manager._compactionCount = snapshot.compactionCount;
    return manager;
  }

  final AgentContextManager _inner;

  /// 触发压缩的输入 token 线（= 模型窗口 − outputFloor − 漂移余量）。
  final int compactThreshold;

  /// 模型上下文窗口大小，供上下文压缩策略和诊断使用。
  final int contextTokens;

  /// 单轮输出的最低保障空间。
  final int outputFloor;

  /// 摘要最大字符数（与提示词约束对齐）。
  final int summaryMaxChars;

  AgentSummarizer? summarizer;
  AgentContextSupplementProvider? contextSupplementProvider;

  String? _summary;
  List<AgentMessage> _contextSupplement = const [];
  int _compactionCount = 0;

  /// 上次压缩时的轮次，用于判断 usage 是否过期。
  int _roundIndexAtLastCompaction = -1;

  /// 上次压缩时 retained 的消息数，用于判断 usage 是否来自压缩后。
  int _messageCountAtLastCompaction = 0;

  /// 本 turn 内是否因失败退避。
  bool _suppressedThisTurn = false;

  /// 最近一次压缩结果，随 snapshot() 输出。
  CompactionOutcome? _lastCompactionOutcome;

  // ---- delegation ----

  @override
  void addMessages(List<AgentMessage> msgs) => _inner.addMessages(msgs);

  @override
  void setMessages(List<AgentMessage> msgs) => _inner.setMessages(msgs);

  /// 将对话历史与压缩状态整体回滚到 [snapshot] 拍摄时刻。
  ///
  /// 与 [setMessages] 不同，摘要、压缩计数与压缩统计一并恢复；
  /// 内部记账对齐到恢复后的列表，等价于「快照时的压缩刚刚完成」，
  /// 此后生成的 assistant usage 才会被当作有效 token 基线。
  /// roundIndex 由 Agent 自管、不属于快照语义，不在此回滚。
  void restoreSnapshot(AgentContextSnapshot snapshot) {
    _inner.setMessages(snapshot.messages);
    _summary = snapshot.summary;
    _compactionCount = snapshot.compactionCount;
    if (snapshot.compactionCount > 0) {
      _roundIndexAtLastCompaction = _inner.roundIndex;
      _messageCountAtLastCompaction = snapshot.messages.length;
    } else {
      _roundIndexAtLastCompaction = -1;
      _messageCountAtLastCompaction = 0;
    }
    final tokensBefore = snapshot.lastCompactionTokensBefore;
    final tokensAfter = snapshot.lastCompactionTokensAfter;
    _lastCompactionOutcome = tokensBefore != null && tokensAfter != null
        ? CompactionOutcome(
            // cutKind/overflowCount 不随快照持久化，此处仅回填 token 统计。
            cutKind: CompactionCutKind.turnBoundary,
            tokensBefore: tokensBefore,
            tokensAfterEstimate: tokensAfter,
            overflowCount: 0,
          )
        : null;
    _contextSupplement = const [];
  }

  @override
  List<AgentMessage> get messages => _inner.messages;

  @override
  void clearMessages() {
    _inner.clearMessages();
    _summary = null;
    _contextSupplement = const [];
    _compactionCount = 0;
    _roundIndexAtLastCompaction = -1;
    _messageCountAtLastCompaction = 0;
    _suppressedThisTurn = false;
    _lastCompactionOutcome = null;
  }

  @override
  int get roundIndex => _inner.roundIndex;

  @override
  set roundIndex(int v) => _inner.roundIndex = v;

  @override
  int get compactionCount => _compactionCount;

  /// 复位 turn 级状态（Agent 在 process 开始时调用）。
  void resetTurnState() {
    _suppressedThisTurn = false;
  }

  /// 读取本次压缩的结构化补充上下文。失败时保留旧缓存并向上抛错。
  Future<void> refreshContextSupplement() async {
    final provider = contextSupplementProvider;
    if (provider == null) {
      _contextSupplement = const [];
      return;
    }
    final next = await provider();
    _contextSupplement = List<AgentMessage>.unmodifiable(next);
  }

  /// 当前压缩已读取的补充上下文，供 summarizer 在模型返回后追加。
  List<AgentMessage> get contextSupplementMessages => _contextSupplement;

  // ---- build (pure, no compaction) ----

  @override
  Future<List<AgentMessage>> buildMessages() async {
    final msgs = await _inner.buildMessages();
    return [..._summaryMessages(), ...msgs];
  }

  List<AgentMessage> _summaryMessages() {
    if (_summary == null || _summary!.isEmpty) {
      return const [];
    }
    return <AgentMessage>[
      AgentMessage.user(
        id: 'ctx_summary',
        content: _summary!,
        type: AgentMessageType.compact_summary,
      ),
    ];
  }

  // ---- compaction ----

  /// 当前 token 估算值，供 Agent 判断是否需要压缩和诊断使用。
  int currentTokensEstimate({required int systemPromptTokens}) {
    return _estimateCurrentTokens(systemPromptTokens: systemPromptTokens);
  }

  /// 是否需要压缩。
  ///
  /// 优先使用上一轮真实 [AiUsage.inputTokens]（已含 system prompt 与 blocks），
  /// 无有效 usage 时退化为估算（覆盖全部 blocks + CJK 计权）。
  bool shouldCompact({required int systemPromptTokens}) {
    if (_suppressedThisTurn) return false;
    if (summarizer == null) return false;
    // 同轮仅在上下文未新增消息时跳过；压缩期间或重试前的追加指令仍需检查。
    if (_inner.roundIndex == _roundIndexAtLastCompaction &&
        _inner.messages.length == _messageCountAtLastCompaction) {
      return false;
    }

    final currentTokens = _estimateCurrentTokens(
      systemPromptTokens: systemPromptTokens,
    );
    return currentTokens > compactThreshold;
  }

  int _estimateCurrentTokens({required int systemPromptTokens}) {
    final msgs = _inner.messages;
    final derivedTokens = estimateAgentMessagesTokens(_summaryMessages());

    // 尝试取最近一条带 usage 的 assistant 消息（仅压缩后生成的才有效）。
    for (var i = msgs.length - 1; i >= 0; i--) {
      final m = msgs[i];
      if (m.role == AgentMessageRole.assistant &&
          m.usage != null &&
          m.usage!.inputTokens > 0) {
        // 只有压缩后生成的 usage 才有效（避免用过期基线重复触发）。
        if (i >= _messageCountAtLastCompaction) {
          // inputTokens 是生成当前 assistant 消息之前的请求输入；当前
          // assistant 及其后的工具结果都会进入下一次请求，需要一并估算。
          final messagesAddedSinceUsage = msgs.sublist(i);
          return m.usage!.inputTokens +
              estimateAgentMessagesTokens(messagesAddedSinceUsage);
        }
        break; // 找到的是压缩前的 usage，不用它
      }
    }

    // 无有效 usage — 估算全部消息 + system prompt
    return estimateAgentMessagesTokens(msgs) +
        derivedTokens +
        systemPromptTokens;
  }

  /// 执行压缩。
  ///
  /// 切点优先落在 turn 边界（user text 消息），当前用户指令永不丢失；
  /// tool_call/tool_result 配对在 retained 内始终完整。
  /// 失败时异常向上抛由 Agent 处理（不静默吞掉）。
  ///
  /// [systemPromptTokens] 与 [shouldCompact] 传入的值一致，使 outcome 的前后
  /// token 数与触发判断同一口径（含 system prompt 与上次 usage 中的工具定义）。
  Future<CompactionOutcome> compact({
    String? taskText,
    AgentCancellationToken? cancellationToken,
    int systemPromptTokens = 0,
  }) async {
    void checkCancellation() {
      if (cancellationToken?.isCancellationRequested ?? false) {
        throw const _CompactionCancelledException();
      }
    }

    checkCancellation();
    final summarizer = this.summarizer;
    if (summarizer == null) {
      return CompactionOutcome(
        cutKind: CompactionCutKind.skipped,
        tokensBefore: 0,
        tokensAfterEstimate: 0,
        overflowCount: 0,
      );
    }

    final msgs = _inner.messages;
    final tokensBefore = _estimateCurrentTokens(
      systemPromptTokens: systemPromptTokens,
    );
    final contextTokensBefore =
        estimateAgentMessagesTokens(msgs) +
        estimateAgentMessagesTokens(_summaryMessages());

    // 选切点
    final cutResult = _selectCutPoint(msgs);
    final cutIdx = cutResult.$1;
    final cutKind = cutResult.$2;
    final needsRestate = cutResult.$3;

    // overflow 为空 — 无需压缩
    if (cutIdx <= 0) {
      return CompactionOutcome(
        cutKind: CompactionCutKind.skipped,
        tokensBefore: tokensBefore,
        tokensAfterEstimate: tokensBefore,
        overflowCount: 0,
      );
    }

    final overflow = msgs.sublist(0, cutIdx);
    var retained = msgs.sublist(cutIdx);

    try {
      // 先计算完整候选状态，全部验证通过后再一次性提交。
      _contextSupplement = const [];
      final rawSummary = await summarizer(
        messages: msgs,
        previousSummary: _summary,
        cancellationToken: cancellationToken,
      );
      checkCancellation();
      await refreshContextSupplement();
      checkCancellation();
      final trimmedSummary = rawSummary.trim();
      final supplementText = _contextSupplementText();
      final narrativeSummary = _withoutGeneratedContext(
        trimmedSummary,
        supplementText,
      );
      if (narrativeSummary.isEmpty) {
        throw StateError('Context compaction returned an empty summary.');
      }
      final candidateNarrative = safeTruncate(
        narrativeSummary,
        summaryMaxChars,
      ).trim();
      if (candidateNarrative.isEmpty) {
        throw StateError('Context compaction produced an empty summary.');
      }
      final compressedUserMessages = _compressedUserMessagesText(overflow);
      final candidateSummary = [
        candidateNarrative,
        if (compressedUserMessages.isNotEmpty) compressedUserMessages,
        if (supplementText.isNotEmpty) supplementText,
      ].join('\n\n');
      final candidateCompactionCount = _compactionCount + 1;

      // intra-turn fallback 时在 retained 头部插入 restate。
      if (needsRestate && taskText != null && taskText.isNotEmpty) {
        final restateContent = safeTruncate(taskText, 4000);
        retained = [
          AgentMessage.user(
            id: 'ctx_restate_$candidateCompactionCount',
            content: '[用户当前指令原文] $restateContent',
          ),
          ...retained,
        ];
      }

      // 从触发基线中扣除消息部分的估算降幅，保留基线里的 system prompt 与工具定义。
      final contextTokensAfter =
          estimateAgentMessagesTokens(retained) +
          estimateTextTokens(candidateSummary);
      final tokensAfterEstimate = max(
        contextTokensAfter,
        tokensBefore - contextTokensBefore + contextTokensAfter,
      );
      final outcome = CompactionOutcome(
        cutKind: cutKind,
        tokensBefore: tokensBefore,
        tokensAfterEstimate: tokensAfterEstimate,
        overflowCount: overflow.length,
      );

      _summary = candidateSummary;
      _compactionCount = candidateCompactionCount;
      _inner.setMessages(retained);
      _roundIndexAtLastCompaction = _inner.roundIndex;
      _messageCountAtLastCompaction = retained.length;
      _lastCompactionOutcome = outcome;
      _contextSupplement = const [];
      return outcome;
    } catch (_) {
      _contextSupplement = const [];
      if (!(cancellationToken?.isCancellationRequested ?? false)) {
        _suppressedThisTurn = true;
      }
      rethrow;
    }
  }

  String _contextSupplementText() => _contextSupplement
      .map((message) => message.content.trim())
      .where((content) => content.isNotEmpty)
      .join('\n\n');

  String _compressedUserMessagesText(List<AgentMessage> overflow) {
    final selected = <AgentMessage>[];
    var remainingTokens = _compressedUserMessagesMaxTokens;
    for (var index = overflow.length - 1; index >= 0; index--) {
      final message = overflow[index];
      if (message.role != AgentMessageRole.user ||
          message.type != AgentMessageType.text ||
          message.id.startsWith('ctx_restate_')) {
        continue;
      }
      final trimmedContent = message.content.trim();
      if (trimmedContent.isEmpty ||
          trimmedContent.startsWith('<system-remind')) {
        continue;
      }
      final messageTokens = estimateTextTokens(message.content);
      if (messageTokens > remainingTokens) {
        break;
      }
      selected.add(message);
      remainingTokens -= messageTokens;
    }
    if (selected.isEmpty) {
      return '';
    }
    final lines = <String>[_compressedUserMessagesHeader];
    for (final message in selected.reversed) {
      final content = message.content.trim().replaceAll(
        RegExp(r'\r\n?|\n'),
        '\n  ',
      );
      lines.add('- $content');
    }
    return lines.join('\n');
  }

  String _withoutExpectedSupplement(String summary, String supplement) {
    if (supplement.isEmpty) {
      return summary.trim();
    }
    final suffix = '\n\n$supplement';
    if (!summary.endsWith(suffix)) {
      return summary.trim();
    }
    return summary.substring(0, summary.length - suffix.length).trim();
  }

  String _withoutGeneratedContext(String summary, String supplement) {
    final withoutSupplement = _withoutExpectedSupplement(summary, supplement);
    final marker = '$_compressedUserMessagesHeader\n';
    final markerIndex = withoutSupplement.startsWith(marker)
        ? 0
        : withoutSupplement.indexOf('\n\n$marker');
    if (markerIndex < 0) {
      return withoutSupplement;
    }
    return withoutSupplement.substring(0, markerIndex).trim();
  }

  /// 选切点：从尾部向前累积估算 token，在候选边界（user text 消息）
  /// 中选择「retained 估算 ≤ 0.35 × compactThreshold」的最老一个。
  /// 无候选时 fallback 到 assistant 边界 + 配对校验 + restate。
  ///
  /// 返回 (cutIndex, cutKind, needsRestate)。
  (int, CompactionCutKind, bool) _selectCutPoint(List<AgentMessage> msgs) {
    final keepTarget = (compactThreshold * 0.35).round();

    // Pass 1: 找所有 user text 候选边界
    final candidates = <int>[];
    for (var i = 0; i < msgs.length; i++) {
      final m = msgs[i];
      if (m.role == AgentMessageRole.user && m.type == AgentMessageType.text) {
        candidates.add(i);
      }
    }

    // 从最老的候选开始检查，选第一个满足 retained <= keepTarget 的
    for (final candidate in candidates) {
      final retained = msgs.sublist(candidate);
      final estimate = estimateAgentMessagesTokens(retained);
      if (estimate <= keepTarget) {
        // 校验配对完整性
        final adjusted = _ensureToolPairing(retained, candidate, msgs);
        return (adjusted, CompactionCutKind.turnBoundary, false);
      }
    }

    // Fallback: 最后一个 assistant 边界
    var cutIdx = _lastAssistantIndex(msgs);
    if (cutIdx <= 0) {
      return (0, CompactionCutKind.skipped, false);
    }

    // 向前调整直到 retained 内所有 tool_result 都有配对 tool_call
    final retained = msgs.sublist(cutIdx);
    final adjustedRetained = _ensureToolPairingFallback(retained, cutIdx, msgs);
    cutIdx = adjustedRetained;

    return (cutIdx, CompactionCutKind.intraTurn, true);
  }

  /// 校验 retained 内 tool_result/tool_call 配对完整性。
  /// 如果首个消息是 orphan tool_result，向前移动切点。
  int _ensureToolPairing(
    List<AgentMessage> retained,
    int originalCutIdx,
    List<AgentMessage> allMsgs,
  ) {
    var cutIdx = originalCutIdx;
    // 如果 retained 首条是 tool_result（orphan），向前找到其配对的 assistant
    while (cutIdx < allMsgs.length) {
      final first = allMsgs[cutIdx];
      if (first.type != AgentMessageType.tool_result) {
        break;
      }
      // tool_result 不应是 retained 首条 — 向后移
      cutIdx++;
    }
    return cutIdx;
  }

  /// Fallback 配对校验：确保 retained 内所有 tool_result 都有配对 tool_call。
  int _ensureToolPairingFallback(
    List<AgentMessage> retained,
    int originalCutIdx,
    List<AgentMessage> allMsgs,
  ) {
    var cutIdx = originalCutIdx;

    // 收集 retained 内所有 tool_call IDs
    final toolCallIds = <String>{};
    for (final m in allMsgs.sublist(cutIdx)) {
      for (final b in m.blocks) {
        if (b is ToolCallBlock) {
          toolCallIds.add(b.callId);
        }
      }
    }

    // 检查 retained 内所有 tool_result 是否有配对
    // 如果有 orphan tool_result，向前移动切点到该 tool_result 之后
    for (var i = cutIdx; i < allMsgs.length; i++) {
      final m = allMsgs[i];
      if (m.type != AgentMessageType.tool_result) continue;
      for (final b in m.blocks) {
        if (b is ToolResultBlock && !toolCallIds.contains(b.toolCallId)) {
          // orphan — 移动切点到这条之后
          cutIdx = i + 1;
          break;
        }
      }
    }

    return cutIdx;
  }

  @override
  AgentContextSnapshot snapshot() {
    final inner = _inner.snapshot();
    return inner.copyWith(
      compactionCount: _compactionCount,
      summary: _summary,
      lastCompactionTokensBefore: _lastCompactionOutcome?.tokensBefore,
      lastCompactionTokensAfter: _lastCompactionOutcome?.tokensAfterEstimate,
      lastCompactionMessageCount: _lastCompactionOutcome == null
          ? null
          : min(_messageCountAtLastCompaction, inner.messages.length),
    );
  }

  // ---- helpers ----

  static int _lastAssistantIndex(List<AgentMessage> msgs) {
    for (var i = msgs.length - 1; i >= 0; i--) {
      if (msgs[i].role == AgentMessageRole.assistant) return i;
    }
    return 0;
  }
}

class _CompactionCancelledException implements Exception {
  const _CompactionCancelledException();
}
