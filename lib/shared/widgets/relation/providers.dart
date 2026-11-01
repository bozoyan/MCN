// 职责: 按关系 ID 订阅详情、当前摘要和可用证据位置。
// 关联文件:
//   lib/shared/entity_graph/providers.dart
//   lib/shared/providers/novel_providers.dart
//   lib/shared/widgets/relation/detail.dart
//   lib/shared/widgets/relation/history.dart
// 遵循的 Rules:
//   .agents/rules/state-management.md
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../database/novel_content_database.dart';
import '../../entity_graph/providers.dart';
import '../../providers/novel_providers.dart';

final relationDetailProvider = StreamProvider.autoDispose
    .family<EntityRelation?, (String, String)>(
      (ref, key) => ref
          .watch(entityRelationsServiceProvider(key.$1))
          .watchRelationById(key.$2),
    );
final relationCurrentProvider = StreamProvider.autoDispose
    .family<RelationSummary?, (String, String)>(
      (ref, key) => ref
          .watch(entityRelationsServiceProvider(key.$1))
          .watchRelationSummaryById(key.$2),
    );

class RelationEvidenceChoice {
  const RelationEvidenceChoice(this.kind, this.id, this.title);
  final String kind;
  final String id;
  final String title;
  String get key => '$kind:$id';
}

typedef RelationEvidenceNavigation = void Function(String kind, String id);

final relationEvidenceChoicesProvider = StreamProvider.autoDispose
    .family<List<RelationEvidenceChoice>, String>((ref, path) {
      final db = ref.watch(novelContentDatabaseProvider(path));
      return db
          .customSelect(
            "SELECT 'chapter' kind, id, COALESCE(title, '') title FROM chapter_nodes WHERE deleted_at = 0 AND type IN ('chapter','extra') UNION ALL SELECT 'scene' kind, id, title FROM screenplay_scenes WHERE deleted_at = 0",
            readsFrom: {db.chapters, db.screenplayScenes},
          )
          .watch()
          .map(
            (rows) => rows
                .map(
                  (r) => RelationEvidenceChoice(
                    r.read<String>('kind'),
                    r.read<String>('id'),
                    r.read<String>('title'),
                  ),
                )
                .toList(),
          );
    });
