// 职责: 锁定 resolveAgentMaxTokens 的三重 clamp 行为（天花板 / 模型上限 / 上下文余量）
// 关联文件:
//   lib/shared/agent/agent_config.dart
//   lib/shared/agent/agent_context_manager.dart
//   lib/shared/models/models_catalog.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/agent/agent_config.dart';
import 'package:reveric/shared/agent/agent_context_manager.dart';
import 'package:reveric/shared/models/models_catalog.dart';

void main() {
  group('resolveAgentMaxTokens', () {
    test('未收录模型退回保守预算，不使用 32768', () {
      expect(resolveAgentMaxTokens('totally-unknown-model'), 32000);
      expect(resolveAgentMaxTokens(null), 32000);
      expect(resolveAgentMaxTokens(''), 32000);
      expect(unknownModelMaxTokens, 32000);
    });

    test('大窗口模型受天花板约束', () {
      // 1M 上下文 → 余量 200000，输出上限 128k/384k，天花板生效。
      expect(resolveAgentMaxTokens('claude-sonnet-5'), agentMaxTokensCeiling);
      expect(resolveAgentMaxTokens('gpt-5.6-sol'), agentMaxTokensCeiling);
      expect(resolveAgentMaxTokens('deepseek-v4-pro'), agentMaxTokensCeiling);
      expect(resolveAgentMaxTokens('glm-5.2'), agentMaxTokensCeiling);
    });

    test('200k 窗口模型受上下文余量约束而非模型输出上限', () {
      // Claude Sonnet 4.5 输出上限 64k，但压缩线在 160k，只剩 40k 给输出。
      // 直接发 48000 会让 input + max_tokens 超过 200k 窗口并触发中途截断。
      expect(resolveAgentMaxTokens('claude-sonnet-4-5'), 40000);
      expect(resolveAgentMaxTokens('claude-opus-4-5'), 40000);
    });

    test('低输出上限模型受模型自身约束，不越界', () {
      // 这批模型输出上限 32000，旧的固定 32768 已经越界。
      for (final model in const [
        'kimi-k2.6',
        'doubao-seed-2-0-pro-260215',
        'minimax-m3',
        'mimo-v2.5',
        'deepseek-v3-2',
      ]) {
        final resolved = resolveAgentMaxTokens(model);
        final cap = lookupCatalogLimit(model)!.output!;
        expect(resolved, lessThanOrEqualTo(cap), reason: model);
        expect(resolved, greaterThan(0), reason: model);
      }
    });

    test('目录内所有带 limit 的模型都不越界且留有上下文余量', () {
      for (final entry in modelsCatalog.entries) {
        final limit = entry.value.limit;
        if (limit == null) {
          continue;
        }
        final resolved = resolveAgentMaxTokens(entry.key);
        expect(resolved, greaterThan(0), reason: entry.key);
        final output = limit.output;
        if (output != null) {
          expect(resolved, lessThanOrEqualTo(output), reason: entry.key);
        }
        final context = limit.context;
        if (context != null) {
          // 压缩线之上必须仍能容下整个输出预算。
          expect(
            compactThresholdForContextLimit(context) + resolved,
            lessThanOrEqualTo(context),
            reason: entry.key,
          );
        }
      }
    });
  });
}
