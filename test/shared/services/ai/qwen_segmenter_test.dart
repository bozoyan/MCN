// 职责: 验证 Qwen 章节分段辅助请求也遵循自定义 Chat Completions 地址。
// 关联文件:
//   lib/shared/services/ai/embedding.dart
//   lib/shared/services/novel_content.dart
//   lib/shared/models/ai_provider.dart

import 'dart:convert';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:reveric/shared/database/novel_content_database.dart';
import 'package:reveric/shared/models/ai_provider.dart';
import 'package:reveric/shared/services/ai/embedding.dart';
import 'package:reveric/shared/services/ai/prompt_template.dart';
import 'package:reveric/shared/services/novel_content.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(PromptTemplateService.loadAll);
  test('Qwen segmenter sends Chat Completions to configured prefix', () async {
    final db = NovelContentDatabase.forTest(NativeDatabase.memory());
    final content = NovelContentService(db);
    try {
      final chapter = await content.createChapter(
        siblingOrder: 1,
        title: 'chapter',
      );
      await content.updateChapterContent(
        chapterId: chapter,
        title: 'chapter',
        outline: '',
        content: 'A bird crosses the sky.',
      );
      final service = AiEmbeddingService(
        providerClient: null,
        config: aiProviderBuiltinById('openai')!.copyWith(
          type: 'qwen',
          baseUrl: 'https://custom.example/proxy/compatible-mode/v1',
          apiKey: 'mock-key',
        ),
        novelContentService: content,
        embeddingModel: 'embedding-fixture',
        segmenterModel: 'qwen3.8-flash',
      );
      var chatRequests = 0;
      await http.runWithClient(
        () => service.rebuildChapterEmbeddings(chapter),
        () => MockClient((request) async {
          expect(request.url.host, 'custom.example');
          expect(request.headers['Authorization'], 'Bearer mock-key');
          if (request.url.path.endsWith('/chat/completions')) {
            chatRequests++;
            expect(
              request.url.path,
              '/proxy/compatible-mode/v1/chat/completions',
            );
            return http.Response(
              jsonEncode({
                'choices': [
                  {
                    'message': {'content': '["A bird crosses the sky."]'},
                  },
                ],
              }),
              200,
            );
          }
          expect(request.url.path, '/proxy/compatible-mode/v1/embeddings');
          return http.Response('{"data":[{"embedding":[0.1,0.2]}]}', 200);
        }),
      );
      expect(chatRequests, 1);
    } finally {
      await db.close();
    }
  });
}
