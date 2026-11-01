// 职责: WeChat iLink Bot HTTP API 客户端 — QR 登录、长轮询收消息、发消息、typing 的底层协议封装
// 关联文件:
//   lib/shared/services/remote/wechat_adapter.dart
//   lib/shared/services/remote/channel_adapter.dart
//   lib/shared/logger/app_logger.dart
// 遵循的 Rules:
//   .agents/rules/error-handling.md
import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../../logger/app_logger.dart';

final _log = AppLogger.forModule('WechatApi');

/// iLink Bot 服务端地址。
const String defaultWechatBaseUrl = 'https://ilinkai.weixin.qq.com';

/// 媒体 CDN 地址（V1 仅文本，预留常量供后续接入）。
const String wechatCdnBaseUrl = 'https://novac2c.cdn.weixin.qq.com/c2c';

/// 协议 channel_version，所有 POST body 的 base_info 中携带。
const String wechatChannelVersion = '1.0.0';

/// errcode -14：session 过期，需重新 QR 登录。
const int wechatErrcodeSessionExpired = -14;

// ── 消息枚举 ────────────────────────────────────────────────────────

/// 消息方向。USER=1（来自用户），BOT=2（机器人发出）。
enum WechatMessageType {
  user(1),
  bot(2);

  const WechatMessageType(this.value);
  final int value;

  static WechatMessageType fromValue(int value) => value == 2 ? bot : user;
}

/// 消息状态。fresh=0，generating=1（流式占位，微信不渲染），finish=2。
enum WechatMessageState {
  fresh(0),
  generating(1),
  finish(2);

  const WechatMessageState(this.value);
  final int value;

  static WechatMessageState fromValue(int value) {
    switch (value) {
      case 0:
        return fresh;
      case 1:
        return generating;
      default:
        return finish;
    }
  }
}

/// 消息体 item 类型。
enum WechatMessageItemType {
  text(1),
  image(2),
  voice(3),
  file(4),
  video(5);

  const WechatMessageItemType(this.value);
  final int value;

  static WechatMessageItemType fromValue(int value) {
    switch (value) {
      case 2:
        return image;
      case 3:
        return voice;
      case 4:
        return file;
      case 5:
        return video;
      default:
        return text;
    }
  }
}

// ── 协议数据类型 ────────────────────────────────────────────────────

class WechatBaseInfo {
  const WechatBaseInfo({this.channelVersion = wechatChannelVersion});

  final String channelVersion;

  Map<String, Object?> toJson() => {'channel_version': channelVersion};
}

class WechatCDNMedia {
  const WechatCDNMedia({
    required this.encryptQueryParam,
    required this.aesKey,
    this.encryptType,
  });

  final String encryptQueryParam;
  final String aesKey;
  final int? encryptType;

  factory WechatCDNMedia.fromJson(Map<String, Object?> json) => WechatCDNMedia(
    encryptQueryParam: json['encrypt_query_param'] as String? ?? '',
    aesKey: json['aes_key'] as String? ?? '',
    encryptType: json['encrypt_type'] as int?,
  );
}

class WechatTextItem {
  const WechatTextItem(this.text);

  final String text;

  Map<String, Object?> toJson() => {'text': text};

  factory WechatTextItem.fromJson(Map<String, Object?> json) =>
      WechatTextItem(json['text'] as String? ?? '');
}

class WechatImageItem {
  const WechatImageItem({required this.media, this.url, this.aeskey});

  final WechatCDNMedia media;
  final String? url;
  final String? aeskey;

  factory WechatImageItem.fromJson(Map<String, Object?> json) =>
      WechatImageItem(
        media: WechatCDNMedia.fromJson(
          (json['media'] as Map<String, Object?>?) ?? const {},
        ),
        url: json['url'] as String?,
        aeskey: json['aeskey'] as String?,
      );
}

class WechatVoiceItem {
  const WechatVoiceItem({required this.media, this.text, this.playtime});

  final WechatCDNMedia media;
  final String? text;
  final int? playtime;

