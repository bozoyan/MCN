// 职责: AI 嵌入文档数据访问对象 — 封装所有 AI 嵌入文档相关的数据库操作
// 关联文件:
//   lib/shared/database/novel_content_database.dart

import 'package:drift/drift.dart';

import '../novel_content_database.dart';

part 'ai_embedding_document_dao.drift.dart';

@DriftAccessor(tables: [AiEmbeddingDocuments])
class AiEmbeddingDocumentDao extends DatabaseAccessor<NovelContentDatabase>
    with _$AiEmbeddingDocumentDaoMixin {
  AiEmbeddingDocumentDao(super.db);

  Future<List<AiEmbeddingDocument>> getAll() {
    return (select(aiEmbeddingDocuments)..orderBy([
          (table) => OrderingTerm(expression: table.sourceType),
          (table) => OrderingTerm(expression: table.sourceId),
          (table) => OrderingTerm(expression: table.chunkIndex),
        ]))
        .get();
  }

  Future<void> deleteBySource(String sourceId) {
    return (delete(
      aiEmbeddingDocuments,
    )..where((table) => table.sourceId.equals(sourceId))).go();
  }

  Future<void> replace({
    required String sourceId,
    required List<AiEmbeddingDocumentsCompanion> documents,
  }) async {
    await transaction(() async {
      await deleteBySource(sourceId);
      if (documents.isEmpty) return;
      await batch((batch) {
        batch.insertAll(aiEmbeddingDocuments, documents);
      });
    });
  }
}
