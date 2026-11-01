// 职责: 验证移动深链只归属匹配的活动事务，冷启动和重复回调不会交换 token。
// 关联文件:
//   lib/shared/services/mcp/oauth/callback.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/services/mcp/oauth/callback.dart';

void main() {
  test(
    'cold callback requests sign-in and simultaneous states stay isolated',
    () async {
      final callbacks = McpOAuthCallbacks();
      addTearDown(callbacks.close);
      callbacks.dispatch(
        Uri.parse('ai.reveric://mcp/oauth/callback?code=old&state=old'),
      );
      expect(callbacks.lastError, 'mcp_oauth_transaction_missing');
      final a = await callbacks.open(mobile: true);
      final b = await callbacks.open(mobile: true);
      addTearDown(a.close);
      addTearDown(b.close);
      a.expectedState = 'a';
      b.expectedState = 'b';
      callbacks.dispatch(
        Uri.parse('ai.reveric://other/oauth/callback?code=wrong&state=a'),
      );
      callbacks.dispatch(
        Uri.parse('ai.reveric://mcp/oauth/callback?code=wrong&state=wrong'),
      );
      await Future<void>.delayed(Duration.zero);
      expect(a.received.isCompleted, false);
      expect(b.received.isCompleted, false);
      callbacks.dispatch(
        Uri.parse('ai.reveric://mcp/oauth/callback?code=B&state=b'),
      );
      expect((await b.result).queryParameters['code'], 'B');
      expect(a.received.isCompleted, false);
      callbacks.dispatch(
        Uri.parse('ai.reveric://mcp/oauth/callback?code=A&state=a'),
      );
      expect((await a.result).queryParameters['code'], 'A');
      callbacks.dispatch(
        Uri.parse('ai.reveric://mcp/oauth/callback?code=replayed&state=a'),
      );
      expect((await a.result).queryParameters['code'], 'A');
    },
  );
}