  factory WechatVoiceItem.fromJson(Map<String, Object?> json) =>
      WechatVoiceItem(
        media: WechatCDNMedia.fromJson(
          (json['media'] as Map<String, Object?>?) ?? const {},
        ),
        text: json['text'] as String?,
        playtime: json['playtime'] as int?,
      );
}

class WechatFileItem {
  const WechatFileItem({
    required this.media,
    this.fileName,
    this.md5,
    this.len,
  });

  final WechatCDNMedia media;
  final String? fileName;
  final String? md5;
  final String? len;

  factory WechatFileItem.fromJson(Map<String, Object?> json) => WechatFileItem(
    media: WechatCDNMedia.fromJson(
      (json['media'] as Map<String, Object?>?) ?? const {},
    ),
    fileName: json['file_name'] as String?,
    md5: json['md5'] as String?,
    len: json['len'] as String?,
  );
}

class WechatVideoItem {
  const WechatVideoItem({required this.media, this.videoSize, this.playLength});

  final WechatCDNMedia media;
  final String? videoSize;
  final int? playLength;

  factory WechatVideoItem.fromJson(Map<String, Object?> json) =>
      WechatVideoItem(
        media: WechatCDNMedia.fromJson(
          (json['media'] as Map<String, Object?>?) ?? const {},
        ),
        videoSize: json['video_size'] as String?,
        playLength: json['play_length'] as int?,
      );
}

class WechatMessageItem {
  const WechatMessageItem({
    required this.type,
    this.textItem,
    this.imageItem,
    this.voiceItem,
    this.fileItem,
    this.videoItem,
  });

  final WechatMessageItemType type;
  final WechatTextItem? textItem;
  final WechatImageItem? imageItem;
  final WechatVoiceItem? voiceItem;
  final WechatFileItem? fileItem;
  final WechatVideoItem? videoItem;

  factory WechatMessageItem.fromJson(Map<String, Object?> json) {
    final type = WechatMessageItemType.fromValue(json['type'] as int? ?? 1);
    return WechatMessageItem(
      type: type,
      textItem: json['text_item'] is Map<String, Object?>
          ? WechatTextItem.fromJson(json['text_item'] as Map<String, Object?>)
          : null,
      imageItem: json['image_item'] is Map<String, Object?>
          ? WechatImageItem.fromJson(json['image_item'] as Map<String, Object?>)
          : null,
      voiceItem: json['voice_item'] is Map<String, Object?>
          ? WechatVoiceItem.fromJson(json['voice_item'] as Map<String, Object?>)
          : null,
      fileItem: json['file_item'] is Map<String, Object?>
          ? WechatFileItem.fromJson(json['file_item'] as Map<String, Object?>)
          : null,
      videoItem: json['video_item'] is Map<String, Object?>
          ? WechatVideoItem.fromJson(json['video_item'] as Map<String, Object?>)
          : null,
    );
  }

  Map<String, Object?> toJson() {
    final json = <String, Object?>{'type': type.value};
    if (textItem != null) {
      json['text_item'] = textItem!.toJson();
    }
    // 出站只用到 text_item；其它 item 由 inbound 解析使用，写场景暂不需要。
    return json;
  }
}

/// iLink Bot 入站消息完整结构。
class WechatMessage {
  const WechatMessage({
    required this.messageId,
    required this.fromUserId,
    required this.toUserId,
    required this.clientId,
    required this.createTimeMs,
    required this.messageType,
    required this.messageState,
    required this.contextToken,
    required this.itemList,
  });

  final int messageId;
  final String fromUserId;
  final String toUserId;
  final String clientId;
  final int createTimeMs;
  final WechatMessageType messageType;
  final WechatMessageState messageState;
  final String contextToken;
  final List<WechatMessageItem> itemList;

