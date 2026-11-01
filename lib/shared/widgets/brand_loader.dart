// 职责: 品牌加载动画（整屏等待用）— 双色折带描线入场，之后循环等待，外部标记完成后淡出。
// 关联文件:
//   assets/logo/reveric_mark.svg
//   assets/logo/reveric_wordmark.png
//   lib/main.dart
//   lib/desktop/pages/onboarding.dart
// 遵循的 Rules:
//   .agents/rules/hooks.md
//   .agents/rules/design-system.md
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import '../theme/theme.dart';

/// 入场时长（秒）。done 早于入场结束时，等入场播完再退出。
const double _kIntro = 1.9;
const double _kLoopPeriod = 1.8;
const double _kExit = 0.45;
const double _kShowFade = 0.3;

/// 舞台坐标系（与 reveric_mark.svg 的 1024 坐标一致）的可视区域。
const Rect _kStage = Rect.fromLTWH(20, 195, 984, 880);
const Rect _kWordmark = Rect.fromLTWH(152, 830, 720, 143);
const double _kCenterX = 512;
const double _kDividerY = 1030;

/// 整屏品牌加载动画。
///
/// [done] 变为 true 后，在入场播完的前提下淡出，结束时回调 [onExited]。
/// [skipIntro] 直接从循环态开始：用于会被反复挂载的启动占位，避免每个阶段重播入场。
/// [showDelay] 仅对 [skipIntro] 生效：这段时间内只铺背景色，超过该时长仍在加载才淡入 logo
/// 并开始循环；期间 done 到达则直接回调，用户完全看不到 logo，避免快速加载时一闪而过。
/// 系统开启「减少动态效果」时直接展示终态（有 showDelay 时保持只铺背景色），done 后立即回调。
class BrandLoader extends HookWidget {
  const BrandLoader({
    super.key,
    this.done = false,
    this.onExited,
    this.skipIntro = false,
    this.showDelay = Duration.zero,
    this.width = 280,
  });

  final bool done;
  final VoidCallback? onExited;
  final bool skipIntro;
  final Duration showDelay;
  final double width;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final palette = _BrandPalette.of(Theme.of(context).brightness);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    final vsync = useSingleTickerProvider();
    // 当前时间（秒）与完成请求时刻；ListenableBuilder 只重建动画子树。
    final startOffset = skipIntro ? _kIntro : 0.0;
    final delay = skipIntro
        ? showDelay.inMicroseconds / Duration.microsecondsPerSecond
        : 0.0;
    final clock = useMemoized(() => ValueNotifier<double>(startOffset));
    // logo 可见度：showDelay 期间为 0，之后淡入到 1。
    final appear = useMemoized(() => ValueNotifier<double>(delay > 0 ? 0 : 1));
    final doneAt = useRef<double?>(null);
    final rawNow = useRef(0.0);
    final exited = useRef(false);

    void exitNow() {
      if (exited.value) {
        return;
      }
      exited.value = true;
      SchedulerBinding.instance.addPostFrameCallback((_) => onExited?.call());
    }

    useEffect(() {
      if (reduceMotion) {
        clock.value = _kIntro;
        return null;
      }
      final ticker = vsync.createTicker((elapsed) {
        final raw = elapsed.inMicroseconds / Duration.microsecondsPerSecond;
        rawNow.value = raw;
        if (exited.value) {
          return;
        }
        // 隐藏期内时钟停在循环起点，淡入的同时从头进入循环。
        final t = startOffset + math.max(0.0, raw - delay);
        appear.value = delay > 0
            ? _interval(raw, delay, delay + _kShowFade)
            : 1;
        clock.value = t;
        final requested = doneAt.value;
        if (requested != null && !exited.value) {
          final exitStart = math.max(requested, _kIntro);
          if (t >= exitStart + _kExit) {
            exited.value = true;
            onExited?.call();
          }
        }
      });
      ticker.start();
      return ticker.dispose;
    }, [reduceMotion]);

    useEffect(() {
      if (!done || doneAt.value != null) {
        return null;
      }
      doneAt.value = clock.value;
      // logo 还没露面（隐藏期内）或关闭了动效：不播淡出，直接结束。
      if (reduceMotion || (delay > 0 && rawNow.value < delay)) {
        exitNow();
      }
      return null;
    }, [done]);

