// 职责: 在固定或自然尺寸的弹窗内承载局部提示，按语义绘制 toast 并以最新提示替换旧提示。
// 关联文件:
//   lib/desktop/widgets/settings/settings_dialog.dart
//   lib/shared/theme/theme.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../localization/app_localization.dart';
import '../localization/locale_keys.dart';
import '../theme/theme.dart';

/// 提示的语义分档，决定 toast 的底色、描边与图标。
enum DialogToastVariant { info, success, warning, error }

/// 标记一条提示的语义分档；外观由 [DialogFeedback] 的 messenger 统一绘制。
///
/// 未包裹时按 [DialogToastVariant.info] 处理，既有的
/// `SnackBar(content: Text(...))` 调用无需改动。在 [DialogFeedback] 之外
/// 直接渲染 child，退化成普通 SnackBar 内容。
class DialogToast extends StatelessWidget {
  const DialogToast({
    super.key,
    required this.child,
    this.variant = DialogToastVariant.info,
  });

  final Widget child;
  final DialogToastVariant variant;

  @override
  Widget build(BuildContext context) => child;
}

/// 放在 Dialog 的尺寸约束内；builder 提供局部 messenger 下的 context。
class DialogFeedback extends StatelessWidget {
  const DialogFeedback({super.key, required this.builder})
    : _mode = _FeedbackMode.bounded;

  /// 包住弹窗 widget，让其 build 中定义的回调也能取得局部 messenger。
  const DialogFeedback.scope({super.key, required this.builder})
    : _mode = _FeedbackMode.scope;

  /// 放在 scope 内的 Dialog.child 或 AlertDialog.content，保留内容固有尺寸。
  const DialogFeedback.surface({super.key, required this.builder})
    : _mode = _FeedbackMode.surface;

  /// 内容子组件自己发提示时，在自然尺寸的 Dialog 内同时创建 scope 和 surface。
  const DialogFeedback.intrinsic({super.key, required this.builder})
    : _mode = _FeedbackMode.intrinsic;

  final WidgetBuilder builder;
  final _FeedbackMode _mode;

  /// 关闭弹窗后的结果提示发送到宿主页面（也可能是外层弹窗）。
  static ScaffoldMessengerState hostMessengerOf(BuildContext context) {
    final messenger = ScaffoldMessenger.of(context);
    return messenger is _DialogMessengerState
        ? ScaffoldMessenger.of(messenger.context)
        : messenger;
  }

  @override
  Widget build(BuildContext context) {
    if (_mode == _FeedbackMode.scope) {
      return _DialogMessenger(child: Builder(builder: builder));
    }
    if (_mode == _FeedbackMode.intrinsic) {
      return _DialogMessenger(child: DialogFeedback.surface(builder: builder));
    }
    if (_mode == _FeedbackMode.surface) {
      final messenger = ScaffoldMessenger.of(context) as _DialogMessengerState;
      return Stack(
        children: [
          Builder(builder: builder),
          Positioned.fill(
            child: _ToastHitRegion(
              toastKey: messenger.toastKey,
              child: const Scaffold(backgroundColor: Colors.transparent),
            ),
          ),
        ],
      );
    }
    return _DialogMessenger(
      // 底色由宿主 Dialog 铺，这里透明以免盖掉毛玻璃或全局背景。
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Builder(builder: builder),
      ),
    );
  }
}

enum _FeedbackMode { bounded, scope, surface, intrinsic }

/// toast 图标与关闭按钮的统一尺寸。
const double _toastIconSize = 16;

/// 一档语义对应的配色与图标。
typedef _ToastPalette = ({
  Color background,
  Color? border,
  Color foreground,
  Color iconColor,
  String icon,
});

_ToastPalette _paletteOf(RevericColors colors, DialogToastVariant variant) {
  return switch (variant) {
    // 中性档就是 designs/desktop/kit.css 的 .m-toast：反色 pill、无描边。
    DialogToastVariant.info => (
      background: colors.textPrimary,
      border: null,
      foreground: colors.surface,
      iconColor: colors.surface,
      icon: RevericIcons.info,
    ),
    // 语义档用成对的 bg / border token。success、warning、error 本身是前景色，
    // 直接当底色在部分主题下过不了对比度，只能当描边和图标色用。
    DialogToastVariant.success => (
      background: colors.additionBg,
      border: colors.additionBorder,
      foreground: colors.textPrimary,
      iconColor: colors.additionBorder,
      icon: RevericIcons.check_circle,
    ),
    DialogToastVariant.warning => (
      background: colors.warningBg,
      border: colors.warningText,
      foreground: colors.textPrimary,
      iconColor: colors.warningText,
      icon: RevericIcons.warning,
    ),
    DialogToastVariant.error => (
      background: colors.deletionBg,
      border: colors.deletionBorder,
      foreground: colors.textPrimary,
      iconColor: colors.deletionBorder,
      icon: RevericIcons.warning_circle,
    ),
  };
}

class _DialogMessenger extends ScaffoldMessenger {
  const _DialogMessenger({required super.child});