  factory WechatMessage.fromJson(Map<String, Object?> json) {
    final rawItems = json['item_list'] as List<Object?>? ?? const [];
    return WechatMessage(
      messageId: json['message_id'] as int? ?? 0,
      fromUserId: json['from_user_id'] as String? ?? '',
      toUserId: json['to_user_id'] as String? ?? '',
      clientId: json['client_id'] as String? ?? '',
      createTimeMs: json['create_time_ms'] as int? ?? 0,
      messageType: WechatMessageType.fromValue(
        json['message_type'] as int? ?? 1,
      ),
      messageState: WechatMessageState.fromValue(
        json['message_state'] as int? ?? 2,
      ),
      contextToken: json['context_token'] as String? ?? '',
      itemList: rawItems
          .whereType<Map<String, Object?>>()
          .map(WechatMessageItem.fromJson)
          .toList(growable: false),
    );
  }
}

// ── 请求 / 响应 ────────────────────────────────────────────────────

class WechatQrCodeResponse {
  const WechatQrCodeResponse({
    required this.qrcode,
    required this.qrcodeImgContent,
  });

  /// QR token，用于后续轮询状态。
  final String qrcode;

  /// 可直接展示的二维码图片 URL 或 base64。
  final String qrcodeImgContent;

  factory WechatQrCodeResponse.fromJson(Map<String, Object?> json) =>
      WechatQrCodeResponse(
        qrcode: json['qrcode'] as String? ?? '',
        qrcodeImgContent: json['qrcode_img_content'] as String? ?? '',
      );
}

enum WechatQrStatus { wait, scanned, confirmed, expired }

class WechatQrStatusResponse {
  const WechatQrStatusResponse({
    required this.status,
    this.botToken,
    this.ilinkBotId,
    this.ilinkUserId,
    this.baseUrl,
  });

  final WechatQrStatus status;
  final String? botToken;
  final String? ilinkBotId;
  final String? ilinkUserId;
  final String? baseUrl;

  factory WechatQrStatusResponse.fromJson(Map<String, Object?> json) {
    final raw = json['status'] as String? ?? 'wait';
    final status = switch (raw) {
      'scaned' || 'scanned' => WechatQrStatus.scanned,
      'confirmed' => WechatQrStatus.confirmed,
      'expired' => WechatQrStatus.expired,
      _ => WechatQrStatus.wait,
    };
    return WechatQrStatusResponse(
      status: status,
      botToken: json['bot_token'] as String?,
      ilinkBotId: json['ilink_bot_id'] as String?,
      ilinkUserId: json['ilink_user_id'] as String?,
      baseUrl: json['baseurl'] as String?,
    );
  }
}

class WechatGetUpdatesResponse {
  const WechatGetUpdatesResponse({
    required this.ret,
    required this.msgs,
    required this.getUpdatesBuf,
    this.errcode,
    this.errmsg,
    this.longpollingTimeoutMs,
  });

  final int ret;
  final List<WechatMessage> msgs;
  final String getUpdatesBuf;
  final int? errcode;
  final String? errmsg;
  final int? longpollingTimeoutMs;

  factory WechatGetUpdatesResponse.fromJson(Map<String, Object?> json) {
    final rawMsgs = json['msgs'] as List<Object?>? ?? const [];
    return WechatGetUpdatesResponse(
      ret: json['ret'] as int? ?? 0,
      msgs: rawMsgs
          .whereType<Map<String, Object?>>()
          .map(WechatMessage.fromJson)
          .toList(growable: false),
      getUpdatesBuf: json['get_updates_buf'] as String? ?? '',
      errcode: json['errcode'] as int?,
      errmsg: json['errmsg'] as String?,
      longpollingTimeoutMs: json['longpolling_timeout_ms'] as int?,
    );
  }
}

class WechatGetConfigResponse {
  const WechatGetConfigResponse({this.typingTicket, this.errcode, this.errmsg});

  final String? typingTicket;
  final int? errcode;
  final String? errmsg;

  factory WechatGetConfigResponse.fromJson(Map<String, Object?> json) =>
      WechatGetConfigResponse(
        typingTicket: json['typing_ticket'] as String?,
        errcode: json['errcode'] as int?,
        errmsg: json['errmsg'] as String?,
      );
}

