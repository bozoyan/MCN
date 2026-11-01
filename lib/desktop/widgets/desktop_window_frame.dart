// 职责: 桌面窗口框架 — 统一承载系统标题栏、窗口拖拽区域和内容避让尺寸。
// 关联文件:
//   lib/desktop/pages/novel_editor.dart
//   lib/desktop/pages/home.dart
//   lib/desktop/widgets/ai/chat/header.dart
//   lib/desktop/widgets/sidebar/sidebar.dart
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../../shared/logger/app_logger.dart';
import '../../shared/widgets/app_background.dart';

final _log = AppLogger.forModule('WindowFrame');

/// 内容铺到窗口顶部，标题栏覆盖其上；各区域自行消费避让尺寸。
/// 使用原生标题栏的窗口通过 showCustomTitleBar 关闭自绘覆盖。
class DesktopWindowFrame extends ConsumerWidget {
  const DesktopWindowFrame({
    super.key,
    required this.child,
    this.titleBarForeground,
    this.titleBarGestureExclusionKeys = const <GlobalKey>[],
    this.showCustomTitleBar = true,
  });

  final Widget child;
  final Widget? titleBarForeground;

  /// Widgets rendered over the title bar, but meant to behave as normal app UI.
  /// These regions must not be claimed by the caption drag/double-click layer,
  /// otherwise double-clicking buttons such as Save can maximize the window.
  final List<GlobalKey> titleBarGestureExclusionKeys;

  /// Flutter 原生 `Window` 使用系统标题栏时关闭自绘标题栏，避免控制到主窗口。
  final bool showCustomTitleBar;

  /// Height of the drag / caption bar overlay (same on all desktop platforms).
  static const double titleBarHeight = 48;

  /// Horizontal width reserved for macOS traffic-light buttons.
  static const double macosTrafficLightWidth = 76;

  /// Horizontal width occupied by Windows/Linux min/max/close buttons
  /// rendered by `WindowCaption`. 3 buttons × 46px each.
  static const double windowsCaptionButtonsWidth = 138;

  /// Width of the novel-editor collapsed AI rail on the right edge.
  /// Caption buttons overlap this rail plus part of the panel to its left.
  static const double collapsedAiRailWidth = 44;

  /// Extra top inset for sidebar content so it clears the title bar overlay.
  /// 沉浸式布局下，child 延伸到 y=0，sidebar 自身需要避让标题栏区域。
  static double get sidebarTopInset => titleBarHeight;

  /// Extra leading inset for the sidebar's first row so it clears the
  /// traffic-light buttons on macOS; 0 on other platforms.
  static double get sidebarLeadingInset =>
      Platform.isMacOS ? macosTrafficLightWidth : 0.0;

  /// Extra trailing inset to avoid Windows/Linux min/max/close caption
  /// buttons; 0 on macOS (按钮在左侧)。
  /// 最右侧的 panel header 应在右侧 padding 中加上这个值，避免按钮被遮挡。
  static double get trailingInset =>
      defaultTargetPlatform == TargetPlatform.macOS
      ? 0.0
      : windowsCaptionButtonsWidth;

  /// Top inset for interactive headers that would otherwise sit under the
  /// Windows system caption hit-test layer.
  /// 布局使用 Flutter 目标平台，允许测试显式覆盖 Windows 分支。
  static double get captionSafeTopInset =>
      defaultTargetPlatform == TargetPlatform.windows ? titleBarHeight : 0.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Stack(
      children: [
        const Positioned.fill(child: AppBackgroundLayer()),
        Positioned.fill(child: child),
        if (showCustomTitleBar)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: titleBarHeight,
            child: Stack(
              children: [
                Positioned.fill(
                  child: Platform.isMacOS
                      ? _MacOSOverlay(
                          gestureExclusionKeys: titleBarGestureExclusionKeys,
                        )
                      : _DesktopCaptionOverlay(
                          brightness: Theme.of(context).brightness,
                          gestureExclusionKeys: titleBarGestureExclusionKeys,
                        ),
                ),
                if (titleBarForeground != null)
                  Positioned.fill(child: titleBarForeground!),
              ],
            ),
          ),
      ],
    );
  }
}

class _MacOSOverlay extends StatelessWidget {
  const _MacOSOverlay({required this.gestureExclusionKeys});

  final List<GlobalKey> gestureExclusionKeys;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const SizedBox(width: DesktopWindowFrame.macosTrafficLightWidth),
        Expanded(
          child: _CaptionHitTestGate(
            gestureExclusionKeys: gestureExclusionKeys,
            child: _CaptionDragArea(child: const SizedBox.expand()),
          ),
        ),
      ],
    );
  }
}