  @override
  ScaffoldMessengerState createState() => _DialogMessengerState();
}

// 继承框架 State 是为了让已有 ScaffoldMessenger.of 调用共用替换策略。
class _DialogMessengerState extends ScaffoldMessengerState {
  final toastKey = GlobalKey();

  @override
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason> showSnackBar(
    SnackBar snackBar, {
    AnimationStyle? snackBarAnimationStyle,
  }) {
    final colors = RevericTheme.colorsOf(context);
    final typography = RevericTheme.typographyOf(context);
    final content = snackBar.content;
    final palette = _paletteOf(
      colors,
      content is DialogToast ? content.variant : DialogToastVariant.info,
    );
    clearSnackBars();
    removeCurrentSnackBar();
    return super.showSnackBar(
      SnackBar(
        key: snackBar.key,
        // pill 自绘：SnackBar 只当定位容器，圆角、描边、阴影、内边距全部可控。
        content: Align(
          child: Container(
            key: toastKey,
            constraints: const BoxConstraints(
              maxWidth: RevericSizes.toastMaxWidth,
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: RevericSpacing.x3l,
              vertical: RevericSpacing.md,
            ),
            decoration: BoxDecoration(
              color: snackBar.backgroundColor ?? palette.background,
              borderRadius: BorderRadius.circular(RevericRadius.large),
              border: palette.border == null
                  ? null
                  : Border.all(
                      color: palette.border!,
                      width: RevericSizes.dividerThickness,
                    ),
              // 尺度取自 designs/desktop/kit.css 的 .m-toast。阴影不能跟
              // textPrimary 走：暗色主题下它是近白色，会变成一圈光晕。
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(
                    alpha: colors.isDark ? 0.38 : 0.22,
                  ),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                RevericIcon(
                  palette.icon,
                  size: _toastIconSize,
                  color: palette.iconColor,
                ),
                const SizedBox(width: RevericSpacing.md),
                Flexible(
                  child: DefaultTextStyle(
                    style: typography.ui.copyWith(
                      color: palette.foreground,
                      height: 1.4,
                    ),
                    child: content,
                  ),
                ),
                // action 画在 pill 内；交给外层 SnackBar 会落到透明区域上。
                if (snackBar.action != null)
                  TextButtonTheme(
                    data: TextButtonThemeData(
                      style: TextButton.styleFrom(
                        foregroundColor: palette.foreground,
                        padding: const EdgeInsets.symmetric(
                          horizontal: RevericSpacing.lg,
                        ),
                      ),
                    ),
                    child: snackBar.action!,
                  ),
                if (snackBar.showCloseIcon ?? false) ...[
                  const SizedBox(width: RevericSpacing.sm),
                  IconButton(
                    icon: RevericIcon(
                      RevericIcons.close,
                      size: _toastIconSize,
                      color: palette.foreground,
                    ),
                    iconSize: _toastIconSize,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(
                      width: RevericSizes.iconButtonSize,
                      height: RevericSizes.iconButtonSize,
                    ),
                    visualDensity: VisualDensity.compact,
                    tooltip: context.t(LocaleKeys.commonClose),
                    onPressed: () =>
                        hideCurrentSnackBar(reason: SnackBarClosedReason.hide),
                  ),
                ],
              ],
            ),
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        margin: const EdgeInsets.symmetric(
          horizontal: RevericSpacing.x4l,
          vertical: RevericSpacing.x5l,
        ),
        padding: EdgeInsets.zero,
        clipBehavior: Clip.none,
        behavior: SnackBarBehavior.floating,
        // Material 自带的关闭图标是 Icons.close，项目覆盖了 Material 字体会渲染成
        // tofu，因此始终自绘。
        showCloseIcon: false,
        hitTestBehavior: snackBar.hitTestBehavior,
        duration: snackBar.duration,
        persist: snackBar.persist,
        animation: snackBar.animation,
        onVisible: snackBar.onVisible,
        dismissDirection: snackBar.dismissDirection,
      ),
      snackBarAnimationStyle: snackBarAnimationStyle,
    );
  }
}

// 透明 Scaffold 只负责显示 toast，空白处的鼠标/触摸必须交还给下面的表单。
class _ToastHitRegion extends SingleChildRenderObjectWidget {
  const _ToastHitRegion({required this.toastKey, required super.child});

  final GlobalKey toastKey;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderToastHitRegion(toastKey);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderToastHitRegion renderObject,
  ) {
    renderObject.toastKey = toastKey;
  }
}

class _RenderToastHitRegion extends RenderProxyBox {
  _RenderToastHitRegion(this.toastKey);

  GlobalKey toastKey;

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    final toast = toastKey.currentContext?.findRenderObject();
    if (toast is! RenderBox || !toast.hasSize) {
      return false;
    }
    final toastPosition = toast.globalToLocal(localToGlobal(position));
    if (!(Offset.zero & toast.size).contains(toastPosition)) {
      return false;
    }
    return super.hitTest(result, position: position);
  }
}
