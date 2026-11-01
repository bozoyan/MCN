// 职责: 通过 New API 的 OpenAI Speech 接口合成语音并校验音频回执。
// 关联文件:
//   lib/shared/services/ai/audio/client.dart
//   lib/shared/models/audio/channels.dart
//   lib/shared/services/ai/new_api.dart
import 'dart:convert';
import 'dart:typed_data';
import '../../../models/audio/request.dart';
import '../../../models/audio/exception.dart';
import 'client.dart';

class NewApiAudioClient extends AudioClient {
  NewApiAudioClient(
    super.client,
    super.apiKey, {
    required super.providerType,
    required this.endpoint,
    super.timeout,
  });
  final Uri endpoint;
  @override
  Uri get requestUrl => endpoint.replace(path: '${endpoint.path}/audio/speech');
  @override
  AudioRequestDefaults get unlistedModelDefaults => const AudioRequestDefaults(
    responseFormat: ConfigValue('mp3'),
    voice: ConfigValue('alloy'),
  );
  @override
  Map<String, String> get headers => {'Authorization': 'Bearer $apiKey'};
  @override
  Map<String, dynamic> encode(
    AudioRequest request, {
    List<Uint8List> references = const [],
  }) {
    if (references.isNotEmpty ||
        request.references.isNotEmpty ||
        !{'mp3', 'wav'}.contains(request.parameters.responseFormat) ||
        request.parameters.voice?.isNotEmpty != true) {
      throw const AudioException('invalid_config');
    }
    return {
      'model': request.modelId,
      'input': request.prompt,
      'voice': request.parameters.voice,
      'response_format': request.parameters.responseFormat,
      if (request.parameters.instructions?.isNotEmpty == true)
        'instructions': request.parameters.instructions,
    };
  }

  @override
  AudioGenerationResult? decodeBinaryResult(
    Uint8List bytes,
    Map<String, String> headers,
    AudioRequest request,
  ) {
    final mime = (headers['content-type'] ?? '').split(';').first;
    final mp3 =
        bytes.length >= 3 &&
        ((bytes[0] == 0x49 && bytes[1] == 0x44 && bytes[2] == 0x33) ||
            (bytes[0] == 0xff && (bytes[1] & 0xe0) == 0xe0));
    final wav =
        bytes.length >= 44 &&
        ascii.decode(bytes.sublist(0, 4), allowInvalid: true) == 'RIFF' &&
        ascii.decode(bytes.sublist(8, 12), allowInvalid: true) == 'WAVE';
    if ((request.parameters.responseFormat == 'mp3' &&
            mime == 'audio/mpeg' &&
            mp3) ||
        (request.parameters.responseFormat == 'wav' &&
            {'audio/wav', 'audio/x-wav', 'audio/wave'}.contains(mime) &&
            wav)) {
      return AudioGenerationResult(bytes);
    }
    throw const FormatException('Invalid New API speech response');
  }

  @override
  AudioGenerationResult decodeResult(Map<String, dynamic> json) =>
      throw const FormatException('Expected binary speech response');
}
