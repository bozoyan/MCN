// 职责: 验证 WeChat iLink Bot HTTP API 客户端 — 协议类型解析、纯函数、MockClient 驱动的端点调用
// 关联文件:
//   lib/shared/services/remote/wechat_api.dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:reveric/shared/services/remote/wechat_api.dart';

http.Response _jsonResponse(Map<String, Object?> body, {int status = 200}) =>
    http.Response(jsonEncode(body), status);

void main() {
  group('WechatMessageType', () {
    test('fromValue maps int to enum', () {
      expect(WechatMessageType.fromValue(1), WechatMessageType.user);
      expect(WechatMessageType.fromValue(2), WechatMessageType.bot);
      expect(WechatMessageType.fromValue(99), WechatMessageType.user);
    });

    test('value round-trips', () {
      expect(WechatMessageType.user.value, 1);
      expect(WechatMessageType.bot.value, 2);
    });
  });

  group('WechatMessageState', () {
    test('values match protocol', () {
      expect(WechatMessageState.fresh.value, 0);
      expect(WechatMessageState.generating.value, 1);
      expect(WechatMessageState.finish.value, 2);
    });
  });

  group('WechatMessageItemType.fromValue', () {
    test('maps all known types and defaults to text', () {
      expect(WechatMessageItemType.fromValue(1), WechatMessageItemType.text);
      expect(WechatMessageItemType.fromValue(2), WechatMessageItemType.image);
      expect(WechatMessageItemType.fromValue(3), WechatMessageItemType.voice);
      expect(WechatMessageItemType.fromValue(4), WechatMessageItemType.file);
      expect(WechatMessageItemType.fromValue(5), WechatMessageItemType.video);
      expect(WechatMessageItemType.fromValue(0), WechatMessageItemType.text);
    });
  });

  group('buildWechatHeaders', () {
    test('contains required headers', () {
      final headers = buildWechatHeaders('tok123');
      expect(headers['Content-Type'], 'application/json');
      expect(headers['AuthorizationType'], 'ilink_bot_token');
      expect(headers['Authorization'], 'Bearer tok123');
      expect(headers['X-WECHAT-UIN'], isNotEmpty);
    });
  });

  group('randomWechatUin', () {
    test('produces base64-decodable string', () {
      final uin = randomWechatUin();
      final decoded = utf8.decode(base64.decode(uin));
      // 解码后是纯数字字符串
      expect(int.tryParse(decoded), isNotNull);
    });

    test('produces different values across calls', () {
      final a = randomWechatUin();
      final b = randomWechatUin();
      expect(a, isNot(equals(b)));
    });
  });

  group('buildWechatTextMessage', () {
    test('builds BOT finish message with single text item', () {
      final msg = buildWechatTextMessage('wxid_abc', 'ctx_tok', 'hello');
      expect(msg['from_user_id'], '');
      expect(msg['to_user_id'], 'wxid_abc');
      expect(msg['message_type'], WechatMessageType.bot.value);
      expect(msg['message_state'], WechatMessageState.finish.value);
      expect(msg['context_token'], 'ctx_tok');
      final clientId = msg['client_id'];
      expect(clientId, isA<String>());
      expect(clientId as String, isNotEmpty);
      final itemList = msg['item_list'] as List<Object?>;
      expect(itemList.length, 1);
      final item = itemList.first as Map<String, Object?>;
      expect(item['type'], WechatMessageItemType.text.value);
      expect((item['text_item'] as Map)['text'], 'hello');
    });

    test('client_id differs per call', () {
      final a = buildWechatTextMessage('u', 'c', 't');
      final b = buildWechatTextMessage('u', 'c', 't');
      expect(a['client_id'], isNot(equals(b['client_id'])));
    });
  });

  group('chunkWechatText', () {
    test('empty text returns single empty chunk', () {
      expect(chunkWechatText('', 10), const ['']);
    });

    test('short text returns single chunk', () {
      expect(chunkWechatText('abc', 10), const ['abc']);
    });

    test('splits by rune count not UTF-16 unit', () {
      // '😀' is 1 rune but 2 UTF-16 units; chunk by runes.
      final text = '😀😀😀';
      final chunks = chunkWechatText(text, 2);
      expect(chunks.length, 2);
      expect(chunks[0].runes.length, 2); // 2 runes
      expect(chunks[1].runes.length, 1);
    });

    test('exact multiple yields no empty trailing chunk', () {
      expect(chunkWechatText('abcdef', 3), const ['abc', 'def']);
    });
  });

  group('extractWechatText', () {
    test('concatenates text items with newline', () {
      final items = [
        const WechatMessageItem(
          type: WechatMessageItemType.text,
          textItem: WechatTextItem('hi'),
        ),
        const WechatMessageItem(
          type: WechatMessageItemType.text,
          textItem: WechatTextItem('there'),
        ),
      ];
      expect(extractWechatText(items), 'hi\nthere');
    });

    test('image without url falls back to placeholder', () {
      const item = WechatMessageItem(
        type: WechatMessageItemType.image,
        imageItem: WechatImageItem(
          media: WechatCDNMedia(encryptQueryParam: '', aesKey: ''),
        ),
      );
      expect(extractWechatText(const [item]), '[image]');
    });

    test('empty list yields empty string', () {
      expect(extractWechatText(const []), '');
    });
  });

  group('WechatMessage.fromJson', () {
    test('parses USER text message', () {
      final msg = WechatMessage.fromJson({
        'message_id': 42,
        'from_user_id': 'wxid_user',
        'to_user_id': 'wxid_bot',
        'client_id': 'cid',
        'create_time_ms': 1700000000000,
        'message_type': 1,
        'message_state': 2,
        'context_token': 'tok',
        'item_list': [
          {
            'type': 1,
            'text_item': {'text': 'hello'},
          },
        ],
      });
      expect(msg.messageId, 42);
      expect(msg.fromUserId, 'wxid_user');
      expect(msg.messageType, WechatMessageType.user);
      expect(msg.contextToken, 'tok');
      expect(msg.itemList.length, 1);
      expect(msg.itemList.first.type, WechatMessageItemType.text);
      expect(msg.itemList.first.textItem?.text, 'hello');
    });

    test('parses missing fields with safe defaults', () {
      final msg = WechatMessage.fromJson({});
      expect(msg.messageId, 0);
      expect(msg.fromUserId, '');
      expect(msg.messageType, WechatMessageType.user);
      expect(msg.itemList, isEmpty);
    });
  });

  group('WechatQrStatusResponse.fromJson', () {
    test('maps scaned and scanned', () {
      expect(
        WechatQrStatusResponse.fromJson({'status': 'scaned'}).status,
        WechatQrStatus.scanned,
      );
      expect(
        WechatQrStatusResponse.fromJson({'status': 'scanned'}).status,
        WechatQrStatus.scanned,
      );
    });

    test('maps confirmed with credentials', () {
      final r = WechatQrStatusResponse.fromJson({
        'status': 'confirmed',
        'bot_token': 'tok',
        'ilink_bot_id': 'bot1',
        'ilink_user_id': 'usr1',
        'baseurl': 'https://x.example',
      });
      expect(r.status, WechatQrStatus.confirmed);
      expect(r.botToken, 'tok');
      expect(r.ilinkBotId, 'bot1');
      expect(r.ilinkUserId, 'usr1');
      expect(r.baseUrl, 'https://x.example');
    });

    test('unknown status falls back to wait', () {
      expect(
        WechatQrStatusResponse.fromJson({'status': 'whatever'}).status,
        WechatQrStatus.wait,
      );
    });
  });

  group('fetchWechatQrCode', () {
    test('parses qrcode + image content', () async {
      final client = MockClient((request) async {
        expect(request.url.path, endsWith('get_bot_qrcode'));
        return _jsonResponse({
          'qrcode': 'qr_tok',
          'qrcode_img_content': 'https://img.example/qr.png',
        });
      });
      final qr = await fetchWechatQrCode(defaultWechatBaseUrl, client: client);
      expect(qr.qrcode, 'qr_tok');
      expect(qr.qrcodeImgContent, 'https://img.example/qr.png');
    });
  });

  group('pollWechatQrStatus', () {
    test('sends iLink-App-ClientVersion header', () async {
      late Map<String, String> capturedHeaders;
      final client = MockClient((request) async {
        capturedHeaders = request.headers;
        return _jsonResponse({'status': 'wait'});
      });
      await pollWechatQrStatus(defaultWechatBaseUrl, 'qr', client: client);
      expect(capturedHeaders['iLink-App-ClientVersion'], '1');
    });

    test('encodes qrcode in query', () async {
      late Uri capturedUri;
      final client = MockClient((request) async {
        capturedUri = request.url;
        return _jsonResponse({'status': 'wait'});
      });
      await pollWechatQrStatus(
        defaultWechatBaseUrl,
        'qr with space',
        client: client,
      );
      expect(capturedUri.query, 'qrcode=qr+with+space');
    });
  });

  group('getWechatUpdates', () {
    test('posts cursor in body and parses response', () async {
      late String capturedBody;
      late Map<String, String> capturedHeaders;
      final client = MockClient((request) async {
        capturedBody = request.body;
        capturedHeaders = request.headers;
        return _jsonResponse({
          'ret': 0,
          'msgs': [
            {
              'message_id': 1,
              'from_user_id': 'wxid_u',
              'to_user_id': 'wxid_b',
              'client_id': 'c1',
              'create_time_ms': 1,
              'message_type': 1,
              'message_state': 2,
              'context_token': 'tok1',
              'item_list': [
                {
                  'type': 1,
                  'text_item': {'text': 'hi'},
                },
              ],
            },
          ],
          'get_updates_buf': 'cursor_next',
        });
      });
      final resp = await getWechatUpdates(
        defaultWechatBaseUrl,
        'tok',
        'cursor_prev',
        client: client,
      );
      expect(resp.ret, 0);
      expect(resp.msgs.length, 1);
      expect(resp.msgs.first.fromUserId, 'wxid_u');
      expect(resp.msgs.first.itemList.first.textItem?.text, 'hi');
      expect(resp.getUpdatesBuf, 'cursor_next');
      final body = jsonDecode(capturedBody) as Map<String, Object?>;
      expect(body['get_updates_buf'], 'cursor_prev');
      expect(capturedHeaders['Authorization'], 'Bearer tok');
    });

    test('empty msgs list when field missing', () async {
      final client = MockClient((request) async => _jsonResponse({'ret': 0}));
      final resp = await getWechatUpdates(
        defaultWechatBaseUrl,
        'tok',
        '',
        client: client,
      );
      expect(resp.msgs, isEmpty);
      expect(resp.getUpdatesBuf, '');
    });
  });

  group('WechatApiError', () {
    test('isSessionExpired true for code -14', () {
      const err = WechatApiError('expired', code: -14);
      expect(err.isSessionExpired, isTrue);
    });

    test('isSessionExpired false for other codes', () {
      const err = WechatApiError('other', code: -5);
      expect(err.isSessionExpired, isFalse);
    });

    test('isSessionExpired false when code null', () {
      const err = WechatApiError('no code');
      expect(err.isSessionExpired, isFalse);
    });
  });

  group('API error handling', () {
    test('non-zero ret throws WechatApiError with errcode', () async {
      final client = MockClient(
        (request) async => _jsonResponse({
          'ret': -1,
          'errcode': -14,
          'errmsg': 'session expired',
        }),
      );
      expect(
        () => getWechatUpdates(defaultWechatBaseUrl, 'tok', '', client: client),
        throwsA(
          isA<WechatApiError>()
              .having((e) => e.code, 'code', -14)
              .having((e) => e.isSessionExpired, 'isSessionExpired', isTrue),
        ),
      );
    });

    test('HTTP non-2xx throws WechatApiError with status', () async {
      final client = MockClient(
        (request) async => _jsonResponse({'errmsg': 'bad'}, status: 500),
      );
      expect(
        () => fetchWechatQrCode(defaultWechatBaseUrl, client: client),
        throwsA(isA<WechatApiError>().having((e) => e.status, 'status', 500)),
      );
    });

    test('empty body on 200 parses as empty map (no throw)', () async {
      final client = MockClient((request) async => http.Response('', 200));
      final resp = await getWechatUpdates(
        defaultWechatBaseUrl,
        'tok',
        '',
        client: client,
      );
      expect(resp.ret, 0);
    });
  });

  group('getWechatConfig + sendWechatTyping', () {
    test('getconfig parses typing_ticket', () async {
      final client = MockClient(
        (request) async => _jsonResponse({'typing_ticket': 'ticket_abc'}),
      );
      final cfg = await getWechatConfig(
        defaultWechatBaseUrl,
        'tok',
        'usr',
        'ctx',
        client: client,
      );
      expect(cfg.typingTicket, 'ticket_abc');
    });

    test('sendtyping posts status in body', () async {
      late Map<String, Object?> body;
      final client = MockClient((request) async {
        body = jsonDecode(request.body) as Map<String, Object?>;
        return _jsonResponse({});
      });
      await sendWechatTyping(
        defaultWechatBaseUrl,
        'tok',
        'usr',
        'ticket',
        1,
        client: client,
      );
      expect(body['ilink_user_id'], 'usr');
      expect(body['typing_ticket'], 'ticket');
      expect(body['status'], 1);
    });
  });

  group('sendWechatMessage', () {
    test('wraps msg + base_info in body', () async {
      late Map<String, Object?> body;
      final client = MockClient((request) async {
        body = jsonDecode(request.body) as Map<String, Object?>;
        return _jsonResponse({});
      });
      final msg = buildWechatTextMessage('u', 'c', 't');
      await sendWechatMessage(defaultWechatBaseUrl, 'tok', msg, client: client);
      expect(body['msg'], isA<Map>());
      expect((body['msg'] as Map)['to_user_id'], 'u');
      expect(body['base_info'], isA<Map>());
    });
  });
}
