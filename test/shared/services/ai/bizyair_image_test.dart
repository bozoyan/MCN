// 职责: 验证 BizyAir 两种供应商类型、渠道清单与 modelzoo / webapp 出图提交与轮询解析。
// 关联文件:
//   lib/shared/services/ai/image/bizyair.dart
//   lib/shared/models/image/channels.dart
//   lib/shared/models/ai_provider.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:reveric/shared/models/ai_provider.dart';
import 'package:reveric/shared/models/image/channels.dart';
import 'package:reveric/shared/services/ai/image/bizyair.dart';
import 'package:reveric/shared/services/ai/image/client.dart';
import 'package:reveric/shared/utils/storage_paths.dart';

const _png =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAACklEQVR4nGMAAQAABQABDQottAAAAABJRU5ErkJggg==';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempSupport;

  // 出图结果落盘依赖 RevericPaths，未初始化会抛错。
  setUp(() async {
    tempSupport = await Directory.systemTemp.createTemp('reveric_bizyair_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async =>
              call.method == 'getApplicationSupportDirectory'
              ? tempSupport.path
              : null,
        );
    await RevericPaths.initialize();
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    if (await tempSupport.exists()) {
      await tempSupport.delete(recursive: true);
    }
  });

  group('BizyAir 供应商配置', () {
    test('两个独立供应商类型与固定 BaseURL', () {
      expect(aiProviderTypeConfigFor('bizyair_modelzoo')!.imageProtocol,
          ImageProtocol.bizyair_modelzoo_image);
      expect(aiProviderTypeConfigFor('bizyair_webapp')!.imageProtocol,
          ImageProtocol.bizyair_webapp_image);
      expect(aiProviderFixedBaseUrl(AiProviderType.bizyair_modelzoo),
          'https://api.bizyair.ai');
      expect(aiProviderFixedBaseUrl(AiProviderType.bizyair_webapp),
          'https://api.bizyair.ai');
    });

    test('modelzoo 12 个端点与 webapp 应用清单', () {
      final modelzoo = imageModelsForProvider('bizyair_modelzoo');
      expect(modelzoo, hasLength(12));
      expect(modelzoo, contains('nano-banana-2-1-channel/text-to-image'));
      expect(modelzoo, contains('gpt-image-2-channel/image-to-image'));
      expect(modelzoo, contains('gpt-image-2-5-flare-channel/text-to-image'));

      final webapp = imageModelsForProvider('bizyair_webapp');
      expect(webapp, ['57932', '57807']);
    });

    test('内置默认实例存在且类型为纯出图', () {
      final zoo = aiProviderBuiltinById('bizyair_modelzoo')!;
      final app = aiProviderBuiltinById('bizyair_webapp')!;
      expect(zoo.type, 'bizyair_modelzoo');
      expect(app.type, 'bizyair_webapp');
      expect(zoo.typeConfig.supportedModelKinds, {AiModelKind.image});
      expect(app.typeConfig.supportedModelKinds, {AiModelKind.image});
    });
  });

  group('BizyAir modelzoo 出图', () {
    test('提交体含提示词、比例与分辨率，并解析 request_id 与图片', () async {
      Map<String, dynamic>? submittedBody;
      Uri? submittedUri;
      final mock = MockClient((request) async {
        if (request.method == 'POST' &&
            request.url.path.contains('/modelzoo/tasks/openapi/')) {
          submittedUri = request.url;
          submittedBody = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({'code': 20000, 'data': {'request_id': 'task-1'}}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.method == 'GET' && request.url.path.contains('task-1')) {
          return http.Response(
            jsonEncode({
              'data': {
                'status': 'Success',
                'outputs': {'images': ['data:image/png;base64,$_png']},
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        throw StateError('Unexpected request: ${request.method} ${request.url}');
      });

      final provider = aiProviderBuiltinById('bizyair_modelzoo')!.copyWith(
        id: 'bz-test',
        enabled: true,
        apiKey: 'test-key',
        imageModels: imageModelsForProvider('bizyair_modelzoo'),
      );
      final client = BizyAirImageClient(
        provider,
        httpClient: mock,
        firstPollDelay: Duration.zero,
        pollInterval: Duration.zero,
      );
      final result = await client.generate(
        ImageGenerationRequest(
          prompt: 'a cat',
          model: 'gpt-image-2-channel/text-to-image',
          aspectRatio: '16:9',
          resolution: '2K',
        ),
      );

      expect(submittedBody!['prompt'], 'a cat');
      expect(submittedBody!['aspect_ratio'], '16:9');
      expect(submittedBody!['resolution'], '2k');
      expect(submittedUri!.path, contains('gpt-image-2-channel/text-to-image'));
      expect(result.hasImage, isTrue);
    });
  });

  group('BizyAir webapp 出图', () {
    test('提交体含 web_app_id 与 input_values，轮询后取输出 URL', () async {
      Map<String, dynamic>? submittedBody;
      Map<String, String>? submittedHeaders;
      final mock = MockClient((request) async {
        if (request.url.path.endsWith('/webapp/task/openapi/create')) {
          submittedBody = jsonDecode(request.body) as Map<String, dynamic>;
          submittedHeaders = request.headers;
          return http.Response(
            jsonEncode({'request_id': 'web-1'}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.url.path.endsWith('/outputs')) {
          return http.Response(
            jsonEncode({
              'data': {
                'outputs': [{'object_url': 'data:image/png;base64,$_png'}],
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.url.path.contains('web-1')) {
          return http.Response(
            jsonEncode({'data': {'status': 'Success'}}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        throw StateError('Unexpected request: ${request.method} ${request.url}');
      });

      final provider = aiProviderBuiltinById('bizyair_webapp')!.copyWith(
        id: 'bz-web-test',
        enabled: true,
        apiKey: 'test-key',
        imageModels: imageModelsForProvider('bizyair_webapp'),
      );
      final client = BizyAirImageClient(
        provider,
        httpClient: mock,
        firstPollDelay: Duration.zero,
        pollInterval: Duration.zero,
      );
      final result = await client.generate(
        ImageGenerationRequest(
          prompt: 'fei girl',
          model: '57932',
          aspectRatio: '9:16',
          resolution: '2K',
        ),
      );

      expect(submittedBody!['web_app_id'], 57932);
      final inputs = submittedBody!['input_values'] as Map<String, dynamic>;
      expect(inputs['231:CLIPTextEncode.text'], 'fei girl');
      expect(inputs['220:EmptySD3LatentImage.width'], isA<int>());
      expect(inputs['220:EmptySD3LatentImage.height'], isA<int>());
      expect(inputs['batch_size'], 4);
      expect(submittedHeaders!['x-bizyair-task-async'], 'enable');
      expect(result.hasImage, isTrue);
    });
  });
}
