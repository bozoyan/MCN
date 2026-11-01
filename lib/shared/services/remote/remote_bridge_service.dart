// 职责: 远程桥接服务 — 编排 WeChat 适配器生命周期、按 chatId 串行化消息、对外暴露登录与桥接状态
// 关联文件:
//   lib/shared/services/remote/channel_adapter.dart
//   lib/shared/services/remote/wechat_adapter.dart
//   lib/shared/logger/app_logger.dart
//   lib/shared/providers/remote_bridge_providers.dart
// 遵循的 Rules:
//   .agents/rules/error-handling.md
//   .agents/rules/service-naming.md
import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../logger/app_logger.dart';
import 'channel_adapter.dart';
import 'wechat_adapter.dart';
import 'wechat_api.dart';

final _log = AppLogger.forModule('RemoteBridge');

/// QR 登录流程的 UI 可观测阶段。
///
/// 服务持有此状态并通过 [ChangeNotifier.notifyListeners] 推送给 UI。
/// 流程：[idle] → [showingQr] → [scanned] → [confirmed] → 回到 [idle]；
/// 二维码过期：[showingQr] → [expired] → [showingQr]（自动重新请求）；
/// 失败：任意阶段 → [error]。
enum BridgeLoginPhase { idle, showingQr, scanned, expired, confirmed, error }

/// 远程桥接服务。
///
/// 编排 [WechatAdapter] 的 QR 登录、启动/停止、入站消息按 chatId 串行路由，
/// 并对外暴露可观测状态（登录阶段、二维码图片、桥接是否在线、最近错误）。
///
/// PR-5 范围：AI-agnostic 部分（适配器生命周期、路由、状态、出站发送）。
/// [onInboundMessage] 是扩展点，由 PR-3/PR-6 接入 AI turn。
///
/// 凭证与 context_token 经回调持久化到 app_settings（方案 §5.2），重启后调
/// [restoreAndStart] 免扫码恢复。-14 时清库由 [onCredentialsCleared] 触发。
class RemoteBridgeService extends ChangeNotifier {
  RemoteBridgeService({WechatAdapter? adapter})
    : _adapter = adapter ?? WechatAdapter() {
    _adapter.onSessionExpired = _onSessionExpired;
    _adapter.onContextTokenChanged = _onContextTokenChanged;
  }

  final WechatAdapter _adapter;

  // ── 登录状态（UI 可观测）──────────────────────────────────────────
  BridgeLoginPhase _loginPhase = BridgeLoginPhase.idle;
  String? _qrImageUrl;
  String? _loginError;
  StreamSubscription<WechatLoginUpdate>? _loginSub;

  // ── 桥接状态 ─────────────────────────────────────────────────────
  bool _started = false;
  Future<void>? _loopFuture;
  int? _startedAt;
  String? _lastError;

  /// chatId → 当前正在处理的 Future。同 chatId 串行化，避免并发 turn。
  final Map<String, Future<void>> _sessionLocks = {};

  /// 扩展点：入站消息处理回调（PR-3/PR-6 注入）。
  ///
  /// 不设则入站消息仅记录日志后被丢弃（V1 PR-5 阶段行为）。
  Future<void> Function(InboundMessage message)? onInboundMessage;

  /// 登录成功回调（凭证已入内存）。provider 层据此持久化凭证并按开关启动桥接。
  /// 不设则仅存内存（重启需重新扫码）。
  Future<void> Function(WechatCredentials credentials)? onLoginConfirmed;

  /// 凭证清除回调（-14 session 过期）。provider 层据此清除 app_settings 中的
  /// credentials + context_tokens。
  Future<void> Function()? onCredentialsCleared;

  /// context_token 变更回调。provider 层据此持久化到 app_settings。
  Future<void> Function(String chatId, String contextToken)?
  onContextTokenChanged;

  /// 当前登录阶段。
  BridgeLoginPhase get loginPhase => _loginPhase;

  /// 是否有进行中的登录流（等待扫码 / 已扫码待确认 / 二维码过期自动重请求）。
  ///
  /// confirmed 与 error 不在此列 — confirmed 时已登录，error 时流已终止。
  /// 供 UI 在卸载时判断是否需要取消登录流，避免后台空跑 QR 轮询。
  bool get isLoginInProgress =>
      _loginPhase == BridgeLoginPhase.showingQr ||
      _loginPhase == BridgeLoginPhase.scanned ||
      _loginPhase == BridgeLoginPhase.expired;

