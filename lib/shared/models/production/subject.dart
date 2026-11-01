// 职责: 判断制作片段绑定的主体类型。
// 关联文件:
//   lib/shared/models/subject.dart
//   lib/shared/database/novel_content_database.dart
//   lib/shared/services/production/canvas_service.dart
import '../../database/novel_content_database.dart';
import '../subject.dart';

extension ProductionClipSubject on ProductionClipRow {
  SubjectKind? get subjectKind => characterId != null
      ? SubjectKind.character
      : locationId != null
      ? SubjectKind.location
      : itemId != null
      ? SubjectKind.compendium
      : null;

  String? get subjectId => characterId ?? locationId ?? itemId;

  bool get hasSubject => subjectKind != null;
}
