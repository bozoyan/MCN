// 职责: 为聊天测试构造完整作品输入，避免依赖真实书库或重复列出无关字段。
// 关联文件:
//   lib/shared/database/app_database.dart
//   lib/shared/models/content_kind.dart

import 'package:reveric/shared/database/app_database.dart';
import 'package:reveric/shared/models/content_kind.dart';
import 'package:reveric/shared/models/novel_type.dart';

Novel buildTestNovel({
  String id = 'test_work',
  String title = 'Test Novel',
  String type = novelTypeOriginal,
  String contentKind = contentKindNovel,
  String? sourceNovelId,
  String? databasePath,
  bool draft = false,
}) => Novel(
  id: id,
  title: title,
  authorName: '',
  description: '',
  status: 'draft',
  type: type,
  contentKind: contentKind,
  sourceNovelId: sourceNovelId,
  contentDatabasePath: databasePath,
  wordCount: 0,
  category: '',
  tags: const [],
  draft: draft,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  deletedAt: notDeletedSentinel,
);
