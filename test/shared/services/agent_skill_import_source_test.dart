// 职责: 验证技能仓库链接解析、编码及不支持来源的拒绝行为。
// 关联文件:
//   lib/shared/services/agent_skill_import_source.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/services/agent_skill_import_source.dart';

void main() {
  test('GitHub shorthand, URL and clone URL use the default branch', () {
    for (final input in [
      'owner/repo',
      'github.com/owner/repo',
      'https://github.com/owner/repo.git/',
    ]) {
      final source = AgentSkillImportSource.parse(input);
      expect(source.project, 'owner/repo');
      expect(source.revisionPath, isEmpty);
      expect(
        source.archiveUri(null).toString(),
        'https://api.github.com/repos/owner/repo/zipball',
      );
    }
  });

  test('GitLab subgroups and slash-containing refs remain encoded once', () {
    final source = AgentSkillImportSource.parse(
      'https://gitlab.com/group/sub/repo/-/tree/feature%2Ftopic/skills/中文?ref_type=heads',
    );
    expect(source.project, 'group/sub/repo');
    expect(source.revisionPath, ['feature/topic', 'skills', '中文']);
    expect(
      source.archiveUri('feature/topic').toString(),
      'https://gitlab.com/api/v4/projects/group%2Fsub%2Frepo/repository/archive.zip?sha=feature%2Ftopic',
    );
    expect(
      source.revisionUri('feature/topic').pathSegments.last,
      'feature/topic',
    );
    expect(
      source.revisionUri('feature/topic').toString(),
      isNot(contains('%25')),
    );
  });

  test('supported file and raw URLs preserve the selected skill', () {
    for (final url in [
      'https://github.com/a/b/blob/main/skills/x/SKILL.md',
      'https://raw.githubusercontent.com/a/b/main/skills/x/SKILL.md',
      'https://gitlab.com/a/b/-/blob/main/skills/x/SKILL.md',
      'https://gitlab.com/a/b/-/raw/main/skills/x/SKILL.md',
      'https://gitee.com/a/b/blob/main/skills/x/SKILL.md',
      'https://gitee.com/a/b/raw/main/skills/x/SKILL.md',
      'https://gitcode.com/a/b/blob/main/skills/x/SKILL.md',
      'https://gitcode.com/a/b/-/blob/main/skills/x/SKILL.md',
      'https://gitcode.com/a/b/raw/main/skills/x/SKILL.md',
    ]) {
      final source = AgentSkillImportSource.parse(url);
      expect(source.singleFile, isTrue);
      expect(source.revisionPath, ['main', 'skills', 'x', 'SKILL.md']);
    }
  });

  test('Gitee resolves default branch and uses anonymous tree and blob APIs', () {
    final source = AgentSkillImportSource.parse('gitee.com/owner/skills.git');
    expect(source.host, 'gitee.com');
    expect(source.project, 'owner/skills');
    expect(
      source.defaultBranchUri.toString(),
      'https://gitee.com/api/v5/repos/owner/skills',
    );
    expect(
      source.treeUri('release/topic').toString(),
      'https://gitee.com/api/v5/repos/owner/skills/git/trees/release%2Ftopic?recursive=1',
    );
    expect(
      source.blobUri('abc').toString(),
      'https://gitee.com/api/v5/repos/owner/skills/git/blobs/abc',
    );
    expect(
      source.revisionUri('release/topic').toString(),
      'https://gitee.com/api/v5/repos/owner/skills/commits/release%2Ftopic',
    );
  });

  test('GitCode uses its anonymous website endpoints and HEAD default', () {
    final source = AgentSkillImportSource.parse('gitcode.com/owner/skills.git');
    expect(source.host, 'gitcode.com');
    expect(source.defaultBranchUri, isNull);
    expect(
      source.archiveUri(null).toString(),
      'https://raw.gitcode.com/owner/skills/archive/refs/heads/HEAD.zip',
    );
    expect(
      source.archiveUri('abcdef').toString(),
      'https://raw.gitcode.com/owner/skills/archive/refs/heads/abcdef.zip',
    );
    expect(
      source.revisionUri('release/topic').toString(),
      'https://web-api.gitcode.com/api/v2/projects/owner%2Fskills/repository/commits/release%2Ftopic',
    );
    expect(source.revisionResponseKey, 'id');
  });

  test('new hosts preserve branch and directory paths', () {
    for (final host in ['gitee.com', 'gitcode.com']) {
      final source = AgentSkillImportSource.parse(
        'https://$host/owner/repo/tree/release%2Ftopic/skills/中文',
      );
      expect(source.revisionPath, ['release/topic', 'skills', '中文']);
      expect(source.singleFile, isFalse);
      expect(source.host, host);
    }
  });

  test('GitLab repository URL supports nested namespaces and .git', () {
    final source = AgentSkillImportSource.parse(
      'https://gitlab.com/a/sub/b.git',
    );
    expect(source.project, 'a/sub/b');
    expect(source.revisionPath, isEmpty);
  });

  test('rejects credentials, other hosts, unsupported pages and traversal', () {
    for (final value in [
      '',
      'https://example.com/a/b',
      'http://github.com/a/b',
      'https://token@github.com/a/b',
      'https://github.com:123/a/b',
      'https://github.com/a/b/issues/1',
      'https://github.com/a/b/tree/',
      'https://github.com/a/b/blob/main/README.md',
      'https://github.com/a/b/tree/main/%2e%2e/private',
      'https://github.com/a%2Fb/repo',
      'https://gitcode.com/a/b/-/',
      'https://gitee.com/a/b/issues/1',
      'https://gitcode.com/a/b/tree/main/%2e%2e/private',
      'https://gitee.com.evil.example/a/b',
    ]) {
      expect(
        () => AgentSkillImportSource.parse(value),
        throwsFormatException,
        reason: value,
      );
    }
  });
}
