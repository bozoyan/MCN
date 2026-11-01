// 职责: 验证 RemoteBridgeService 生命周期、登录状态、会话锁、出站发送
// 关联文件:
//   lib/shared/services/remote/remote_bridge_service.dart
//   lib/shared/services/remote/wechat_adapter.dart
//   lib/shared/services/remote/wechat_api.dart
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:reveric/shared/services/remote/remote_bridge_service.dart';
import 'package:reveric/shared/services/remote/wechat_adapter.dart';
import 'package:reveric/shared/services/remote/wechat_api.dart';

http.Response _jsonResponse(Map<String, Object?> body, {int status = 200}) =>
    http.Response(jsonEncode(body), status);

Future<void> _hold() => Future<void>.delayed(const Duration(milliseconds: 5));

Map<String, Object?> _userMsg({
  int messageId = 1,
  String fromUserId = 'wxid_user',
  String text = 'hello',
  String contextToken = 'ctx_tok',
}) => {
  'message_id': messageId,
  'from_user_id': fromUserId,
  'to_user_id': 'wxid_bot',
  'client_id': 'cid',
  'create_time_ms': 1700000000000,
  'message_type': 1,
  'message_state': 2,
  'context_token': contextToken,
  'item_list': [
    {
      'type': 1,
      'text_item': {'text': text},
    },
  ],
};

WechatAdapterConfig _fastConfig() => const WechatAdapterConfig(
  qrPollInterval: Duration(milliseconds: 5),
  pollRetryBase: Duration(milliseconds: 1),
  pollRetryMax: Duration(milliseconds: 5),
);

http.Response _confirmedResponse() => _jsonResponse({
  'status': 'confirmed',
  'bot_token': 'tok',
  'ilink_bot_id': 'bot',
  'ilink_user_id': 'usr',
});

/// 构造登录 + 可注入 getupdates / sendmsg 行为的 MockClient。
http.Client _mockClient({
  required Future<http.Response> Function(http.Request request) updatesHandler,
  Future<http.Response> Function(http.Request request)? sendHandler,
  Future<http.Response> Function(http.Request request)? typingHandler,
}) {
  return MockClient((request) async {
    final path = request.url.path;
    if (path.contains('get_bot_qrcode')) {
      return _jsonResponse({'qrcode': 'qr', 'qrcode_img_content': 'img'});
    }
    if (path.contains('get_qrcode_img')) {
      return http.Response.bytes([], 200);
    }
    if (path.contains('get_qrcode_status')) {
      return _confirmedResponse();
    }
    if (path.contains('getupdates')) {
      return updatesHandler(request);
    }
    if (path.contains('sendmsg')) {
      return sendHandler?.call(request) ?? _jsonResponse({'ret': 0});
    }
    if (path.contains('sendtyping')) {
      return typingHandler?.call(request) ?? _jsonResponse({'ret': 0});
    }
    if (path.contains('getconfig')) {
      return _jsonResponse({'typing_ticket': 'ticket_x'});
    }
    return _jsonResponse({});
  });
}

