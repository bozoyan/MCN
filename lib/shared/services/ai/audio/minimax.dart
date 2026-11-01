// 职责: 编解码 MiniMax 配乐与语音合成协议和业务错误回执。
// 关联文件:
//   lib/shared/services/ai/audio/client.dart
//   lib/shared/models/audio/request.dart
//   lib/shared/models/audio/channels.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/ai.json
//   assets/translations/zh-CN/ai.json
import 'dart:typed_data';
import '../../../localization/locale_keys.dart';
import '../../../models/audio/exception.dart';
import '../../../models/audio/request.dart';
import '../../../models/audio/channels.dart';
import '../media_diagnostics.dart';
import 'client.dart';

class MinimaxAudioClient extends AudioClient {
  MinimaxAudioClient(
    super.client,
    super.apiKey, {
    required super.providerType,
    required this.endpoint,
    super.timeout = const Duration(minutes: 5),
  });

  final Uri endpoint;
  @override
  AudioRequestDefaults get unlistedModelDefaults =>
      const AudioRequestDefaults(responseFormat: ConfigValue('mp3'));
  @override
  Map<String, String> get headers => {'Authorization': 'Bearer $apiKey'};
  @override
  Uri get requestUrl {
    final path = endpoint.path.replaceFirst(RegExp(r'/+$'), '');
    return endpoint.replace(
      path: '$path${path.endsWith('/v1') ? '' : '/v1'}/music_generation',
    );
  }

  @override
  Uri submissionUrl(AudioRequest request) {
    if (lookupAudioChannelModel(
          providerType,
          request.modelId,
        )?.capabilities.speech !=
        true) {
      return requestUrl;
    }
    final path = endpoint.path.replaceFirst(RegExp(r'/+$'), '');
    return endpoint.replace(
      path: '$path${path.endsWith('/v1') ? '' : '/v1'}/t2a_v2',
    );
  }

  @override
  Map<String, dynamic> encode(
    AudioRequest request, {
    List<Uint8List> references = const [],
  }) {
    if (request.parameters.responseFormat != 'mp3') {
      throw const AudioException('invalid_config');
    }
    if (references.isNotEmpty) {
      throw const AudioException('invalid_config');
    }
    final speech = request.modelId.startsWith('speech-');
    return {
      'model': request.modelId,
      if (speech) ...{
        'text': request.prompt,
        'voice_setting': {
          'voice_id': request.parameters.voice,
          'speed': 1,
          'vol': 1,
          'pitch': 0,
        },
        'language_boost': 'auto',
      } else
        'prompt': request.prompt,
      'stream': false,
      'output_format': 'hex',
      if (!speech) 'is_instrumental': true,
      'audio_setting': {
        if (request.parameters.sampleRate != null)
          'sample_rate': request.parameters.sampleRate,
        if (request.parameters.bitrate != null)
          'bitrate': request.parameters.bitrate,
        'format': request.parameters.responseFormat,
      },
    };
  }

  @override
  String? providerMessage(Map<String, dynamic> json) =>
      (json['base_resp'] as Map?)?['status_msg'] as String?;

  @override
  AudioGenerationResult decodeResult(Map<String, dynamic> json) {
    final status = (json['base_resp'] as Map?)?['status_code'];
    if (status is! int) {
      throw const FormatException('Missing MiniMax status');
    }
    if (status != 0) {
      final (code, key) = switch (status) {
        1002 => ('rate_limited', LocaleKeys.aiRateLimited),
        1004 || 2049 => ('authentication', LocaleKeys.aiApiKeyInvalid),
        1008 => ('rejected', LocaleKeys.aiProviderPaymentRequired),
        1026 => ('rejected', LocaleKeys.aiContentRejected),
        2013 => ('rejected', LocaleKeys.aiBadRequest),
        _ => ('rejected', LocaleKeys.aiRequestFailed),
      };
      throw AudioException(
        code,
        statusCode: 200,
        providerCode: status,
        messageKey: key,
        providerMessage: providerMessage(json),
        detail: providerErrorDetail('$status', providerMessage(json), apiKey),
      );
    }
    final data = json['data'] as Map?;
    final hex = data?['audio'];
    if (data?['status'] != 2 ||
        hex is! String ||
        hex.isEmpty ||
        hex.length.isOdd) {
      throw const FormatException('Invalid MiniMax audio receipt');
    }
    final bytes = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] =
          (_hexDigit(hex.codeUnitAt(i * 2)) << 4) |
          _hexDigit(hex.codeUnitAt(i * 2 + 1));
    }
    final id3 =
        bytes.length >= 3 &&
        bytes[0] == 0x49 &&
        bytes[1] == 0x44 &&
        bytes[2] == 0x33;
    final frame =
        bytes.length >= 4 && bytes[0] == 0xff && (bytes[1] & 0xe0) == 0xe0;
    if (!id3 && !frame) {
      throw const FormatException('Invalid MP3 output');
    }
    return AudioGenerationResult(bytes);
  }
}

int _hexDigit(int code) => switch (code) {
  >= 48 && <= 57 => code - 48,
  >= 65 && <= 70 => code - 55,
  >= 97 && <= 102 => code - 87,
  _ => throw const FormatException('Invalid hex audio'),
};