  /// 当前二维码图片 URL/base64（仅 [BridgeLoginPhase.showingQr] 有值）。
  String? get qrImageUrl => _qrImageUrl;

  /// 登录错误信息（仅 [BridgeLoginPhase.error] 有值）。
  String? get loginError => _loginError;

  /// 桥接是否在线（消费循环运行中）。
  bool get isRunning => _started;

  /// 桥接最近错误。
  String? get lastError => _lastError;

  /// 适配器是否已登录（内存凭证存在）。
  bool get isLoggedIn => _adapter.isLoggedIn;

  /// 当前 context_token 内存快照（供持久化回调使用）。
  Map<String, String> get contextTokens => _adapter.contextTokens;

  // ── 登录 ─────────────────────────────────────────────────────────

  /// 启动 QR 登录流程。重复调用时若已有登录流在跑，则忽略。
  Future<void> startLogin() async {
    if (_loginSub != null) {
      _log.debug('startLogin ignored — already in progress');
      return;
    }
    _loginError = null;
    _setLoginPhase(BridgeLoginPhase.showingQr);

    try {
      _loginSub = _adapter.login().listen(
        _onLoginUpdate,
        onError: (Object error, StackTrace stack) {
          _log.error(
            'login stream error: $error',
            error: error,
            stackTrace: stack,
          );
          _loginError = error.toString();
          _setLoginPhase(BridgeLoginPhase.error);
        },
        onDone: () {
          _loginSub = null;
        },
      );
      await _loginSub!.asFuture();
    } catch (error, stack) {
      _log.error('startLogin failed: $error', error: error, stackTrace: stack);
      _loginError = error.toString();
      _setLoginPhase(BridgeLoginPhase.error);
    }
  }

  /// 取消进行中的登录流程。
  Future<void> cancelLogin() async {
    final sub = _loginSub;
    if (sub == null) {
      _setLoginPhase(BridgeLoginPhase.idle);
      return;
    }
    await sub.cancel();
    _loginSub = null;
    _qrImageUrl = null;
    _loginError = null;
    _setLoginPhase(BridgeLoginPhase.idle);
    _log.info('login cancelled by user');
  }

  Future<void> _onLoginUpdate(WechatLoginUpdate update) async {
    switch (update.step) {
      case WechatLoginStep.qrReady:
        _qrImageUrl = update.qrImageUrl;
        _setLoginPhase(BridgeLoginPhase.showingQr, forceNotify: true);
      case WechatLoginStep.scanned:
        _setLoginPhase(BridgeLoginPhase.scanned);
      case WechatLoginStep.expired:
        _qrImageUrl = null;
        _setLoginPhase(BridgeLoginPhase.expired);
      case WechatLoginStep.confirmed:
        _qrImageUrl = null;
        _loginError = null;
        _setLoginPhase(BridgeLoginPhase.confirmed);
        _log.info('login confirmed — bridge ready to start');
        final creds = update.credentials;
        if (creds != null) {
          final cb = onLoginConfirmed;
          if (cb != null) {
            try {
              await cb(creds);
            } catch (error, stack) {
              _log.error(
                'onLoginConfirmed persist failed: $error',
                error: error,
                stackTrace: stack,
              );
            }
          }
        }
    }
  }

  void _setLoginPhase(BridgeLoginPhase phase, {bool forceNotify = false}) {
    if (_loginPhase == phase && !forceNotify) {
      return;
    }
    _loginPhase = phase;
    notifyListeners();
  }

  // ── 桥接生命周期 ─────────────────────────────────────────────────

  /// 启动桥接：开启适配器长轮询 + 入站消费循环。
  ///
  /// 调用前需先完成 [startLogin]（[isLoggedIn] == true）。
  /// 重复调用是 no-op。
  Future<void> start() async {
    if (_started) {
      return;
    }
    if (!_adapter.isLoggedIn) {
      throw StateError(
        'RemoteBridgeService.start called before login — call startLogin() first',
      );
    }
    _started = true;
    _lastError = null;
    _startedAt = DateTime.now().millisecondsSinceEpoch;
    await _adapter.start();
    _loopFuture = _consumeLoop();
    _log.info('bridge started');
    notifyListeners();
  }

