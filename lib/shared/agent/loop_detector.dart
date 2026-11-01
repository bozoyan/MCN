// 职责: Agent 循环检测 — 2 层检测（连续重复 / 状态推进）
// 关联文件:
//   lib/shared/agent/agent.dart
//   lib/shared/agent/agent_event.dart

import 'dart:convert';

import 'message.dart' show ToolCall;

/// 循环检测配置。
class LoopDetectorConfig {
  /// 连续重复达到此次数 → 注入提示后给模型一次纠正机会（软循环）。
  final int hintThreshold;

  /// 连续重复达到此次数 → 直接终止 loop（硬循环）。
  final int abortThreshold;

  /// 状态推进检测的窗口大小。
  final int stateWindowSize;

  const LoopDetectorConfig({
    this.hintThreshold = 3,
    this.abortThreshold = 5,
    this.stateWindowSize = 5,
  });
}

/// 循环检测严重级别。
enum LoopSeverity {
  /// 软循环 — 注入提示后给模型一次纠正机会。
  hint,

  /// 硬循环 — 直接终止 loop。
  abort,
}

/// 循环检测结果。
class LoopDetectResult {
  final String reason;
  final LoopSeverity severity;
  final Map<String, dynamic> details;

  const LoopDetectResult(
    this.reason, {
    required this.severity,
    this.details = const {},
  });

  @override
  String toString() => 'LoopDetectResult($reason, severity=$severity)';
}

/// 2 层循环检测器。
///
/// - Layer 1: 连续重复 — 最近 N 次 tool call 完全相同才判定，区分软/硬
/// - Layer 2: 状态推进 — round 签名（含 text + tool 结果摘要）无变化视为振荡
class LoopDetector {
  final LoopDetectorConfig config;

  final List<String> _callHistory = [];
  final List<String> _stateHistory = [];

  /// 本轮已注入过提示，避免对同一循环连续多次注入。
  bool _hintInjected = false;

  LoopDetector({LoopDetectorConfig? config})
    : config = config ?? const LoopDetectorConfig();

  /// 记录一轮 LLM 输出（含文本与 tool calls），用于状态推进检测。
  ///
  /// [resultDigest] 为本轮 tool 结果摘要（ok/error 关键字段），纳入签名以区分
  /// "相同调用不同结果"与"相同调用相同结果"。
  void recordRound(
    String text,
    List<ToolCall> toolCalls, {
    String? resultDigest,
  }) {
    _stateHistory.add(_roundSignature(text, toolCalls, resultDigest));
    if (_stateHistory.length > config.stateWindowSize) {
      _stateHistory.removeAt(0);
    }
  }

  /// 记录一次 tool call（连续重复检测用）。
  void recordToolCall(ToolCall call) {
    final h = _hashCall(call);
    // 换了 call（连续重复被打破）→ 之前针对上一个循环注入的提示已失效，清除标记。
    // 否则 hint 标记会一直粘滞到下一次空 tool 轮，导致后续一个「全新且合法」的
    // 连续重复被上一个循环的提示状态连坐、直接 abort 而拿不到自己的 hint 机会。
    if (_callHistory.isNotEmpty && _callHistory.last != h) {
      _hintInjected = false;
    }
    _callHistory.add(h);
    // 连续重复只需看最近 abortThreshold 次，无需保留更长历史。
    if (_callHistory.length > config.abortThreshold) {
      _callHistory.removeAt(0);
    }
  }

  /// 主检测入口：null = 正常，非 null = 检测到循环。
  LoopDetectResult? check() {
    // Layer 1: 连续重复 — 最近 N 次调用完全相同
    if (_callHistory.length >= config.hintThreshold) {
      final consecutive = _consecutiveIdenticalCount();
      if (consecutive >= config.abortThreshold) {
        return LoopDetectResult(
          'Repeated tool call detected '
          '($consecutive consecutive identical calls, abort threshold ${config.abortThreshold})',
          severity: LoopSeverity.abort,
          details: {
            'consecutiveCount': consecutive,
            'threshold': config.abortThreshold,
          },
        );
      }
      if (consecutive >= config.hintThreshold) {
        return LoopDetectResult(
          'Repeated tool call detected '
          '($consecutive consecutive identical calls, hint threshold ${config.hintThreshold})',
          severity: LoopSeverity.hint,
          details: {
            'consecutiveCount': consecutive,
            'threshold': config.hintThreshold,
          },
        );
      }
    }

    // Layer 2: 状态推进 — 窗口内所有签名相同说明振荡
    if (_stateHistory.length >= config.stateWindowSize) {
      if (_stateHistory.toSet().length == 1) {
        return LoopDetectResult(
          'State oscillation detected '
          '(no progression in ${config.stateWindowSize} rounds)',
          severity: LoopSeverity.abort,
          details: {'stateWindowSize': config.stateWindowSize},
        );
      }
    }

    return null;
  }

  /// 标记已注入提示。注入后下一次 check 若仍未脱离循环，severity 升级为 abort。
  void markHintInjected() {
    _hintInjected = true;
  }

  /// 提示是否已注入。
  bool get hintInjected => _hintInjected;

  /// 重置连续重复检测状态（保留 Layer 2 状态推进历史）。
  ///
  /// 当模型本轮无 tool_calls（脱离 tool 循环）时调用，避免历史连续计数影响后续判定。
  /// tool call「发生变化」不在此处理——由 [recordToolCall] 在连续重复被打破时
  /// 单独清除 hint 标记。
  void resetConsecutive() {
    _callHistory.clear();
    _hintInjected = false;
  }

  /// 重置状态（给复用场景用）。
  void reset() {
    _callHistory.clear();
    _stateHistory.clear();
    _hintInjected = false;
  }

  // ---------------------------------------------------------------------------
  // helpers
  // ---------------------------------------------------------------------------

  /// 计算从末尾往前有多少个连续相同的 call hash。
  ///
  /// 例如 [A, B, B, B] → 3（末尾 3 个 B 相同）。
  /// [A, B, A, C] → 1（末尾只有 1 个 C）。
  int _consecutiveIdenticalCount() {
    if (_callHistory.isEmpty) return 0;
    final last = _callHistory.last;
    var count = 1;
    for (var i = _callHistory.length - 2; i >= 0; i--) {
      if (_callHistory[i] == last) {
        count++;
      } else {
        break;
      }
    }
    return count;
  }

  String _hashCall(ToolCall call) {
    return '${call.toolName}:${jsonEncode(call.arguments)}';
  }

  /// 本轮签名：text 摘要 + tool call 签名 + 结果摘要。
  ///
  /// 纳入 text 以区分"模型在思考推进"与"纯机械重复"；纳入 resultDigest 以区分
  /// "相同调用不同结果"与"相同调用相同结果"。
  String _roundSignature(
    String text,
    List<ToolCall> calls,
    String? resultDigest,
  ) {
    final textDigest = text.length > 64 ? text.substring(0, 64) : text;
    final callSig = calls
        .map((c) => '${c.toolName}:${jsonEncode(c.arguments)}')
        .join('|');
    return '$textDigest::$callSig::${resultDigest ?? ''}';
  }
}
