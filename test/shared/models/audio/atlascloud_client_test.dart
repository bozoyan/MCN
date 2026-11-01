// 职责: 验证 AtlasCloud 音频目录、官方参数契约、异步回执与错误边界。
// 关联文件:
//   lib/shared/services/ai/audio/atlascloud.dart
//   lib/shared/models/audio/channels.dart
//   test/shared/models/audio/atlascloud_schemas.json
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:reveric/shared/models/ai_provider.dart';
import 'package:reveric/shared/models/audio/channels.dart';
import 'package:reveric/shared/models/audio/exception.dart';
import 'package:reveric/shared/models/audio/request.dart';
import 'package:reveric/shared/services/ai/audio/atlascloud.dart';

AudioRequest request(String model) => AudioRequest(
  providerId: 'atlas',
  modelId: model,
  prompt: 'Hello',
  originalPrompt: 'Hello',
);

Map<String, dynamic> receipt(String status, {List<String>? outputs}) => {
  'code': 200,
  'data': {'id': 'prediction-1', 'status': status, 'outputs': ?outputs},
};

void main() {
  final schemas =
      jsonDecode(
            File(
              'test/shared/models/audio/atlascloud_schemas.json',
            ).readAsStringSync(),
          )
          as Map;
  test('AtlasCloud exposes only supported audio-file models', () {
    final provider = aiProviderBuiltinById(
      'openai',
    )!.copyWith(type: 'atlascloud');
    expect(provider.supportsModelKind(AiModelKind.audio), isTrue);
    expect(audioModelsForProvider('atlascloud'), unorderedEquals(schemas.keys));
    expect(
      lookupAudioChannelModel('atlascloud', 'minimax/lyrics-generation'),
      isNull,
    );
    expect(
      lookupAudioChannelModel('atlascloud', 'bytedance/seed-asr-2.0'),
      isNull,
    );
    expect(lookupAudioChannelModel('atlascloud', 'suno/chirp-v6'), isNull);
  });

  for (final model in schemas.keys.cast<String>()) {
    test(
      '$model submits flattened official parameters and retains prediction ID',
      () async {
        var calls = 0;
        final client = AtlasCloudAudioClient(
          MockClient((r) async {
            calls++;
            expect(r.method, 'POST');
            expect(
              r.url.toString(),
              'https://api.atlascloud.ai/api/v1/model/generateAudio',
            );
            expect(r.headers['Authorization'], 'Bearer secret');
            final body = jsonDecode(r.body) as Map<String, dynamic>;
            validate(body, schemas[model] as Map);
            expect(body['model'], model);
            expect(
              body[model.startsWith('minimax/music-') ? 'prompt' : 'text'],
              'Hello',
            );
            if (model.startsWith('minimax/music-')) {
              expect(body['is_instrumental'], true);
            }
            if (model.startsWith('google/')) {
              expect(body.keys, unorderedEquals(['model', 'text', 'voice']));
            }
            return http.Response(jsonEncode(receipt('processing')), 200);
          }),
          'secret',
        );
        final result = await client.generate(request(model));
        expect(result.isPending, isTrue);
        expect(result.providerTaskId, 'prediction-1');
        expect(calls, 1);
      },
    );
  }

  test(
    'Seed serializes audio and image references using base64 source fields',
    () {
      final client = AtlasCloudAudioClient(
        MockClient((_) async => throw StateError('encode only')),
        'secret',
      );
      for (final kind in ['audio', 'image']) {
        final bytes = Uint8List.fromList([1, 2, 3]);
        final input = resolveAudioRequest(
          'atlascloud',
          AudioRequest(
            providerId: 'atlas',
            modelId: 'bytedance/seed-audio-1.0',
            prompt: kind == 'audio' ? '@Audio1 Hello' : 'Hello',
            originalPrompt: 'Hello',
            references: [
              AudioReference(
                assetId: 'ref',
                kind: kind,
                mimeType: kind == 'audio' ? 'audio/wav' : 'image/png',
                bytes: 3,
                durationMs: 1000,
              ),
            ],
          ),
        );
        final body = client.encode(input, references: [bytes]);
        expect(body['references'], [
          {'${kind}_data': base64Encode(bytes)},
        ]);
        expect(body['format'], 'wav');
        validate(body, schemas[input.modelId] as Map);
      }
    },
  );

  test(
    'query uses fixed authenticated endpoint and returns URL without downloading',
    () async {
      final client = AtlasCloudAudioClient(
        MockClient((r) async {
          expect(r.method, 'GET');
          expect(
            r.url.toString(),
            'https://api.atlascloud.ai/api/v1/model/prediction/prediction-1',
          );
          expect(r.headers['Authorization'], 'Bearer secret');
          return http.Response(
            jsonEncode(
              receipt('completed', outputs: ['https://cdn.example/result.wav']),
            ),
            200,
          );
        }),
        'secret',
      );
      final result = await client.query('prediction-1');
      expect(result.isPending, isFalse);
      expect(result.bytes, isEmpty);
      expect(result.url.toString(), 'https://cdn.example/result.wav');
    },
  );

  for (final status in ['failed', 'timeout', 'cancelled']) {
    test('$status preserves redacted provider diagnostics', () {
      final client = AtlasCloudAudioClient(
        MockClient((_) async => throw StateError('decode only')),
        'secret',
      );
      expect(
        () => client.decodeResult({
          'code': 200,
          'data': {
            'id': 'prediction-1',
            'status': status,
            'error_code': 42,
            'error': 'Provider failed secret',
          },
        }),
        throwsA(
          isA<AudioException>()
              .having((e) => e.code, 'code', 'rejected')
              .having(
                (e) => e.providerMessage,
                'original message',
                'Provider failed secret',
              )
              .having(
                (e) => e.detail,
                'detail',
                allOf(contains('42'), isNot(contains('secret'))),
              ),
        ),
      );
    });
  }

  test('missing, multiple, insecure and textual outputs are rejected', () {
    final client = AtlasCloudAudioClient(
      MockClient((_) async => throw StateError('decode only')),
      'secret',
    );
    for (final outputs in [
      <String>[],
      ['lyrics'],
      ['http://cdn.example/audio'],
      ['https://user:pass@cdn.example/audio'],
      ['https://cdn.example/one', 'https://cdn.example/two'],
    ]) {
      expect(
        () => client.decodeResult(receipt('completed', outputs: outputs)),
        throwsFormatException,
      );
    }
  });

  test('query rejects a different prediction ID', () async {
    final client = AtlasCloudAudioClient(
      MockClient(
        (_) async => http.Response(jsonEncode(receipt('processing')), 200),
      ),
      'secret',
    );
    await expectLater(client.query('other'), throwsA(isA<AudioException>()));
  });

  test('prediction query retries TLS failures without another POST', () async {
    var calls = 0;
    final client = AtlasCloudAudioClient(
      MockClient((r) async {
        calls++;
        expect(r.method, 'GET');
        if (calls == 1) {
          throw const HandshakeException(
            'Connection terminated during handshake',
          );
        }
        return http.Response(
          jsonEncode(
            receipt('completed', outputs: ['https://cdn.example/audio.wav']),
          ),
          200,
        );
      }),
      'secret',
    );
    final result = await client.query('prediction-1');
    expect(result.url.toString(), 'https://cdn.example/audio.wav');
    expect(calls, 2);
  });

  test(
    'prediction logs state without credentials or signed output URLs',
    () async {
      final lines = <String>[];
      final original = debugPrint;
      debugPrint = (message, {wrapWidth}) {
        if (message != null) {
          lines.add(message);
        }
      };
      addTearDown(() => debugPrint = original);
      final body = receipt(
        'completed',
        outputs: ['https://cdn.example/audio.wav?token=private-signature'],
      );
      (body['data'] as Map)['price'] = '0.000864';
      (body['data'] as Map)['api_key'] = 'secret-key';
      final client = AtlasCloudAudioClient(
        MockClient((_) async => http.Response(jsonEncode(body), 200)),
        'secret-key',
      );
      await client.query('prediction-1');
      final log = lines.singleWhere(
        (line) => line.contains('[AtlasCloudAudio] response'),
      );
      expect(log, contains('status=completed'));
      expect(log, isNot(contains('private-signature')));
      expect(log, isNot(contains('secret-key')));
      expect(log, isNot(contains('https://')));
    },
  );

  for (final status in [403, 429, 503, 200]) {
    test('query status $status retries only transient HTTP errors', () async {
      var calls = 0;
      final client = AtlasCloudAudioClient(
        MockClient((_) async {
          calls++;
          return http.Response('invalid body', status);
        }),
        'secret',
        readRetryDelay: Duration.zero,
      );
      await expectLater(
        client.query('prediction-1'),
        throwsA(isA<AudioException>()),
      );
      expect(calls, status == 429 || status == 503 ? 3 : 1);
    });
  }

  test('HTTP failure and cancellation never resubmit', () async {
    var calls = 0;
    final client = AtlasCloudAudioClient(
      MockClient((_) async {
        calls++;
        return http.Response('{"message":"Unavailable"}', 503);
      }),
      'secret',
    );
    await expectLater(
      client.generate(request('bytedance/seed-audio-1.0')),
      throwsA(
        isA<AudioException>().having((e) => e.code, 'code', 'unavailable'),
      ),
    );
    expect(calls, 1);
    await expectLater(
      client.generate(
        request('bytedance/seed-audio-1.0'),
        abortTrigger: Future.value(),
      ),
      throwsA(isA<AudioException>().having((e) => e.code, 'code', 'cancelled')),
    );
    expect(calls, 1);
  });
}

// Snapshot of official input schemas; assertion covers required names, types,
// enumerations and bounds without copying request encoding into the test.
void validate(Object? value, Map schema) {
  if (schema['enum'] case final List values) {
    expect(values, contains(value));
  }
  switch (schema['type']) {
    case 'object':
      expect(value, isA<Map>());
      final object = value as Map;
      final properties = schema['properties'] as Map;
      for (final key in (schema['required'] as List? ?? [])) {
        expect(object.containsKey(key), isTrue, reason: 'required: $key');
      }
      for (final key in object.keys) {
        expect(
          properties.containsKey(key),
          isTrue,
          reason: 'unknown field: $key',
        );
        validate(object[key], properties[key] as Map);
      }
    case 'array':
      expect(value, isA<List>());
      for (final item in value as List) {
        validate(item, schema['items'] as Map);
      }
    case 'string':
      expect(value, isA<String>());
      if (schema['maxLength'] case final int max) {
        expect((value as String).runes.length, lessThanOrEqualTo(max));
      }
    case 'integer':
      expect(value, isA<int>());
    case 'boolean':
      expect(value, isA<bool>());
    case 'number':
      expect(value, isA<num>());
  }
}
