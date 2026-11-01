// 职责: 验证 AtlasCloud 模型发现与各视频端点的真实请求契约。
// 关联文件:
//   lib/shared/models/video/channels.dart
//   lib/shared/services/ai/video/atlascloud.dart
//   lib/shared/widgets/settings/provider_config_panel.dart

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:reveric/shared/models/ai_provider.dart';
import 'package:reveric/shared/models/video/channels.dart';
import 'package:reveric/shared/models/video/request.dart';
import 'package:reveric/shared/models/video/task_result.dart';
import 'package:reveric/shared/services/ai/video/atlascloud.dart';
import 'package:reveric/shared/widgets/settings/provider_config_panel.dart';

void main() {
  testAtlasRoutes();
  testWireConventions();
  test(
    'AtlasCloud video discovery includes the official model families',
    () async {
      final provider = aiProviderBuiltinById(
        'openai',
      )!.copyWith(type: 'atlascloud');
      final models = await fetchProviderModels(
        provider,
        kind: AiModelKind.video,
      );
      expect(
        models,
        containsAll([
          'bytedance/seedance-2.5',
          'bytedance/seedance-2.0',
          'bytedance/seedance-2.0-fast',
          'bytedance/seedance-2.0-mini',
          'google/veo3.1',
          'google/veo3.1-fast',
          'google/veo3.1-lite',
          'kwaivgi/kling-v3.0-pro',
          'alibaba/wan-3.0',
          'alibaba/wan-3.0-prime',
          'minimax/h3',
          'pixverse/v6',
          'xai/grok-imagine-video-v1.5',
        ]),
      );
      expect(
        models.where(
          (id) =>
              id.startsWith('vidu/') || id.startsWith('bytedance/seedance-v1'),
        ),
        isEmpty,
      );
    },
  );
}

VideoReference reference(VideoInputRole role) => VideoReference(
  role: role,
  url: Uri.parse('https://media.example/${role.name}'),
  mimeType: switch (role.kind) {
    VideoMediaKind.image => 'image/png',
    VideoMediaKind.video => 'video/mp4',
    VideoMediaKind.audio => 'audio/mpeg',
  },
  fileSize: 100,
  mediaInfo: const VideoMediaInfo(
    width: 720,
    height: 720,
    durationMs: 2000,
    frameRate: 30,
  ),
);

VideoRequest request(
  String model,
  VideoMode mode, {
  String? resolution,
  int? duration,
}) {
  final channel = lookupVideoChannelModel('atlascloud', model)!;
  final route = (channel.protocolOptions as AtlasCloudVideoOptions).routeFor(
    mode,
  )!;
  final selectedResolution = resolution ?? route.resolutions.first;
  return VideoRequest(
    modelId: model,
    prompt: 'A bird flying over the sea',
    mode: mode,
    resolution: selectedResolution,
    ratio: route.ratios.first,
    durationSeconds:
        duration ??
        (route.eightSecondResolutions.contains(selectedResolution)
            ? 8
            : route.durations.first),
    audio: channel.requestDefaults.audio,
    promptExtend: channel.requestDefaults.promptExtend,
  );
}

AtlasCloudVideoClient client(http.Client transport) => AtlasCloudVideoClient(
  httpClient: transport,
  providerType: 'atlascloud',
  apiKey: 'test-key',
);

void testAtlasRoutes() {
  for (final model in videoModelsForProvider('atlascloud')) {
    final channel = lookupVideoChannelModel('atlascloud', model)!;
    final options = channel.protocolOptions;
    if (options is! AtlasCloudVideoOptions) {
      continue; // Existing Seedance routes are covered by client_test.dart.
    }
    for (final mode in VideoMode.values) {
      final route = options.routeFor(mode);
      if (route == null) {
        continue;
      }
      test(
        '$model $mode submits an official-schema request and polls the original task',
        () async {
          final refs = switch (mode) {
            VideoMode.text => <VideoReference>[],
            VideoMode.first_frame => [reference(VideoInputRole.first_frame)],
            VideoMode.first_last_frame => [
              reference(VideoInputRole.first_frame),
              reference(VideoInputRole.last_frame),
            ],
            VideoMode.reference => [
              for (final role in [
                VideoInputRole.reference_image,
                VideoInputRole.reference_video,
                VideoInputRole.reference_audio,
              ])
                if ((route.referenceCounts[role.kind] ?? 0) > 0)
                  reference(role),
            ],
          };
          final methods = <String>[];
          final api = client(
            MockClient((r) async {
              methods.add(r.method);
              expect(r.headers['Authorization'], 'Bearer test-key');
              if (r.method == 'POST') {
                expect(
                  r.url.toString(),
                  'https://api.atlascloud.ai/api/v1/model/generateVideo',
                );
                final body = jsonDecode(r.body) as Map<String, dynamic>;
                expect(body['model'], route.modelId);
                expect(body.values, isNot(contains(null)));
                validateSchema(
                  body,
                  officialSchemas[body['model']] as Map<String, dynamic>,
                );
                return http.Response(
                  '{"code":200,"data":{"id":"task-1","status":"processing"}}',
                  200,
                );
              }
              expect(
                r.url.toString(),
                'https://api.atlascloud.ai/api/v1/model/prediction/task-1',
              );
              return http.Response(
                '{"code":200,"data":{"id":"task-1","status":"completed","outputs":["https://result.example/video.mp4"]}}',
                200,
              );
            }),
          );
          final task = await api.submit(request(model, mode), refs);
          expect(task.modelId, model);
          expect((await api.query(task)).status, VideoRemoteStatus.succeeded);
          expect(methods, ['POST', 'GET']);
        },
      );
    }
  }
}

