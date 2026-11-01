// 职责: 解析公开 GitHub / GitLab / Gitee / GitCode 技能仓库、目录和 SKILL.md 链接。
// 关联文件:
//   lib/shared/services/agent_skill_import_orchestrator.dart
//   lib/shared/widgets/agent_skill_import_source_form.dart

class AgentSkillImportSource {
  const AgentSkillImportSource._({
    required this.host,
    required this.project,
    required this.revisionPath,
    required this.singleFile,
  });

  final String host;
  final String project;
  // 浏览器链接中的 ref 可能包含斜线，由下载阶段向仓库确认边界。
  final List<String> revisionPath;
  final bool singleFile;

  static const supportedHosts = {
    'github.com',
    'gitlab.com',
    'gitee.com',
    'gitcode.com',
  };

  String get revisionResponseKey =>
      host == 'gitlab.com' || host == 'gitcode.com' ? 'id' : 'sha';

  Uri? get defaultBranchUri =>
      host == 'gitee.com' ? Uri.https(host, '/api/v5/repos/$project') : null;

  static AgentSkillImportSource parse(String input) {
    var value = input.trim();
    if (RegExp(r'^[\w.-]+/[\w.-]+$').hasMatch(value)) {
      value = 'https://github.com/$value';
    } else if (supportedHosts.any((host) => value.startsWith('$host/'))) {
      value = 'https://$value';
    }
    // Uri 会规范化点路径，必须在解析之前拒绝其原始输入。
    if (RegExp(r'%(?![a-fA-F0-9]{2})').hasMatch(value)) {
      throw const FormatException('Invalid URL encoding');
    }
    final decodedPath = value
        .split(RegExp(r'[?#]'))
        .first
        .replaceAllMapped(
          RegExp(r'%([a-fA-F0-9]{2})'),
          (match) => String.fromCharCode(int.parse(match[1]!, radix: 16)),
        );
    if (decodedPath.split('/').any((part) => part == '.' || part == '..') ||
        decodedPath.contains('\\') ||
        decodedPath.contains('\u0000')) {
      throw const FormatException('Invalid repository path');
    }
    final uri = Uri.tryParse(value);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.userInfo.isNotEmpty ||
        (uri.hasPort && uri.port != 443) ||
        !{...supportedHosts, 'raw.githubusercontent.com'}.contains(uri.host)) {
      throw const FormatException(
        'Expected a supported public repository HTTPS URL',
      );
    }
    final parts = uri.pathSegments.toList();
    if (parts.isNotEmpty && parts.last.isEmpty) {
      parts.removeLast();
    }
    if (parts.length < 2 ||
        parts.any(
          (part) =>
              part.isEmpty ||
              part == '.' ||
              part == '..' ||
              part.contains('\\') ||
              part.contains('\u0000'),
        )) {
      throw const FormatException('Invalid repository path');
    }
    final gitlab = uri.host == 'gitlab.com';
    final raw = uri.host == 'raw.githubusercontent.com';
    final marker = gitlab ? parts.indexOf('-') : 2;
    final projectEnd = gitlab ? (marker < 0 ? parts.length : marker) : 2;
    if (projectEnd < 2) {
      throw const FormatException('Invalid repository path');
    }
    final projectParts = parts.take(projectEnd).toList();
    projectParts[projectParts.length - 1] = projectParts.last.replaceFirst(
      RegExp(r'\.git$'),
      '',
    );
    if (projectParts.any((part) => part.isEmpty || part.contains('/'))) {
      throw const FormatException('Invalid repository path');
    }
    var revisionPath = <String>[];
    var singleFile = raw;
    if (raw) {
      revisionPath = parts.skip(2).toList();
    } else if (parts.length > projectEnd) {
      final actionIndex =
          gitlab || (uri.host == 'gitcode.com' && parts[2] == '-')
          ? (gitlab ? marker + 1 : 3)
          : 2;
      if (parts.length <= actionIndex + 1 ||
          !{'tree', 'blob', 'raw'}.contains(parts[actionIndex])) {
        throw const FormatException(
          'Expected a repository, directory or SKILL.md URL',
        );
      }
      singleFile = parts[actionIndex] != 'tree';
      revisionPath = parts.skip(actionIndex + 1).toList();
    }
    if (singleFile &&
        (revisionPath.length < 2 ||
            revisionPath.last.toLowerCase() != 'skill.md')) {
      throw const FormatException('Expected a SKILL.md file URL');
    }
    if (revisionPath.length > 24) {
      throw const FormatException('Repository path is too deep');
    }
    return AgentSkillImportSource._(
      host: raw ? 'github.com' : uri.host,
      project: projectParts.join('/'),
      revisionPath: revisionPath,
      singleFile: singleFile,
    );
  }

  Uri archiveUri(String? ref) {
    return switch (host) {
      'github.com' => Uri(
        scheme: 'https',
        host: 'api.github.com',
        pathSegments: ['repos', ...project.split('/'), 'zipball', ?ref],
      ),
      'gitlab.com' => Uri(
        scheme: 'https',
        host: host,
        pathSegments: [
          'api',
          'v4',
          'projects',
          project,
          'repository',
          'archive.zip',
        ],
        queryParameters: ref == null ? null : {'sha': ref},
      ),
      // 与网页下载按钮一致；HEAD 使用仓库默认分支，commit SHA 固定扫描快照。
      'gitcode.com' => Uri(
        scheme: 'https',
        host: 'raw.gitcode.com',
        pathSegments: [
          ...project.split('/'),
          'archive',
          'refs',
          'heads',
          '${ref ?? 'HEAD'}.zip',
        ],
      ),
      _ => throw StateError('Archive requires a resolved repository revision'),
    };
  }

  bool get usesFileApi => host == 'gitee.com';

  Uri treeUri(String ref) => Uri(
    scheme: 'https',
    host: host,
    pathSegments: [
      'api',
      'v5',
      'repos',
      ...project.split('/'),
      'git',
      'trees',
      ref,
    ],
    queryParameters: {'recursive': '1'},
  );

  Uri blobUri(String sha) => Uri(
    scheme: 'https',
    host: host,
    pathSegments: [
      'api',
      'v5',
      'repos',
      ...project.split('/'),
      'git',
      'blobs',
      sha,
    ],
  );

  Uri revisionUri(String ref) => switch (host) {
    'github.com' => Uri(
      scheme: 'https',
      host: 'api.github.com',
      pathSegments: ['repos', ...project.split('/'), 'commits', ref],
    ),
    'gitlab.com' => Uri(
      scheme: 'https',
      host: host,
      pathSegments: [
        'api',
        'v4',
        'projects',
        project,
        'repository',
        'commits',
        ref,
      ],
    ),
    'gitcode.com' => Uri(
      scheme: 'https',
      host: 'web-api.gitcode.com',
      pathSegments: [
        'api',
        'v2',
        'projects',
        project,
        'repository',
        'commits',
        ref,
      ],
    ),
    'gitee.com' => Uri(
      scheme: 'https',
      host: host,
      pathSegments: [
        'api',
        'v5',
        'repos',
        ...project.split('/'),
        'commits',
        ref,
      ],
    ),
    _ => throw StateError('Unsupported repository host'),
  };
}
