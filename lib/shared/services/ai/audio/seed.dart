// 职责: 将音频请求及 WAV 回执转换为火山引擎 Seed Audio 协议。
// 关联文件:
//   lib/shared/services/ai/audio/client.dart
//   lib/shared/models/audio/request.dart
//   lib/shared/models/audio/channels.dart
import 'dart:convert';
import 'dart:typed_data';
import '../../../models/audio/request.dart';
import '../../../models/audio/exception.dart';
import 'client.dart';

class SeedAudioClient extends AudioClient {
  SeedAudioClient(
    super.client,
    super.apiKey, {
    required super.providerType,
    super.timeout,
  });

  static final endpoint = Uri.parse(
    'https://openspeech.bytedance.com/api/v3/tts/create',
  );
  @override
  Uri get requestUrl => endpoint;
  @override
  AudioRequestDefaults get unlistedModelDefaults =>
      const AudioRequestDefaults(responseFormat: ConfigValue('wav'));
  @override
  Map<String, String> get headers => {'X-Api-Key': apiKey};

  @override
  Map<String, dynamic> encode(
    AudioRequest request, {
    List<Uint8List> references = const [],
  }) {
    if (request.parameters.responseFormat != 'wav') {
      throw const AudioException('invalid_config');
    }
    if (references.length != request.references.length) {
      throw const AudioException('invalid_reference');
    }
    return {
      'model': request.modelId,
      'text_prompt': request.prompt,
      if (references.isNotEmpty)
        'references': [
          for (final (index, bytes) in references.indexed)
            {'${request.references[index].kind}_data': base64Encode(bytes)},
        ],
      'audio_config': {
        'format': request.parameters.responseFormat,
        if (request.parameters.sampleRate != null)
          'sample_rate': request.parameters.sampleRate,
      },
    };
  }

  static Uint8List decode(Map<String, dynamic> body) {
    final audio = body['audio'];
    if (audio is! String || audio.isEmpty) {
      throw const FormatException('Missing audio output');
    }
    final bytes = base64Decode(audio);
    if (bytes.length < 44 ||
        ascii.decode(bytes.sublist(0, 4)) != 'RIFF' ||
        ascii.decode(bytes.sublist(8, 12)) != 'WAVE') {
      throw const FormatException('Invalid WAV output');
    }
    return bytes;
  }

  @override
  AudioGenerationResult decodeResult(Map<String, dynamic> json) {
    final uri = json['url'] is String
        ? Uri.tryParse(json['url'] as String)
        : null;
    if (uri != null &&
        (uri.scheme != 'https' ||
            uri.host.isEmpty ||
            uri.userInfo.isNotEmpty)) {
      throw const FormatException('Invalid audio output URL');
    }
    return AudioGenerationResult(decode(json), url: uri);
  }
}
