// 职责: 测试 setup_phase 门控 — 仅在新建小说且有 novel_onboarding=eligible 时展示初始化引导
// 关联文件:
//   lib/shared/services/ai/prompts/setup_phase_gate.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/services/ai/prompts/setup_phase_gate.dart';

void main() {
  group('SetupPhaseGate', () {
    test('returns false when novelOnboardingEligible is false', () {
      // 新约束：导入小说路径不写 novel_onboarding=eligible，不应展示 setup_phase
      expect(
        SetupPhaseGate.shouldShow(
          novelOnboardingEligible: false,
          hasNovel: true,
          hasAgentRules: false,
          novelChatSessionCount: 1,
        ),
        isFalse,
      );
    });

    test('returns true when eligible, no rules, and within session budget', () {
      // 正常新建小说：novel_onboarding=eligible + 无 rules + 会话数 <= 3
      expect(
        SetupPhaseGate.shouldShow(
          novelOnboardingEligible: true,
          hasNovel: true,
          hasAgentRules: false,
          novelChatSessionCount: 1,
        ),
        isTrue,
      );
      expect(
        SetupPhaseGate.shouldShow(
          novelOnboardingEligible: true,
          hasNovel: true,
          hasAgentRules: false,
          novelChatSessionCount: 3,
        ),
        isTrue,
      );
    });

    test('returns false when session count exceeds budget', () {
      expect(
        SetupPhaseGate.shouldShow(
          novelOnboardingEligible: true,
          hasNovel: true,
          hasAgentRules: false,
          novelChatSessionCount: 4,
        ),
        isFalse,
      );
    });

    test('returns false when novel is missing', () {
      expect(
        SetupPhaseGate.shouldShow(
          novelOnboardingEligible: true,
          hasNovel: false,
          hasAgentRules: false,
          novelChatSessionCount: 1,
        ),
        isFalse,
      );
    });

    test('returns false when agent rules already exist', () {
      // 已有 agent rules 时不再展示 setup_phase（用户已配置规则）
      expect(
        SetupPhaseGate.shouldShow(
          novelOnboardingEligible: true,
          hasNovel: true,
          hasAgentRules: true,
          novelChatSessionCount: 1,
        ),
        isFalse,
      );
    });

    test('returns false when session count is unknown', () {
      expect(
        SetupPhaseGate.shouldShow(
          novelOnboardingEligible: true,
          hasNovel: true,
          hasAgentRules: false,
          novelChatSessionCount: null,
        ),
        isFalse,
      );
    });
  });
}
