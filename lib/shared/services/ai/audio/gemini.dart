// 职责: 调用 Gemini 原生语音接口，按返回 MIME 提取 WAV、MP3 和 OGG 音频。
// 关联文件:
//   lib/shared/services/ai/audio/client.dart
//   lib/shared/services/ai/new_api.dart
//   lib/shared/models/audio/channels.dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import '../../../models/audio/request.dart';
import '../../../models/audio/exception.dart';
import 'client.dart';

class GeminiAudioClient extends AudioClient {
  GeminiAudioClient(
    super.client,
    super.apiKey, {
    required super.providerType,
    required this.endpoint,
    super.timeout,
  });
  final Uri endpoint;
  @override
  Uri get requestUrl => endpoint;
  @override
  Uri submissionUrl(AudioRequest request) => endpoint.replace(
    path:
        '${endpoint.path}/v1beta/models/${Uri.encodeComponent(request.modelId)}:generateContent',
  );
  @override
  Map<String, String> get headers => {'x-goog-api-key': apiKey};
  @override
  AudioRequestDefaults get unlistedModelDefaults => const AudioRequestDefaults(
    responseFormat: ConfigValue('wav'),
    voice: ConfigValue('Kore'),
  );
  @override
  Map<String, dynamic> encode(
    AudioRequest request, {
    List<Uint8List> references = const [],
  }) {
    if (references.isNotEmpty ||
        request.references.isNotEmpty ||
        request.parameters.responseFormat != 'wav' ||
        request.parameters.voice?.isNotEmpty != true) {
      throw const AudioException('invalid_config');
    }
    final instruction = request.parameters.instructions;
    return {
      'contents': [
        {
          'role': 'user',
          'parts': [
            {
              'text': [
                if (instruction != null && instruction.isNotEmpty) instruction,
                request.prompt,
              ].join('\n\n'),
            },
          ],
        },
      ],
      'generationConfig': {
        'responseModalities': ['AUDIO'],
        'speechConfig': {
          'voiceConfig': {
            'prebuiltVoiceConfig': {'voiceName': request.parameters.voice},
          },
        },
      },
    };
  }

  @override
  AudioGenerationResult decodeResult(Map<String, dynamic> json) {
    final finishes = <String>[];
    for (final candidate in json['candidates'] as List? ?? []) {
      if (candidate['finishReason'] case final String reason) {
        finishes.add(reason);
      }
      for (final part in candidate['content']?['parts'] as List? ?? []) {
        final inline = part['inlineData'] ?? part['inline_data'];
        if (inline is! Map) {
          continue;
        }
        final mime = inline['mimeType'] ?? inline['mime_type'];
        if (mime is! String) {
          throw const FormatException('Missing Gemini inline MIME type');
        }
        final type = ContentType.parse(mime);
        if (type.primaryType != 'audio') {
          continue;
        }
        final data = inline['data'];
        if (data is! String || data.isEmpty) {
          throw FormatException('Empty Gemini audio payload ($mime)');
        }
        final Uint8List bytes;
        try {
          bytes = base64Decode(data);
        } on FormatException {
          // Do not attach the encoded audio to the exception or logs.
          throw FormatException('Invalid Gemini audio base64 ($mime)');
        }
        return _decodeAudio(type, bytes);
      }
    }
    throw FormatException(
      'Missing Gemini audio output; finishReasons=$finishes; '
      'blockReason=${json['promptFeedback']?['blockReason']}',
    );
  }

  // 按返回 MIME 保留容器音频，不在这里猜测格式或转码。
  // L16、A-law、μ-law 等其他格式暂不支持，需要时在此扩展。
  AudioGenerationResult _decodeAudio(ContentType type, Uint8List bytes) {
    final mime = type.mimeType.toLowerCase();
    if (bytes.isEmpty) {
      throw FormatException('Empty Gemini audio payload ($mime)');
    }
    final outputMime = switch (mime) {
      'audio/wav' || 'audio/x-wav' || 'audio/wave' => 'audio/wav',
      'audio/mp3' || 'audio/mpeg' => 'audio/mpeg',
      'audio/ogg' => 'audio/ogg',
      _ => throw FormatException('Unsupported Gemini audio MIME type: $type'),
    };
    return AudioGenerationResult(bytes, mimeType: outputMime);
  }
}
