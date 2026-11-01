// 职责: 封面生成记录的一行 — 批次时间、成功张数、状态徽标、参数摘要，以及选中与删除。
// 关联文件:
//   lib/shared/providers/cover_studio_providers.dart
//   lib/desktop/features/cover_studio/records.dart
//   lib/mobile/features/cover_studio/records_sheet.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/zh-CN/common.json
//   assets/translations/en/common.json
//   assets/translations/en/editor.json
//   assets/translations/zh-CN/editor.json
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/data-deletion.md
//   .agents/rules/i18n.md

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../database/app_database.dart';
import '../../localization/app_localization.dart';
import '../../localization/locale_keys.dart';
import '../../providers/cover_studio_providers.dart';
import '../../theme/theme.dart';

class CoverBatchRow extends ConsumerWidget {
  const CoverBatchRow({
    super.key,
    required this.novelId,
    required this.batch,
    required this.active,
    required this.busy,
    this.onSelected,
  });

  final String novelId;
  final ImageBatchRow batch;
  final bool active;
  final bool busy;

  /// 选中之后宿主还要做的事，比如移动端关掉记录抽屉回到画布。
  final VoidCallback? onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final slots = ref.watch(coverSlotViewsProvider(batch.id, novelId));
    final controller = ref.read(
      coverStudioControllerProvider(novelId).notifier,
    );
    final succeeded = slots.where((slot) => slot.succeeded).length;

    return Material(
      // 记录行不再画缩略图，选中态只剩底色和字重可认。
      color: active ? colors.selected : Colors.transparent,
      borderRadius: BorderRadius.circular(RevericRadius.medium),
      child: InkWell(
        onTap: busy
            ? null
            : () {
                controller.selectBatch(batch);
                onSelected?.call();
              },
        borderRadius: BorderRadius.circular(RevericRadius.medium),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: RevericSpacing.sm,
            vertical: RevericSpacing.sm,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        Text(
                          _timeLabel(batch.createdAt),
                          style: typo.uiSmallSemibold.copyWith(
                            color: active
                                ? colors.textPrimary
                                : colors.textSecondary,
                          ),
                        ),
                        _Pill(
                          label: context.t(
                            LocaleKeys.editorCoverBatchCount,
                            namedArgs: {'count': '$succeeded'},
                          ),
                        ),
                        ?_statusPill(context, colors),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _noteFor(context, batch),
                      style: typo.uiTiny.copyWith(color: colors.textMuted),
                    ),
                  ],
                ),
              ),
              // 删除只收走这条记录：出的图留在图片库，已设为封面或当参考图的那张
              // 不受影响。与会话列表一致，×常驻行尾，不做 hover 才现。
              Tooltip(
                message: context.t(LocaleKeys.commonDelete),
                child: InkWell(
                  key: ValueKey('cover-batch-delete-${batch.id}'),
                  onTap: busy ? null : () => controller.deleteBatch(batch.id),
                  borderRadius: BorderRadius.circular(RevericRadius.small),
                  child: Padding(
                    padding: const EdgeInsets.all(RevericSpacing.xxs),
                    child: RevericIcon(
                      RevericIcons.close,
                      size: 12,
                      color: colors.textSubtle,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget? _statusPill(BuildContext context, RevericColors colors) {
    final (key, color) = switch (batch.status) {
      imageBatchStatusRunning => (
        LocaleKeys.editorCoverBatchStatusRunning,
        colors.accent,
      ),
      imageBatchStatusStopping => (
        LocaleKeys.editorCoverBatchStatusStopping,
        colors.accent,
      ),
      imageBatchStatusPartial => (
        LocaleKeys.editorCoverBatchStatusPartial,
        colors.warningText,
      ),
      imageBatchStatusCanceled => (
        LocaleKeys.editorCoverBatchStatusCanceled,
        colors.textSubtle,
      ),
      imageBatchStatusFailed => (
        LocaleKeys.editorCoverBatchStatusFailed,
        colors.error,
      ),
      // completed 不挂徽标：正常完成不需要额外说明。
      _ => (null, colors.textSubtle),
    };
    if (key == null) {
      return null;
    }
    return _Pill(label: context.t(key), color: color);
  }

  /// 记录行的副标题：这一批是按什么参数出的。参数存在 params_json 里。
  String _noteFor(BuildContext context, ImageBatchRow batch) {
    final params = _decodeParams(batch.paramsJson);
    final parts = <String>[
      if (params['style'] case final String style when style.isNotEmpty) style,
      if (params['palette'] case final String palette when palette.isNotEmpty)
        palette,
      if (params['references'] case final List<dynamic> refs
          when refs.isNotEmpty)
        context.t(
          LocaleKeys.editorCoverReferenceCount,
          namedArgs: {'count': '${refs.length}'},
        ),
    ];
    return parts.isEmpty ? batch.model ?? '' : parts.join(' · ');
  }

  static Map<String, dynamic> _decodeParams(String? paramsJson) {
    if (paramsJson == null || paramsJson.isEmpty) {
      return const {};
    }
    try {
      final decoded = jsonDecode(paramsJson);
      return decoded is Map<String, dynamic> ? decoded : const {};
    } catch (_) {
      return const {};
    }
  }

  String _timeLabel(DateTime createdAt) {
    final local = createdAt.toLocal();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '${local.month}/${local.day} $hh:$mm';
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, this.color});

  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final foreground = color ?? colors.textMuted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(RevericRadius.small),
        border: Border.all(color: foreground.withValues(alpha: 0.5)),
      ),
      child: Text(
        label,
        style: typo.uiTinySemibold.copyWith(color: foreground),
      ),
    );
  }
}
