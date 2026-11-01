// 职责: 移动端封面横向胶片条 — 序号、重出标记与已应用标记，点选切换当前方案。
// 关联文件:
//   lib/shared/providers/cover_studio_providers.dart
//   lib/mobile/features/cover_studio/canvas.dart
//   lib/shared/providers/novel_providers.dart
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/performance.md
//   .agents/rules/icons.md

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../shared/providers/cover_studio_providers.dart';
import '../../../shared/providers/novel_providers.dart';
import '../../../shared/theme/theme.dart';

/// 一格缩略图的高度。手机上竖版封面按 2:3 算宽约 48，四张并排还留得下手指间距。
const _thumbHeight = 72.0;

/// 横排贴在主图下面 —— 手机的瓶颈是宽度，竖排会把主图挤扁。
class MobileCoverFilmstrip extends ConsumerWidget {
  const MobileCoverFilmstrip({
    super.key,
    required this.novelId,
    required this.slots,
    required this.appliedAssetId,
  });

  final String novelId;
  final List<CoverSlotView> slots;
  final String? appliedAssetId;

  /// 画布算「适应」缩放时要扣掉的高度：缩略图 + 上下间距。
  static const stripHeight = _thumbHeight + RevericSpacing.md * 2;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (slots.isEmpty) {
      return const SizedBox.shrink();
    }
    final state = ref.watch(coverStudioControllerProvider(novelId));
    final controller = ref.read(
      coverStudioControllerProvider(novelId).notifier,
    );

    return SizedBox(
      height: stripHeight,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: RevericSpacing.x2l,
          vertical: RevericSpacing.md,
        ),
        itemCount: slots.length,
        separatorBuilder: (_, _) => const SizedBox(width: RevericSpacing.sm),
        itemBuilder: (context, index) {
          final slot = slots[index];
          return _Thumb(
            novelId: novelId,
            slot: slot,
            selected: slot.ordinal == state.selectedOrdinal,
            applied: slot.asset != null && slot.asset!.id == appliedAssetId,
            onTap: () => controller.selectOrdinal(slot.ordinal),
          );
        },
      ),
    );
  }
}

class _Thumb extends ConsumerWidget {
  const _Thumb({
    required this.novelId,
    required this.slot,
    required this.selected,
    required this.applied,
    required this.onTap,
  });

  final String novelId;
  final CoverSlotView slot;
  final bool selected;
  final bool applied;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final path = ref
        .read(imageLibraryServiceProvider)
        .resolve(slot.asset?.path);

    return GestureDetector(
      onTap: onTap,
      child: Stack(
        children: [
          Container(
            height: _thumbHeight,
            width: _thumbHeight * 2 / 3,
            decoration: BoxDecoration(
              color: colors.surfaceContainer,
              border: Border.all(
                color: selected ? colors.accent : colors.border,
                width: selected ? 2 : 1,
              ),
              borderRadius: BorderRadius.circular(RevericRadius.small),
            ),
            clipBehavior: Clip.antiAlias,
            child: path == null
                ? Center(
                    child: RevericIcon(
                      slot.failed
                          ? RevericIcons.warning
                          : RevericIcons.image_outlined,
                      size: 14,
                      color: slot.failed ? colors.error : colors.textSubtle,
                    ),
                  )
                : Image(
                    // 缩略图只有 48px 宽，解码整张原图纯属浪费（performance.md）。
                    image: ResizeImage(FileImage(File(path)), width: 144),
                    fit: BoxFit.cover,
                  ),
          ),
          Positioned(
            left: 3,
            top: 3,
            child: _Badge(
              label: '${slot.ordinal + 1}',
              background: selected
                  ? colors.accent
                  : colors.surface.withValues(alpha: 0.85),
              foreground: selected ? colors.onAccent : colors.textSecondary,
              typo: typo,
            ),
          ),
          // 重出过的一张，右下角一点标记。
          if (slot.previousAsset != null)
            Positioned(
              right: 5,
              bottom: 5,
              child: Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colors.accent,
                ),
              ),
            ),
          if (applied)
            Positioned(
              right: 3,
              top: 3,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colors.accent,
                ),
                child: RevericIcon(
                  RevericIcons.check,
                  size: 8,
                  color: colors.onAccent,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({
    required this.label,
    required this.background,
    required this.foreground,
    required this.typo,
  });

  final String label;
  final Color background;
  final Color foreground;
  final RevericTypography typo;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(RevericRadius.small),
      ),
      child: Text(
        label,
        style: typo.uiTinySemibold.copyWith(color: foreground),
      ),
    );
  }
}
