// 职责: WeChat iLink Bot adapter — 实现 BaseChannelAdapter，封装 QR 登录、长轮询收消息、发消息、typing
// 关联文件:
//   lib/shared/services/remote/channel_adapter.dart
//   lib/shared/services/remote/wechat_api.dart
//   lib/shared/logger/app_logger.dart
// 遵循的 Rules:
//   .agents/rules/error-handling.md
import 'dart:async';

import 'package:http/http.dart' as http;

import '../../logger/app_logger.dart';
import 'channel_adapter.dart';
import 'wechat_api.dart';

final _log = AppLogger.forModule('WechatAdapter');

/// WeChat channel type identifier (registered in adapter registry).
const String wechatChannelType = 'wechat';

/// QR 登录流程的单次状态更新（供 UI 展示二维码与进度）。
class WechatLoginUpdate {
  const WechatLoginUpdate._({
    required this.step,
    this.qrImageUrl,
    this.credentials,
  });

  final WechatLoginStep step;

  /// 仅 [WechatLoginStep.qrReady] 时有值 — 可直接展示的二维码图片 URL/base64。
  final String? qrImageUrl;

  /// 仅 [WechatLoginStep.confirmed] 时有值 — 登录成功凭证。
  final WechatCredentials? credentials;

  @override
  String toString() => 'WechatLoginUpdate($step)';
}

/// QR 登录步骤。
enum WechatLoginStep { qrReady, scanned, confirmed, expired }

/// WeChat adapter 配置。
class WechatAdapterConfig {
  const WechatAdapterConfig({
    this.baseUrl = defaultWechatBaseUrl,
    this.maxTextLength = PlatformLimits.wechat,
    this.qrPollInterval = const Duration(seconds: 2),
    this.pollRetryBase = const Duration(seconds: 1),
    this.pollRetryMax = const Duration(seconds: 10),
  });

  final String baseUrl;

  /// 单条出站消息最大字符数；超出走 chunking。
  final int maxTextLength;

  /// QR 状态轮询间隔。
  final Duration qrPollInterval;

  /// 长轮询失败后的初始退避。
  final Duration pollRetryBase;

  /// 长轮询失败后的最大退避。
  final Duration pollRetryMax;
}

/// WeChat iLink Bot 适配器。
///
/// 实现 [BaseChannelAdapter] 通用协议，封装 iLink Bot 的 QR 登录、长轮询
/// 收消息、发消息、typing。凭证可经 [restoreCredentials] 从 AppStates 恢复
/// （方案 §5.2），重启后免扫码直入已登录态。
///
/// 典型生命周期：
/// 1. [login] — 产出 [WechatLoginUpdate] 流，UI 展示二维码，扫码确认后凭证入内存。
///    或 [restoreCredentials] — 从持久化恢复凭证，跳过 QR。
/// 2. [start] — 启动长轮询循环，[consumeOne] 开始返回入站消息。
/// 3. [send] / [onMessageStart] / [onMessageEnd] — 出站与 typing。
/// 4. [stop] — 关闭 client，排空 [consumeOne] 等待者（resolve null）。
class WechatAdapter extends BaseChannelAdapter {
  WechatAdapter({this._config = const WechatAdapterConfig(), this._client});

  final WechatAdapterConfig _config;
  http.Client? _client;

  WechatCredentials? _credentials;
  String _cursor = '';

  /// chatId (wxid) → 最近一次入站消息的 context_token。出站必须回传。
  final Map<String, String> _contextTokens = {};

  /// chatId → 缓存的 typing_ticket，避免每次 typing 都 getconfig。
  final Map<String, String> _typingTickets = {};

  final List<InboundMessage> _queue = [];
  Completer<InboundMessage?>? _waiter;

  bool _stopped = true;
  Future<void>? _runFuture;
  int? _connectedAt;
  int? _lastMessageAt;
  String? _lastError;

  /// session 过期（errcode -14）回调。bridge 收到后应重新触发 [login]。
  /// 不设则仅记录日志并停止循环。
  Future<void> Function()? onSessionExpired;

  /// context_token 变更回调（chatId, token）。bridge 持久化到 app_settings。
  /// 不设则仅存内存（重启后丢失，需等用户先发一条消息刷新 token）。
  void Function(String chatId, String contextToken)? onContextTokenChanged;

