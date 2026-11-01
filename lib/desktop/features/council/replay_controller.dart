// 职责: 圆周会议讨论记录的本地定速重放 — 按均匀字符速率模拟流式发言，供 debug 录视频。
// 关联文件:
//   lib/shared/models/agent_council_models.dart
//   lib/shared/agent/agent_run_state.dart
//   lib/desktop/features/council/discussion_section.dart
// 遵循的 Rules:
//   .agents/rules/code-style.md

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../shared/agent/agent_run_state.dart';
import '../../../shared/models/agent_council_models.dart';
import '../../../shared/utils/utf16_safe_text.dart';

/// 重放过程中的展示快照；非重放时为 null。
class CouncilReplaySnapshot {
  final AgentCouncilSession session;
  final AgentRunState? activeRun;
  final CouncilParticipant? currentSpeaker;
  final bool isSummarizing;

  const CouncilReplaySnapshot({
    required this.session,
    this.activeRun,
    this.currentSpeaker,
    this.isSummarizing = false,
  });
}

/// 将已落盘的 Council 消息按定速「打字机」重放，驱动现有流式 UI。
///
/// 不改写真实 session / provider / DB；仅产出 [snapshot] 供面板覆盖展示。
class CouncilReplayController extends ChangeNotifier {
  CouncilReplayController({
    this.charsPerTick = 3,
    this.tickInterval = const Duration(milliseconds: 40),
    this.messageGap = const Duration(milliseconds: 450),
    this.summarizingHold = const Duration(milliseconds: 800),
  });

  /// 每个 tick 追加的字符数（约 75 cps @ 默认间隔）。
  final int charsPerTick;
  final Duration tickInterval;
  final Duration messageGap;
  final Duration summarizingHold;

  Timer? _timer;
  AgentCouncilSession? _source;
  List<CouncilMessage> _messages = const [];
  var _messageIndex = 0;
  var _charIndex = 0;
  var _isReplaying = false;
  CouncilReplaySnapshot? _snapshot;

  bool get isReplaying => _isReplaying;
  CouncilReplaySnapshot? get snapshot => _snapshot;

  /// 可重放：至少有一条非空讨论消息。
  static bool canReplay(AgentCouncilSession session) {
    for (final round in session.rounds) {
      for (final message in round.messages) {
        if (message.content.trim().isNotEmpty) {
          return true;
        }
      }
    }
    return false;
  }

  void start(AgentCouncilSession source) {
    stop(notify: false);
    final flat = <CouncilMessage>[];
    for (final round in source.rounds) {
      flat.addAll(round.messages);
    }
    if (flat.isEmpty) {
      return;
    }
    _source = source;
    _messages = flat;
    _messageIndex = 0;
    _charIndex = 0;
    _isReplaying = true;
    _snapshot = CouncilReplaySnapshot(
      session: _emptyDisplaySession(source),
      currentSpeaker: null,
      isSummarizing: false,
    );
    notifyListeners();
    _beginCurrentMessage();
  }

  void stop({bool notify = true}) {
    _timer?.cancel();
    _timer = null;
    _source = null;
    _messages = const [];
    _messageIndex = 0;
    _charIndex = 0;
    _isReplaying = false;
    _snapshot = null;
    if (notify) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    stop(notify: false);
    super.dispose();
  }

  void _beginCurrentMessage() {
    final source = _source;
    if (source == null || !_isReplaying) {
      return;
    }
    if (_messageIndex >= _messages.length) {
      _enterSummarizing(source);
      return;
    }

    final message = _messages[_messageIndex];
    _charIndex = 0;

    if (message.participantId == '__user__' || message.content.isEmpty) {
      _commitMessage(message);
      _scheduleAfter(messageGap, _beginCurrentMessage);
      return;
    }

    final speaker = _participantFor(source, message);
    _snapshot = CouncilReplaySnapshot(
      session: _snapshot!.session.copyWith(phase: CouncilPhase.discussing),
      currentSpeaker: speaker,
      isSummarizing: false,
    );
    notifyListeners();
    _scheduleAfter(messageGap, _startStreaming);
  }

  void _startStreaming() {
    final source = _source;
    if (source == null || !_isReplaying || _messageIndex >= _messages.length) {
      return;
    }
    final message = _messages[_messageIndex];
    final speaker = _participantFor(source, message);
    _snapshot = CouncilReplaySnapshot(
      session: _snapshot!.session.copyWith(phase: CouncilPhase.discussing),
      activeRun: AgentRunState(
        agentId: message.participantId,
        agentName: message.participantName,
        round: message.round,
        accumulatedText: '',
      ),
      currentSpeaker: speaker,
      isSummarizing: false,
    );
    notifyListeners();
    _schedulePeriodic(_onStreamTick);
  }

