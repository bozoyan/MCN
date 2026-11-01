// 职责: 将音频提示词和参考素材提交到 OpenRouter Speech API 并将 PCM 响应无损封装为 WAV。
// 关联文件:
//   lib/shared/services/ai/audio/client.dart
//   lib/shared/models/audio/channels.dart
//   lib/shared/models/audio/request.dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import '../../../models/audio/exception.dart';
import '../../../models/audio/request.dart';
import 'client.dart';

class OpenRouterAudioClient extends AudioClient {
  OpenRouterAudioClient(
    super.client,
    super.apiKey, {
    required super.providerType,
    super.timeout,
  });
  @override
  Uri get requestUrl => Uri.parse('https://openrouter.ai/api/v1/audio/speech');
  @override
  AudioRequestDefaults get unlistedModelDefaults =>
      const AudioRequestDefaults(responseFormat: ConfigValue('mp3'));
  @override
  Map<String, String> get headers => {'Authorization': 'Bearer $apiKey'};
  @override
  Map<String, dynamic> encode(
    AudioRequest request, {
    List<Uint8List> references = const [],
  }) {
    if (!{'pcm', 'mp3'}.contains(request.parameters.responseFormat)) {
      throw const AudioException('invalid_config');
    }
    if (references.length != request.references.length) {
      throw const AudioException('invalid_config');
    }
    return {
      'model': request.modelId,
      'input': request.prompt,
      if (request.parameters.voice?.isNotEmpty == true)
        'voice': request.parameters.voice,
      if (request.parameters.instructions?.isNotEmpty == true)
        'instructions': request.parameters.instructions,
      'response_format': request.parameters.responseFormat,
      if (references.isNotEmpty)
        'input_references': [
          for (var i = 0; i < references.length; i++)
            if (request.references[i].kind == 'image')
              {
                'type': 'image_url',
                'image_url': {
                  'url':
                      'data:${request.references[i].mimeType};base64,${base64Encode(references[i])}',
                },
              }
            else
              {
                'type': 'input_audio',
                'input_audio': {
                  'data':
                      'data:${request.references[i].mimeType};base64,${base64Encode(references[i])}',
                },
              },
        ],
    };
  }

  @override
  AudioGenerationResult decodeBinaryResult(
    Uint8List bytes,
    Map<String, String> headers,
    AudioRequest request,
  ) {
    // https://openrouter.ai/docs/api/api-reference/tts/create-speech
    // The PCM wire contract is signed 16-bit little-endian; rate and channel
    // count are supplied in Content-Type, not inferred from the model ID.
    final type = ContentType.parse(headers['content-type'] ?? '');
    if (request.parameters.responseFormat == 'mp3') {
      final id3 =
          bytes.length >= 3 &&
          bytes[0] == 0x49 &&
          bytes[1] == 0x44 &&
          bytes[2] == 0x33;
      final frame =
          bytes.length >= 4 && bytes[0] == 0xff && (bytes[1] & 0xe0) == 0xe0;
      if (type.mimeType != 'audio/mpeg' || (!id3 && !frame)) {
        throw const FormatException('Invalid OpenRouter MP3 response');
      }
      return AudioGenerationResult(bytes);
    }
    final rate = int.tryParse(type.parameters['rate'] ?? '');
    final channels = int.tryParse(type.parameters['channels'] ?? '');
    if (request.parameters.responseFormat != 'pcm' ||
        type.mimeType != 'audio/pcm' ||
        rate == null ||
        rate <= 0 ||
        channels == null ||
        channels <= 0 ||
        channels > 32767 ||
        rate * channels * 2 > 0xffffffff ||
        bytes.isEmpty ||
        bytes.length % (channels * 2) != 0) {
      throw const FormatException('Invalid OpenRouter PCM response');
    }
    final wav = Uint8List(44 + bytes.length);
    final header = ByteData.sublistView(wav);
    wav.setRange(0, 4, ascii.encode('RIFF'));
    header.setUint32(4, 36 + bytes.length, Endian.little);
    wav.setRange(8, 16, ascii.encode('WAVEfmt '));
    header.setUint32(16, 16, Endian.little);
    header.setUint16(20, 1, Endian.little);
    header.setUint16(22, channels, Endian.little);
    header.setUint32(24, rate, Endian.little);
    header.setUint32(28, rate * channels * 2, Endian.little);
    header.setUint16(32, channels * 2, Endian.little);
    header.setUint16(34, 16, Endian.little);
    wav.setRange(36, 40, ascii.encode('data'));
    header.setUint32(40, bytes.length, Endian.little);
    wav.setRange(44, wav.length, bytes);
    return AudioGenerationResult(wav);
  }

  @override
  AudioGenerationResult decodeResult(Map<String, dynamic> json) =>
      throw const FormatException('Expected OpenRouter binary PCM audio');
}
