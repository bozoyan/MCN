// 职责: 解析技能广场链接目录并提供分类和关键词匹配。
// 关联文件:
//   lib/shared/services/agent_skill_catalog_service.dart
//   lib/shared/widgets/agent_skill/marketplace_browser.dart
import '../services/agent_skill_import_source.dart';

class MarketplaceAgentSkill {
  const MarketplaceAgentSkill({
    required this.name,
    required this.description,
    required this.url,
    this.whenToUse = '',
    this.category = '',
    this.tags = const [],
  });

  final String name;
  final String description;
  final String url;
  final String whenToUse;
  final String category;
  final List<String> tags;

  bool get canImport {
    try {
      AgentSkillImportSource.parse(url);
      return true;
    } on FormatException {
      return false;
    }
  }

  bool matches(String query) => [
    name,
    description,
    whenToUse,
    category,
    ...tags,
  ].any((text) => text.toLowerCase().contains(query.trim().toLowerCase()));

  static List<MarketplaceAgentSkill> parseCatalog(Object? data) {
    if (data is! List) {
      throw const FormatException('Skill catalog must be an array');
    }
    final urls = <String>{};
    return List.unmodifiable(
      data.map((item) {
        if (item is! Map<String, dynamic>) {
          throw const FormatException('Skill catalog entry must be an object');
        }
        String field(String key, {bool required = false}) {
          final value = item[key];
          if (!item.containsKey(key) && !required) {
            return '';
          }
          if (value is! String || (required && value.trim().isEmpty)) {
            throw FormatException('Invalid skill catalog field: $key');
          }
          return value.trim();
        }

        final url = field('url', required: true);
        final uri = Uri.tryParse(url);
        if (uri == null ||
            uri.scheme != 'https' ||
            uri.host.isEmpty ||
            uri.userInfo.isNotEmpty ||
            RegExp(r'[\x00-\x20\x7f]').hasMatch(url)) {
          throw const FormatException('Skill catalog URL must be public HTTPS');
        }
        if (!urls.add(url)) {
          throw FormatException('Duplicate skill catalog URL: $url');
        }
        final tags = item.containsKey('tags') ? item['tags'] : const <String>[];
        if (tags is! List || tags.any((tag) => tag is! String)) {
          throw const FormatException('Skill catalog tags must be strings');
        }
        return MarketplaceAgentSkill(
          name: field('name', required: true),
          description: field('description', required: true),
          url: url,
          whenToUse: field('when_to_use'),
          category: field('category'),
          tags: List.unmodifiable(tags.cast<String>()),
        );
      }),
    );
  }
}
