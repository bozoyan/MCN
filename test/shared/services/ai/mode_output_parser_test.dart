// 职责: 验证 AI 模式分段输出解析 — 小剧场/独白流式中途不露格式标记，议会总结按小节取条目。
// 关联文件:
//   lib/shared/services/ai/mode_output_parser.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/services/ai/mode_output_parser.dart';

void main() {
  group('parseTheaterOutput partial', () {
    test('hides tags before the dialogue section starts', () {
      final r = parseTheaterOutput('【对象】\n萧炎\n\n【舞台', partial: true);
      expect(r.dialogue, isEmpty);
      expect(r.stageDirection, isNull);
      expect(r.addressee, '萧炎');
    });

    test('shows stage direction and growing dialogue', () {
      final r = parseTheaterOutput(
        '【对象】\n无\n\n【舞台指示】\n按住剑柄\n\n【台词】\n你来晚',
        partial: true,
      );
      expect(r.addressee, isNull);
      expect(r.stageDirection, '按住剑柄');
      expect(r.dialogue, '你来晚');
    });

    test('untagged output streams as-is', () {
      expect(parseTheaterOutput('你来晚了', partial: true).dialogue, '你来晚了');
    });
  });

  test('final theater output falls back to raw text without tags', () {
    final r = parseTheaterOutput('【舞台指示】\n无\n\n【台词】\n熄灯。');
    expect(r.stageDirection, isNull);
    expect(r.dialogue, '熄灯。');
    expect(parseTheaterOutput('只说了一句').dialogue, '只说了一句');
  });

  group('parseMonologueOutput', () {
    test('partial hides the half-written header', () {
      final r = parseMonologueOutput('【内心', partial: true);
      expect(r.innerThoughts, isEmpty);
      expect(r.plannedActions, isEmpty);
    });

    test('splits both sections', () {
      final r = parseMonologueOutput('【内心活动】\n不能退\n【接下来的行动】\n拔剑');
      expect(r.innerThoughts, '不能退');
      expect(r.plannedActions, '拔剑');
    });
  });

  group('parseCouncilSummary', () {
    test('collects top-level items of the template sections', () {
      final r = parseCouncilSummary('''
## 共识要点
- 开篇保留悬念（剧情架构师）
- 建议加快节奏（节奏专家）

## 关键分歧
- 是否提前揭示身份
  - 观点A（人物分析师）：提前

## 待决事项
- 主角动机何时交代

## 下一步行动
1. 改写第一章结尾
2、补一场配角戏
''');
      // 「建议」出现在条目里不再被当成小节标题。
      expect(r.keyPoints, ['开篇保留悬念（剧情架构师）', '建议加快节奏（节奏专家）']);
      expect(r.openQuestions, ['主角动机何时交代']);
      expect(r.actionItems, ['改写第一章结尾', '补一场配角戏']);
    });

    test('returns empty lists without the expected headings', () {
      final r = parseCouncilSummary('核心要点：\n- 旧格式');
      expect(r.keyPoints, isEmpty);
      expect(r.actionItems, isEmpty);
    });
  });

  group('parseCouncilOutput', () {
    test('strips the trailing addressee line', () {
      final r = parseCouncilOutput('判断：延后揭示\n\n【请回应】人物分析师');
      expect(r.content, '判断：延后揭示');
      expect(r.addressee, '人物分析师');
    });

    test('partial output hides a half-written tag', () {
      expect(parseCouncilOutput('判断：延后\n【请回', partial: true).content, '判断：延后');
      expect(parseCouncilOutput('判断：延后').addressee, isNull);
    });
  });
}