/// 等待 service 进入指定登录阶段。
Future<void> _waitForPhase(
  RemoteBridgeService service,
  BridgeLoginPhase phase, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (service.loginPhase != phase) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out waiting for phase $phase; current=${service.loginPhase}');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  group('RemoteBridgeService initial state', () {
    test('offline + idle + not logged in', () {
      final service = RemoteBridgeService();
      expect(service.loginPhase, BridgeLoginPhase.idle);
      expect(service.isRunning, isFalse);
      expect(service.isLoggedIn, isFalse);
      expect(service.qrImageUrl, isNull);
      expect(service.loginError, isNull);
      expect(service.lastError, isNull);
      service.dispose();
    });
  });

  group('RemoteBridgeService.start without login', () {
    test('throws StateError', () async {
      final service = RemoteBridgeService();
      expect(() => service.start(), throwsStateError);
      service.dispose();
    });
  });

  group('RemoteBridgeService.startLogin', () {
    test('drives login phase: showingQr → confirmed', () async {
      final client = _mockClient(
        updatesHandler: (_) async {
          await _hold();
          return _jsonResponse({'ret': 0, 'msgs': []});
        },
      );
      final adapter = WechatAdapter(config: _fastConfig(), client: client);
      final service = RemoteBridgeService(adapter: adapter);

      final phases = <BridgeLoginPhase>[];
      service.addListener(() => phases.add(service.loginPhase));

      await service.startLogin();

      expect(service.loginPhase, BridgeLoginPhase.confirmed);
      expect(service.isLoggedIn, isTrue);
      expect(service.qrImageUrl, isNull);
      expect(phases, contains(BridgeLoginPhase.showingQr));
      expect(phases, contains(BridgeLoginPhase.confirmed));
      service.dispose();
    });

    test(
      'login confirmed callback can start the bridge before login completes',
      () async {
        final client = _mockClient(
          updatesHandler: (_) async {
            await _hold();
            return _jsonResponse({'ret': 0, 'msgs': []});
          },
        );
        final adapter = WechatAdapter(config: _fastConfig(), client: client);
        final service = RemoteBridgeService(adapter: adapter);
        service.onLoginConfirmed = (_) => service.start();

        await service.startLogin();

        expect(service.isLoggedIn, isTrue);
        expect(
          service.isRunning,
          isTrue,
          reason:
              'a newly confirmed login must start consuming inbound messages',
        );

        await service.stop();
        service.dispose();
      },
    );

    test('qrImageUrl is set during showingQr phase', () async {
      final client = _mockClient(
        updatesHandler: (_) async {
          await _hold();
          return _jsonResponse({'ret': 0, 'msgs': []});
        },
      );
      final adapter = WechatAdapter(config: _fastConfig(), client: client);
      final service = RemoteBridgeService(adapter: adapter);

      // 在另一个 zone 中轮询，捕获 showingQr 阶段的 qrImageUrl
      String? capturedQr;
      final stopPolling = Completer<void>();
      () async {
        while (!stopPolling.isCompleted) {
          if (service.loginPhase == BridgeLoginPhase.showingQr &&
              capturedQr == null) {
            capturedQr = service.qrImageUrl;
          }
          await Future<void>.delayed(const Duration(milliseconds: 2));
        }
      }();

      await service.startLogin();
      stopPolling.complete();

      expect(capturedQr, 'img');
      service.dispose();
    });
  });

  group('RemoteBridgeService.cancelLogin', () {
    test('resets phase to idle when no login in progress', () async {
      final service = RemoteBridgeService();
      await service.cancelLogin();
      expect(service.loginPhase, BridgeLoginPhase.idle);
      service.dispose();
    });

    test('cancels in-progress login', () async {
      // QR 永远不 confirm：卡在 showingQr → scanned 循环
      final client = MockClient((request) async {
        final path = request.url.path;
        if (path.contains('get_bot_qrcode')) {
          return _jsonResponse({'qrcode': 'qr', 'qrcode_img_content': 'img'});
        }
        if (path.contains('get_qrcode_status')) {
          return _jsonResponse({'status': 'wait'});
        }
        return _jsonResponse({});
      });
      final adapter = WechatAdapter(config: _fastConfig(), client: client);
      final service = RemoteBridgeService(adapter: adapter);

      // 启动登录但不 await — 让它在后台轮询
      unawaited(service.startLogin());
      await _waitForPhase(service, BridgeLoginPhase.showingQr);

      await service.cancelLogin();
      expect(service.loginPhase, BridgeLoginPhase.idle);
      expect(service.qrImageUrl, isNull);
      service.dispose();
    });
  });

  group('RemoteBridgeService.start + stop', () {
    test('start sets isRunning; stop clears it', () async {
      final client = _mockClient(
        updatesHandler: (_) async {
          await _hold();
          return _jsonResponse({'ret': 0, 'msgs': []});
        },
      );
      final adapter = WechatAdapter(config: _fastConfig(), client: client);
      final service = RemoteBridgeService(adapter: adapter);

      await service.startLogin();
      expect(service.isLoggedIn, isTrue);

      await service.start();
      expect(service.isRunning, isTrue);

      await service.stop();
      expect(service.isRunning, isFalse);
      service.dispose();
    });

    test('start is no-op when already running', () async {
      final client = _mockClient(
        updatesHandler: (_) async {
          await _hold();
          return _jsonResponse({'ret': 0, 'msgs': []});
        },
      );
      final adapter = WechatAdapter(config: _fastConfig(), client: client);
      final service = RemoteBridgeService(adapter: adapter);

      await service.startLogin();
      await service.start();
      final startedAt1 = service.status().startedAt;
      await service.start(); // no-op
      final startedAt2 = service.status().startedAt;
      expect(startedAt1, startedAt2);

      await service.stop();
      service.dispose();
    });

    test('stop is no-op when not running', () async {
      final service = RemoteBridgeService();
      await service.stop(); // should not throw
      expect(service.isRunning, isFalse);
      service.dispose();
    });
  });

  group('RemoteBridgeService.logout', () {
    test(
      'stops bridge, clears credentials, resets phase, fires onCredentialsCleared',
      () async {
        final client = _mockClient(
          updatesHandler: (_) async {
            await _hold();
            return _jsonResponse({'ret': 0, 'msgs': []});
          },
        );
        final adapter = WechatAdapter(config: _fastConfig(), client: client);
        final service = RemoteBridgeService(adapter: adapter);

        var credentialsCleared = false;
        service.onCredentialsCleared = () async {
          credentialsCleared = true;
        };

        await service.startLogin();
        expect(service.isLoggedIn, isTrue);
        await service.start();
        expect(service.isRunning, isTrue);

        await service.logout();

        expect(service.isLoggedIn, isFalse, reason: 'credentials cleared');
        expect(service.isRunning, isFalse, reason: 'bridge stopped');
        expect(
          service.loginPhase,
          BridgeLoginPhase.idle,
          reason: 'phase reset to idle so user can re-scan',
        );
        expect(
          service.lastError,
          isNull,
          reason: 'user logout is not an error',
        );
        expect(
          credentialsCleared,
          isTrue,
          reason:
              'persistence clearing callback must fire to drop AppStates creds',
        );
        service.dispose();
      },
    );

    test('logout is no-op when not logged in', () async {
      final service = RemoteBridgeService();
      var credentialsCleared = false;
      service.onCredentialsCleared = () async {
        credentialsCleared = true;
      };

      await service.logout();

      expect(service.isLoggedIn, isFalse);
      expect(service.loginPhase, BridgeLoginPhase.idle);
      expect(
        credentialsCleared,
        isFalse,
        reason: 'no-op logout must not fire persistence clearing',
      );
      service.dispose();
    });
  });

  group('RemoteBridgeService.sendToUser', () {
    test('returns false when not logged in', () async {
      final service = RemoteBridgeService();
      final ok = await service.sendToUser('wxid_user', 'hi');
      expect(ok, isFalse);
      service.dispose();
    });

    test('returns true on successful send', () async {
      final client = _mockClient(
        updatesHandler: (_) async {
          await _hold();
          return _jsonResponse({'ret': 0, 'msgs': []});
        },
        sendHandler: (_) async => _jsonResponse({'ret': 0}),
      );
      final adapter = WechatAdapter(config: _fastConfig(), client: client);
      final service = RemoteBridgeService(adapter: adapter);

      await service.startLogin();
      // 先用一条入站消息让 adapter 缓存 context_token
      // 直接通过 send 调用，因 context_token 未缓存会失败
      final okNoContext = await service.sendToUser('wxid_user', 'hi');
      expect(okNoContext, isFalse, reason: 'no context_token cached');

      service.dispose();
    });
  });

  group('RemoteBridgeService session lock', () {
    test('same chatId messages are processed serially', () async {
      int updatesCalls = 0;
      final client = _mockClient(
        updatesHandler: (_) async {
          updatesCalls += 1;
          if (updatesCalls == 1) {
            return _jsonResponse({
              'ret': 0,
              'msgs': [
                _userMsg(messageId: 1, text: 'first'),
                _userMsg(messageId: 2, text: 'second'),
              ],
              'get_updates_buf': 'c',
            });
          }
          await _hold();
          return _jsonResponse({'ret': 0, 'msgs': []});
        },
      );
      final adapter = WechatAdapter(config: _fastConfig(), client: client);
      final service = RemoteBridgeService(adapter: adapter);

      await service.startLogin();
      await service.start();

      final processed = <String>[];
      final gate = Completer<void>();
      service.onInboundMessage = (message) async {
        processed.add(message.text);
        if (message.text == 'first') {
          // 阻塞 first 处理，直到我们放行
          await gate.future;
        }
      };

      // 等待 first 被拉取并进入 handler
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(processed, ['first'], reason: 'first should be in-flight');

      // 放行 first，second 应随后处理
      gate.complete();
      // 轮询等待 second 完成
      final deadline = DateTime.now().add(const Duration(seconds: 3));
      while (!processed.contains('second') &&
          DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(processed, ['first', 'second']);

      await service.stop();
      service.dispose();
    });

    test('cross-chatId messages can be processed concurrently', () async {
      int updatesCalls = 0;
      final client = _mockClient(
        updatesHandler: (_) async {
          updatesCalls += 1;
          if (updatesCalls == 1) {
            return _jsonResponse({
              'ret': 0,
              'msgs': [
                _userMsg(messageId: 1, fromUserId: 'wxid_a', text: 'from_a'),
                _userMsg(messageId: 2, fromUserId: 'wxid_b', text: 'from_b'),
              ],
              'get_updates_buf': 'c',
            });
          }
          await _hold();
          return _jsonResponse({'ret': 0, 'msgs': []});
        },
      );
      final adapter = WechatAdapter(config: _fastConfig(), client: client);
      final service = RemoteBridgeService(adapter: adapter);

      await service.startLogin();
      await service.start();

      final started = <String>[];
      final completed = <String>[];
      final gateA = Completer<void>();
      service.onInboundMessage = (message) async {
        started.add(message.text);
        if (message.text == 'from_a') {
          await gateA.future;
        }
        completed.add(message.text);
      };

      // 等待两条都进入 handler（并发）
      final deadline = DateTime.now().add(const Duration(seconds: 3));
      while (started.length < 2 && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(started, containsAll(const ['from_a', 'from_b']));
      // from_b 应已完成，from_a 仍阻塞
      expect(completed, ['from_b']);

      gateA.complete();
      // 等待 from_a 完成
      final deadline2 = DateTime.now().add(const Duration(seconds: 3));
      while (!completed.contains('from_a') &&
          DateTime.now().isBefore(deadline2)) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(completed, containsAll(const ['from_a', 'from_b']));

      await service.stop();
      service.dispose();
    });

    test('no inbound handler drops message without crashing', () async {
      int updatesCalls = 0;
      final client = _mockClient(
        updatesHandler: (_) async {
          updatesCalls += 1;
          if (updatesCalls == 1) {
            return _jsonResponse({
              'ret': 0,
              'msgs': [_userMsg(text: 'will be dropped')],
              'get_updates_buf': 'c',
            });
          }
          await _hold();
          return _jsonResponse({'ret': 0, 'msgs': []});
        },
      );
      final adapter = WechatAdapter(config: _fastConfig(), client: client);
      final service = RemoteBridgeService(adapter: adapter);
      // 不设 onInboundMessage

      await service.startLogin();
      await service.start();

      // 等待消费循环处理该消息（仅记录日志，不崩）
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(service.isRunning, isTrue);
      expect(service.lastError, isNull);

      await service.stop();
      service.dispose();
    });

    test('handler exception is caught and recorded as lastError', () async {
      int updatesCalls = 0;
      final client = _mockClient(
        updatesHandler: (_) async {
          updatesCalls += 1;
          if (updatesCalls == 1) {
            return _jsonResponse({
              'ret': 0,
              'msgs': [_userMsg(text: 'boom')],
              'get_updates_buf': 'c',
            });
          }
          await _hold();
          return _jsonResponse({'ret': 0, 'msgs': []});
        },
      );
      final adapter = WechatAdapter(config: _fastConfig(), client: client);
      final service = RemoteBridgeService(adapter: adapter);

      service.onInboundMessage = (message) async {
        throw StateError('handler boom: ${message.text}');
      };

      await service.startLogin();
      await service.start();

      // 等待异常被捕获
      final deadline = DateTime.now().add(const Duration(seconds: 3));
      while (service.lastError == null && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(service.lastError, contains('handler boom'));
      expect(service.isRunning, isTrue, reason: 'bridge keeps running');

      await service.stop();
      service.dispose();
    });
  });

  group('RemoteBridgeService.restoreAndStart', () {
    test('autoStart:false restores credentials without consuming', () async {
      final client = _mockClient(
        updatesHandler: (_) async {
          await _hold();
          return _jsonResponse({'ret': 0, 'msgs': []});
        },
      );
      final adapter = WechatAdapter(config: _fastConfig(), client: client);
      final service = RemoteBridgeService(adapter: adapter);

      final ok = await service.restoreAndStart(
        credentials: const WechatCredentials(
          token: 'tok',
          baseUrl: 'https://example.test',
          accountId: 'bot',
          userId: 'usr',
        ),
        autoStart: false,
      );

      expect(ok, isTrue);
      expect(
        service.isLoggedIn,
        isTrue,
        reason: 'credentials restored so UI shows connected and 开关 can flip on',
      );
      expect(
        service.isRunning,
        isFalse,
        reason: 'user turned the bridge off — no consume loop',
      );
      expect(service.loginPhase, BridgeLoginPhase.confirmed);
      service.dispose();
    });
  });

  group('RemoteBridgeService session expiry (-14)', () {
    test('resets phase to idle so the re-scan entry is reachable', () async {
      final client = _mockClient(
        updatesHandler: (_) async {
          await _hold();
          return _jsonResponse({'ret': -14, 'errcode': -14});
        },
      );
      final adapter = WechatAdapter(config: _fastConfig(), client: client);
      final service = RemoteBridgeService(adapter: adapter);

      var credentialsCleared = false;
      service.onCredentialsCleared = () async {
        credentialsCleared = true;
      };

      await service.startLogin();
      await service.start();
      expect(service.loginPhase, BridgeLoginPhase.confirmed);

      final deadline = DateTime.now().add(const Duration(seconds: 3));
      while (service.isLoggedIn && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }

      expect(service.isLoggedIn, isFalse, reason: 'adapter dropped creds');
      expect(service.isRunning, isFalse);
      expect(
        service.loginPhase,
        BridgeLoginPhase.idle,
        // confirmed 会让 UI 停在没有按钮的「已连接」静态卡，用户无法重新扫码。
        reason: 'phase must fall back to idle to render the QR login entry',
      );
      expect(service.lastError, contains('-14'));
      expect(credentialsCleared, isTrue);
      service.dispose();
    });
  });

  group('RemoteBridgeService.status', () {
    test('reports running + startedAt when started', () async {
      final client = _mockClient(
        updatesHandler: (_) async {
          await _hold();
          return _jsonResponse({'ret': 0, 'msgs': []});
        },
      );
      final adapter = WechatAdapter(config: _fastConfig(), client: client);
      final service = RemoteBridgeService(adapter: adapter);

      await service.startLogin();
      await service.start();

      final s = service.status();
      expect(s.running, isTrue);
      expect(s.startedAt, isNotNull);
      expect(s.adapters, hasLength(1));
      expect(s.adapters.first.channelType, wechatChannelType);
      expect(s.adapters.first.running, isTrue);

      await service.stop();
      service.dispose();
    });
  });
}
