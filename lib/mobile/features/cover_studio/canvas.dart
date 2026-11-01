// 职责: 移动端封面画布 — 主预览按可用空间自适应，下面接胶片条与说明行。
// 关联文件:
//   lib/shared/providers/cover_studio_providers.dart
//   lib/shared/widgets/cover_studio/slot_view.dart
//   lib/mobile/features/cover_studio/filmstrip.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/editor.json
//   assets/translations/zh-CN/editor.json
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/i18n.md
//   .agents/rules/icons.md

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/providers/cover_studio_providers.dart';
import '../../../shared/services/cover_prompt_builder.dart';
import '../../../shared/theme/theme.dart';
import '../../../shared/widgets/cover_studio/slot_view.dart';
import 'filmstrip.dart';

/// 舞台左右各留 20，与页面其它区块对齐。
const _stagePadH = 40.0;

/// 舞台上下留白 + 说明行的高度，`coverFitZoom` 要按它算「适应」。
const _stagePadV = 24.0;
const _belowPaper = 36.0;

class MobileCoverCanvas extends ConsumerWidget {
  const MobileCoverCanvas({
    super.key,
    required this.novelId,
    required this.novelTitle,
    required this.slots,
    required this.appliedAssetId,
    required this.onRework,
  });

  final String novelId;
  final String novelTitle;
  final List<CoverSlotView> slots;
  final String? appliedAssetId;
  final void Function(int ordinal) onRework;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = RevericTheme.colorsOf(context);
    final state = ref.watch(coverStudioControllerProvider(novelId));
    final ratio = coverRatioOf(state.ratioId);
    final selected = _selectedSlot(state.selectedOrdinal);

    if (slots.isEmpty && !state.generating) {
      return _EmptyStage(novelTitle: novelTitle);
    }

    // 缩放改画面宽度而不是 transform：transform 不占布局，放大后会盖住下面的
    // 胶片条与动作行。
    final paperWidth = coverPaperWidth * (state.zoom / 100);

    return LayoutBuilder(
      builder: (context, constraints) {
        // 胶片条在图下面而不是旁边，所以宽度不扣胶片条、高度要扣掉它。
        final fitted = coverFitZoom(
          stageWidth: constraints.maxWidth,
          stageHeight: constraints.maxHeight,
          aspectRatio: ratio.aspectRatio,
          stagePadH: _stagePadH,
          stagePadV: _stagePadV,
          filmstripWidth: 0,
          filmstripGap: 0,
          belowPaper:
              _belowPaper +
              (slots.isEmpty ? 0 : MobileCoverFilmstrip.stripHeight),
        );
        if (state.followFit && (state.zoom - fitted).abs() >= 0.5) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!context.mounted) {
              return;
            }
            ref
                .read(coverStudioControllerProvider(novelId).notifier)
                .applyFitZoom(fitted);
          });
        }

        return Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                // 放大到画面比屏幕还宽时横向可拖；没超出时 minWidth 保持居中。
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minWidth: math.max(0, constraints.maxWidth - _stagePadH),
                    ),
                    child: Column(
                      children: [
                        SizedBox(
                          key: const ValueKey('cover-stage-paper'),
                          width: paperWidth,
                          child: AspectRatio(
                            aspectRatio: ratio.aspectRatio,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: colors.surfaceContainer,
                                border: Border.all(color: colors.borderInput),
                                borderRadius: BorderRadius.circular(
                                  RevericRadius.medium,
                                ),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(
                                  RevericRadius.medium,
                                ),
                                child: CoverSlotCanvas(
                                  novelId: novelId,
                                  slot: selected,
                                  reworking:
                                      selected != null &&
                                      state.reworkingOrdinal ==
                                          selected.ordinal,
                                  onRework: onRework,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: RevericSpacing.sm),
                        CoverSlotCaption(
                          novelId: novelId,
                          slot: selected,
                          maxWidth: double.infinity,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            MobileCoverFilmstrip(
              key: const ValueKey('cover-filmstrip'),
              novelId: novelId,
              slots: slots,
              appliedAssetId: appliedAssetId,
            ),
          ],
        );
      },
    );
  }

  CoverSlotView? _selectedSlot(int ordinal) {
    if (slots.isEmpty) {
      return null;
    }
    for (final slot in slots) {
      if (slot.ordinal == ordinal) {
        return slot;
      }
    }
    return slots.first;
  }
}

class _EmptyStage extends StatelessWidget {
  const _EmptyStage({required this.novelTitle});

  final String novelTitle;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    // 生成入口在底部常驻条。这里只说明预览区怎么用。
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: RevericSpacing.x4l),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RevericIcon(
              RevericIcons.palette_outlined,
              size: 34,
              color: colors.textMuted,
            ),
            const SizedBox(height: RevericSpacing.md),
            Text(
              context.t(
                LocaleKeys.editorCoverEmptyTitle,
                namedArgs: {'title': novelTitle},
              ),
              textAlign: TextAlign.center,
              style: typo.heading2.copyWith(color: colors.textPrimary),
            ),
            const SizedBox(height: RevericSpacing.sm),
            Text(
              context.t(LocaleKeys.editorCoverEmptyBodyMobile),
              textAlign: TextAlign.center,
              style: typo.uiSmall.copyWith(color: colors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
