// 职责: 系统通知服务 — 跨平台发送本地通知并把点击回调分发给业务侧。
// 关联文件:
//   lib/shared/providers/ai_mode_processing.dart
//   lib/main.dart
// 遵循的 Rules:
//   .agents/rules/error-handling.md
//   .agents/rules/local-dependencies.md

import 'dart:io';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../logger/app_logger.dart';

final _log = AppLogger.forModule('Notification');

/// 通知被点击时的回调；[payload] 由发送方自定义，用于定位要打开的内容。
typedef SystemNotificationTapHandler = void Function(String payload);

/// 系统本地通知门面。
///
/// 保留静态门面而不是让调用方直接用 [FlutterLocalNotificationsPlugin]：调用点
/// 分散在 AI 会话和后台任务等多处，平台差异与初始化时序需要收在一处。
///
/// 平台差异：Windows 走 Toast，非 MSIX 打包时无法撤回或查询已发通知——本应用
/// 不需要这两项能力。移动端进入后台会被系统挂起，通知只在应用产生事件时出现。
class SystemNotificationService {
  SystemNotificationService._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static bool _initialized = false;
  static SystemNotificationTapHandler? _onTap;

  /// Android 通知渠道。渠道一经创建，其重要级别由系统接管，改代码不会生效，
  /// 因此这里一次性定为默认重要级别。
  static const AndroidNotificationDetails _androidDetails =
      AndroidNotificationDetails(
        'reveric_default',
        'Reveric',
        channelDescription: '后台任务完成与失败提醒',
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
      );

  static const NotificationDetails _details = NotificationDetails(
    android: _androidDetails,
    iOS: DarwinNotificationDetails(),
    macOS: DarwinNotificationDetails(),
    linux: LinuxNotificationDetails(),
    windows: WindowsNotificationDetails(),
  );

  /// 初始化插件并注册点击回调。重复调用是幂等的。
  ///
  /// [onTap] 在通知被点击时触发，用于导航到对应内容。
  static Future<void> initialize({SystemNotificationTapHandler? onTap}) async {
    _onTap = onTap;
    if (_initialized) {
      return;
    }
    try {
      const settings = InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        // 权限在首次发送时按需申请，不在启动时打断用户。
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
        macOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
        linux: LinuxInitializationSettings(defaultActionName: 'Open'),
        windows: WindowsInitializationSettings(
          appName: 'Reveric',
          appUserModelId: kDebugMode ? 'ai.reveric.debug' : 'ai.reveric',
          guid: kDebugMode
              ? '30c68781-e02c-4fab-a47e-c94e7d57fa2a'
              : 'b2ea38b6-1e84-4651-a790-82f4136d07ae',
        ),
      );
      await _plugin.initialize(
        settings: settings,
        onDidReceiveNotificationResponse: _handleResponse,
      );
      _initialized = true;
    } catch (error, stackTrace) {
      // 通知能力不可用不应影响主流程，只记录一次诊断日志。
      _log.warning('Failed to initialize notifications: $error');
      if (_log.isDebugEnabled) {
        _log.debug('Notification init stack: $stackTrace');
      }
    }
  }

  static void _handleResponse(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null || payload.isEmpty) {
      return;
    }
    final handler = _onTap;
    if (handler == null) {
      return;
    }
    handler(payload);
  }

  /// 发送一条通知。
  ///
  /// [identifier] 用于生成稳定的通知 id；同一 identifier 会覆盖上一条。
  /// [payload] 会原样带回 [initialize] 注册的点击回调。
  static Future<void> show({
    required String identifier,
    required String title,
    required String body,
    String? payload,
    bool Function()? shouldShow,
  }) async {
    if (shouldShow != null && !shouldShow()) {
      return;
    }
    if (!_initialized) {
      await initialize(onTap: _onTap);
    }
    try {
      if (shouldShow != null && !shouldShow()) {
        return;
      }
      if (!await _ensurePermission()) {
        return;
      }
      if (shouldShow != null && !shouldShow()) {
        return;
      }
      await _plugin.show(
        id: _notificationId(identifier),
        title: title,
        body: body,
        notificationDetails: _details,
        payload: payload,
      );
    } catch (error) {
      // 通知发送失败不影响核心功能，只记录日志
      _log.warning('Failed to show notification: $error');
    }
  }

  /// 首次发送时按需申请权限。已授权或平台无需申请时返回 true。
  static Future<bool> _ensurePermission() async {
    if (Platform.isIOS) {
      final granted = await _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(alert: true, sound: true);
      return granted ?? false;
    }
    if (Platform.isMacOS) {
      final granted = await _plugin
          .resolvePlatformSpecificImplementation<
            MacOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(alert: true, sound: true);
      return granted ?? false;
    }
    if (Platform.isAndroid) {
      final granted = await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
      return granted ?? false;
    }
    return true;
  }

  /// 通知 id 必须是 32 位有符号整数，这里由 identifier 稳定散列得到：
  /// 同一业务对象重复通知会覆盖而不是堆叠。
  static int _notificationId(String identifier) {
    return identifier.hashCode & 0x7fffffff;
  }
}