  @override
  ChannelType get channelType => wechatChannelType;

  @override
  Future<void> start() async {
    if (!_stopped) {
      return;
    }
    if (_credentials == null) {
      throw StateError(
        'WechatAdapter.start called before login — call login() first',
      );
    }
    _stopped = false;
    _lastError = null;
    _client ??= http.Client();
    _runFuture = _runLoop();
  }

  @override
  Future<void> stop() async {
    _stopped = true;
    _client?.close();
    _client = null;
    final waiter = _waiter;
    if (waiter != null && !waiter.isCompleted) {
      waiter.complete(null);
    }
    _waiter = null;
    final run = _runFuture;
    if (run != null) {
      await run;
    }
    _runFuture = null;
  }

  @override
  bool isRunning() => !_stopped;

  @override
  Future<InboundMessage?> consumeOne() async {
    if (_queue.isNotEmpty) {
      return _queue.removeAt(0);
    }
    if (_stopped) {
      return null;
    }
    _waiter = Completer<InboundMessage?>();
    return _waiter!.future;
  }

  @override
  Future<SendResult> send(OutboundMessage message) async {
    final credentials = _credentials;
    if (credentials == null) {
      return SendResult.failure('WechatAdapter not logged in');
    }
    final contextToken = _contextTokens[message.address.chatId];
    if (contextToken == null || contextToken.isEmpty) {
      return SendResult.failure(
        'no context_token for ${message.address.chatId} — reply to an inbound message first',
      );
    }
    final client = _ensureClient();
    try {
      for (final chunk in chunkWechatText(
        message.text,
        _config.maxTextLength,
      )) {
        await sendWechatMessage(
          credentials.baseUrl,
          credentials.token,
          buildWechatTextMessage(message.address.chatId, contextToken, chunk),
          client: client,
        );
      }
      _lastMessageAt = DateTime.now().millisecondsSinceEpoch;
      return SendResult.success();
    } catch (error, stackTrace) {
      _log.error(
        'send failed chatId=${message.address.chatId}: $error',
        error: error,
        stackTrace: stackTrace,
      );
      return SendResult.failure(error.toString());
    }
  }

  @override
  String? validateConfig() {
    if (_config.baseUrl.isEmpty) {
      return 'baseUrl is empty';
    }
    return null;
  }

  @override
  Future<void> onMessageStart(String chatId) async {
    await _sendTyping(chatId, 1);
  }

  @override
  Future<void> onMessageEnd(String chatId) async {
    await _sendTyping(chatId, 2);
  }

  @override
  AdapterStatus status() => AdapterStatus(
    channelType: wechatChannelType,
    running: !_stopped,
    connectedAt: _connectedAt,
    lastMessageAt: _lastMessageAt,
    error: _lastError,
  );

  // ── 登录 ──────────────────────────────────────────────────────────

