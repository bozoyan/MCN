// 职责: 以稳定错误码、HTTP 状态和安全文案标识传递音频失败。
// 关联文件:
//   lib/shared/models/audio/request.dart
//   lib/shared/services/ai/audio/client.dart
//   lib/shared/services/production/audio_service.dart

class AudioException implements Exception {
  const AudioException(
    this.code, {
    this.statusCode,
    this.messageKey,
    this.providerMessage,
    this.providerCode,
    this.detail,
  });

  final String code;
  final int? statusCode;
  final int? providerCode;

  /// 仅携带固定本地化 key，不携带供应商原文或签名地址。
  final String? messageKey;

  /// 未识别出专用文案时的供应商原始 message，界面优先于通用兜底文案展示。
  final String? providerMessage;

  /// 脱敏后的供应商错误码和原文，只返回给 Agent。
  final String? detail;

  @override
  String toString() =>
      'AudioException($code, HTTP $statusCode, provider $providerCode)';
}