    useEffect(() {
      return () {
        clock.dispose();
        appear.dispose();
      };
    }, []);

    final height = width * _kStage.height / _kStage.width;
    final scale = width / _kStage.width;

    return ColoredBox(
      color: colors.canvas,
      child: Center(
        child: SizedBox(
          width: width,
          height: height,
          child: ListenableBuilder(
            listenable: Listenable.merge([clock, appear]),
            builder: (context, _) {
              final t = clock.value;
              if (appear.value == 0) {
                return const SizedBox.shrink();
              }
              final exit = _exitProgress(t, doneAt.value);
              final word = _interval(t, 1.3, 1.9, Curves.easeOutCubic);
              final wordRect = _toLocal(_kWordmark, scale);
              return Opacity(
                opacity: appear.value * (1 - exit),
                child: Transform.scale(
                  scale: 1 + 0.04 * exit,
                  origin: Offset(
                    (_kCenterX - _kStage.center.dx) * scale,
                    (630 - _kStage.center.dy) * scale,
                  ),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: CustomPaint(
                          painter: _BrandMarkPainter(t: t, palette: palette),
                        ),
                      ),
                      Positioned(
                        left: wordRect.left,
                        top: wordRect.top + 18 * (1 - word) * scale,
                        width: wordRect.width,
                        height: wordRect.height,
                        child: Opacity(
                          opacity: word,
                          child: Image.asset(
                            'assets/logo/reveric_wordmark.png',
                            color: palette.word,
                            colorBlendMode: BlendMode.srcIn,
                            fit: BoxFit.fill,
                            filterQuality: FilterQuality.medium,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  static double _exitProgress(double t, double? doneAt) {
    if (doneAt == null) {
      return 0;
    }
    final exitStart = math.max(doneAt, _kIntro);
    return _interval(t, exitStart, exitStart + _kExit, Curves.easeInCubic);
  }

  static Rect _toLocal(Rect stageRect, double scale) => Rect.fromLTWH(
    (stageRect.left - _kStage.left) * scale,
    (stageRect.top - _kStage.top) * scale,
    stageRect.width * scale,
    stageRect.height * scale,
  );
}

double _interval(
  double t,
  double begin,
  double end, [
  Curve curve = Curves.linear,
]) {
  final x = ((t - begin) / (end - begin)).clamp(0.0, 1.0);
  return curve.transform(x);
}

/// 品牌色：logo 本身的颜色，不随主题 accent 变化，只区分深浅。
class _BrandPalette {
  const _BrandPalette({
    required this.ink,
    required this.accent,
    required this.word,
  });

  /// 上方主折带。
  final Color ink;

  /// 下方折带，也用于分隔线与循环光点的光晕。
  final Color accent;
  final Color word;

  static const _light = _BrandPalette(
    ink: Color(0xFF283B5E),
    accent: Color(0xFF8797D2),
    word: Color(0xFF283B5E),
  );
  // 深色背景上主折带的深蓝几乎不可见，换成浅长春花色；与 Android 深色启动页一致。
  static const _dark = _BrandPalette(
    ink: Color(0xFFC5CEF0),
    accent: Color(0xFF8797D2),
    word: Color(0xFFE3E7F6),
  );

  static _BrandPalette of(Brightness brightness) =>
      brightness == Brightness.dark ? _dark : _light;
}

class _BrandMarkPainter extends CustomPainter {
  _BrandMarkPainter({required this.t, required this.palette});

  final double t;
  final _BrandPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / _kStage.width;
    canvas.save();
    canvas.scale(scale);
    canvas.translate(-_kStage.left, -_kStage.top);

    final drawTop = _interval(t, 0.0, 0.8, Curves.easeInOutCubic);
    final drawLower = _interval(t, 0.2, 1.0, Curves.easeInOutCubic);
    final fill = _interval(t, 0.85, 1.25, Curves.easeOutCubic);
    final outline = 1 - _interval(t, 1.1, 1.4);
    final word = _interval(t, 1.3, 1.9, Curves.easeOutCubic);

    final looping = t >= _kIntro;
    final loopT = math.max(0.0, t - _kIntro);
    final breathe = looping
        ? (1 - math.cos(loopT / _kLoopPeriod * math.pi * 2)) / 2
        : 0.0;
    final dotP = looping
        ? (1 - math.cos(loopT / _kLoopPeriod * math.pi)) / 2
        : 0.0;

    if (breathe > 0) {
      canvas.drawCircle(
        _MarkPaths.toStage(_MarkPaths.lowerCenter),
        150,
        Paint()
          ..color = palette.accent.withValues(alpha: 0.18 * breathe)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 40),
      );
    }

    canvas.save();
    canvas.translate(_MarkPaths.offset, _MarkPaths.offset);
    canvas.scale(_MarkPaths.scale);

    if (fill > 0) {
      canvas.drawPath(
        _MarkPaths.top,
        Paint()..color = palette.ink.withValues(alpha: fill),
      );
      // 循环时下方折带轻微下沉再回位，像翻折的纸页；只向远离上方折带的方向移动，不吃掉两者间的缝。
      canvas.save();
      canvas.translate(0, 12 * breathe);
      canvas.drawPath(
        _MarkPaths.lower,
        Paint()..color = palette.accent.withValues(alpha: fill),
      );
      canvas.restore();
    }

    if (outline > 0) {
      final stroke = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round;
      _drawPartial(
        canvas,
        _MarkPaths.top,
        drawTop,
        stroke..color = palette.ink.withValues(alpha: outline),
      );
      _drawPartial(
        canvas,
        _MarkPaths.lower,
        drawLower,
        stroke..color = palette.accent.withValues(alpha: outline),
      );
    }
    canvas.restore();

    if (word > 0) {
      _drawDivider(canvas, word);
    }

    if (looping) {
      canvas.drawCircle(
        Offset(_lerp(_kCenterX - 120, _kCenterX + 120, dotP), _kDividerY),
        5,
        Paint()..color = palette.ink.withValues(alpha: 0.9),
      );
    }

    canvas.restore();
  }

  void _drawPartial(Canvas canvas, Path path, double progress, Paint paint) {
    if (progress <= 0) {
      return;
    }
    for (final metric in path.computeMetrics()) {
      canvas.drawPath(metric.extractPath(0, metric.length * progress), paint);
    }
  }

  void _drawDivider(Canvas canvas, double word) {
    final y = _kDividerY + 18 * (1 - word);
    final half = 128 * word;
    canvas.drawLine(
      Offset(_kCenterX - half, y),
      Offset(_kCenterX + half, y),
      Paint()
        ..color = palette.accent.withValues(alpha: 0.8 * word)
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_BrandMarkPainter oldDelegate) =>
      oldDelegate.t != t || oldDelegate.palette != palette;
}

double _lerp(double a, double b, double p) => a + (b - a) * p;

/// reveric_mark.svg 的两条折带，坐标为 SVG 原始坐标；
/// 经 [offset] 平移、[scale] 缩放后落到 1024 舞台坐标。
abstract final class _MarkPaths {
  static const double offset = 72.05;
  static const double scale = 0.7;

  /// 下方折带的视觉中心（原始坐标），循环光晕围绕它。
  static const Offset lowerCenter = Offset(660, 830);

  static Offset toStage(Offset p) =>
      Offset(p.dx * scale + offset, p.dy * scale + offset);

  static final top = Path()
    ..moveTo(334, 620)
    ..cubicTo(334, 512, 436, 465, 579, 423)
    ..cubicTo(749, 372, 882, 326, 923, 248)
    ..lineTo(923, 429)
    ..cubicTo(923, 510, 836, 540, 718, 577)
    ..cubicTo(550, 633, 338, 722, 338, 811)
    ..cubicTo(334, 803, 334, 792, 334, 781)
    ..close();

  static final lower = Path()
    ..moveTo(608, 637)
    ..cubicTo(608, 708, 672, 744, 758, 781)
    ..cubicTo(845, 818, 892, 843, 913, 918)
    ..cubicTo(924, 953, 926, 985, 921, 1009)
    ..cubicTo(862, 949, 744, 935, 626, 925)
    ..cubicTo(507, 915, 415, 891, 415, 816)
    ..cubicTo(415, 752, 490, 691, 608, 637)
    ..close();
}
