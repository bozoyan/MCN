// 职责: 测试 AgentSkillTransferService 的导出（skill 目录/ZIP）与扫描发现。
//   导入写入依赖 InstalledAgentSkillsNotifier，此处覆盖纯 I/O 与解析路径。
// 关联文件:
//   lib/shared/services/agent_skill_transfer.dart
//   lib/shared/services/agent_skill_import_parser.dart
//   lib/shared/models/novel_agent_skill.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/models/novel_agent_skill.dart';
import 'package:reveric/shared/services/agent_skill_import_parser.dart';
import 'package:reveric/shared/services/agent_skill_transfer.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('agent_skill_transfer_test_');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  NovelAgentSkillModel makeEntry({
    required String name,
    String description = 'desc',
    String prompt = 'prompt body',
    String category = '',
    List<String> tags = const [],
  }) {
    return NovelAgentSkillModel(
      id: 'id_$name',
      sourceKind: AgentSkillSourceKind.novelLocal,
      name: name,
      description: description,
      prompt: prompt,
      category: category,
      tags: tags,
      createdAt: DateTime(2025, 1, 1),
      updatedAt: DateTime(2025, 1, 1),
    );
  }

  group('exportToDirectory', () {
    test('writes skill-name/SKILL.md layout', () async {
      final entries = [
        makeEntry(name: '扩写场景', category: '扩写', tags: ['节奏']),
        makeEntry(name: '爽文节奏', category: '节奏'),
      ];
      final service = const AgentSkillTransferService();

      final paths = await service.exportToDirectory(
        dirPath: tempDir.path,
        entries: entries,
      );

      expect(paths.length, 2);
      for (final path in paths) {
        expect(p.basename(path), 'SKILL.md');
        expect(File(path).existsSync(), isTrue);
        final parsed = AgentSkillImportParser.parse(
          File(path).readAsStringSync(),
        );
        expect(parsed, isNotNull, reason: '$path should be parseable');
      }

      expect(
        paths.any((path) => path.contains('${p.separator}扩写场景${p.separator}')),
        isTrue,
      );
    });

    test('handles duplicate names with suffix dirs', () async {
      final entries = [makeEntry(name: '同名技能'), makeEntry(name: '同名技能')];
      final service = const AgentSkillTransferService();

      final paths = await service.exportToDirectory(
        dirPath: tempDir.path,
        entries: entries,
      );

      expect(paths.length, 2);
      expect(p.basename(p.dirname(paths[0])), '同名技能');
      expect(p.basename(p.dirname(paths[1])), '同名技能 (2)');
    });

    test('sanitizes illegal directory characters', () async {
      final entries = [makeEntry(name: 'a/b:c*d?e')];
      final service = const AgentSkillTransferService();

      final paths = await service.exportToDirectory(
        dirPath: tempDir.path,
        entries: entries,
      );

      final dirName = p.basename(p.dirname(paths[0]));
      expect(dirName, isNot(contains('/')));
      expect(dirName, isNot(contains(':')));
      expect(dirName, isNot(contains('*')));
      expect(dirName, isNot(contains('?')));
    });

    test('creates directory if not exists', () async {
      final subDir = p.join(tempDir.path, 'nested', 'deep');
      final entries = [makeEntry(name: 'test')];
      final service = const AgentSkillTransferService();

      final paths = await service.exportToDirectory(
        dirPath: subDir,
        entries: entries,
      );

      expect(File(paths[0]).existsSync(), isTrue);
    });
  });

  group('exportToZip', () {
    test('writes a valid zip containing all entries', () async {
      final entries = [
        makeEntry(name: '技能A', category: '扩写', tags: ['x']),
        makeEntry(name: '技能B'),
      ];
      final zipPath = p.join(tempDir.path, 'export.zip');
      final service = const AgentSkillTransferService();

      final result = await service.exportToZip(
        zipPath: zipPath,
        entries: entries,
      );

      expect(result, zipPath);
      expect(File(zipPath).existsSync(), isTrue);
      expect(File(zipPath).lengthSync(), greaterThan(0));
    });
  });

  group('discoverInDirectory', () {
    test('finds nested SKILL.md and marks name conflicts', () {
      final skillDir = Directory(p.join(tempDir.path, '扩写场景'))..createSync();
      File(p.join(skillDir.path, 'SKILL.md')).writeAsStringSync(
        AgentSkillImportParser.write(
          name: '扩写场景',
          description: 'desc',
          body: 'body',
          category: '扩写',
        ),
      );
      // Nested reference.md should be ignored.
      File(p.join(skillDir.path, 'notes.md')).writeAsStringSync('# notes');

      final service = const AgentSkillTransferService();
      final candidates = service.discoverInDirectory(
        dirPath: tempDir.path,
        existing: [makeEntry(name: '扩写场景')],
      );

      expect(candidates.length, 1);
      expect(candidates.first.name, '扩写场景');
      expect(candidates.first.nameConflict, isTrue);
      expect(candidates.first.category, '扩写');
    });
  });

  group('discoverFromFiles', () {
    test('parses a single selected markdown file', () {
      final file = File(p.join(tempDir.path, 'legacy.md'))
        ..writeAsStringSync(
          AgentSkillImportParser.write(
            name: '单文件技能',
            description: 'd',
            body: 'b',
          ),
        );

      final service = const AgentSkillTransferService();
      final candidates = service.discoverFromFiles(
        filePaths: [file.path],
        existing: const [],
      );

      expect(candidates.length, 1);
      expect(candidates.first.name, '单文件技能');
      expect(candidates.first.nameConflict, isFalse);
    });
  });

  group('round-trip export -> parse', () {
    test('exported SKILL.md can be re-parsed with all fields', () async {
      final entries = [
        makeEntry(
          name: '完整技能',
          description: '完整描述',
          prompt: '# 指令\n详细步骤...',
          category: '扩写',
          tags: ['节奏', '爽文'],
        ),
      ];
      final service = const AgentSkillTransferService();

      final paths = await service.exportToDirectory(
        dirPath: tempDir.path,
        entries: entries,
      );

      final content = File(paths[0]).readAsStringSync();
      final parsed = AgentSkillImportParser.parse(content)!;

      expect(p.basename(paths[0]), 'SKILL.md');
      expect(parsed.name, '完整技能');
      expect(parsed.description, '完整描述');
      expect(parsed.body, '# 指令\n详细步骤...');
      expect(parsed.category, '扩写');
      expect(parsed.tags, ['节奏', '爽文']);
    });
  });
}