  /// 执行 QR 登录流程，产出 [WechatLoginUpdate] 流。
  ///
  /// - qrReady：携带二维码图片，UI 展示。
  /// - scanned：用户已扫码，等待确认。
  /// - confirmed：登录成功，凭证已写入内存，流结束。
  /// - expired：二维码过期，会自动重新请求新二维码（流不结束）。
  ///
  /// 调用方应在 confirmed 后调 [start] 启动长轮询。
  Stream<WechatLoginUpdate> login() async* {
    _log.info(
      'login started — polling interval=${_config.qrPollInterval.inSeconds}s',
    );
    while (true) {
      final client = _ensureClient();
      if (_log.isDebugEnabled) {
        _log.debug('fetching QR code from ${_config.baseUrl}');
      }
      final qr = await fetchWechatQrCode(_config.baseUrl, client: client);
      final qrcodePrefix = qr.qrcode.length > 10
          ? qr.qrcode.substring(0, 10)
          : qr.qrcode;
      _log.info(
        'QR code fetched — qrcode=$qrcodePrefix... qrcodeImgContent.length=${qr.qrcodeImgContent.length}',
      );
      yield WechatLoginUpdate._(
        step: WechatLoginStep.qrReady,
        qrImageUrl: qr.qrcodeImgContent,
      );

      var lastStatus = WechatQrStatus.wait;
      var pollCount = 0;
      while (true) {
        pollCount++;
        if (_log.isDebugEnabled) {
          _log.debug(
            'poll #$pollCount — waiting ${_config.qrPollInterval.inSeconds}s before request',
          );
        }
        await Future<void>.delayed(_config.qrPollInterval);
        try {
          final resp = await pollWechatQrStatus(
            _config.baseUrl,
            qr.qrcode,
            client: client,
          );

          if (resp.status != lastStatus) {
            _log.info(
              'poll #$pollCount status changed: $lastStatus -> ${resp.status}',
            );
            switch (resp.status) {
              case WechatQrStatus.scanned:
                yield const WechatLoginUpdate._(step: WechatLoginStep.scanned);
              case WechatQrStatus.confirmed:
                final token = resp.botToken;
                final botId = resp.ilinkBotId;
                final userId = resp.ilinkUserId;
                if (token == null || botId == null || userId == null) {
                  _lastError = 'QR confirmed but missing credentials';
                  throw WechatApiError(_lastError!);
                }
                final credentials = WechatCredentials(
                  token: token,
                  baseUrl: resp.baseUrl ?? _config.baseUrl,
                  accountId: botId,
                  userId: userId,
                );
                _credentials = credentials;
                _cursor = '';
                _contextTokens.clear();
                _typingTickets.clear();
                _connectedAt = DateTime.now().millisecondsSinceEpoch;
                _lastError = null;
                _log.info('login confirmed userId=$userId');
                yield WechatLoginUpdate._(
                  step: WechatLoginStep.confirmed,
                  credentials: credentials,
                );
                return;
              case WechatQrStatus.expired:
                _log.info('QR code expired — re-fetching');
                yield const WechatLoginUpdate._(step: WechatLoginStep.expired);
                break; // 内层 while，重新请求二维码
              case WechatQrStatus.wait:
                break;
            }
            lastStatus = resp.status;
          } else {
            if (_log.isDebugEnabled) {
              _log.debug('poll #$pollCount status unchanged: ${resp.status}');
            }
          }

          if (resp.status == WechatQrStatus.expired) {
            break;
          }
        } catch (error, stack) {
          _log.warning('poll #$pollCount failed: $error — retrying');
          if (_log.isDebugEnabled) {
            _log.debug('poll error stack: $stack');
          }
        }
      }
    }
  }

  /// 当前是否已登录（内存凭证存在）。
  bool get isLoggedIn => _credentials != null;

  /// 当前内存凭证快照（供 bridge 持久化）。null 表示未登录。
  WechatCredentials? get credentials => _credentials;

  /// 当前 context_token 内存快照（供 bridge 持久化）。
  Map<String, String> get contextTokens => Map.unmodifiable(_contextTokens);

  /// 从持久化恢复凭证（免扫码直入已登录态）。
  ///
  /// 调用后 [isLoggedIn] == true，可直接 [start]。重置 cursor 与缓存。
  /// 不恢复 context_tokens — 用 [restoreContextTokens] 单独传入。
  void restoreCredentials(WechatCredentials credentials) {
    _credentials = credentials;
    _cursor = '';
    _contextTokens.clear();
    _typingTickets.clear();
    _connectedAt = DateTime.now().millisecondsSinceEpoch;
    _lastError = null;
    _log.info('credentials restored userId=${credentials.userId}');
  }

  /// 从持久化恢复 context_tokens map（chatId → token）。
  void restoreContextTokens(Map<String, String> tokens) {
    _contextTokens
      ..clear()
      ..addAll(tokens);
    _log.info('context_tokens restored count=${tokens.length}');
  }

  /// 清除内存凭证及相关缓存（cursor / context_tokens / typing_tickets）。
  ///
  /// 调用后 [isLoggedIn] == false。供 bridge 在用户主动登出时调用。
  /// 不关闭 client（由 [stop] 负责）；不删除持久化（由 bridge 回调负责）。
  void clearCredentials() {
    _credentials = null;
    _cursor = '';
    _contextTokens.clear();
    _typingTickets.clear();
    _connectedAt = null;
    _log.info('credentials cleared');
  }

  // ── 长轮询循环 ────────────────────────────────────────────────────