class _DesktopCaptionOverlay extends StatefulWidget {
  const _DesktopCaptionOverlay({
    required this.brightness,
    required this.gestureExclusionKeys,
  });

  final Brightness brightness;
  final List<GlobalKey> gestureExclusionKeys;

  @override
  State<_DesktopCaptionOverlay> createState() => _DesktopCaptionOverlayState();
}

class _DesktopCaptionOverlayState extends State<_DesktopCaptionOverlay>
    with WindowListener {
  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 左侧 DragToMoveArea 覆盖除右侧系统按钮外的整条标题栏，让窗口可拖动。
    // 使用 HitTestBehavior.translucent，单次点击穿透到子组件业务按钮，仅拖拽
    // 手势触发窗口移动。右侧 138px 留给三个系统按钮。
    return Row(
      children: [
        Expanded(
          child: _CaptionHitTestGate(
            gestureExclusionKeys: widget.gestureExclusionKeys,
            child: _CaptionDragArea(child: const SizedBox.expand()),
          ),
        ),
        SizedBox(
          width: DesktopWindowFrame.windowsCaptionButtonsWidth,
          height: DesktopWindowFrame.titleBarHeight,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              WindowCaptionButton.minimize(
                brightness: widget.brightness,
                onPressed: () async {
                  final isMinimized = await windowManager.isMinimized();
                  if (isMinimized) {
                    windowManager.restore();
                  } else {
                    windowManager.minimize();
                  }
                },
              ),
              FutureBuilder<bool>(
                future: windowManager.isMaximized(),
                builder: (context, snapshot) {
                  if (snapshot.data == true) {
                    return WindowCaptionButton.unmaximize(
                      brightness: widget.brightness,
                      onPressed: () {
                        windowManager.unmaximize();
                      },
                    );
                  }
                  return WindowCaptionButton.maximize(
                    brightness: widget.brightness,
                    onPressed: () {
                      windowManager.maximize();
                    },
                  );
                },
              ),
              WindowCaptionButton.close(
                brightness: widget.brightness,
                onPressed: () {
                  windowManager.close();
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  void onWindowMaximize() {
    setState(() {});
  }

  @override
  void onWindowUnmaximize() {
    setState(() {});
  }
}

class _CaptionDragArea extends StatefulWidget {
  const _CaptionDragArea({required this.child});

  final Widget child;

  @override
  State<_CaptionDragArea> createState() => _CaptionDragAreaState();
}

class _CaptionDragAreaState extends State<_CaptionDragArea> {
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanStart: (details) {
        // checkpoint 立即落盘：startDragging 走 vendored window_manager 原生
        // 代码（0.9.1 引入），若崩溃发生在窗口拖拽中，最后一条日志即此处。
        _log.checkpoint('title bar drag started (native)');
        windowManager.startDragging();
      },
      onDoubleTap: () async {
        final isMaximized = await windowManager.isMaximized();
        if (isMaximized) {
          windowManager.unmaximize();
        } else {
          windowManager.maximize();
        }
      },
      child: widget.child,
    );
  }
}

class _CaptionHitTestGate extends SingleChildRenderObjectWidget {
  const _CaptionHitTestGate({
    required this.gestureExclusionKeys,
    required super.child,
  });

  final List<GlobalKey> gestureExclusionKeys;

  @override
  _CaptionHitTestGateRenderObject createRenderObject(BuildContext context) {
    return _CaptionHitTestGateRenderObject(gestureExclusionKeys);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _CaptionHitTestGateRenderObject renderObject,
  ) {
    renderObject.gestureExclusionKeys = gestureExclusionKeys;
  }
}

class _CaptionHitTestGateRenderObject extends RenderProxyBox {
  _CaptionHitTestGateRenderObject(this._gestureExclusionKeys);

  List<GlobalKey> _gestureExclusionKeys;

  set gestureExclusionKeys(List<GlobalKey> value) {
    _gestureExclusionKeys = value;
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (_isExcluded(localToGlobal(position))) {
      return false;
    }
    return super.hitTest(result, position: position);
  }

  bool _isExcluded(Offset globalPosition) {
    for (final key in _gestureExclusionKeys) {
      final context = key.currentContext;
      if (context == null) {
        continue;
      }
      final renderObject = context.findRenderObject();
      if (renderObject is! RenderBox || !renderObject.hasSize) {
        continue;
      }
      final origin = renderObject.localToGlobal(Offset.zero);
      final rect = origin & renderObject.size;
      if (rect.contains(globalPosition)) {
        return true;
      }
    }
    return false;
  }
}