  /// 停止桥接：关闭适配器 + 结束消费循环。
  ///
  /// 不等待进行中的 session handler（它们会在 send 失败时优雅降级）。
  /// 重复调用是 no-op。
  Future<void> stop() async {
    if (!_started) {
      return;
    }
    _started = false;
    await _adapter.stop();
    final loop = _loopFuture;
    if (loop != null) {
      await loop;
    }
    _loopFuture = null;
    _sessionLocks.clear();
    _log.info('bridge stopped');
    notifyListeners();
  }

  /// 用户主动登出：停止桥接、取消进行中的登录流、清除内存凭证、重置登录态，
  /// 并触发 [onCredentialsCleared] 回调以删除持久化（credentials + context_tokens）。
  ///
  /// 与 [_onSessionExpired]（errcode -14 被动过期）不同，这是用户主动解绑：
  /// 不设置 `_lastError`，登录阶段回到 [BridgeLoginPhase.idle] 以便重新扫码。
  /// 未登录且无进行中的登录流时为 no-op。
  Future<void> logout() async {
    if (!isLoggedIn && _loginPhase == BridgeLoginPhase.idle && !_started) {
      return;
    }
    _log.info('logout requested by user');
    if (_started) {
      await stop();
    }
    if (_loginSub != null) {
      await cancelLogin();
    }
    _adapter.clearCredentials();
    _qrImageUrl = null;
    _loginError = null;
    _lastError = null;
    _setLoginPhase(BridgeLoginPhase.idle, forceNotify: true);
    final cb = onCredentialsCleared;
    if (cb != null) {
      try {
        await cb();
      } catch (error, stack) {
        _log.error(
          'onCredentialsCleared failed: $error',
          error: error,
          stackTrace: stack,
        );
      }
    }
  }

  /// 从持久化恢复凭证并（按需）启动桥接（免扫码）。
  ///
  /// app 启动时若 app_settings 中有凭证，调本方法恢复：
  /// 1. adapter.restoreCredentials + restoreContextTokens
  /// 2. 登录阶段置 confirmed（UI 显示已登录）
  /// 3. [autoStart] 为 true 时 bridge.start（开启长轮询）
  ///
  /// [autoStart] 为 false 用于「用户关掉了远程桥接开关」：恢复凭证让 UI 显示已连接、
  /// 开关可一键打开，但不起消费循环。
  ///
  /// 返回 true 表示恢复成功；false 表示凭证无效或启动失败（调用方应让用户重扫码）。
  Future<bool> restoreAndStart({
    required WechatCredentials credentials,
    Map<String, String> contextTokens = const {},
    bool autoStart = true,
  }) async {
    try {
      _adapter.restoreCredentials(credentials);
      if (contextTokens.isNotEmpty) {
        _adapter.restoreContextTokens(contextTokens);
      }
      _setLoginPhase(BridgeLoginPhase.confirmed);
      if (autoStart) {
        await start();
      } else {
        // 不启动也要通知一次：UI 需要从未登录卡切到已连接卡（开关为关）。
        notifyListeners();
      }
      _log.info(
        'bridge restored userId=${credentials.userId} '
        'contextTokens=${contextTokens.length} started=$autoStart',
      );
      return true;
    } catch (error, stack) {
      _log.error(
        'restoreAndStart failed: $error',
        error: error,
        stackTrace: stack,
      );
      _lastError = 'restore failed: $error';
      notifyListeners();
      return false;
    }
  }

  /// 适配器 session 过期回调（errcode -14）。
  ///
  /// 适配器此时已清空自身内存凭证（[isLoggedIn] 变 false），这里必须把登录阶段一并
  /// 退回 [BridgeLoginPhase.idle]：否则阶段停留在 confirmed，UI 会渲染没有任何按钮的
  /// 「已连接」静态卡，用户看不到也点不到重新扫码入口。[_lastError] 保留供 UI 说明原因。
  Future<void> _onSessionExpired() async {
    _log.warning('adapter session expired — stopping bridge');
    _lastError = 'session expired (errcode -14)';
    if (_started) {
      _started = false;
      _loopFuture = null;
      _sessionLocks.clear();
    }
    _qrImageUrl = null;
    _loginError = null;
    _setLoginPhase(BridgeLoginPhase.idle, forceNotify: true);
    // 清库：清除 app_settings 中的 credentials + chat contexts。
    final cb = onCredentialsCleared;
    if (cb != null) {
      try {
        await cb();
      } catch (error, stack) {
        _log.error(
          'onCredentialsCleared failed: $error',
          error: error,
          stackTrace: stack,
        );
      }
    }
  }