/// QR 登录成功后持有的凭证。
///
/// 序列化用于 AppStates KV 持久化（方案 §5.2），重启后免扫码恢复。
/// 明文存储的妥协见方案 §10。
class WechatCredentials {
  const WechatCredentials({
    required this.token,
    required this.baseUrl,
    required this.accountId,
    required this.userId,
  });

  final String token;
  final String baseUrl;
  final String accountId;
  final String userId;

  Map<String, Object?> toJson() => {
    'token': token,
    'base_url': baseUrl,
    'account_id': accountId,
    'user_id': userId,
  };

  factory WechatCredentials.fromJson(Map<String, Object?> json) =>
      WechatCredentials(
        token: json['token'] as String? ?? '',
        baseUrl: json['base_url'] as String? ?? defaultWechatBaseUrl,
        accountId: json['account_id'] as String? ?? '',
        userId: json['user_id'] as String? ?? '',
      );

  @override
  String toString() =>
      'WechatCredentials(userId=$userId, accountId=$accountId)';
}

// ── 异常 ────────────────────────────────────────────────────────────

/// iLink Bot API 错误。`code` 为协议 errcode（如 -14 表示 session 过期）。
class WechatApiError implements Exception {
  const WechatApiError(
    this.message, {
    this.status = 0,
    this.code,
    this.payload,
  });

  final String message;
  final int status;
  final int? code;
  final Object? payload;

  bool get isSessionExpired => code == wechatErrcodeSessionExpired;

  @override
  String toString() =>
      'WechatApiError($message${code != null ? ', code=$code' : ''}${status != 0 ? ', status=$status' : ''})';
}

// ── 工具函数 ────────────────────────────────────────────────────────

String _normalizeBaseUrl(String baseUrl) =>
    baseUrl.replaceAll(RegExp(r'/+$'), '');

WechatBaseInfo _buildBaseInfo() => const WechatBaseInfo();

/// 生成 X-WECHAT-UIN header：base64(String(randomUint32))。
String randomWechatUin() {
  final value = Random.secure().nextInt(0xFFFFFFFF);
  return base64.encode(utf8.encode(value.toString()));
}

/// 构造所有 POST 请求共用的 header。
Map<String, String> buildWechatHeaders(String token) => {
  'Content-Type': 'application/json',
  'AuthorizationType': 'ilink_bot_token',
  'Authorization': 'Bearer $token',
  'X-WECHAT-UIN': randomWechatUin(),
};

const _uuid = Uuid();

/// 构造一条文本出站消息（message_state=finish，单条 item_list）。
Map<String, Object?> buildWechatTextMessage(
  String userId,
  String contextToken,
  String text,
) => {
  'from_user_id': '',
  'to_user_id': userId,
  'client_id': _uuid.v4(),
  'message_type': WechatMessageType.bot.value,
  'message_state': WechatMessageState.finish.value,
  'context_token': contextToken,
  'item_list': [
    {
      'type': WechatMessageItemType.text.value,
      'text_item': {'text': text},
    },
  ],
};

// ── HTTP 执行 ───────────────────────────────────────────────────────

Map<String, Object?> _parseJsonResponse(http.Response response, String label) {
  final body = response.body;
  final payload = body.isEmpty
      ? <String, Object?>{}
      : jsonDecode(body) as Map<String, Object?>;

  if (response.statusCode < 200 || response.statusCode >= 300) {
    final errmsg =
        payload['errmsg'] as String? ?? '$label HTTP ${response.statusCode}';
    throw WechatApiError(
      errmsg,
      status: response.statusCode,
      code: payload['errcode'] as int?,
      payload: payload,
    );
  }

  final ret = payload['ret'];
  if (ret is int && ret != 0) {
    throw WechatApiError(
      (payload['errmsg'] as String?) ?? '$label failed (ret=$ret)',
      status: response.statusCode,
      code: payload['errcode'] as int? ?? ret,
      payload: payload,
    );
  }

  return payload;
}