  void _onStreamTick() {
    final source = _source;
    if (source == null || !_isReplaying || _messageIndex >= _messages.length) {
      return;
    }
    final message = _messages[_messageIndex];
    final content = message.content;
    if (_charIndex >= content.length) {
      _timer?.cancel();
      _timer = null;
      _commitMessage(message);
      _scheduleAfter(messageGap, _beginCurrentMessage);
      return;
    }

    var end = (_charIndex + charsPerTick).clamp(0, content.length);
    // 边界落在代理对（emoji）中间时并入本 tick，避免产生落单代理导致渲染抛错。
    if (splitsSurrogatePair(content, end)) {
      end += 1;
    }
    final delta = content.substring(_charIndex, end);
    _charIndex = end;
    final current = _snapshot?.activeRun;
    if (current == null) {
      return;
    }
    _snapshot = CouncilReplaySnapshot(
      session: _snapshot!.session,
      activeRun: current.withAppendedText(delta),
      currentSpeaker: _snapshot!.currentSpeaker,
      isSummarizing: false,
    );
    notifyListeners();
  }

  void _commitMessage(CouncilMessage message) {
    final base = _snapshot!.session;
    final rounds = List<CouncilRound>.of(base.rounds);
    final idx = rounds.indexWhere((r) => r.roundNumber == message.round);
    if (idx >= 0) {
      rounds[idx] = rounds[idx].copyWith(
        messages: [...rounds[idx].messages, message],
      );
    } else {
      rounds.add(
        CouncilRound(
          roundNumber: message.round,
          messages: [message],
          isComplete: false,
        ),
      );
      rounds.sort((a, b) => a.roundNumber.compareTo(b.roundNumber));
    }

    CouncilRound? sourceRound;
    for (final round in _source!.rounds) {
      if (round.roundNumber == message.round) {
        sourceRound = round;
        break;
      }
    }
    if (sourceRound != null) {
      final rIdx = rounds.indexWhere((r) => r.roundNumber == message.round);
      final displayed = rounds[rIdx].messages.length;
      if (displayed >= sourceRound.messages.length && sourceRound.isComplete) {
        rounds[rIdx] = rounds[rIdx].copyWith(isComplete: true);
      }
    }

    _snapshot = CouncilReplaySnapshot(
      session: base.copyWith(
        rounds: rounds,
        phase: CouncilPhase.discussing,
        summary: null,
      ),
      activeRun: null,
      currentSpeaker: null,
      isSummarizing: false,
    );
    _messageIndex += 1;
    notifyListeners();
  }

  void _enterSummarizing(AgentCouncilSession source) {
    final summary = source.summary;
    if (summary == null) {
      _finish();
      return;
    }
    _snapshot = CouncilReplaySnapshot(
      session: _snapshot!.session.copyWith(
        phase: CouncilPhase.summarizing,
        summary: null,
      ),
      isSummarizing: true,
    );
    notifyListeners();
    _scheduleAfter(summarizingHold, () {
      if (!_isReplaying) {
        return;
      }
      _snapshot = CouncilReplaySnapshot(
        session: _snapshot!.session.copyWith(
          phase: CouncilPhase.completed,
          summary: summary,
        ),
        isSummarizing: false,
      );
      notifyListeners();
      // 展示总结后再结束，面板切回真实 session（内容一致）。
      _scheduleAfter(messageGap, _finish);
    });
  }

  void _finish() {
    _timer?.cancel();
    _timer = null;
    _source = null;
    _messages = const [];
    _messageIndex = 0;
    _charIndex = 0;
    _isReplaying = false;
    _snapshot = null;
    notifyListeners();
  }

  void _scheduleAfter(Duration delay, void Function() callback) {
    _timer?.cancel();
    _timer = Timer(delay, callback);
  }

  void _schedulePeriodic(void Function() callback) {
    _timer?.cancel();
    _timer = Timer.periodic(tickInterval, (_) => callback());
  }

  static AgentCouncilSession _emptyDisplaySession(AgentCouncilSession source) {
    return AgentCouncilSession(
      id: source.id,
      title: source.title,
      novelId: source.novelId,
      topic: source.topic,
      participants: source.participants,
      rounds: const [],
      summary: null,
      phase: CouncilPhase.discussing,
      failure: null,
      createdAt: source.createdAt,
      updatedAt: source.updatedAt,
    );
  }

  static CouncilParticipant _participantFor(
    AgentCouncilSession source,
    CouncilMessage message,
  ) {
    return source.participants.firstWhere(
      (p) => p.id == message.participantId,
      orElse: () => CouncilParticipant(
        id: message.participantId,
        name: message.participantName,
        description: '',
        prompt: '',
      ),
    );
  }
}
