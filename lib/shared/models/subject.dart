// 职责: 定义可绑定照片的主体类型、选择列表信息与资料详情。
// 关联文件:
//   lib/shared/database/novel_content_database.dart
//   lib/shared/services/subjects.dart
//   lib/shared/widgets/subject_picker.dart
//   lib/shared/models/production/subject.dart
import '../database/novel_content_database.dart';
import '../utils/chapter_entity_recognition.dart';

enum SubjectKind { character, location, compendium }

/// 图鉴四类条目在 items 表中的 type。
const compendiumEntityTypes = {
  entityTypeItem,
  entityTypeCreature,
  entityTypeFaction,
  entityTypeSkill,
};

class Subject {
  const Subject({
    required this.id,
    required this.name,
    required this.photos,
    this.aliases = const [],
    this.avatarAssetId,
    this.category,
  });

  final String id;
  final String name;
  final List<SubjectPhoto> photos;
  final List<String> aliases;
  final String? avatarAssetId;

  /// 图鉴条目的 items.type，供选择弹窗按类型筛选；人物和地点为 null。
  final String? category;

  bool matches(String query) =>
      name.toLowerCase().contains(query) ||
      aliases.any((alias) => alias.toLowerCase().contains(query));
}

/// 资料详情里展示的字段，界面按字段决定文案。
enum SubjectField {
  identity,
  age,
  appearance,
  description,
  personality,
  motivation,
  arc,
  biography,
  currentState,
  category,
  content,
}

/// 主体资料：卡片头部信息、非空字段（按展示顺序）和照片。
class SubjectProfile {
  const SubjectProfile({
    required this.entity,
    required this.fields,
    required this.photos,
  });

  final ChapterEntityMention entity;
  final List<(SubjectField, String)> fields;
  final List<SubjectPhoto> photos;
}