void testWireConventions() {
  test(
    'Veo uses aspect_ratio and rejects invalid high-resolution duration before POST',
    () async {
      var calls = 0;
      final api = client(
        MockClient((_) async {
          calls++;
          return http.Response('{"data":{"id":"task"}}', 200);
        }),
      );
      final body = api.encode(request('google/veo3.1', VideoMode.text), []);
      expect(body['aspect_ratio'], '16:9');
      expect(body.containsKey('ratio'), isFalse);
      expect(body['generate_audio'], false);
      await expectLater(
        api.submit(
          request(
            'google/veo3.1',
            VideoMode.text,
            resolution: '1080p',
            duration: 4,
          ),
          [],
        ),
        throwsA(
          isA<VideoException>().having((e) => e.field, 'field', 'duration'),
        ),
      );
      expect(calls, 0);
    },
  );
  test(
    'first/last frames select the actual PixVerse and Veo Lite endpoints',
    () {
      final api = client(
        MockClient((_) async => throw StateError('unexpected HTTP')),
      );
      final refs = [
        reference(VideoInputRole.first_frame),
        reference(VideoInputRole.last_frame),
      ];
      final pixverse = api.encode(
        request('pixverse/v6', VideoMode.first_last_frame),
        refs,
      );
      expect(pixverse['model'], 'pixverse/v6/start-end-to-video');
      expect(pixverse['image'], refs.first.url.toString());
      expect(pixverse['end_image'], refs.last.url.toString());
      expect(pixverse.containsKey('last_image'), isFalse);
      final veo = api.encode(
        request('google/veo3.1-lite', VideoMode.first_last_frame),
        refs,
      );
      expect(veo['model'], 'google/veo3.1-lite/start-end-frame-to-video');
      expect(veo['last_image'], refs.last.url.toString());
    },
  );
  test(
    'Kling, PixVerse, Grok and Wan preserve their own field conventions',
    () {
      final api = client(
        MockClient((_) async => throw StateError('unexpected HTTP')),
      );
      final kling = api.encode(
        request('kwaivgi/kling-v3.0-pro', VideoMode.first_last_frame),
        [
          reference(VideoInputRole.first_frame),
          reference(VideoInputRole.last_frame),
        ],
      );
      expect(kling['end_image'], 'https://media.example/last_frame');
      expect(kling['sound'], true);
      expect(kling.containsKey('generate_audio'), isFalse);
      final pix = api.encode(request('pixverse/v6', VideoMode.reference), [
        reference(VideoInputRole.reference_image),
      ]);
      expect(pix['images'], [
        {'image': 'https://media.example/reference_image'},
      ]);
      expect(pix['quality'], '360p');
      final grok = api.encode(
        request('xai/grok-imagine-video-v1.5', VideoMode.first_frame),
        [reference(VideoInputRole.first_frame)],
      );
      expect(grok['image_url'], 'https://media.example/first_frame');
      expect(grok.containsKey('generate_audio'), isFalse);
      final wan = api.encode(request('alibaba/wan-3.0', VideoMode.reference), [
        reference(VideoInputRole.reference_image),
        reference(VideoInputRole.reference_video),
      ]);
      expect(wan['refers'], [
        {'url': 'https://media.example/reference_image', 'type': 'image'},
        {'url': 'https://media.example/reference_video', 'type': 'video'},
      ]);
      expect(wan['audio'], true);
      final wan25 = api.encode(request('alibaba/wan-2.5', VideoMode.text), []);
      expect(wan25['size'], '832*480');
      expect(wan25.containsKey('resolution'), isFalse);
      expect(wan25.containsKey('ratio'), isFalse);
    },
  );
  test(
    'unsupported reference routes and Grok 1080p references never reach POST',
    () async {
      var calls = 0;
      final api = client(
        MockClient((_) async {
          calls++;
          throw StateError('must not POST');
        }),
      );
      final frameRequest = request('google/veo3.1-fast', VideoMode.first_frame);
      final unsupported = VideoRequest(
        modelId: frameRequest.modelId,
        prompt: frameRequest.prompt,
        mode: VideoMode.reference,
        resolution: frameRequest.resolution,
        ratio: frameRequest.ratio,
        durationSeconds: frameRequest.durationSeconds,
        audio: frameRequest.audio,
      );
      await expectLater(
        api.submit(unsupported, [reference(VideoInputRole.reference_image)]),
        throwsA(isA<VideoException>()),
      );
      await expectLater(
        api.submit(
          request(
            'xai/grok-imagine-video-v1.5',
            VideoMode.reference,
            resolution: '1080p',
          ),
          [reference(VideoInputRole.reference_image)],
        ),
        throwsA(
          isA<VideoException>().having((e) => e.field, 'field', 'resolution'),
        ),
      );
      expect(calls, 0);
    },
  );
}

void validateSchema(Object? value, Map<String, dynamic> schema) {
  switch (schema['type']) {
    case 'object':
      expect(value, isA<Map>());
      final object = value! as Map;
      final properties = schema['properties'] as Map;
      for (final key in schema['required'] as List? ?? []) {
        expect(object.containsKey(key), isTrue, reason: 'required $key');
      }
      for (final entry in object.entries) {
        expect(
          properties.containsKey(entry.key),
          isTrue,
          reason: 'undocumented ${entry.key}',
        );
        validateSchema(
          entry.value,
          properties[entry.key] as Map<String, dynamic>,
        );
      }
    case 'array':
      expect(value, isA<List>());
      final list = value! as List;
      if (schema['maxItems'] != null) {
        expect(list.length, lessThanOrEqualTo(schema['maxItems']));
      }
      for (final item in list) {
        validateSchema(item, schema['items'] as Map<String, dynamic>);
      }
    case 'string':
      expect(value, isA<String>());
    case 'boolean':
      expect(value, isA<bool>());
    case 'integer':
      expect(value, isA<int>());
    case 'number':
      expect(value, isA<num>());
  }
  if (schema['enum'] != null) {
    expect(schema['enum'] as List, contains(value));
  }
  if (value is num) {
    if (schema['minimum'] != null) {
      expect(value, greaterThanOrEqualTo(schema['minimum']));
    }
    if (schema['maximum'] != null) {
      expect(value, lessThanOrEqualTo(schema['maximum']));
    }
  }
}

