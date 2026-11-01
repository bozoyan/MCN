// 职责: 按渠道型号编解码 Qwen 非流式语音与音频生成请求，并保留可恢复下载的 WAV 回执。
// 关联文件:
//   lib/shared/services/ai/audio/client.dart
//   lib/shared/models/audio/request.dart
//   lib/shared/models/audio/channels.dart
//   lib/shared/services/ai/media_diagnostics.dart
import 'dart:convert';
import 'dart:typed_data';
import '../../../logger/app_logger.dart';
import '../../../models/audio/channels.dart';
import '../../../models/audio/exception.dart';
import '../../../models/audio/request.dart';
import '../media_diagnostics.dart';
import 'client.dart';

final _log = AppLogger.forModule('QwenAudio');

/// 沿用渠道的主机和代理前缀，将兼容模式地址转换为原生语音接口。
Uri qwenAudioEndpoint(String configuredBaseUrl, {String? modelId}) {
  final base = Uri.parse(configuredBaseUrl.trim());
  final path = base.path
      .replaceFirst(RegExp(r'/+$'), '')
      .replaceFirst(RegExp(r'/compatible-mode/v1$'), '');
  final service =
      lookupAudioChannelModel(
            'qwen',
            modelId,
          )?.protocolOptions.qwenUsesSpeechSynthesizer ==
          true
      ? 'audio/tts/SpeechSynthesizer'
      : 'aigc/multimodal-generation/generation';
  return base.replace(path: '$path/api/v1/services/$service');
}

class QwenAudioClient extends AudioClient {
  QwenAudioClient(
    super.client,
    super.apiKey, {
    required this.endpoint,
    super.timeout = const Duration(minutes: 5),
  }) : super(providerType: 'qwen');
  final Uri endpoint;
  @override
  Uri get requestUrl => endpoint;
  @override
  AudioRequestDefaults get unlistedModelDefaults =>
      const AudioRequestDefaults(responseFormat: ConfigValue('wav'));
  @override
  Map<String, String> get headers => {'Authorization': 'Bearer $apiKey'};

  @override
  Map<String, dynamic> encode(
    AudioRequest request, {
    List<Uint8List> references = const [],
  }) {
    final channel = lookupAudioChannelModel('qwen', request.modelId);
    if (request.parameters.responseFormat != 'wav' ||
        request.parameters.bitrate != null) {
      throw const AudioException('invalid_config');
    }
    if (channel?.protocolOptions.qwenUsesSpeechSynthesizer == true) {
      final speech = channel!.capabilities.speech;
      final sampleRate = request.parameters.sampleRate;
      final sampleRates = speech
          ? const {8000, 12000, 16000, 22050, 24000, 44100, 48000}
          : const {8000, 16000, 24000, 44100, 48000};
      if (sampleRate != null && !sampleRates.contains(sampleRate) ||
          speech &&
              (request.parameters.voice?.trim().isNotEmpty != true ||
                  request.references.isNotEmpty ||
                  references.isNotEmpty) ||
          !speech &&
              (request.parameters.voice?.isNotEmpty == true ||
                  request.parameters.instructions?.isNotEmpty == true)) {
        throw const AudioException('invalid_config');
      }
      if (references.length != request.references.length ||
          references.indexed.any(
            (entry) => entry.$2.length != request.references[entry.$1].bytes,
          )) {
        throw const AudioException('invalid_reference');
      }
      return {
        'model': request.modelId,
        'input': {
          if (speech) ...{
            'text': request.prompt,
            'voice': request.parameters.voice,
            if (request.parameters.instructions?.isNotEmpty == true)
              'instruction': request.parameters.instructions,
          } else ...{
            'text_prompt': request.prompt.replaceAllMapped(
              RegExp(r'@(?:Audio|音频|voice)(\d+)'),
              (match) {
                final ordinal = int.parse(match.group(1)!);
                if (ordinal < 1 || ordinal > references.length) {
                  throw const AudioException('invalid_reference');
                }
                return '@voice$ordinal';
              },
            ),
            if (references.isNotEmpty)
              'references': [
                for (var i = 0; i < references.length; i++)
                  {
                    'audio_data':
                        'data:${request.references[i].mimeType};base64,${base64Encode(references[i])}',
                  },
              ],
          },
          'format': request.parameters.responseFormat,
          'sample_rate': ?sampleRate,
        },
      };
    }
    if (references.isNotEmpty ||
        request.references.isNotEmpty ||
        request.parameters.sampleRate != null ||
        request.parameters.voice?.trim().isNotEmpty != true ||
        request.parameters.instructions?.isNotEmpty == true) {
      throw const AudioException('invalid_config');
    }
    return {
      'model': request.modelId,
      'input': {'text': request.prompt, 'voice': request.parameters.voice},
    };
  }

  @override
  AudioGenerationResult decodeResult(Map<String, dynamic> json) {
    if (_log.isDebugEnabled) {
      _log.debug(
        'response usage=${safeMediaDiagnostic(jsonEncode(json['usage']), apiKey)} '
        'body=${safeMediaDiagnostic(jsonEncode(json), apiKey)}',
      );
    }
    final output = json['output'] as Map<String, dynamic>;
    final audio = output['audio'] as Map<String, dynamic>;
    final url = Uri.parse(audio['url'] as String);
    if (!{'http', 'https'}.contains(url.scheme) ||
        url.host.isEmpty ||
        url.userInfo.isNotEmpty ||
        url.hasFragment) {
      throw const FormatException('Invalid Qwen audio output URL');
    }
    // OSS signed output URLs support HTTPS; never fetch generated audio in plaintext.
    return AudioGenerationResult(
      Uint8List(0),
      url: url.replace(scheme: 'https'),
    );
  }
}
