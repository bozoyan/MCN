// 职责: 验证 Qwen 非实时音频的协议分流、默认参数、参考素材编码与输出下载。
// 关联文件:
//   lib/shared/services/ai/audio/qwen.dart
//   lib/shared/models/audio/channels.dart
//   lib/shared/models/audio/request.dart
//   lib/shared/services/production/audio_generate_orchestrator.dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:reveric/shared/models/audio/channels.dart';
import 'package:reveric/shared/models/audio/exception.dart';
import 'package:reveric/shared/models/audio/request.dart';
import 'package:reveric/shared/models/storyboard/prompt.dart';
import 'package:reveric/shared/services/ai/audio/client.dart';
import 'package:reveric/shared/services/ai/audio/qwen.dart';
import 'package:reveric/shared/services/production/audio_generate_orchestrator.dart';

const _next = 'qwen-audio-3.1-tts-next';
const _plus = 'qwen-audio-3.1-tts-plus';
const _flash = 'qwen-audio-3.0-tts-flash';

AudioRequest _request(
  String model, {
  String prompt = '你好。',
  AudioRequestDefaults parameters = const AudioRequestDefaults(),
  List<AudioReference> references = const [],
}) => AudioRequest(
  providerId: 'qwen',
  modelId: model,
  prompt: prompt,
  originalPrompt: prompt,
  parameters: parameters,
  references: references,
);

AudioReference _reference({
  String id = 'sample',
  String kind = 'audio',
  String mimeType = 'audio/wav',
  int bytes = 3,
  int? durationMs = 30000,
}) => AudioReference(
  assetId: id,
  inputId: id,
  kind: kind,
  mimeType: mimeType,
  bytes: bytes,
  durationMs: durationMs,
);

