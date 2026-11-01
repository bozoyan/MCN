// 职责: 测试 SessionSubscriptionsDao — 验证幂等写入、按 session/target 级联清理、channel_type 可空
// 关联文件:
//   lib/shared/database/daos/session_subscriptions_dao.dart
//   lib/shared/database/app_database.dart

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/database/app_database.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTest(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  group('SessionSubscriptionsDao', () {
    test(
      'add then listBySession returns the subscription with channel',
      () async {
        await db.sessionSubscriptionsDao.add(
          sessionId: 'session_1',
          subscriberType: sessionSubscriberRemoteChat,
          targetId: 'wxid_alice',
          channelType: sessionChannelWechat,
        );

        final subs = await db.sessionSubscriptionsDao.listBySession(
          'session_1',
        );

        expect(subs, hasLength(1));
        expect(subs.single.sessionId, 'session_1');
        expect(subs.single.subscriberType, sessionSubscriberRemoteChat);
        expect(subs.single.targetId, 'wxid_alice');
        expect(subs.single.channelType, sessionChannelWechat);
      },
    );

    test(
      'add is idempotent on unique (sessionId, subscriberType, targetId)',
      () async {
        // 同一订阅关系重复写入必须幂等：转发恢复路径会重复注册订阅行，
        // 不能因唯一约束报错，也不能产生重复行导致下行消息重复发送。
        await db.sessionSubscriptionsDao.add(
          sessionId: 'session_1',
          subscriberType: sessionSubscriberRemoteChat,
          targetId: 'wxid_alice',
          channelType: sessionChannelWechat,
        );
        await db.sessionSubscriptionsDao.add(
          sessionId: 'session_1',
          subscriberType: sessionSubscriberRemoteChat,
          targetId: 'wxid_alice',
          channelType: sessionChannelWechat,
        );

        final subs = await db.sessionSubscriptionsDao.listBySession(
          'session_1',
        );

        expect(subs, hasLength(1));
      },
    );

    test('channelType is nullable for task_comments subscriber', () async {
      // remote_chat 需要 channel_type 决定走哪个 adapter；task_comments 落本地
      // comment，无 channel 概念，必须允许 null。
      await db.sessionSubscriptionsDao.add(
        sessionId: 'session_1',
        subscriberType: sessionSubscriberRemoteChat,
        targetId: 'wxid_alice',
        channelType: sessionChannelWechat,
      );
      await db.sessionSubscriptionsDao.add(
        sessionId: 'session_1',
        subscriberType: sessionSubscriberTaskComments,
        targetId: 'task_42',
      );

      final subs = await db.sessionSubscriptionsDao.listBySession('session_1');

      final remote = subs.singleWhere(
        (s) => s.subscriberType == sessionSubscriberRemoteChat,
      );
      expect(remote.channelType, sessionChannelWechat);
      final comments = subs.singleWhere(
        (s) => s.subscriberType == sessionSubscriberTaskComments,
      );
      expect(comments.channelType, isNull);
    });

    test('deleteBySession removes only that session subscriptions', () async {
      // session 删除时必须级联清理其订阅行，否则转发指向死目标、表缓慢膨胀。
      await db.sessionSubscriptionsDao.add(
        sessionId: 'session_a',
        subscriberType: sessionSubscriberRemoteChat,
        targetId: 'wxid_alice',
      );
      await db.sessionSubscriptionsDao.add(
        sessionId: 'session_b',
        subscriberType: sessionSubscriberRemoteChat,
        targetId: 'wxid_alice',
      );

      await db.sessionSubscriptionsDao.deleteBySession('session_a');

      expect(
        await db.sessionSubscriptionsDao.listBySession('session_a'),
        isEmpty,
      );
      expect(
        await db.sessionSubscriptionsDao.listBySession('session_b'),
        hasLength(1),
      );
    });

    test('deleteByTarget removes by (subscriberType, targetId)', () async {
      // task 删除或 forwarder 遇死目标时按 target 清理；不能误删同 session 的其他订阅。
      await db.sessionSubscriptionsDao.add(
        sessionId: 'session_1',
        subscriberType: sessionSubscriberRemoteChat,
        targetId: 'wxid_dead',
      );
      await db.sessionSubscriptionsDao.add(
        sessionId: 'session_1',
        subscriberType: sessionSubscriberRemoteChat,
        targetId: 'wxid_alive',
      );
      await db.sessionSubscriptionsDao.add(
        sessionId: 'session_1',
        subscriberType: sessionSubscriberTaskComments,
        targetId: 'wxid_dead',
      );

      await db.sessionSubscriptionsDao.deleteByTarget(
        subscriberType: sessionSubscriberRemoteChat,
        targetId: 'wxid_dead',
      );

      final subs = await db.sessionSubscriptionsDao.listBySession('session_1');
      expect(subs, hasLength(2));
      expect(
        subs.where(
          (s) =>
              s.subscriberType == sessionSubscriberRemoteChat &&
              s.targetId == 'wxid_dead',
        ),
        isEmpty,
      );
    });
  });
}
