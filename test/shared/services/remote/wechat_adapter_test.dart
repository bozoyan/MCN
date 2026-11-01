// 职责: 验证 WechatAdapter.clearCredentials 清空内存凭证与 context_tokens
// 关联文件:
//   lib/shared/services/remote/wechat_adapter.dart
//   lib/shared/services/remote/wechat_api.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/services/remote/wechat_adapter.dart';
import 'package:reveric/shared/services/remote/wechat_api.dart';

void main() {
  group('WechatAdapter.clearCredentials', () {
    test(
      'clears credentials and context_tokens, flips isLoggedIn to false',
      () {
        final adapter = WechatAdapter();
        // 用 restore 系列填入内存凭证与 context_tokens（不走网络）。
        adapter.restoreCredentials(
          const WechatCredentials(
            token: 'tok',
            baseUrl: 'https://example.com',
            accountId: 'bot',
            userId: 'usr',
          ),
        );
        adapter.restoreContextTokens({'chat_a': 'tok_a', 'chat_b': 'tok_b'});

        expect(
          adapter.isLoggedIn,
          isTrue,
          reason: 'precondition: credentials restored',
        );
        expect(
          adapter.contextTokens,
          hasLength(2),
          reason: 'precondition: context_tokens present',
        );

        adapter.clearCredentials();

        expect(adapter.isLoggedIn, isFalse, reason: 'credentials cleared');
        expect(adapter.credentials, isNull, reason: 'credentials field nulled');
        expect(
          adapter.contextTokens,
          isEmpty,
          reason:
              'context_tokens cleared so stale tokens do not leak to the '
              'next login session (wrong chat context_token)',
        );
      },
    );

    test('is idempotent when already logged out', () {
      final adapter = WechatAdapter();
      expect(adapter.isLoggedIn, isFalse);

      adapter.clearCredentials();

      expect(adapter.isLoggedIn, isFalse);
      expect(adapter.contextTokens, isEmpty);
    });
  });
}
