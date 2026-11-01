// 职责: 测试「本轮使用的 slash chip（skill / subagent）名」在用户消息 metadata 中的编解码 — 只记录 slash chip，缺省/脏数据安全回退。
// 关联文件:
//   lib/shared/models/queued_chat_message.dart
//   lib/shared/models/novel_workspace.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/models/novel_workspace.dart';
import 'package:reveric/shared/models/queued_chat_message.dart';

void main() {
  group('slashChipsMetadataFromReferences', () {
    test('returns null when no slash chip is attached', () {
      expect(slashChipsMetadataFromReferences(const []), isNull);
      expect(
        slashChipsMetadataFromReferences(const [
          AiContextReference(
            section: NovelWorkspaceSection.chapters,
            itemId: 'ch1',
            label: 'Chapter 1',
          ),
        ]),
        isNull,
      );
    });

    test('collects skill and subagent chip labels, trimmed and non-empty', () {
      final metadata = slashChipsMetadataFromReferences(const [
        AiContextReference(
          section: NovelWorkspaceSection.overview,
          itemId: 'skill_1',
          label: ' 正文写手 ',
          kind: AiContextReferenceKind.skill,
        ),
        AiContextReference(
          section: NovelWorkspaceSection.overview,
          itemId: 'skill_2',
          label: '   ',
          kind: AiContextReferenceKind.skill,
        ),
        AiContextReference(
          section: NovelWorkspaceSection.overview,
          itemId: 'agent_1',
          label: '剧情顾问',
          kind: AiContextReferenceKind.subagent,
        ),
        AiContextReference(
          section: NovelWorkspaceSection.chapters,
          itemId: 'ch1',
          label: 'Chapter 1',
        ),
      ]);

      expect(metadata, isNotNull);
      expect(metadata![kAiMessageSkillNamesKey], ['正文写手']);
      expect(metadata[kAiMessageSubagentNamesKey], ['剧情顾问']);
    });

    test('omits empty categories from metadata', () {
      final metadata = slashChipsMetadataFromReferences(const [
        AiContextReference(
          section: NovelWorkspaceSection.overview,
          itemId: 'agent_1',
          label: '剧情顾问',
          kind: AiContextReferenceKind.subagent,
        ),
      ]);

      expect(metadata, isNotNull);
      expect(metadata!.containsKey(kAiMessageSkillNamesKey), isFalse);
      expect(metadata[kAiMessageSubagentNamesKey], ['剧情顾问']);
    });
  });

  group('namesFromMessageMetadata', () {
    test('round-trips names written by slashChipsMetadataFromReferences', () {
      final metadata = slashChipsMetadataFromReferences(const [
        AiContextReference(
          section: NovelWorkspaceSection.overview,
          itemId: 'skill_1',
          label: '正文写手',
          kind: AiContextReferenceKind.skill,
        ),
        AiContextReference(
          section: NovelWorkspaceSection.overview,
          itemId: 'agent_1',
          label: '剧情顾问',
          kind: AiContextReferenceKind.subagent,
        ),
      ]);

      expect(skillNamesFromMessageMetadata(metadata), ['正文写手']);
      expect(subagentNamesFromMessageMetadata(metadata), ['剧情顾问']);
    });

    test('returns empty list for missing or malformed metadata', () {
      expect(skillNamesFromMessageMetadata(null), isEmpty);
      expect(subagentNamesFromMessageMetadata(null), isEmpty);
      expect(skillNamesFromMessageMetadata(const {}), isEmpty);
      expect(
        skillNamesFromMessageMetadata(const {'skill_names': 'not-a-list'}),
        isEmpty,
      );
      expect(
        subagentNamesFromMessageMetadata(const {'subagent_names': 42}),
        isEmpty,
      );
      expect(
        skillNamesFromMessageMetadata(const {
          'skill_names': ['正文写手', 42, '  ', null],
        }),
        ['正文写手'],
      );
    });
  });
}