Future<Map<String, Object?>> _apiGet(
  String baseUrl,
  String path, {
  Map<String, String> headers = const {},
  required http.Client client,
  Duration timeout = const Duration(seconds: 15),
}) async {
  final uri = Uri.parse('${_normalizeBaseUrl(baseUrl)}/$path');
  final start = DateTime.now();
  if (_log.isDebugEnabled) {
    _log.debug(
      'GET $uri headers=${headers.keys} timeout=${timeout.inSeconds}s',
    );
  }
  try {
    final response = await client.get(uri, headers: headers).timeout(timeout);
    if (_log.isDebugEnabled) {
      _log.debug(
        'GET $uri status=${response.statusCode} duration=${DateTime.now().difference(start).inMilliseconds}ms',
      );
    }
    return _parseJsonResponse(response, path);
  } on TimeoutException {
    final duration = DateTime.now().difference(start).inMilliseconds;
    _log.warning(
      'GET $uri TIMEOUT after ${duration}ms (configured ${timeout.inSeconds}s)',
    );
    rethrow;
  }
}

Future<Map<String, Object?>> _apiPost(
  String baseUrl,
  String endpoint,
  Object body,
  String token, {
  required http.Client client,
  Duration timeout = const Duration(seconds: 40),
}) async {
  final uri = Uri.parse('${_normalizeBaseUrl(baseUrl)}/$endpoint');
  final start = DateTime.now();
  if (_log.isDebugEnabled) {
    _log.debug(
      'POST $uri timeout=${timeout.inSeconds}s bodyKeys=${(body as Map).keys}',
    );
  }
  try {
    final response = await client
        .post(uri, headers: buildWechatHeaders(token), body: jsonEncode(body))
        .timeout(timeout);
    if (_log.isDebugEnabled) {
      _log.debug(
        'POST $uri status=${response.statusCode} duration=${DateTime.now().difference(start).inMilliseconds}ms',
      );
    }
    return _parseJsonResponse(response, endpoint);
  } on TimeoutException {
    final duration = DateTime.now().difference(start).inMilliseconds;
    _log.warning(
      'POST $uri TIMEOUT after ${duration}ms (configured ${timeout.inSeconds}s)',
    );
    rethrow;
  }
}

// ── 对外 API ────────────────────────────────────────────────────────

/// 获取登录二维码（Step 1）。
///
/// 注意：`qrcode_img_content` 返回的是微信小程序跳转链接，不是直接的图片 URL。
/// UI 层需要使用二维码生成库将该链接生成本地二维码。
Future<WechatQrCodeResponse> fetchWechatQrCode(
  String baseUrl, {
  required http.Client client,
}) async {
  if (_log.isDebugEnabled) {
    _log.debug('fetchWechatQrCode baseUrl=$baseUrl');
  }
  final json = await _apiGet(
    baseUrl,
    'ilink/bot/get_bot_qrcode?bot_type=3',
    client: client,
  );
  final resp = WechatQrCodeResponse.fromJson(json);
  if (_log.isDebugEnabled) {
    final qrcodePrefix = resp.qrcode.length > 10
        ? resp.qrcode.substring(0, 10)
        : resp.qrcode;
    _log.debug(
      'fetchWechatQrCode completed qrcode=$qrcodePrefix... qrcodeImgContent=${resp.qrcodeImgContent}',
    );
  }
  return resp;
}

/// 轮询二维码状态（Step 2）。Server hold ~35s，timeout 40s。
Future<WechatQrStatusResponse> pollWechatQrStatus(
  String baseUrl,
  String qrcode, {
  required http.Client client,
}) async {
  if (_log.isDebugEnabled) {
    final qrcodePrefix = qrcode.length > 10 ? qrcode.substring(0, 10) : qrcode;
    _log.debug('pollWechatQrStatus qrcode=$qrcodePrefix...');
  }
  final json = await _apiGet(
    baseUrl,
    'ilink/bot/get_qrcode_status?qrcode=${Uri.encodeQueryComponent(qrcode)}',
    headers: {'iLink-App-ClientVersion': '1'},
    client: client,
    timeout: const Duration(seconds: 40),
  );
  final resp = WechatQrStatusResponse.fromJson(json);
  if (_log.isDebugEnabled) {
    _log.debug(
      'pollWechatQrStatus status=${resp.status} botToken=${resp.botToken != null ? "present" : "null"}',
    );
  }
  return resp;
}

