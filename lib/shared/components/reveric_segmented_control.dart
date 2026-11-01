// 职责: Reveric 分段控件 — 通用 N 段切换，用带阴影的滑块标示选中态并平滑滑动。
// 关联文件:
//   lib/shared/theme/theme.dart
//   lib/shared/widgets/settings/usage_view.dart
// 遵循的 Rules:
//   .agents/rules/design-system.md

import 'package:flutter/material.dart';

import '../theme/theme.dart';

/// 分段控件的单个分段。[value] 用于回传选中项；[icon] 为可选的
/// [RevericIcons] 资源路径。
class RevericSegment<T> {
  const RevericSegment({
    required this.value,
    required this.label,
    this.icon,
    this.badgeLabel,
  });

  final T value;
  final String label;
  final String? icon;
  final String? badgeLabel;
}

/// 通用分段控件（segmented control）。
///
/// 选中态用一枚比轨道更亮的滑块（sliding pill）标示，切换时在轨道内平滑滑动。
/// 浅色主题靠阴影托起（surface / surfaceContainer 等 token 几乎同色）；深色主题
/// 阴影不可见且 surface 比轨道更暗，改用 surfaceContainerHigh 让滑块浮在轨道上。
///
/// 控件会填满父级宽度（各分段等宽），由调用方通过外层约束决定整体宽度。
class RevericSegmentedControl<T> extends StatelessWidget {
  const RevericSegmentedControl({
    super.key,
    required this.segments,
    required this.selected,
    required this.onChanged,
    this.height = RevericSizes.segmentHeight,
  });

  final List<RevericSegment<T>> segments;
  final T selected;
  final ValueChanged<T> onChanged;

  /// 请求的内容高度；移动端至少 48px，不包含上下轨道留白。
  final double height;

  /// 控件自然总高度，供调用方预留等高占位；包含平台触控下限及轨道留白。
  static double totalHeight(
    BuildContext context, {
    double height = RevericSizes.segmentHeight,
  }) {
    final mobile = switch (Theme.of(context).platform) {
      TargetPlatform.android || TargetPlatform.iOS => true,
      _ => false,
    };
    final contentHeight = mobile && height < RevericSizes.touchTargetSize
        ? RevericSizes.touchTargetSize
        : height;
    return contentHeight + 2 * RevericSizes.segmentTrackPadding;
  }

  static const Duration _slide = Duration(milliseconds: 280);
  static const Curve _curve = Curves.easeInOutCubic;

  int get _selectedIndex => segments.indexWhere((s) => s.value == selected);

  @override
  Widget build(BuildContext context) {
    assert(segments.isNotEmpty, 'segments must not be empty');
    final colors = RevericTheme.colorsOf(context);
    final count = segments.length;
    final selectedIndex = _selectedIndex;
    assert(selectedIndex >= 0, 'selected must match a segment');
    assert(
      segments.map((s) => s.value).toSet().length == count,
      'segment values must be unique',
    );
    final duration = MediaQuery.of(context).disableAnimations
        ? Duration.zero
        : _slide;
    // 滑块在轨道内的水平对齐：i 段 → x = -1 + 2i/(count-1)。
    final alignX = count <= 1 ? 0.0 : -1 + 2 * selectedIndex / (count - 1);

    return Container(
      padding: const EdgeInsets.all(RevericSizes.segmentTrackPadding),
      decoration: BoxDecoration(
        color: colors.surfaceDim,
        borderRadius: BorderRadius.circular(RevericRadius.medium),
      ),
      child: SizedBox(
        height:
            totalHeight(context, height: height) -
            2 * RevericSizes.segmentTrackPadding,
        child: Stack(
          children: [
            if (selectedIndex >= 0)
              AnimatedAlign(
                duration: duration,
                curve: _curve,
                alignment: AlignmentDirectional(alignX, 0),
                child: FractionallySizedBox(
                  widthFactor: 1 / count,
                  heightFactor: 1,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.brightness == Brightness.dark
                          ? colors.surfaceContainerHigh
                          : colors.surface,
                      borderRadius: BorderRadius.circular(RevericRadius.small),
                      border: Border.all(color: colors.borderInput),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.06),
                          blurRadius: 4,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            Row(
              children: [
                for (final segment in segments)
                  _SegmentLabel(
                    segment: segment,
                    active: segment.value == selected,
                    onTap: () => onChanged(segment.value),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SegmentLabel<T> extends StatelessWidget {
  const _SegmentLabel({
    required this.segment,
    required this.active,
    required this.onTap,
  });

  final RevericSegment<T> segment;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final color = active ? colors.textPrimary : colors.textMuted;
    final label = [
      segment.label,
      if (segment.badgeLabel != null) segment.badgeLabel!,
    ].join(' ');
    return Expanded(
      child: Semantics(
        selected: active,
        inMutuallyExclusiveGroup: true,
        button: true,
        label: label,
        child: Tooltip(
          message: label,
          excludeFromSemantics: true,
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(RevericRadius.small),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: RevericSpacing.xs,
                ),
                child: Center(
                  child: ExcludeSemantics(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (segment.icon != null) ...[
                          RevericIcon(
                            segment.icon!,
                            size: RevericSizes.buttonIconSize,
                            color: color,
                          ),
                          const SizedBox(width: RevericSpacing.xxs),
                        ],
                        Flexible(
                          child: AnimatedDefaultTextStyle(
                            duration: MediaQuery.of(context).disableAnimations
                                ? Duration.zero
                                : RevericSegmentedControl._slide,
                            curve: RevericSegmentedControl._curve,
                            style: (active ? typo.uiSemibold : typo.ui)
                                .copyWith(color: color),
                            child: Text(
                              segment.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        if (segment.badgeLabel != null) ...[
                          const SizedBox(width: RevericSpacing.xxs),
                          Text(
                            segment.badgeLabel!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: typo.uiTiny.copyWith(
                              color: colors.textMuted,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
