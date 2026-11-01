// 职责: 聊天出图对话框的参数记忆 — 上次使用的模型/尺寸/请求级参数快照与 JSON 往返。
// 关联文件:
//   lib/shared/models/image/extras.dart
//   lib/desktop/widgets/ai/chat/image_dialog.dart
// 遵循的 Rules:
//   .agents/rules/json.md
import 'dart:convert';

import 'extras.dart';

/// 聊天出图对话框上次使用的参数快照,存于 `app_settings` 单 key。
///
/// 读写只在对话框入口完成(打开时恢复、生成时保存),不进全局设置状态;
/// 模型 id 失效、尺寸不被当前渠道支持时由对话框自行回落默认值。
class ChatImageMemoryData {
  const ChatImageMemoryData({this.modelOptionId, this.size, this.extras});

  static const appSettingsKey = 'chat_image_memory';
  static const currentVersion = 1;

  static const defaults = ChatImageMemoryData();

  /// 上次使用的模型选项 id(`providerId::model`)。
  final String? modelOptionId;

  /// 上次使用的尺寸(如 `1024x1024`)。
  final String? size;

  /// 上次编辑的请求级扩展参数;空参数归一为 null,不落库。
  final ImageRequestExtras? extras;

  factory ChatImageMemoryData.decode(
    String raw, {
    ChatImageMemoryData fallback = defaults,
  }) {
    return ChatImageMemoryData.fromJson(
      _decodeObject(raw, appSettingsKey),
      fallback: fallback,
    );
  }

  factory ChatImageMemoryData.fromJson(
    Map<String, dynamic> json, {
    ChatImageMemoryData fallback = defaults,
  }) {
    final extrasRaw = json['extras'];
    return ChatImageMemoryData(
      modelOptionId: _optionalString(json['modelOptionId']),
      size: _optionalString(json['size']),
      extras: extrasRaw is Map
          ? ImageRequestExtras.fromJson(
              extrasRaw.map((key, value) => MapEntry(key.toString(), value)),
            )
          : fallback.extras,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'version': currentVersion,
    if (modelOptionId != null) 'modelOptionId': modelOptionId,
    if (size != null) 'size': size,
    if (extras case final extras?) 'extras': extras.toJson(),
  };

  String encode() => jsonEncode(toJson());
}

Map<String, dynamic> _decodeObject(String raw, String settingsKey) {
  final decoded = jsonDecode(raw);
  if (decoded is! Map) {
    throw FormatException('$settingsKey must be a JSON object');
  }
  return decoded.map((key, value) => MapEntry(key.toString(), value));
}

String? _optionalString(Object? value) {
  if (value is! String || value.isEmpty) {
    return null;
  }
  return value;
}
