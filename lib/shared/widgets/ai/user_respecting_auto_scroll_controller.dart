// 职责: 协调流式内容列表的自动贴底，并在用户回看历史时暂停跟随
// 关联文件:
//   lib/shared/widgets/ai/chat/auto_scroll_hook.dart
//   lib/shared/widgets/ai/council/timeline.dart
//   lib/desktop/features/roleplay/panel.dart
//   lib/mobile/features/council/page_widgets.dart
//   lib/mobile/features/roleplay/page_widgets.dart
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;

/// 为会持续追加内容的列表保留「仅在用户仍停留在底部时自动跟随」的语义。
///
/// 语义与 `useChatAutoScroll`（lib/shared/widgets/ai/chat/auto_scroll_hook.dart）
/// 一致，供无法使用 hook 的 `State` 调用方复用：
/// - 流式追加（[scheduleScrollToBottom] 传 `streaming: true`）每帧 `jumpTo` 贴底。
///   **不能用动画**：300ms 动画会被下一次流式更新抢占重建，滚动位置几乎不推进，
///   而这份滞后又会被 [_trackUserScroll] 误判成「用户上滑」从而永久关闭跟随。
/// - 非流式（新消息落库、会话加载）距离远则瞬切并跨帧收敛，距离近则平滑滑动。
/// - 用户上滑 / 拖动起手即暂停跟随；回到底部附近恢复。
/// - 会话切换、用户主动发送消息由调用方显式 [resumeFollow]。
class UserRespectingAutoScrollController {
  UserRespectingAutoScrollController() {
    scrollController.addListener(_trackUserScroll);
  }

  static const _bottomTolerance = 48.0;
  static const _maxConvergeAttempts = 6;

  final scrollController = ScrollController();
  var _userScrolledAwayFromBottom = false;
  var _isAutoScrolling = false;
  var _autoScrollGeneration = 0;
  var _isDisposed = false;

  void _trackUserScroll() {
    if (!scrollController.hasClients) {
      return;
    }
    final position = scrollController.position;
    if (!position.hasContentDimensions) {
      return;
    }
    // 用户向上滚动时需要优先于程序滚动被识别；否则流式更新会取消手势。
    if (position.userScrollDirection == ScrollDirection.forward) {
      _userScrolledAwayFromBottom = true;
      return;
    }
    // 程序滚动期间一律忽略：既不把贴底过程的滞后误判成用户上滑，
    // 也不把用户刚置位的暂停标记在贴底瞬间冲回。
    if (_isAutoScrolling) {
      return;
    }
    _userScrolledAwayFromBottom =
        position.pixels < position.maxScrollExtent - _bottomTolerance;
  }

  /// 在当前帧的列表尺寸稳定后贴底；用户正在回看历史时保持原位置。
  ///
  /// [streaming] 表示本次更新来自进行中的流式输出（调用方一般传 `activeRun != null`）。
  void scheduleScrollToBottom({bool streaming = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_isDisposed ||
          _userScrolledAwayFromBottom ||
          !scrollController.hasClients) {
        return;
      }
      final position = scrollController.position;
      if (!position.hasContentDimensions || position.maxScrollExtent <= 0) {
        return;
      }
      if (streaming) {
        // 已贴底时不重复 jumpTo：内容未增高时 jumpTo 是 no-op，
        // 却仍会通知滚动监听并驱动整棵消息列表重排重绘。
        if (position.pixels < position.maxScrollExtent - 0.5) {
          _jumpToBottom();
        }
        return;
      }
      final distance = position.maxScrollExtent - position.pixels;
      if (distance > position.viewportDimension * 1.5) {
        _jumpToBottom(converge: true);
      } else if (distance > 1) {
        _animateToBottom();
      }
    });
  }

  /// 恢复自动跟随。会话切换、用户主动发送消息时调用，
  /// 否则一次回看历史会让该列表在整个生命周期内都不再贴底。
  void resumeFollow() {
    _userScrolledAwayFromBottom = false;
  }

  void _jumpToBottom({bool converge = false}) {
    // jumpTo 会同步通知滚动监听；置位让监听忽略这次程序滚动。
    _isAutoScrolling = true;
    scrollController.jumpTo(scrollController.position.maxScrollExtent);
    _isAutoScrolling = false;
    if (converge) {
      _convergeToBottom(0);
    }
  }

  // lazy 项布局后 maxScrollExtent 可能继续增长，跨帧重复贴底直到收敛。
  void _convergeToBottom(int attempt) {
    if (attempt >= _maxConvergeAttempts) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_isDisposed ||
          _userScrolledAwayFromBottom ||
          !scrollController.hasClients) {
        return;
      }
      final position = scrollController.position;
      if (!position.hasContentDimensions ||
          position.pixels >= position.maxScrollExtent - 0.5) {
        return;
      }
      _isAutoScrolling = true;
      scrollController.jumpTo(position.maxScrollExtent);
      _isAutoScrolling = false;
      _convergeToBottom(attempt + 1);
    });
  }

  Future<void> _animateToBottom() async {
    final generation = ++_autoScrollGeneration;
    _isAutoScrolling = true;
    try {
      await scrollController.animateTo(
        scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    } finally {
      // 新动画抢占旧动画会让旧 future 立即完成；只有最新一次动画有权清除标记，
      // 否则守卫会在新动画运行期间失效。
      if (generation == _autoScrollGeneration) {
        _isAutoScrolling = false;
      }
    }
    if (_isDisposed ||
        generation != _autoScrollGeneration ||
        !scrollController.hasClients) {
      return;
    }
    // 仅在动画确实停在底部时才恢复跟随：被用户拖动打断时不能覆盖其暂停意图。
    final position = scrollController.position;
    if (position.pixels >= position.maxScrollExtent - _bottomTolerance) {
      _userScrolledAwayFromBottom = false;
    }
  }

  /// 在触摸拖动刚开始时就暂停贴底，避免程序滚动抢走该手势。
  bool handleScrollNotification(ScrollNotification notification) {
    // 只响应本列表自身的滚动：卡片内嵌套滚动区（横向代码块等）冒泡上来的通知
    // 不应被当成用户在回看本列表历史。
    if (notification.depth != 0) {
      return false;
    }
    if (notification is ScrollStartNotification &&
        notification.dragDetails != null) {
      _userScrolledAwayFromBottom = true;
    } else if (notification is ScrollEndNotification &&
        notification.metrics.pixels >=
            notification.metrics.maxScrollExtent - _bottomTolerance) {
      // 手势结束时仍在底部容差内（例如只轻推了几十像素）→ 视为没有离开底部。
      // 监听器只在位置变化时才跑，不补这一下的话这类微小拖动会永久关闭跟随。
      _userScrolledAwayFromBottom = false;
    }
    return false;
  }

  void dispose() {
    _isDisposed = true;
    scrollController
      ..removeListener(_trackUserScroll)
      ..dispose();
  }
}