/// 长轮询拉取新消息。Server hold ~35s，timeout 40s。
Future<WechatGetUpdatesResponse> getWechatUpdates(
  String baseUrl,
  String token,
  String cursor, {
  required http.Client client,
}) async {
  final body = <String, Object?>{
    'get_updates_buf': cursor,
    'base_info': _buildBaseInfo().toJson(),
  };
  final json = await _apiPost(
    baseUrl,
    'ilink/bot/getupdates',
    body,
    token,
    client: client,
    timeout: const Duration(seconds: 40),
  );
  return WechatGetUpdatesResponse.fromJson(json);
}

/// 发送一条文本消息。调用方负责 chunking（见 [chunkWechatText]）。
Future<Map<String, Object?>> sendWechatMessage(
  String baseUrl,
  String token,
  Map<String, Object?> msg, {
  required http.Client client,
}) async {
  return _apiPost(
    baseUrl,
    'ilink/bot/sendmessage',
    {'msg': msg, 'base_info': _buildBaseInfo().toJson()},
    token,
    client: client,
    timeout: const Duration(seconds: 15),
  );
}

/// 获取 typing_ticket（发送 typing 前置）。
Future<WechatGetConfigResponse> getWechatConfig(
  String baseUrl,
  String token,
  String userId,
  String contextToken, {
  required http.Client client,
}) async {
  final body = <String, Object?>{
    'ilink_user_id': userId,
    'context_token': contextToken,
    'base_info': _buildBaseInfo().toJson(),
  };
  final json = await _apiPost(
    baseUrl,
    'ilink/bot/getconfig',
    body,
    token,
    client: client,
    timeout: const Duration(seconds: 15),
  );
  return WechatGetConfigResponse.fromJson(json);
}

/// status: 1=start typing, 2=stop typing。
Future<void> sendWechatTyping(
  String baseUrl,
  String token,
  String userId,
  String ticket,
  int status, {
  required http.Client client,
}) async {
  final body = <String, Object?>{
    'ilink_user_id': userId,
    'typing_ticket': ticket,
    'status': status,
    'base_info': _buildBaseInfo().toJson(),
  };
  await _apiPost(
    baseUrl,
    'ilink/bot/sendtyping',
    body,
    token,
    client: client,
    timeout: const Duration(seconds: 15),
  );
}

// ── 文本工具 ────────────────────────────────────────────────────────

/// 按字符数切分长文本（按 Unicode codepoint 计数），适配微信长度限制。
List<String> chunkWechatText(String text, int limit) {
  if (text.isEmpty) {
    return const [''];
  }
  final chars = text.runes.toList(growable: false);
  final chunks = <String>[];
  for (var i = 0; i < chars.length; i += limit) {
    final end = (i + limit).clamp(0, chars.length);
    chunks.add(String.fromCharCodes(chars.sublist(i, end)));
  }
  return chunks;
}

/// 从 item_list 提取纯文本（image/voice/file/video 降级为占位符）。
String extractWechatText(List<WechatMessageItem> items) {
  final parts = <String>[];
  for (final item in items) {
    switch (item.type) {
      case WechatMessageItemType.text:
        final text = item.textItem?.text ?? '';
        if (text.isNotEmpty) {
          parts.add(text);
        }
      case WechatMessageItemType.image:
        parts.add(item.imageItem?.url ?? '[image]');
      case WechatMessageItemType.voice:
        parts.add(item.voiceItem?.text ?? '[voice]');
      case WechatMessageItemType.file:
        parts.add(item.fileItem?.fileName ?? '[file]');
      case WechatMessageItemType.video:
        parts.add('[video]');
    }
  }
  return parts.join('\n');
}