// 官方 schema 的结构性快照（仅类型、必填和枚举），不包含提示词或示例媒体。
// https://static.atlascloud.ai/model/schema/<model-id-with-slashes-replaced-by-hyphens>.json
final officialSchemas = jsonDecode(_officialSchemaJson) as Map<String, dynamic>;
const _officialSchemaJson = r'''{
"alibaba/happyhorse-1.0/text-to-video":{"type":"object","required":["model","prompt"],"properties":{"model":{"type":"string","enum":["alibaba/happyhorse-1.0/text-to-video"]},"prompt":{"type":"string"},"resolution":{"enum":["720p","1080p"],"type":"string"},"ratio":{"enum":["16:9","9:16","1:1","4:3","3:4"],"type":"string"},"duration":{"minimum":3,"maximum":15,"type":"integer"},"seed":{"minimum":-1,"maximum":2147483647,"type":"integer"}}},
"alibaba/happyhorse-1.0/image-to-video":{"type":"object","required":["model","image"],"properties":{"model":{"type":"string","enum":["alibaba/happyhorse-1.0/image-to-video"]},"image":{"type":"string"},"prompt":{"type":"string"},"resolution":{"enum":["720p","1080p"],"type":"string"},"duration":{"minimum":3,"maximum":15,"type":"integer"},"seed":{"minimum":-1,"maximum":2147483647,"type":"integer"}}},
"alibaba/happyhorse-1.0/reference-to-video":{"type":"object","required":["model","prompt","images"],"properties":{"model":{"type":"string","enum":["alibaba/happyhorse-1.0/reference-to-video"]},"prompt":{"type":"string"},"images":{"type":"array","minItems":1,"maxItems":9,"items":{"type":"string"}},"resolution":{"enum":["720p","1080p"],"type":"string"},"ratio":{"enum":["16:9","9:16","1:1","4:3","3:4"],"type":"string"},"duration":{"minimum":3,"maximum":15,"type":"integer"},"seed":{"minimum":-1,"maximum":2147483647,"type":"integer"}}},
"alibaba/happyhorse-1.1/text-to-video":{"type":"object","required":["model","prompt"],"properties":{"model":{"type":"string","enum":["alibaba/happyhorse-1.1/text-to-video"]},"prompt":{"type":"string"},"resolution":{"enum":["480p","720p","1080p"],"type":"string"},"ratio":{"enum":["16:9","9:16","1:1","4:3","3:4","4:5","5:4","9:21","21:9"],"type":"string"},"duration":{"minimum":3,"maximum":15,"type":"integer"},"seed":{"minimum":-1,"maximum":2147483647,"type":"integer"}}},
"alibaba/happyhorse-1.1/image-to-video":{"type":"object","required":["model","image"],"properties":{"model":{"type":"string","enum":["alibaba/happyhorse-1.1/image-to-video"]},"image":{"type":"string"},"prompt":{"type":"string"},"resolution":{"enum":["480p","720p","1080p"],"type":"string"},"duration":{"minimum":3,"maximum":15,"type":"integer"},"seed":{"minimum":-1,"maximum":2147483647,"type":"integer"}}},
"alibaba/happyhorse-1.1/reference-to-video":{"type":"object","required":["model","prompt","images"],"properties":{"model":{"type":"string","enum":["alibaba/happyhorse-1.1/reference-to-video"]},"prompt":{"type":"string"},"images":{"type":"array","minItems":1,"maxItems":9,"items":{"type":"string"}},"resolution":{"enum":["480p","720p","1080p"],"type":"string"},"ratio":{"enum":["16:9","9:16","1:1","4:3","3:4","4:5","5:4","9:21","21:9"],"type":"string"},"duration":{"minimum":3,"maximum":15,"type":"integer"},"seed":{"minimum":-1,"maximum":2147483647,"type":"integer"}}},
"alibaba/wan-2.5/text-to-video":{"required":["model","prompt","size"],"type":"object","properties":{"model":{"type":"string"},"audio":{"type":"string"},"duration":{"enum":[5,10],"type":"integer"},"enable_prompt_expansion":{"type":"boolean"},"negative_prompt":{"type":"string"},"prompt":{"type":"string"},"seed":{"type":"integer"},"size":{"enum":["832*480","480*832","624*624","1280*720","720*1280","960*960","1088*832","832*1088","1920*1080","1080*1920","1440*1440","1632*1248","1248*1632"],"type":"string"},"generate_audio":{"type":"boolean"}}},
"alibaba/wan-2.5/image-to-video":{"required":["model","image","prompt","resolution"],"type":"object","properties":{"model":{"type":"string"},"audio":{"type":"string"},"duration":{"enum":[5,10],"type":"integer"},"enable_prompt_expansion":{"type":"boolean"},"image":{"type":"string"},"negative_prompt":{"type":"string"},"prompt":{"type":"string"},"resolution":{"enum":["480p","720p","1080p"],"type":"string"},"generate_audio":{"type":"boolean"},"seed":{"type":"integer"}}},
"alibaba/wan-2.6/text-to-video":{"required":["model","prompt","size"],"type":"object","properties":{"model":{"type":"string"},"audio":{"type":"string"},"duration":{"enum":[5,10,15],"type":"integer"},"enable_prompt_expansion":{"type":"boolean"},"negative_prompt":{"type":"string"},"prompt":{"type":"string"},"seed":{"type":"integer"},"size":{"enum":["1280*720","720*1280","960*960","1088*832","832*1088","1920*1080","1080*1920","1440*1440","1632*1248","1248*1632"],"type":"string"},"shot_type":{"enum":["multi","single"],"type":"string"},"generate_audio":{"type":"boolean"}}},
"alibaba/wan-2.7/text-to-video":{"type":"object","required":["model","prompt"],"properties":{"model":{"type":"string","enum":["alibaba/wan-2.7/text-to-video"]},"prompt":{"type":"string"},"negative_prompt":{"type":"string"},"audio":{"type":"string"},"resolution":{"enum":["720P","1080P"],"type":"string"},"ratio":{"enum":["16:9","9:16","1:1","4:3","3:4"],"type":"string"},"duration":{"minimum":2,"maximum":15,"type":"integer"},"prompt_extend":{"type":"boolean"},"seed":{"minimum":-1,"maximum":2147483647,"type":"integer"}}},
"alibaba/wan-2.7/image-to-video":{"type":"object","required":["model"],"properties":{"model":{"type":"string","enum":["alibaba/wan-2.7/image-to-video"]},"prompt":{"type":"string"},"negative_prompt":{"type":"string"},"image":{"type":"string"},"last_image":{"type":"string"},"video":{"type":"string"},"audio":{"type":"string"},"resolution":{"enum":["720P","1080P"],"type":"string"},"duration":{"minimum":2,"maximum":15,"type":"integer"},"prompt_extend":{"type":"boolean"},"seed":{"minimum":-1,"maximum":2147483647,"type":"integer"}}},
"alibaba/wan-2.7/reference-to-video":{"type":"object","required":["model","prompt"],"properties":{"model":{"type":"string","enum":["alibaba/wan-2.7/reference-to-video"]},"prompt":{"type":"string"},"negative_prompt":{"type":"string"},"images":{"type":"array","items":{"type":"string"}},"videos":{"type":"array","items":{"type":"string"}},"audio":{"type":"string"},"resolution":{"enum":["720P","1080P"],"type":"string"},"ratio":{"enum":["16:9","9:16","1:1","4:3","3:4"],"type":"string"},"duration":{"minimum":2,"maximum":10,"type":"integer"},"prompt_extend":{"type":"boolean"},"seed":{"minimum":-1,"maximum":2147483647,"type":"integer"}}},
"alibaba/wan-3.0-prime/text-to-video":{"required":["model","prompt"],"type":"object","properties":{"model":{"type":"string"},"prompt":{"type":"string"},"resolution":{"enum":["1080p","720p","480p","720p-esr","1080p-esr","1440p-esr","4k-esr"],"type":"string"},"duration":{"enum":[-1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30],"type":"number"},"ratio":{"enum":["adaptive","16:9","4:3","1:1","3:4","9:16"],"type":"string"},"audio":{"type":"boolean"},"seed":{"type":"integer"}}},
"alibaba/wan-3.0-prime/image-to-video":{"required":["model","prompt","image"],"type":"object","properties":{"model":{"type":"string"},"prompt":{"type":"string"},"image":{"type":"string"},"last_image":{"type":"string"},"resolution":{"enum":["1080p","720p","480p","720p-esr","1080p-esr","1440p-esr","4k-esr"],"type":"string"},"duration":{"enum":[-1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30],"type":"number"},"audio":{"type":"boolean"},"seed":{"type":"integer"}}},
"alibaba/wan-3.0-prime/reference-to-video":{"required":["model","prompt"],"type":"object","properties":{"model":{"type":"string"},"prompt":{"type":"string"},"refers":{"type":"array","maxItems":20,"items":{"type":"object","required":["url"],"properties":{"url":{"type":"string"},"type":{"type":"string","enum":["image","video","audio"]}}}},"resolution":{"enum":["1080p","720p","480p","720p-esr","1080p-esr","1440p-esr","4k-esr"],"type":"string"},"duration":{"enum":[-1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30],"type":"number"},"ratio":{"enum":["adaptive","16:9","4:3","1:1","3:4","9:16"],"type":"string"},"audio":{"type":"boolean"},"enable_thinking":{"type":"boolean"},"file":{"type":"string"},"link":{"type":"string"},"seed":{"type":"integer"}}},
"alibaba/wan-3.0/text-to-video":{"required":["model","prompt"],"type":"object","properties":{"model":{"type":"string"},"prompt":{"type":"string"},"resolution":{"enum":["1080p","720p","480p","720p-esr","1080p-esr","1440p-esr","4k-esr"],"type":"string"},"duration":{"enum":[-1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30],"type":"number"},"ratio":{"enum":["adaptive","16:9","4:3","1:1","3:4","9:16"],"type":"string"},"audio":{"type":"boolean"},"seed":{"type":"integer"}}},
"alibaba/wan-3.0/image-to-video":{"required":["model","prompt","image"],"type":"object","properties":{"model":{"type":"string"},"prompt":{"type":"string"},"image":{"type":"string"},"last_image":{"type":"string"},"resolution":{"enum":["1080p","720p","480p","720p-esr","1080p-esr","1440p-esr","4k-esr"],"type":"string"},"duration":{"enum":[-1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30],"type":"number"},"audio":{"type":"boolean"},"seed":{"type":"integer"}}},
"alibaba/wan-3.0/reference-to-video":{"required":["model","prompt"],"type":"object","properties":{"model":{"type":"string"},"prompt":{"type":"string"},"refers":{"type":"array","maxItems":20,"items":{"type":"object","required":["url","type"],"properties":{"url":{"type":"string"},"type":{"type":"string","enum":["image","video","audio"]}}}},"resolution":{"enum":["1080p","720p","480p","720p-esr","1080p-esr","1440p-esr","4k-esr"],"type":"string"},"duration":{"enum":[-1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30],"type":"number"},"ratio":{"enum":["adaptive","16:9","4:3","1:1","3:4","9:16"],"type":"string"},"audio":{"type":"boolean"},"enable_thinking":{"type":"boolean"},"file":{"type":"string"},"link":{"type":"string"},"seed":{"type":"integer"}}},
"atlascloud/van-2.5/text-to-video":{"required":["model","prompt","size"],"type":"object","properties":{"model":{"type":"string"},"audio":{"type":"string"},"duration":{"enum":[5,10],"type":"integer"},"enable_prompt_expansion":{"type":"boolean"},"negative_prompt":{"type":"string"},"prompt":{"type":"string"},"seed":{"type":"integer"},"size":{"enum":["1280*720","720*1280","1920*1080","1080*1920"],"type":"string"}}},
"atlascloud/van-2.5/image-to-video":{"required":["model","image","prompt","resolution"],"type":"object","properties":{"model":{"type":"string"},"audio":{"type":"string"},"duration":{"enum":[5,10],"type":"integer"},"enable_prompt_expansion":{"type":"boolean"},"image":{"type":"string"},"negative_prompt":{"type":"string"},"prompt":{"type":"string"},"resolution":{"enum":["720p","1080p"],"type":"string"},"seed":{"type":"integer"}}},
"atlascloud/van-2.6/text-to-video":{"required":["model","prompt","size"],"type":"object","properties":{"model":{"type":"string"},"audio":{"type":"string"},"duration":{"enum":[5,10,15],"type":"integer"},"enable_prompt_expansion":{"type":"boolean"},"negative_prompt":{"type":"string"},"prompt":{"type":"string"},"seed":{"type":"integer"},"size":{"enum":["1920*1080","1080*1920","1440*1440","1632*1248","1248*1632"],"type":"string"},"shot_type":{"enum":["multi","single"],"type":"string"},"generate_audio":{"type":"boolean"}}},
"atlascloud/van-2.6/image-to-video":{"required":["model","image","prompt","resolution"],"type":"object","properties":{"model":{"type":"string"},"audio":{"type":"string"},"duration":{"enum":[5,10,15],"type":"integer"},"enable_prompt_expansion":{"type":"boolean"},"image":{"type":"string"},"negative_prompt":{"type":"string"},"prompt":{"type":"string"},"resolution":{"enum":["1080p"],"type":"string"},"seed":{"type":"integer"},"shot_type":{"enum":["multi","single"],"type":"string"},"generate_audio":{"type":"boolean"}}},
"bytedance/seedance-2.0-fast/text-to-video":{"type":"object","required":["model","prompt"],"properties":{"model":{"type":"string"},"prompt":{"type":"string"},"duration":{"type":"integer","enum":[-1,4,5,6,7,8,9,10,11,12,13,14,15]},"resolution":{"type":"string","enum":["480p","720p","720p-SR","1080p-SR","1440p-SR"]},"ratio":{"type":"string","enum":["16:9","4:3","1:1","3:4","9:16","21:9","adaptive"]},"bitrate_mode":{"type":"string","enum":["standard","high"]},"generate_audio":{"type":"boolean"},"seed":{"type":"integer","minimum":-1,"maximum":4294967295},"watermark":{"type":"boolean"},"return_last_frame":{"type":"boolean"}}},
"bytedance/seedance-2.0-fast/image-to-video":{"type":"object","required":["model","image"],"properties":{"model":{"type":"string"},"prompt":{"type":"string"},"image":{"type":"string"},"last_image":{"type":"string"},"duration":{"type":"integer","enum":[-1,4,5,6,7,8,9,10,11,12,13,14,15]},"resolution":{"type":"string","enum":["480p","720p","720p-SR","1080p-SR","1440p-SR"]},"ratio":{"type":"string","enum":["16:9","4:3","1:1","3:4","9:16","21:9","adaptive"]},"bitrate_mode":{"type":"string","enum":["standard","high"]},"generate_audio":{"type":"boolean"},"seed":{"type":"integer","minimum":-1,"maximum":4294967295},"watermark":{"type":"boolean"},"return_last_frame":{"type":"boolean"}}},
"bytedance/seedance-2.0-fast/reference-to-video":{"type":"object","required":["model"],"properties":{"model":{"type":"string"},"prompt":{"type":"string"},"reference_images":{"type":"array","minItems":1,"maxItems":9,"items":{"type":"string"}},"reference_videos":{"type":"array","minItems":1,"maxItems":3,"items":{"type":"string"}},"duration":{"type":"integer","enum":[-1,4,5,6,7,8,9,10,11,12,13,14,15]},"resolution":{"type":"string","enum":["480p","720p","720p-SR","1080p-SR","1440p-SR"]},"ratio":{"type":"string","enum":["16:9","4:3","1:1","3:4","9:16","21:9","adaptive"]},"bitrate_mode":{"type":"string","enum":["standard","high"]},"generate_audio":{"type":"boolean"},"seed":{"type":"integer","minimum":-1,"maximum":4294967295},"watermark":{"type":"boolean"},"return_last_frame":{"type":"boolean"},"reference_audios":{"type":"array","minItems":1,"maxItems":3,"items":{"type":"string"}}}},
"bytedance/seedance-2.0-mini/text-to-video":{"type":"object","required":["model","prompt"],"properties":{"model":{"type":"string"},"prompt":{"type":"string"},"duration":{"type":"integer","enum":[-1,4,5,6,7,8,9,10,11,12,13,14,15]},"resolution":{"type":"string","enum":["480p","720p","720p-SR","1080p-SR","1440p-SR"]},"ratio":{"type":"string","enum":["16:9","4:3","1:1","3:4","9:16","21:9","adaptive"]},"bitrate_mode":{"type":"string","enum":["standard","high"]},"generate_audio":{"type":"boolean"},"seed":{"type":"integer","minimum":-1,"maximum":4294967295},"watermark":{"type":"boolean"},"return_last_frame":{"type":"boolean"}}},
"bytedance/seedance-2.0-mini/image-to-video":{"type":"object","required":["model","image"],"properties":{"model":{"type":"string"},"prompt":{"type":"string"},"image":{"type":"string"},"last_image":{"type":"string"},"duration":{"type":"integer","enum":[-1,4,5,6,7,8,9,10,11,12,13,14,15]},"resolution":{"type":"string","enum":["480p","720p","720p-SR","1080p-SR","1440p-SR"]},"ratio":{"type":"string","enum":["16:9","4:3","1:1","3:4","9:16","21:9","adaptive"]},"bitrate_mode":{"type":"string","enum":["standard","high"]},"generate_audio":{"type":"boolean"},"seed":{"type":"integer","minimum":-1,"maximum":4294967295},"watermark":{"type":"boolean"},"return_last_frame":{"type":"boolean"}}},
"bytedance/seedance-2.0-mini/reference-to-video":{"type":"object","required":["model"],"properties":{"model":{"type":"string"},"prompt":{"type":"string"},"reference_images":{"type":"array","minItems":1,"maxItems":9,"items":{"type":"string"}},"reference_videos":{"type":"array","minItems":1,"maxItems":3,"items":{"type":"string"}},"duration":{"type":"integer","enum":[-1,4,5,6,7,8,9,10,11,12,13,14,15]},"resolution":{"type":"string","enum":["480p","720p","720p-SR","1080p-SR","1440p-SR"]},"ratio":{"type":"string","enum":["16:9","4:3","1:1","3:4","9:16","21:9","adaptive"]},"bitrate_mode":{"type":"string","enum":["standard","high"]},"generate_audio":{"type":"boolean"},"seed":{"type":"integer","minimum":-1,"maximum":4294967295},"watermark":{"type":"boolean"},"return_last_frame":{"type":"boolean"},"reference_audios":{"type":"array","minItems":1,"maxItems":3,"items":{"type":"string"}}}},
"google/gemini-omni-flash/text-to-video":{"required":["model","prompt"],"type":"object","properties":{"model":{"type":"string"},"prompt":{"type":"string"},"duration":{"type":"integer","maximum":10,"minimum":3},"aspect_ratio":{"enum":["16:9","9:16"],"type":"string"},"resolution":{"enum":["720p"],"type":"string"},"thinking_level":{"enum":["default","high","low"],"type":"string"},"seed":{"type":"integer"}}},
"google/gemini-omni-flash/image-to-video":{"required":["model","image","prompt"],"type":"object","properties":{"model":{"type":"string"},"image":{"type":"string"},"prompt":{"type":"string"},"duration":{"maximum":10,"minimum":3,"type":"integer"},"aspect_ratio":{"enum":["16:9","9:16"],"type":"string"},"resolution":{"enum":["720p"],"type":"string"},"thinking_level":{"enum":["default","high","low"],"type":"string"},"seed":{"type":"integer"}}},
"google/gemini-omni-flash/reference-to-video":{"required":["model","prompt","images"],"type":"object","properties":{"model":{"type":"string"},"prompt":{"type":"string"},"images":{"maxItems":10,"minItems":1,"type":"array","items":{"type":"string"}},"duration":{"maximum":10,"minimum":3,"type":"integer"},"aspect_ratio":{"enum":["16:9","9:16"],"type":"string"},"resolution":{"enum":["720p"],"type":"string"},"thinking_level":{"enum":["default","high","low"],"type":"string"},"seed":{"type":"integer"}}},
"google/veo3.1-fast/text-to-video":{"required":["model","prompt"],"type":"object","properties":{"model":{"type":"string"},"aspect_ratio":{"enum":["16:9","9:16"],"type":"string"},"duration":{"enum":[8,4,6],"type":"integer"},"generate_audio":{"type":"boolean"},"negative_prompt":{"type":"string"},"prompt":{"type":"string"},"resolution":{"enum":["720p","1080p","4k"],"type":"string"},"seed":{"type":"integer"}}},
"google/veo3.1-fast/image-to-video":{"required":["model","prompt","image"],"type":"object","properties":{"model":{"type":"string"},"aspect_ratio":{"enum":["16:9","9:16"],"type":"string"},"duration":{"enum":[8,4,6],"type":"integer"},"generate_audio":{"type":"boolean"},"image":{"type":"string"},"last_image":{"type":"string"},"negative_prompt":{"type":"string"},"prompt":{"type":"string"},"resolution":{"enum":["720p","1080p","4k"],"type":"string"},"seed":{"type":"integer"}}},
"google/veo3.1-lite/text-to-video":{"required":["model","prompt"],"type":"object","properties":{"model":{"type":"string"},"prompt":{"type":"string"},"aspect_ratio":{"enum":["16:9","9:16"],"type":"string"},"duration":{"enum":[4,6,8],"type":"integer"},"resolution":{"enum":["720p","1080p"],"type":"string"},"seed":{"type":"integer"}}},
"google/veo3.1-lite/image-to-video":{"required":["model","prompt","image"],"type":"object","properties":{"model":{"type":"string"},"prompt":{"type":"string"},"image":{"type":"string"},"aspect_ratio":{"enum":["16:9","9:16"],"type":"string"},"duration":{"enum":[4,6,8],"type":"integer"},"resolution":{"enum":["720p","1080p"],"type":"string"},"seed":{"type":"integer"}}},
"google/veo3.1-lite/start-end-frame-to-video":{"required":["model","prompt","image","last_image"],"type":"object","properties":{"model":{"type":"string"},"prompt":{"type":"string"},"image":{"type":"string"},"last_image":{"type":"string"},"aspect_ratio":{"enum":["16:9","9:16"],"type":"string"},"duration":{"enum":[4,6,8],"type":"integer"},"resolution":{"enum":["720p","1080p"],"type":"string"},"seed":{"type":"integer"}}},
"google/veo3.1/text-to-video":{"required":["model","prompt"],"type":"object","properties":{"model":{"type":"string"},"aspect_ratio":{"enum":["16:9","9:16"],"type":"string"},"duration":{"enum":[8,4,6],"type":"integer"},"generate_audio":{"type":"boolean"},"negative_prompt":{"type":"string"},"prompt":{"type":"string"},"resolution":{"enum":["720p","1080p","4k"],"type":"string"},"seed":{"type":"integer"}}},
"google/veo3.1/image-to-video":{"required":["model","prompt","image"],"type":"object","properties":{"model":{"type":"string"},"aspect_ratio":{"enum":["16:9","9:16"],"type":"string"},"duration":{"enum":[8,4,6],"type":"integer"},"generate_audio":{"type":"boolean"},"image":{"type":"string"},"last_image":{"type":"string"},"negative_prompt":{"type":"string"},"prompt":{"type":"string"},"resolution":{"enum":["720p","1080p","4k"],"type":"string"},"seed":{"type":"integer"}}},
"google/veo3.1/reference-to-video":{"required":["model","prompt","images"],"type":"object","properties":{"model":{"type":"string"},"generate_audio":{"type":"boolean"},"images":{"maxItems":3,"minItems":1,"type":"array","items":{"type":"string"}},"negative_prompt":{"type":"string"},"prompt":{"type":"string"},"duration":{"enum":[8],"type":"integer"},"resolution":{"enum":["720p","1080p","4k"],"type":"string"},"seed":{"type":"integer"}}},
"kwaivgi/kling-v3.0-4k/text-to-video":{"required":["model"],"type":"object","properties":{"model":{"type":"string"},"aspect_ratio":{"enum":["16:9","9:16","1:1"],"type":"string"},"cfg_scale":{"maximum":1,"minimum":0,"type":"number"},"duration":{"enum":[3,4,5,6,7,8,9,10,11,12,13,14,15],"type":"integer"},"negative_prompt":{"type":"string"},"prompt":{"type":"string"},"sound":{"type":"boolean"},"multi_shot":{"type":"boolean"},"shot_type":{"type":"string","enum":["customize","intelligence"]}}},
"kwaivgi/kling-v3.0-4k/image-to-video":{"required":["model","image"],"type":"object","properties":{"model":{"type":"string"},"cfg_scale":{"maximum":1,"minimum":0,"type":"number"},"duration":{"enum":[3,4,5,6,7,8,9,10,11,12,13,14,15],"type":"integer"},"end_image":{"type":"string"},"image":{"type":"string"},"negative_prompt":{"type":"string"},"prompt":{"type":"string"},"sound":{"type":"boolean"},"resolution":{"type":"string"},"multi_shot":{"type":"boolean"},"shot_type":{"type":"string","enum":["customize","intelligence"]}}},
"kwaivgi/kling-v3.0-pro/text-to-video":{"required":["model"],"type":"object","properties":{"model":{"type":"string"},"aspect_ratio":{"enum":["16:9","9:16","1:1"],"type":"string"},"cfg_scale":{"maximum":1,"minimum":0,"type":"number"},"duration":{"enum":[3,4,5,6,7,8,9,10,11,12,13,14,15],"type":"integer"},"negative_prompt":{"type":"string"},"prompt":{"type":"string"},"sound":{"type":"boolean"},"multi_shot":{"type":"boolean"},"shot_type":{"type":"string","enum":["customize","intelligence"]}}},
"kwaivgi/kling-v3.0-pro/image-to-video":{"required":["model","image"],"type":"object","properties":{"model":{"type":"string","enum":["kwaivgi/kling-v3.0-pro/image-to-video"]},"cfg_scale":{"maximum":1,"minimum":0,"type":"number"},"duration":{"enum":[3,4,5,6,7,8,9,10,11,12,13,14,15],"type":"integer"},"end_image":{"type":"string"},"image":{"type":"string"},"negative_prompt":{"type":"string"},"prompt":{"type":"string"},"sound":{"type":"boolean"},"resolution":{"type":"string","enum":["1080P","1440P-SR"]},"multi_shot":{"type":"boolean"},"shot_type":{"type":"string","enum":["customize","intelligence"]}}},
"kwaivgi/kling-v3.0-std/text-to-video":{"required":["model"],"type":"object","properties":{"model":{"type":"string"},"aspect_ratio":{"enum":["16:9","9:16","1:1"],"type":"string"},"cfg_scale":{"maximum":1,"minimum":0,"type":"number"},"duration":{"enum":[3,4,5,6,7,8,9,10,11,12,13,14,15],"type":"integer"},"negative_prompt":{"type":"string"},"prompt":{"type":"string"},"sound":{"type":"boolean"},"multi_shot":{"type":"boolean"},"shot_type":{"type":"string","enum":["customize","intelligence"]}}},
"kwaivgi/kling-v3.0-std/image-to-video":{"required":["model","image"],"type":"object","properties":{"model":{"type":"string","enum":["kwaivgi/kling-v3.0-std/image-to-video"]},"cfg_scale":{"maximum":1,"minimum":0,"type":"number"},"duration":{"enum":[3,4,5,6,7,8,9,10,11,12,13,14,15],"type":"integer"},"end_image":{"type":"string"},"image":{"type":"string"},"negative_prompt":{"type":"string"},"prompt":{"type":"string"},"sound":{"type":"boolean"},"resolution":{"type":"string","enum":["720P","1080P-SR","1440P-SR"]},"multi_shot":{"type":"boolean"},"shot_type":{"type":"string","enum":["customize","intelligence"]}}},
"kwaivgi/kling-v3.0-turbo/text-to-video":{"required":["model","prompt"],"type":"object","properties":{"model":{"type":"string"},"aspect_ratio":{"enum":["16:9","9:16","1:1"],"type":"string"},"resolution":{"enum":["720p","1080p"],"type":"string"},"duration":{"enum":[3,4,5,6,7,8,9,10,11,12,13,14,15],"type":"integer"},"prompt":{"type":"string"}}},
"kwaivgi/kling-v3.0-turbo/image-to-video":{"required":["model","image"],"type":"object","properties":{"model":{"type":"string"},"duration":{"enum":[3,4,5,6,7,8,9,10,11,12,13,14,15],"type":"integer"},"image":{"type":"string"},"prompt":{"type":"string"},"resolution":{"enum":["720p","1080p"],"type":"string"}}},
"kwaivgi/kling-video-o1/text-to-video":{"required":["model","prompt"],"type":"object","properties":{"model":{"type":"string"},"aspect_ratio":{"enum":["16:9","9:16","1:1"],"type":"string"},"duration":{"enum":[5,10],"type":"integer"},"prompt":{"type":"string"}}},
"kwaivgi/kling-video-o1/image-to-video":{"required":["model","prompt","image"],"type":"object","properties":{"model":{"type":"string"},"aspect_ratio":{"enum":["16:9","9:16","1:1"],"type":"string"},"duration":{"enum":[5,10],"type":"integer"},"image":{"type":"string"},"last_image":{"type":"string"},"prompt":{"type":"string"}}},
"kwaivgi/kling-video-o3-4k/text-to-video":{"required":["model"],"type":"object","properties":{"model":{"type":"string"},"aspect_ratio":{"enum":["16:9","9:16","1:1"],"type":"string"},"duration":{"enum":[3,4,5,6,7,8,9,10,11,12,13,14,15],"type":"integer"},"prompt":{"type":"string"},"sound":{"type":"boolean"},"multi_shot":{"type":"boolean"},"shot_type":{"type":"string","enum":["customize","intelligence"]}}},
"kwaivgi/kling-video-o3-4k/image-to-video":{"required":["model","image"],"type":"object","properties":{"model":{"type":"string"},"duration":{"enum":[3,4,5,6,7,8,9,10,11,12,13,14,15],"type":"integer"},"end_image":{"type":"string"},"image":{"type":"string"},"prompt":{"type":"string"},"sound":{"type":"boolean"},"multi_shot":{"type":"boolean"},"shot_type":{"type":"string","enum":["customize","intelligence"]}}},
"minimax/h3/text-to-video":{"required":["model","prompt","resolution","duration"],"type":"object","properties":{"model":{"type":"string"},"prompt":{"type":"string"},"resolution":{"enum":["480P","768P","2K"],"type":"string"},"duration":{"enum":[4,5,6,7,8,9,10,11,12,13,14,15],"type":"number"},"ratio":{"enum":["21:9","16:9","4:3","1:1","3:4","9:16"],"type":"string"},"prompt_expansion":{"type":"boolean"}}},
"minimax/h3/image-to-video":{"required":["model","prompt","resolution","duration"],"type":"object","properties":{"model":{"type":"string"},"prompt":{"type":"string"},"image":{"type":"string"},"end_image":{"type":"string"},"resolution":{"enum":["480P","768P","2K","1080p-esr","1440p-esr","4k-esr"],"type":"string"},"duration":{"enum":[4,5,6,7,8,9,10,11,12,13,14,15],"type":"number"},"ratio":{"enum":["adaptive"],"type":"string"},"prompt_expansion":{"type":"boolean"}}},
"minimax/h3/reference-to-video":{"required":["model","prompt","resolution","duration","refers"],"type":"object","properties":{"model":{"type":"string"},"prompt":{"type":"string"},"refers":{"type":"array","minItems":1,"items":{"type":"object","required":["url"],"properties":{"url":{"type":"string"},"type":{"type":"string","enum":["image","video","audio"]}}}},"resolution":{"enum":["480P","768P","2K","1080p-esr","1440p-esr","4k-esr"],"type":"string"},"duration":{"enum":[4,5,6,7,8,9,10,11,12,13,14,15],"type":"number"},"ratio":{"enum":["adaptive","21:9","16:9","4:3","1:1","3:4","9:16"],"type":"string"},"prompt_expansion":{"type":"boolean"}}},
"pixverse/c1/text-to-video":{"required":["model","prompt"],"type":"object","properties":{"model":{"type":"string"},"duration":{"enum":[1,2,3,4,5,6,7,8,9,10,11,12,13,14,15],"type":"integer"},"prompt":{"type":"string"},"sound":{"type":"boolean"},"quality":{"enum":["360p","540p","720p","1080p"],"type":"string"},"aspect_ratio":{"enum":["16:9","9:16","1:1","4:3","3:4","2:3","3:2","21:9"],"type":"string"},"seed":{"type":"integer"}}},
"pixverse/c1/image-to-video":{"required":["model","prompt"],"type":"object","properties":{"model":{"type":"string"},"duration":{"enum":[1,2,3,4,5,6,7,8,9,10,11,12,13,14,15],"type":"integer"},"prompt":{"type":"string"},"image":{"type":"string"},"sound":{"type":"boolean"},"quality":{"enum":["360p","540p","720p","1080p"],"type":"string"},"seed":{"type":"integer"}}},
"pixverse/c1/start-end-to-video":{"required":["model","prompt"],"type":"object","properties":{"model":{"type":"string"},"duration":{"enum":[1,2,3,4,5,6,7,8,9,10,11,12,13,14,15],"type":"integer"},"image":{"type":"string"},"end_image":{"type":"string"},"prompt":{"type":"string"},"sound":{"type":"boolean"},"quality":{"enum":["360p","540p","720p","1080p"],"type":"string"},"seed":{"type":"integer"}}},
"pixverse/c1/reference-to-video":{"required":["model","prompt","images"],"type":"object","properties":{"model":{"type":"string"},"duration":{"enum":[1,2,3,4,5,6,7,8,9,10,11,12,13,14,15],"type":"integer"},"prompt":{"type":"string"},"sound":{"type":"boolean"},"quality":{"enum":["360p","540p","720p","1080p"],"type":"string"},"aspect_ratio":{"enum":["16:9","9:16","1:1","4:3","3:4","2:3","3:2","21:9"],"type":"string"},"seed":{"type":"integer"},"images":{"type":"array","minItems":1,"maxItems":7,"items":{"type":"object","required":["image"],"properties":{"image":{"type":"string"},"type":{"type":"string","enum":["subject","background"]},"ref_name":{"type":"string"}}}}}},
"pixverse/v6/text-to-video":{"required":["model","prompt"],"type":"object","properties":{"model":{"type":"string"},"duration":{"enum":[1,2,3,4,5,6,7,8,9,10,11,12,13,14,15],"type":"integer"},"prompt":{"type":"string"},"sound":{"type":"boolean"},"quality":{"enum":["360p","540p","720p","1080p"],"type":"string"},"aspect_ratio":{"enum":["16:9","9:16","1:1","4:3","3:4","2:3","3:2","21:9"],"type":"string"},"seed":{"type":"integer"}}},
"pixverse/v6/image-to-video":{"required":["model","prompt"],"type":"object","properties":{"model":{"type":"string"},"duration":{"enum":[1,2,3,4,5,6,7,8,9,10,11,12,13,14,15],"type":"integer"},"prompt":{"type":"string"},"image":{"type":"string"},"sound":{"type":"boolean"},"quality":{"enum":["360p","540p","720p","1080p"],"type":"string"},"seed":{"type":"integer"}}},
"pixverse/v6/start-end-to-video":{"required":["model","prompt"],"type":"object","properties":{"model":{"type":"string"},"duration":{"enum":[1,2,3,4,5,6,7,8,9,10,11,12,13,14,15],"type":"integer"},"image":{"type":"string"},"end_image":{"type":"string"},"prompt":{"type":"string"},"sound":{"type":"boolean"},"quality":{"enum":["360p","540p","720p","1080p"],"type":"string"},"seed":{"type":"integer"}}},
"pixverse/v6/reference-to-video":{"required":["model","prompt","images"],"type":"object","properties":{"model":{"type":"string"},"duration":{"enum":[1,2,3,4,5,6,7,8,9,10,11,12,13,14,15],"type":"integer"},"prompt":{"type":"string"},"sound":{"type":"boolean"},"quality":{"enum":["360p","540p","720p","1080p"],"type":"string"},"aspect_ratio":{"enum":["16:9","9:16","1:1","4:3","3:4","2:3","3:2","21:9"],"type":"string"},"seed":{"type":"integer"},"images":{"type":"array","minItems":1,"maxItems":7,"items":{"type":"object","required":["image"],"properties":{"image":{"type":"string"},"type":{"type":"string","enum":["subject","background"]},"ref_name":{"type":"string"}}}}}},
"xai/grok-imagine-video-v1.5/text-to-video":{"type":"object","required":["model","prompt"],"properties":{"model":{"type":"string"},"prompt":{"type":"string"},"duration":{"type":"integer","minimum":1,"maximum":15},"resolution":{"type":"string","enum":["480p","720p","1080p"]},"aspect_ratio":{"type":"string","enum":["1:1","16:9","9:16","4:3","3:4","3:2","2:3"]}}},
"xai/grok-imagine-video-v1.5/image-to-video":{"type":"object","required":["model","prompt","image_url"],"properties":{"model":{"type":"string"},"prompt":{"type":"string"},"image_url":{"type":"string"},"duration":{"type":"integer","minimum":1,"maximum":15},"resolution":{"type":"string","enum":["480p","720p","1080p"]},"aspect_ratio":{"type":"string","enum":["1:1","16:9","9:16","4:3","3:4","3:2","2:3"]}}},
"xai/grok-imagine-video-v1.5/reference-to-video":{"type":"object","required":["model","prompt","image_urls"],"properties":{"model":{"type":"string"},"prompt":{"type":"string"},"image_urls":{"type":"array","minItems":1,"maxItems":7,"items":{"type":"string"}},"duration":{"type":"integer","minimum":1,"maximum":15},"resolution":{"type":"string","enum":["480p","720p"]},"aspect_ratio":{"type":"string","enum":["1:1","16:9","9:16","4:3","3:4","3:2","2:3"]}}},
"xai/grok-imagine-video/text-to-video":{"type":"object","required":["model","prompt"],"properties":{"model":{"type":"string"},"prompt":{"type":"string"},"duration":{"type":"integer","minimum":1,"maximum":15},"resolution":{"type":"string","enum":["480p","720p"]},"aspect_ratio":{"type":"string","enum":["1:1","16:9","9:16","4:3","3:4","3:2","2:3"]}}},
"xai/grok-imagine-video/image-to-video":{"type":"object","required":["model","prompt","image_url"],"properties":{"model":{"type":"string"},"prompt":{"type":"string"},"image_url":{"type":"string"},"duration":{"type":"integer","minimum":1,"maximum":15},"resolution":{"type":"string","enum":["480p","720p"]},"aspect_ratio":{"type":"string","enum":["1:1","16:9","9:16","4:3","3:4","3:2","2:3"]}}},
"xai/grok-imagine-video/reference-to-video":{"type":"object","required":["model","prompt","image_urls"],"properties":{"model":{"type":"string"},"prompt":{"type":"string"},"image_urls":{"type":"array","minItems":1,"maxItems":7,"items":{"type":"string"}},"duration":{"type":"integer","minimum":1,"maximum":10},"resolution":{"type":"string","enum":["480p","720p"]},"aspect_ratio":{"type":"string","enum":["1:1","16:9","9:16","4:3","3:4","3:2","2:3"]}}}
}''';
