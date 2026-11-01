// dart format width=80
// ignore_for_file: type=lint
part of 'ai_embedding_document_dao.dart';

mixin _$AiEmbeddingDocumentDaoMixin on DatabaseAccessor<NovelContentDatabase> {
  $AiEmbeddingDocumentsTable get aiEmbeddingDocuments =>
      attachedDatabase.aiEmbeddingDocuments;
  AiEmbeddingDocumentDaoManager get managers =>
      AiEmbeddingDocumentDaoManager(this);
}

class AiEmbeddingDocumentDaoManager {
  final _$AiEmbeddingDocumentDaoMixin _db;
  AiEmbeddingDocumentDaoManager(this._db);
  $$AiEmbeddingDocumentsTableTableManager get aiEmbeddingDocuments =>
      $$AiEmbeddingDocumentsTableTableManager(
        _db.attachedDatabase,
        _db.aiEmbeddingDocuments,
      );
}
