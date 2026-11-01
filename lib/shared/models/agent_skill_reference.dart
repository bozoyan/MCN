// 职责: AgentSkill references 附件模型与路径校验 — 相对 skill root 存储，
//   供 agent-skills Reference CRUD 与导入导出使用。
// 关联文件:
//   lib/shared/models/novel_agent_skill.dart
//   lib/shared/models/agent_skill.dart
//   lib/shared/database/app_database.dart
//   lib/shared/services/ai/agent_skills_run_command_handler.dart
// 遵循的 Rules:
//   .agents/rules/enum-naming.md

import 'dart:convert';

/// 单个 references 文件（相对 skill root，如 `references/forms.md`）。
class AgentSkillReferenceFile {
  const AgentSkillReferenceFile({required this.path, required this.content});

  /// 相对 skill root 的路径，必须以 `references/` 开头。
  final String path;
  final String content;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'path': path,
    'content': content,
  };

  factory AgentSkillReferenceFile.fromJson(Map<String, dynamic> json) {
    return AgentSkillReferenceFile(
      path: (json['path'] ?? '').toString(),
      content: (json['content'] ?? '').toString(),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is AgentSkillReferenceFile &&
        other.path == path &&
        other.content == content;
  }

  @override
  int get hashCode => Object.hash(path, content);
}

/// references 清单项。运行时构建 `<skill_resources>` 只需要路径，不预读正文。
class AgentSkillReferenceDescriptor {
  const AgentSkillReferenceDescriptor({
    required this.path,
    this.byteSize,
    this.sha256,
  });

  final String path;
  final int? byteSize;
  final String? sha256;
}

/// AgentSkill references 校验约定。
abstract final class AgentSkillReferences {
  static const relativeDir = 'references';
  static const relativeDirPrefix = 'references/';
  static const maxCount = 128;
  static const maxContentBytes = 64 * 1024;
  static const maxTotalContentBytes = 1024 * 1024;

  static const allowedExtensions = <String>{
    '.md',
    '.txt',
    '.json',
    '.yaml',
    '.yml',
    '.csv',
    '.xml',
  };

  /// 相对路径是否合法：`references/**`，无 `..`、隐藏路径或空目录段。
  static bool isValidRelativePath(String path) {
    final normalized = path.trim().replaceAll('\\', '/');
    if (!normalized.startsWith(relativeDirPrefix)) {
      return false;
    }
    if (normalized.contains('//')) {
      return false;
    }
    final segments = normalized.substring(relativeDirPrefix.length).split('/');
    if (segments.isEmpty || segments.any((segment) => segment.isEmpty)) {
      return false;
    }
    if (segments.any(
      (segment) => segment == '.' || segment == '..' || segment.startsWith('.'),
    )) {
      return false;
    }
    final rest = segments.last;
    final dot = rest.lastIndexOf('.');
    if (dot <= 0) {
      return false;
    }
    final ext = rest.substring(dot).toLowerCase();
    return allowedExtensions.contains(ext);
  }

  /// 规范化并校验列表；非法项抛 [FormatException]。
  static List<AgentSkillReferenceFile> normalizeOrThrow(
    Iterable<AgentSkillReferenceFile> files,
  ) {
    final seen = <String>{};
    final out = <AgentSkillReferenceFile>[];
    var totalBytes = 0;
    for (final file in files) {
      final path = file.path.trim().replaceAll('\\', '/');
      if (!isValidRelativePath(path)) {
        throw FormatException('Invalid agent skill reference path: $path');
      }
      if (seen.contains(path)) {
        throw FormatException('Duplicate agent skill reference path: $path');
      }
      final content = file.content;
      final contentBytes = _utf8ByteLength(content);
      if (contentBytes > maxContentBytes) {
        throw FormatException(
          'Agent skill reference exceeds $maxContentBytes bytes: $path',
        );
      }
      if (totalBytes + contentBytes > maxTotalContentBytes) {
        throw FormatException(
          'Agent skill references exceed total max bytes of '
          '$maxTotalContentBytes',
        );
      }
      seen.add(path);
      out.add(AgentSkillReferenceFile(path: path, content: content));
      totalBytes += contentBytes;
      if (out.length > maxCount) {
        throw FormatException(
          'Agent skill references exceed max count of $maxCount',
        );
      }
    }
    out.sort((a, b) => a.path.compareTo(b.path));
    return List<AgentSkillReferenceFile>.unmodifiable(out);
  }

  /// 宽松解析（DB / import）：丢弃非法、重复、超限项，不截断用户文件。
  static List<AgentSkillReferenceFile> sanitize(
    Iterable<AgentSkillReferenceFile> files,
  ) {
    final seen = <String>{};
    final out = <AgentSkillReferenceFile>[];
    var totalBytes = 0;
    for (final file in files) {
      if (out.length >= maxCount) {
        break;
      }
      final path = file.path.trim().replaceAll('\\', '/');
      if (!isValidRelativePath(path) || seen.contains(path)) {
        continue;
      }
      final content = file.content;
      final contentBytes = _utf8ByteLength(content);
      if (contentBytes > maxContentBytes ||
          totalBytes + contentBytes > maxTotalContentBytes) {
        continue;
      }
      seen.add(path);
      out.add(AgentSkillReferenceFile(path: path, content: content));
      totalBytes += contentBytes;
    }
    out.sort((a, b) => a.path.compareTo(b.path));
    return List<AgentSkillReferenceFile>.unmodifiable(out);
  }

  static int _utf8ByteLength(String value) => utf8.encode(value).length;
}