void main() {
  test('Qwen exposes two speech models and one reference audio model', () {
    expect(audioModelsForProvider('qwen'), [_plus, _flash, _next]);
    expect(
      audioModelsForProvider(
        'qwen',
      ).where((id) => lookupAudioChannelModel('qwen', id)!.capabilities.speech),
      [_plus, _flash],
    );
    final next = lookupAudioChannelModel('qwen', _next)!;
    expect(next.capabilities.voices, isEmpty);
    expect(next.capabilities.supportsInstructions, isFalse);
    expect(next.requestDefaults.voice, isNull);
    expect(next.requestDefaults.sampleRate, 48000);
  });

  for (final (model, voice, rate) in [
    (_plus, 'longanhuan_v3.1', 24000),
    (_flash, 'longanhuan_v3.6', 24000),
    (_next, null, 48000),
    ('proxy/qwen-audio-3.1-tts-plus', 'longanhuan_v3.1', 24000),
  ]) {
    test(
      '$model sends non-streaming input and downloads WAV separately',
      () async {
        final endpoint = qwenAudioEndpoint(
          'https://proxy.example/qwen/compatible-mode/v1/',
          modelId: model,
        );
        expect(
          endpoint.path,
          '/qwen/api/v1/services/audio/tts/SpeechSynthesizer',
        );
        var calls = 0;
        final transport = MockClient((r) async {
          calls++;
          expect(r.headers['Authorization'], 'Bearer qwen-key');
          expect(r.headers['Content-Type'], 'application/json');
          expect(r.headers['X-DashScope-SSE'], isNull);
          expect(r.url, endpoint);
          expect(jsonDecode(r.body), {
            'model': model,
            'input': {
              model == _next ? 'text_prompt' : 'text': '你好。',
              'voice': ?voice,
              'format': 'wav',
              'sample_rate': rate,
              if (model == _plus || model == _flash) 'instruction': '温暖、平静',
            },
          });
          return http.Response(
            '{"output":{"audio":{"url":"http://output.example/audio.wav?signature=test"}}}',
            200,
          );
        });
        addTearDown(transport.close);
        final api = QwenAudioClient(transport, 'qwen-key', endpoint: endpoint);
        final result = await api.generate(
          _request(
            model,
            parameters: AudioRequestDefaults(
              instructions: ConfigValue(
                model == _plus || model == _flash ? '温暖、平静' : null,
              ),
            ),
          ),
        );
        expect(calls, 1);
        expect(result.bytes, isEmpty);
        final output = Uint8List(44)
          ..setRange(0, 4, ascii.encode('RIFF'))
          ..setRange(8, 12, ascii.encode('WAVE'));
        final downloader = MockClient((r) async {
          expect(
            r.url.toString(),
            'https://output.example/audio.wav?signature=test',
          );
          expect(r.headers['Authorization'], isNull);
          return http.Response.bytes(output, 200);
        });
        addTearDown(downloader.close);
        expect(
          await downloadAudioOutput(result.url!, httpClient: downloader),
          output,
        );
      },
    );
  }

  final encoder = QwenAudioClient(
    MockClient((_) async => throw StateError('encode only')),
    'key',
    endpoint: qwenAudioEndpoint('https://example.test'),
  );
  test(
    'Next maps ordered production references to voice slots and data URIs',
    () {
      final refs = [
        _reference(id: 'one'),
        _reference(id: 'two', mimeType: 'audio/mpeg'),
        _reference(id: 'three', mimeType: 'audio/ogg'),
      ];
      final source =
          '${StoryboardPrompt.reference('two', '乙')}回答'
          '${StoryboardPrompt.reference('one', '甲')}，@音频3 加入。';
      final prompt = compileAudioPrompt(source, refs);
      final request = resolveAudioRequest(
        'qwen',
        _request(_next, prompt: prompt, references: refs),
      );
      final restored = AudioRequest.fromJson(request.toJson());
      final body = encoder.encode(
        restored,
        references: [
          Uint8List.fromList([1, 2, 3]),
          Uint8List(3),
          Uint8List(3),
        ],
      );
      expect(
        (body['input'] as Map)['text_prompt'],
        '@voice2回答@voice1，@voice3 加入。',
      );
      expect((body['input'] as Map)['references'], [
        {'audio_data': 'data:audio/wav;base64,AQID'},
        {'audio_data': 'data:audio/mpeg;base64,AAAA'},
        {'audio_data': 'data:audio/ogg;base64,AAAA'},
      ]);
      expect(restored.prompt, prompt);
      expect((body['input'] as Map).containsKey('voice'), isFalse);
      expect(
        () => encoder.encode(restored, references: [Uint8List(3)]),
        throwsA(isA<AudioException>()),
      );
      expect(
        () => encoder.encode(
          restored,
          references: [Uint8List(2), Uint8List(3), Uint8List(3)],
        ),
        throwsA(isA<AudioException>()),
      );
    },
  );

  for (final (model, limit) in [
    (_plus, 20000),
    (_flash, 20000),
    (_next, 3000),
  ]) {
    test(
      '$model enforces its text limit without splitting Unicode characters',
      () {
        resolveAudioRequest('qwen', _request(model, prompt: '声' * limit));
        expect(
          () => resolveAudioRequest(
            'qwen',
            _request(model, prompt: '声' * limit + '🎵'),
          ),
          throwsA(
            isA<AudioException>().having(
              (e) => e.code,
              'code',
              'audio_prompt_length',
            ),
          ),
        );
      },
    );
  }

  test(
    'Next rejects unsupported or oversized references and missing slots',
    () {
      for (final refs in [
        List.generate(4, (i) => _reference(id: '$i')),
        [_reference(mimeType: 'audio/pcm')],
        [_reference(kind: 'image', mimeType: 'image/png')],
        [_reference(bytes: 10 * 1024 * 1024 + 1)],
        [_reference(durationMs: 30001)],
        [_reference(durationMs: null)],
      ]) {
        expect(
          () => resolveAudioRequest('qwen', _request(_next, references: refs)),
          throwsA(isA<AudioException>()),
        );
      }
      for (final prompt in ['@voice0', '@voice2', '@Audio2', '@音频2']) {
        expect(
          () => encoder.encode(
            resolveAudioRequest(
              'qwen',
              _request(_next, prompt: prompt, references: [_reference()]),
            ),
            references: [Uint8List(3)],
          ),
          throwsA(isA<AudioException>()),
        );
      }
    },
  );

  test(
    'Qwen rejects unsupported parameters before any network submission',
    () async {
      final api = QwenAudioClient(
        MockClient((_) async => fail('invalid requests must not reach HTTP')),
        'key',
        endpoint: qwenAudioEndpoint('https://example.test'),
      );
      for (final request in [
        _request(
          _next,
          parameters: const AudioRequestDefaults(
            voice: ConfigValue('longanhuan_v3.1'),
          ),
        ),
        _request(
          _next,
          parameters: const AudioRequestDefaults(
            instructions: ConfigValue('calm'),
          ),
        ),
        _request(
          _next,
          parameters: const AudioRequestDefaults(
            sampleRate: ConfigValue(22050),
          ),
        ),
        _request(
          _plus,
          parameters: const AudioRequestDefaults(
            sampleRate: ConfigValue(12345),
          ),
        ),
        _request(
          _plus,
          parameters: const AudioRequestDefaults(
            responseFormat: ConfigValue('mp3'),
          ),
        ),
        _request(
          _plus,
          parameters: const AudioRequestDefaults(bitrate: ConfigValue(128000)),
        ),
        _request(_flash, references: [_reference()]),
      ]) {
        await expectLater(
          api.generate(request),
          throwsA(isA<AudioException>()),
        );
      }
    },
  );

  test(
    'speech preserves custom voice IDs and explicit omission of sample rate',
    () {
      final input =
          encoder.encode(
                resolveAudioRequest(
                  'qwen',
                  _request(
                    _plus,
                    parameters: const AudioRequestDefaults(
                      voice: ConfigValue('custom-cloned-voice'),
                      sampleRate: ConfigValue(null),
                    ),
                  ),
                ),
              )['input']
              as Map;
      expect(input['voice'], 'custom-cloned-voice');
      expect(input.containsKey('sample_rate'), isFalse);
    },
  );
}