  /// 适配器 context_token 变更回调 — 转发给 provider 层持久化。
  Future<void> _onContextTokenChanged(String chatId, String token) async {
    final cb = onContextTokenChanged;
    if (cb == null) {
      return;
    }
    try {
      await cb(chatId, token);
    } catch (error, stack) {
      _log.error(
        'onContextTokenChanged persist failed chatId=$chatId: $error',
        error: error,
        stackTrace: stack,
      );
    }
  }

  // ── 消费循环与路由 ───────────────────────────────────────────────

  Future<void> _consumeLoop() async {
    while (_started) {
      final InboundMessage? message;
      try {
        message = await _adapter.consumeOne();
      } catch (error, stack) {
        if (!_started) {
          break;
        }
        _log.error('consumeOne error: $error', error: error, stackTrace: stack);
        _lastError = error.toString();
        notifyListeners();
        continue;
      }
      if (message == null) {
        // adapter 停止时 resolve null
        break;
      }
      await _routeAndProcess(message);
    }
  }

  /// 按 chatId 串行化处理：同 chatId 的消息排队执行，跨 chatId 并发。
  Future<void> _routeAndProcess(InboundMessage message) async {
    final chatId = message.address.chatId;
    final previous = _sessionLocks[chatId] ?? Future<void>.value();
    final current = previous.then((_) => _handleMessage(message));
    _sessionLocks[chatId] = current;
    // 当前任务完成后从锁表中移除，避免 Map 无限增长。
    current.whenComplete(() {
      if (_sessionLocks[chatId] == current) {
        _sessionLocks.remove(chatId);
      }
    });
    // 不 await — 消费循环应继续拉取下一条消息，跨 chatId 并发。
    unawaited(current);
  }

  Future<void> _handleMessage(InboundMessage message) async {
    final handler = onInboundMessage;
    if (handler == null) {
      _log.warning(
        'no inbound handler — dropping message chatId=${message.address.chatId}',
      );
      return;
    }
    try {
      await handler(message);
    } catch (error, stack) {
      _log.error(
        'inbound handler error chatId=${message.address.chatId}: $error',
        error: error,
        stackTrace: stack,
      );
      _lastError = error.toString();
      notifyListeners();
    }
  }

  // ── 出站 ─────────────────────────────────────────────────────────

  /// 向指定 chatId 发送文本。返回是否成功。
  ///
  /// 不抛异常：失败仅记录并返回 false，调用方（AI turn 层）无需 try/catch。
  Future<bool> sendToUser(String chatId, String text) async {
    try {
      final result = await _adapter.send(
        OutboundMessage(
          address: ChannelAddress(
            channelType: wechatChannelType,
            chatId: chatId,
          ),
          text: text,
        ),
      );
      if (!result.ok) {
        _log.warning('sendToUser failed chatId=$chatId: ${result.error}');
      }
      return result.ok;
    } catch (error, stack) {
      _log.error(
        'sendToUser exception chatId=$chatId: $error',
        error: error,
        stackTrace: stack,
      );
      return false;
    }
  }

  /// 通知适配器开始处理（触发 typing 指示器）。
  Future<void> notifyProcessingStart(String chatId) async {
    try {
      await _adapter.onMessageStart(chatId);
    } catch (error) {
      if (_log.isDebugEnabled) {
        _log.debug('notifyProcessingStart chatId=$chatId failed: $error');
      }
    }
  }

  /// 通知适配器处理结束（关闭 typing 指示器）。
  Future<void> notifyProcessingEnd(String chatId) async {
    try {
      await _adapter.onMessageEnd(chatId);
    } catch (error) {
      if (_log.isDebugEnabled) {
        _log.debug('notifyProcessingEnd chatId=$chatId failed: $error');
      }
    }
  }

  // ── 状态快照 ─────────────────────────────────────────────────────

  /// 当前桥接系统状态快照。
  BridgeStatus status() => BridgeStatus(
    running: _started,
    startedAt: _startedAt,
    adapters: [_adapter.status()],
  );

  @override
  void dispose() {
    _loginSub?.cancel();
    _loginSub = null;
    if (_started) {
      _started = false;
      _adapter.stop();
    }
    super.dispose();
  }
}
