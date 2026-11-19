// 职责: 验证 BizyAir 多密钥池的解析、游标轮转与客户端换 key 重试。
// 关联文件:
//   lib/shared/services/ai/bizyair_keys.dart
//   lib/shared/services/ai/image/bizyair.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:reveric/shared/models/ai_provider.dart';
import 'package:reveric/shared/models/image/channels.dart';
import 'package:reveric/shared/services/ai/bizyair_keys.dart';
import 'package:reveric/shared/services/ai/image.dart';
import 'package:reveric/shared/services/ai/image/bizyair.dart';
import 'package:reveric/shared/services/ai/image/client.dart';
import 'package:reveric/shared/utils/storage_paths.dart';

const _png =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAACklEQVR4nGMAAQAABQABDQottAAAAABJRU5ErkJggg==';

const _okTask =
    '{"code":20000,"data":{"request_id":"t-1"}}';
final _okPoll = jsonEncode({
  'data': {
    'status': 'Success',
    'outputs': {'images': ['data:image/png;base64,$_png']},
  },
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempSupport;

  setUp(() async {
    tempSupport = await Directory.systemTemp.createTemp('reveric_bizyair_key_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => call.method == 'getApplicationSupportDirectory'
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

  group('密钥池解析', () {
    test('跳过注释空行，兼容 KEY=value 与引号、同行逗号分隔', () {
      final keys = BizyAirKeyPool.parseKeys('''
# 这是注释
sk-aaa

export BIZYAIR_API_KEY="sk-bbb"
sk-ccc, sk-ddd
''');
      expect(keys, ['sk-aaa', 'sk-bbb', 'sk-ccc', 'sk-ddd']);
    });

    test('Key 字段为 txt 文件路径时按密钥池文件读取', () async {
      final poolFile = File('${tempSupport.path}/pool.txt');
      await poolFile.writeAsString('# 池\nkey-1\nkey-2\n');
      final pool = await BizyAirKeyPool.resolve(poolFile.path);
      expect(pool.keys, ['key-1', 'key-2']);
      expect(pool.current, 'key-1');
    });

    test('Key 字段直接写多把时按内联密钥解析', () async {
      final pool = await BizyAirKeyPool.resolve('key-a\nkey-b');
      expect(pool.keys, ['key-a', 'key-b']);
    });
  });

  group('游标轮转', () {
    test('任务成功后游标推进，下一次从下一把 key 开始', () async {
      final cursor = File('${tempSupport.path}/cursor.json');
      final first = await BizyAirKeyPool.resolve(
        'k1\nk2',
        cursorFile: cursor,
      );
      expect(first.current, 'k1');
      await first.commit();

      final second = await BizyAirKeyPool.resolve(
        'k1\nk2',
        cursorFile: cursor,
      );
      expect(second.current, 'k2');
      await second.commit();

      final third = await BizyAirKeyPool.resolve('k1\nk2', cursorFile: cursor);
      expect(third.current, 'k1');
    });

    test('单把 key 时 advance 返回 false，不空转', () {
      final pool = BizyAirKeyPool.fromKeys(['only']);
      expect(pool.advance(), isFalse);
      expect(pool.current, 'only');
    });
  });

  group('客户端多密钥', () {
    test('连续两个任务使用不同 key，Authorization 随之轮换', () async {
      final auths = <String>[];
      final mock = MockClient((request) async {
        if (request.method == 'POST') {
          auths.add(request.headers['authorization'] ?? '');
          return http.Response(_okTask, 200);
        }
        return http.Response(_okPoll, 200);
      });

      final provider = aiProviderBuiltinById('bizyair_modelzoo')!.copyWith(
        id: 'bz-multikey',
        enabled: true,
        apiKey: 'key-one\nkey-two',
        imageModels: imageModelsForProvider('bizyair_modelzoo'),
      );
      final client = BizyAirImageClient(
        provider,
        httpClient: mock,
        firstPollDelay: Duration.zero,
        pollInterval: Duration.zero,
      );

      Future<void> run() => client.generate(
        ImageGenerationRequest(
          prompt: 'cat',
          model: 'gpt-image-2-channel/text-to-image',
          aspectRatio: '1:1',
          resolution: '2K',
        ),
      );

      await run();
      await run();

      expect(auths, ['Bearer key-one', 'Bearer key-two']);
    });

    test('当前 key 提交被拒时串行切下一把重试', () async {
      final auths = <String>[];
      final mock = MockClient((request) async {
        final auth = request.headers['authorization'] ?? '';
        if (request.method == 'POST') {
          auths.add(auth);
          if (auth == 'Bearer bad-key') {
            return http.Response('{"message":"invalid api key"}', 401);
          }
          return http.Response(_okTask, 200);
        }
        return http.Response(_okPoll, 200);
      });

      final provider = aiProviderBuiltinById('bizyair_modelzoo')!.copyWith(
        id: 'bz-retry',
        enabled: true,
        apiKey: 'bad-key\ngood-key',
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
          prompt: 'cat',
          model: 'gpt-image-2-channel/text-to-image',
          aspectRatio: '1:1',
          resolution: '2K',
        ),
      );

      expect(auths, ['Bearer bad-key', 'Bearer good-key']);
      expect(result.hasImage, isTrue);
    });

    test('前一个任务失败不阻塞排队中的后续任务', () async {
      var posts = 0;
      final mock = MockClient((request) async {
        if (request.method == 'POST') {
          posts++;
          return posts == 1
              ? http.Response('{"message":"server error"}', 500)
              : http.Response(_okTask, 200);
        }
        return http.Response(_okPoll, 200);
      });

      final provider = aiProviderBuiltinById('bizyair_modelzoo')!.copyWith(
        id: 'bz-queue',
        enabled: true,
        apiKey: 'only-key',
        imageModels: imageModelsForProvider('bizyair_modelzoo'),
      );
      final client = BizyAirImageClient(
        provider,
        httpClient: mock,
        firstPollDelay: Duration.zero,
        pollInterval: Duration.zero,
      );

      Future<AiImageGenerationResult> run() => client.generate(
        ImageGenerationRequest(
          prompt: 'cat',
          model: 'gpt-image-2-channel/text-to-image',
          aspectRatio: '1:1',
          resolution: '2K',
        ),
      );

      final first = run();
      final second = run();
      await expectLater(first, throwsA(isA<AiImageGenerationException>()));
      final result = await second;
      expect(result.hasImage, isTrue);
    });
  });
}