  Future<void> _runLoop() async {
    _log.info('long-poll loop started');
    var retryDelay = _config.pollRetryBase;

    while (!_stopped) {
      try {
        final credentials = _credentials;
        if (credentials == null) {
          _lastError = 'long-poll without credentials';
          _log.error(_lastError!);
          break;
        }
        final client = _ensureClient();
        final updates = await getWechatUpdates(
          credentials.baseUrl,
          credentials.token,
          _cursor,
          client: client,
        );

        _cursor = updates.getUpdatesBuf.isEmpty
            ? _cursor
            : updates.getUpdatesBuf;
        retryDelay = _config.pollRetryBase;

        for (final raw in updates.msgs) {
          _rememberContext(raw);
          final inbound = _toInboundMessage(raw);
          if (inbound != null) {
            _enqueue(inbound);
          }
        }
      } catch (error, stackTrace) {
        if (_stopped) {
          break;
        }
        if (error is WechatApiError && error.isSessionExpired) {
          _log.warning('session expired (errcode -14), stopping loop');
          _handleSessionExpired();
          break;
        }
        // client.close() during stop 触发的 ClientException — 视为停止
        if (_stopped) {
          break;
        }
        _lastError = error.toString();
        _log.error(
          'long-poll error: $error',
          error: error,
          stackTrace: stackTrace,
        );
        await Future<void>.delayed(retryDelay);
        retryDelay = Duration(
          milliseconds: (retryDelay.inMilliseconds * 2).clamp(
            0,
            _config.pollRetryMax.inMilliseconds,
          ),
        );
      }
    }

    _log.info('long-poll loop stopped');
  }

  void _handleSessionExpired() {
    _credentials = null;
    _cursor = '';
    _contextTokens.clear();
    _typingTickets.clear();
    _lastError = 'session expired (errcode -14)';
    _stopped = true;
    final cb = onSessionExpired;
    if (cb != null) {
      cb();
    }
  }

  void _enqueue(InboundMessage message) {
    final waiter = _waiter;
    if (waiter != null && !waiter.isCompleted) {
      waiter.complete(message);
      _waiter = null;
    } else {
      _queue.add(message);
    }
    _lastMessageAt = DateTime.now().millisecondsSinceEpoch;
  }

  void _rememberContext(WechatMessage message) {
    // 入站消息 message_type=USER：from_user_id 是用户；回传时 to_user_id = 用户。
    final userId = message.messageType == WechatMessageType.user
        ? message.fromUserId
        : message.toUserId;
    if (userId.isNotEmpty && message.contextToken.isNotEmpty) {
      final changed = _contextTokens[userId] != message.contextToken;
      _contextTokens[userId] = message.contextToken;
      if (changed) {
        final cb = onContextTokenChanged;
        if (cb != null) {
          cb(userId, message.contextToken);
        }
      }
    }
  }

  InboundMessage? _toInboundMessage(WechatMessage message) {
    if (message.messageType != WechatMessageType.user) {
      return null;
    }
    final text = extractWechatText(message.itemList);
    return InboundMessage(
      messageId: message.messageId.toString(),
      address: ChannelAddress(
        channelType: wechatChannelType,
        chatId: message.fromUserId,
        userId: message.fromUserId,
      ),
      text: text,
      timestamp: message.createTimeMs,
      raw: message,
    );
  }

  // ── typing ────────────────────────────────────────────────────────

  Future<void> _sendTyping(String chatId, int status) async {
    final credentials = _credentials;
    if (credentials == null) {
      return;
    }
    final contextToken = _contextTokens[chatId];
    if (contextToken == null) {
      return;
    }
    try {
      final client = _ensureClient();
      var ticket = _typingTickets[chatId];
      if (ticket == null) {
        final config = await getWechatConfig(
          credentials.baseUrl,
          credentials.token,
          chatId,
          contextToken,
          client: client,
        );
        ticket = config.typingTicket;
        if (ticket == null || ticket.isEmpty) {
          if (_log.isDebugEnabled) {
            _log.debug('typing: no typing_ticket for $chatId');
          }
          return;
        }
        _typingTickets[chatId] = ticket;
      }
      await sendWechatTyping(
        credentials.baseUrl,
        credentials.token,
        chatId,
        ticket,
        status,
        client: client,
      );
    } catch (error) {
      // typing 失败不影响主链路，仅记录。
      if (_log.isDebugEnabled) {
        _log.debug('typing status=$status chatId=$chatId failed: $error');
      }
    }
  }

  http.Client _ensureClient() {
    var client = _client;
    if (client == null) {
      client = http.Client();
      _client = client;
    }
    return client;
  }
}
