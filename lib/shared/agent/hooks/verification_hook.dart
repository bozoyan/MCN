// 职责: Agent 自动验证钩子 — 在 agent 完成前触发一轮自验证，检查产出质量和规则符合度
// 关联文件:
//   lib/shared/agent/agent_hook.dart
//   lib/shared/agent/agent.dart

import 'dart:async';

import '../agent_hook.dart';
import '../message.dart';

/// Agent 完成前自动注入验证指令的钩子。
///
/// 在 [beforeDone] 中追加一条 user message，要求 agent 自我审查产出质量
/// 并检查是否符合用户规则。agent 完成审查后，[beforeDone] 再次触发，
/// 此时 [VerificationHook] 不再重复注入，避免无限循环。
///
/// 该钩子不绑定特定验证 agent 名称，模型从系统 prompt 中可用的 SubAgent
/// 列表自行选择。用户可自定义或替换验证 agent。
class VerificationHook extends AgentHook {
  /// 最大验证轮次。
  final int maxVerifications;

  bool _verificationRequested = false;
  bool _verificationDone = false;

  VerificationHook({this.maxVerifications = 1});

  @override
  FutureOr<void> beforeDone(BeforeDoneContext ctx) async {
    if (_verificationDone) {
      return;
    }

    if (_verificationRequested) {
      _verificationDone = true;
      return;
    }

    _verificationRequested = true;

    ctx.followUp(
      AgentMessage.user(
        id: 'auto_verify_${DateTime.now().millisecondsSinceEpoch}',
        content:
            '请审查你刚才的产出，检查以下方面：\n'
            '1. 情节逻辑和角色一致性\n'
            '2. 世界观规则遵守情况\n'
            '3. 用户自定义规则符合度（如有）\n'
            '\n'
            '如果发现任何问题，请修正。如果无问题，回复"审查通过"即可。',
      ),
    );
  }
}
