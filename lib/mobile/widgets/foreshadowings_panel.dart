// 职责: 移动端伏笔分区列表 — 列出伏笔条目（状态 + 标题 + 已关联位置 + 铺垫预览）、新建、左滑删除、点击进入伏笔编辑页。
// 关联文件:
//   lib/mobile/pages/foreshadowing_editor_page.dart
//   lib/mobile/widgets/section_scaffold.dart
//   lib/shared/widgets/foreshadowing/position_links.dart
//   lib/shared/providers/novel_providers.dart
//   lib/shared/models/foreshadowing.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/workspace.json
//   assets/translations/zh-CN/workspace.json
//   assets/translations/en/mobile.json
//   assets/translations/zh-CN/mobile.json
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
// 遵循的 Rules:
//   .agents/rules/state-management.md
//   .agents/rules/design-system.md
//   .agents/rules/icons.md
//   .agents/rules/i18n.md
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../shared/localization/app_localization.dart';
import '../../shared/localization/locale_keys.dart';
import '../../shared/models/foreshadowing.dart';
import '../../shared/providers/novel_providers.dart';
import '../../shared/theme/theme.dart';
import '../../shared/widgets/foreshadowing/position_links.dart';
import '../pages/foreshadowing_editor_page.dart';
import 'delete_confirm.dart';
import 'section_scaffold.dart';

class MobileForeshadowingsPanel extends ConsumerWidget {
  const MobileForeshadowingsPanel({
    super.key,
    required this.novelId,
    required this.databasePath,
    required this.onCreate,
  });

  final String novelId;
  final String databasePath;

  /// 新建入口由标题栏右上角承载；空状态引导按钮复用同一回调。
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(foreshadowingsProvider(databasePath));
    final foreshadowings = async.asData?.value ?? const <Foreshadowing>[];
    final enabled = foreshadowings.enabled.sorted;

    if (async.isLoading && foreshadowings.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    Future<void> openEditor(Foreshadowing f) async {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => MobileForeshadowingEditorPage(
            novelId: novelId,
            databasePath: databasePath,
            foreshadowingId: f.id,
          ),
        ),
      );
    }

    Future<void> deleteEntry(Foreshadowing f) async {
      final confirmed = await showMobileDeleteConfirm(context, title: f.title);
      if (!confirmed) {
        return;
      }
      final service = ref.read(novelContentServiceProvider(databasePath));
      await service.deleteForeshadowing(f.id);
    }

    // 位置候选按作品解析一次，卡片只查表；每张卡片各自解析会把季 / 集 / 场次
    // 的订阅扇出乘以列表长度。
    final positions = {
      for (final target in watchForeshadowingPositionTargets(
        context,
        ref,
        databasePath,
      ).options)
        target.id: target.shortLabel,
    };

    // 新建入口由外部标题栏承载；空状态仍保留引导按钮（走 onCreate）。
    return MobileSectionListScaffold(
      createLabel: context.t(LocaleKeys.workspaceNewForeshadowing),
      onCreate: onCreate,
      showCreateBar: false,
      emptyIcon: RevericIcons.alt_route_outlined,
      emptySectionLabel: context.t(LocaleKeys.workspaceForeshadowings),
      emptyHint: context.t(LocaleKeys.workspaceForeshadowingsHint),
      itemCount: enabled.length,
      itemBuilder: (_, index) => _ForeshadowingCard(
        f: enabled[index],
        positions: positions,
        onTap: openEditor,
        onDelete: deleteEntry,
      ),
    );
  }
}

class _ForeshadowingCard extends StatelessWidget {
  const _ForeshadowingCard({
    required this.f,
    required this.positions,
    required this.onTap,
    required this.onDelete,
  });

  final Foreshadowing f;

  /// 位置 ID → 短标签，小说是章节标题，剧本是「第 N 集 · 第 M 场」。
  final Map<String, String> positions;
  final ValueChanged<Foreshadowing> onTap;
  final ValueChanged<Foreshadowing> onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final title = f.title.trim().isEmpty
        ? context.t(LocaleKeys.commonUntitled)
        : f.title.trim();
    final preview = f.setupSummary;
    final statusColor = _statusColor(f.normalizedStatus, colors);
    final statusLabel = _statusLabel(context, f.normalizedStatus);

    final setupId = foreshadowingPositionId(f, setup: true);
    final payoffId = foreshadowingPositionId(f, setup: false);
    final setupLabel =
        _positionLabel(context, setupId) ??
        context.t(LocaleKeys.workspaceForeshadowSetupPosition);
    final payoffPending = payoffId == null;
    final payoffLabel =
        _positionLabel(context, payoffId) ??
        context.t(LocaleKeys.workspaceForeshadowPayoffPending);

    return MobileSectionCard(
      onTap: () => onTap(f),
      onDelete: () => onDelete(f),
      deleteLabel: context.t(LocaleKeys.commonDelete),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              RevericIcon(RevericIcons.flag, size: 16, color: statusColor),
              const SizedBox(width: RevericSpacing.sm),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: typo.uiSemibold.copyWith(color: colors.textPrimary),
                ),
              ),
              MobileSectionTagChip(
                label: statusLabel,
                backgroundColor: statusColor.withValues(alpha: 0.12),
                foregroundColor: statusColor,
              ),
            ],
          ),
          const SizedBox(height: RevericSpacing.sm),
          // 位置标签长度不可控（章节标题、「第 N 集 · 第 M 场」），两端都要能压缩。
          Row(
            children: [
              Flexible(child: MobileSectionTagChip(label: setupLabel)),
              const SizedBox(width: RevericSpacing.xs),
              RevericIcon(
                RevericIcons.arrow_forward,
                size: 13,
                color: colors.textSubtle,
              ),
              const SizedBox(width: RevericSpacing.xs),
              Flexible(
                child: MobileSectionTagChip(
                  label: payoffLabel,
                  backgroundColor: payoffPending ? colors.surfaceDim : null,
                  foregroundColor: payoffPending ? colors.textSubtle : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: RevericSpacing.sm),
          MobileSectionPreviewText(
            preview: preview,
            emptyPlaceholder: context.t(LocaleKeys.mobileEditorEntryNoContent),
            maxLines: 3,
          ),
        ],
      ),
    );
  }

  /// 已关联但目标已被删除时，与编辑页保持同一口径显示「目标不可用」。
  String? _positionLabel(BuildContext context, String? id) {
    if (id == null) {
      return null;
    }
    return positions[id] ??
        context.t(LocaleKeys.workspaceForeshadowPositionUnavailable);
  }
}

Color _statusColor(String status, RevericColors colors) {
  return switch (status) {
    foreshadowingStatusPlanted => colors.accentAmber,
    foreshadowingStatusPayoff => colors.accent,
    foreshadowingStatusAbandoned => colors.textMuted,
    _ => colors.textSubtle,
  };
}

String _statusLabel(BuildContext context, String status) {
  return switch (status) {
    foreshadowingStatusPending => context.t(
      LocaleKeys.foreshadowingStatusPending,
    ),
    foreshadowingStatusPlanted => context.t(
      LocaleKeys.foreshadowingStatusPlanted,
    ),
    foreshadowingStatusPayoff => context.t(
      LocaleKeys.foreshadowingStatusPayoff,
    ),
    foreshadowingStatusAbandoned => context.t(
      LocaleKeys.foreshadowingStatusAbandoned,
    ),
    _ => status,
  };
}
