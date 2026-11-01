// 职责: 验证 AskUser 通知的前台判断、恢复检查和权限等待竞争。
// 关联文件:
//   lib/shared/providers/ai_mode_processing.dart
//   lib/shared/services/system_notification_service.dart
//   lib/shared/services/ai/pending_ask_user.dart
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:reveric/shared/models/ai_session_mode.dart';
import 'package:reveric/shared/models/ask_user_models.dart';
import 'package:reveric/shared/providers/ai_mode_processing.dart';
import 'package:reveric/shared/services/ai/pending_ask_user.dart';
import 'package:reveric/shared/services/system_notification_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  late Completer<bool> permission;
  late Completer<void> requested;
  late List<String> shown;
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    MacOSFlutterLocalNotificationsPlugin.registerWith();
    permission = Completer<bool>();
    requested = Completer<void>();
    shown = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'requestPermissions') {
            if (!requested.isCompleted) {
              requested.complete();
            }
            return permission.future;
          }
          if (call.method == 'show') {
            shown.add((call.arguments as Map)['title'] as String);
          }
          return true;
        });
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  for (final resolution in ['answer', 'timeout', 'cancel']) {
    test(
      'does not show stale notification after permission and $resolution',
      () async {
        var now = DateTime(2026);
        final pending = PendingAskUser(
          request: const AskUserRequest(callId: 'ask', questions: []),
          runId: 1,
          now: () => now,
        )..start();
        addTearDown(pending.cancel);
        final sending = SystemNotificationService.show(
          identifier: resolution,
          title: 'question',
          body: 'body',
          shouldShow: () => pending.notificationIsCurrent(reminder: false),
        );
        await requested.future.timeout(const Duration(seconds: 3));
        if (resolution == 'answer') {
          pending.complete(const AskUserResult(ok: true));
        } else if (resolution == 'cancel') {
          pending.cancel();
        } else {
          now = now.add(const Duration(minutes: 30));
          pending.checkDeadline();
        }
        permission.complete(true);
        await sending;
        expect(shown, isEmpty);
      },
    );
  }

  test(
    'permission denial does not prevent automatic completion or later chat notification',
    () async {
      var now = DateTime(2026);
      final pending = PendingAskUser(
        request: const AskUserRequest(callId: 'ask', questions: []),
        runId: 1,
        now: () => now,
      )..start();
      addTearDown(pending.cancel);
      final sending = SystemNotificationService.show(
        identifier: 'ask',
        title: 'question',
        body: 'body',
        shouldShow: () => pending.notificationIsCurrent(reminder: false),
      );
      await requested.future.timeout(const Duration(seconds: 3));
      permission.complete(false);
      await sending;
      now = now.add(const Duration(minutes: 30));
      pending.checkDeadline();
      expect((await pending.future).resolution, AskUserResolution.timeout);
      permission = Completer<bool>()..complete(true);
      await SystemNotificationService.show(
        identifier: 'chat',
        title: 'completed',
        body: 'body',
      );
      expect(shown, ['completed']);
    },
  );

  test(
    'tracker requires both visible session and foreground app; resume checks deadlines',
    () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final tracker = container.read(aiModeProcessingTrackerProvider.notifier);
      expect(
        tracker.isViewingSession(mode: AiSessionMode.chat, sessionId: 'a'),
        false,
      );
      tracker.setForegroundSession(
        mode: AiSessionMode.chat,
        sessionId: 'a',
        foreground: true,
      );
      expect(
        tracker.isViewingSession(mode: AiSessionMode.chat, sessionId: 'a'),
        true,
      );
      expect(
        tracker.isViewingSession(mode: AiSessionMode.chat, sessionId: 'b'),
        false,
      );
      tracker.setAppForeground(false);
      expect(
        tracker.isViewingSession(mode: AiSessionMode.chat, sessionId: 'a'),
        false,
      );
      var now = DateTime(2026);
      var reminders = 0;
      final pending = PendingAskUser(
        request: const AskUserRequest(callId: 'ask', questions: []),
        runId: 1,
        now: () => now,
        onReminder: (_) {
          reminders++;
        },
        onResolved: (pending, _) =>
            tracker.removeResumeCheck(pending.checkDeadline),
      )..start();
      tracker.addResumeCheck(pending.checkDeadline);
      now = now.add(const Duration(minutes: 30));
      tracker.setAppForeground(true);
      expect((await pending.future).resolution, AskUserResolution.timeout);
      expect(reminders, 0);
      tracker.setAppForeground(true);
      expect(reminders, 0);
    },
  );
}
