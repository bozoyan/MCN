// 职责: 编解码 AtlasCloud 音频提交及预测查询，保留可恢复的任务回执。
// 关联文件:
//   lib/shared/services/ai/audio/client.dart
//   lib/shared/models/audio/channels.dart
//   lib/shared/models/audio/request.dart
//   lib/shared/services/ai/media_diagnostics.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/ai.json
//   assets/translations/zh-CN/ai.json
import 'dart:convert';
import 'dart:typed_data';
import '../../../logger/app_logger.dart';
import '../../../utils/ai_error.dart';
import '../../../localization/locale_keys.dart';
import '../../../models/audio/channels.dart';
import '../../../models/audio/exception.dart';
import '../../../models/audio/request.dart';
import '../media_diagnostics.dart';
import 'client.dart';

final _log = AppLogger.forModule('AtlasCloudAudio');

class AtlasCloudAudioClient extends AudioClient {
  AtlasCloudAudioClient(
    super.client,
    super.apiKey, {
    super.timeout,
    super.readRetryDelay,
  }) : super(providerType: 'atlascloud');

  static final endpoint = Uri.parse('https://api.atlascloud.ai/api/v1/model/');
  @override
  Uri get requestUrl => endpoint.resolve('generateAudio');
  @override
  Map<String, String> get headers => {'Authorization': 'Bearer $apiKey'};
  @override
  AudioRequestDefaults get unlistedModelDefaults =>
      const AudioRequestDefaults(responseFormat: ConfigValue('mp3'));

  @override
  Map<String, dynamic> encode(
    AudioRequest request, {
    List<Uint8List> references = const [],
  }) {
    final channel = lookupAudioChannelModel(providerType, request.modelId);
    final parameters = request.parameters;
    if (channel == null ||
        parameters.responseFormat != channel.requestDefaults.responseFormat ||
        parameters.instructions?.isNotEmpty == true) {
      throw const AudioException('invalid_config');
    }
    if (references.length != request.references.length ||
        (request.modelId != 'bytedance/seed-audio-1.0' &&
            references.isNotEmpty)) {
      throw const AudioException('invalid_reference');
    }
    final music = request.modelId.startsWith('minimax/music-');
    final seed = request.modelId == 'bytedance/seed-audio-1.0';
    final xai = request.modelId == 'xai/tts-v1';
    final configurableFormat =
        music || seed || xai || request.modelId.startsWith('minimax/speech-');
    if ((music || seed) && parameters.voice?.isNotEmpty == true) {
      throw const AudioException('invalid_config');
    }
    if ((!configurableFormat &&
            (parameters.sampleRate != null || parameters.bitrate != null)) ||
        (seed && parameters.bitrate != null)) {
      throw const AudioException('invalid_config');
    }
    return {
      'model': request.modelId,
      if (music) ...{
        'prompt': request.prompt,
        'is_instrumental': true,
      } else
        'text': request.prompt,
      if (parameters.voice != null)
        (xai ? 'voice_id' : 'voice'): parameters.voice,
      if (xai) 'language': 'auto',
      if (configurableFormat) ...{
        (xai ? 'codec' : 'format'): parameters.responseFormat,
        if (parameters.sampleRate != null) 'sample_rate': parameters.sampleRate,
        if (parameters.bitrate != null && !seed)
          (xai ? 'bit_rate' : 'bitrate'): parameters.bitrate,
      },
      if (references.isNotEmpty)
        'references': [
          for (final (index, bytes) in references.indexed)
            {'${request.references[index].kind}_data': base64Encode(bytes)},
        ],
    };
  }

  Future<AudioGenerationResult> query(
    String id, {
    Future<void>? abortTrigger,
  }) async {
    if (id.trim().isEmpty) {
      throw const AudioException('invalid_config');
    }
    final result = await executeRequest(
      'GET',
      endpoint.resolve('prediction/${Uri.encodeComponent(id)}'),
      abortTrigger: abortTrigger,
    );
    if (result.providerTaskId != id) {
      throw const AudioException('unavailable');
    }
    return result;
  }

  @override
  String? providerMessage(Map<String, dynamic> json) =>
      tryReadProviderMessage(json);

  @override
  AudioGenerationResult decodeResult(Map<String, dynamic> json) {
    if (_log.isDebugEnabled) {
      _log.debug(
        'response code=${json['code']} '
        'status=${(json['data'] as Map?)?['status']}',
      );
    }
    final data = json['data'] as Map<String, dynamic>?;
    if ((json['code'] != null && json['code'] != 200) ||
        json['error'] != null) {
      throw AudioException(
        'rejected',
        messageKey: LocaleKeys.aiRequestFailed,
        providerMessage: providerMessage(json),
        detail: providerErrorDetail(
          json['code']?.toString(),
          providerMessage(json),
          apiKey,
        ),
      );
    }
    if (data == null) {
      throw const FormatException('Missing AtlasCloud prediction');
    }
    final id = data['id'];
    if (id is! String || id.trim().isEmpty) {
      throw const FormatException('Missing AtlasCloud prediction ID');
    }
    switch (data['status']) {
      case 'created':
      case 'starting':
      case 'queued':
      case 'processing':
        return AudioGenerationResult.pending(id);
      case 'completed':
      case 'succeeded':
        final outputs = data['outputs'];
        if (outputs is! List ||
            outputs.length != 1 ||
            outputs.single is! String) {
          throw const FormatException('Expected one AtlasCloud audio output');
        }
        final url = Uri.tryParse(outputs.single as String);
        if (url == null ||
            url.scheme != 'https' ||
            url.host.isEmpty ||
            url.userInfo.isNotEmpty ||
            url.hasFragment) {
          throw const FormatException('Invalid AtlasCloud audio output URL');
        }
        return AudioGenerationResult(
          Uint8List(0),
          url: url,
          providerTaskId: id,
        );
      case 'failed':
      case 'timeout':
      case 'cancelled':
        throw AudioException(
          'rejected',
          messageKey: LocaleKeys.aiRequestFailed,
          providerMessage: providerMessage(json),
          detail: providerErrorDetail(
            data['error_code']?.toString(),
            data['error']?.toString(),
            apiKey,
          ),
        );
      default:
        throw FormatException(
          'Unknown AtlasCloud prediction status: ${data['status']}',
        );
    }
  }
}
