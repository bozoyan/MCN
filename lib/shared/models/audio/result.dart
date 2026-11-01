// 职责: 保存音频响应与临时下载地址，并统一响应格式对应的本地文件格式。
// 关联文件:
//   lib/shared/services/ai/audio/client.dart
//   lib/shared/services/production/audio_service.dart
import 'dart:typed_data';
import 'exception.dart';

class AudioGenerationResult {
  AudioGenerationResult(
    Uint8List bytes, {
    this.url,
    this.providerTaskId,
    this.mimeType,
  }) : bytes = Uint8List.fromList(bytes);
  AudioGenerationResult.pending(String id)
    : providerTaskId = id,
      bytes = Uint8List(0),
      url = null,
      mimeType = null;
  final Uint8List bytes;

  /// 客户端声明的实际输出 MIME，供播放和保存选择正确扩展名。
  final String? mimeType;
  final Uri? url;
  final String? providerTaskId;
  bool get isPending => providerTaskId != null && url == null && bytes.isEmpty;
}

/// 优先使用客户端返回的实际格式；未声明 MIME 的协议沿用请求格式。
String audioOutputFileFormat(String? responseFormat, {String? mimeType}) {
  if (mimeType != null) {
    return switch (mimeType.split(';').first.trim().toLowerCase()) {
      'audio/wav' || 'audio/x-wav' || 'audio/wave' => 'wav',
      'audio/mp3' || 'audio/mpeg' => 'mp3',
      'audio/ogg' => 'ogg',
      _ => throw const AudioException('invalid_result'),
    };
  }
  return switch (responseFormat) {
    'pcm' || 'wav' => 'wav',
    'mp3' => 'mp3',
    'ogg' => 'ogg',
    _ => throw const AudioException('invalid_config'),
  };
}
