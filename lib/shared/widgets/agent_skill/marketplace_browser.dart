// 职责: 提供技能广场搜索、分类、缓存状态与链接打开的共享状态，供桌面 / 移动端各自渲染。
// 关联文件:
//   lib/shared/providers/agent_skill_catalog_providers.dart
//   lib/desktop/features/agent_skills/marketplace_catalog_tab.dart
//   lib/mobile/features/agent_skills/marketplace_tab.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/agent_skill.json
//   assets/translations/zh-CN/agent_skill.json
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
// 遵循的 Rules:
//   .agents/rules/hooks.md
//   .agents/rules/search-debounce.md
//   .agents/rules/design-system.md
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../components/reveric_button.dart';
import '../../components/reveric_search_field.dart';
import '../../localization/app_localization.dart';
import '../../localization/locale_keys.dart';
import '../../logger/app_logger.dart';
import '../../models/marketplace_agent_skill.dart';
import '../../providers/agent_skill_catalog_providers.dart';
import '../../theme/theme.dart';

final marketplaceLinkLauncherProvider = Provider<Future<bool> Function(Uri)>(
  (ref) =>
      (uri) => launchUrl(uri, mode: LaunchMode.externalApplication),
);
final _log = AppLogger.forModule('SkillMarketplace');

/// 技能广场一帧的展示状态；[filtered] 为 null 表示尚无目录数据。
class MarketplaceCatalogView {
  const MarketplaceCatalogView({
    required this.list,
    required this.searchController,
    required this.categories,
    required this.selectedCategory,
    required this.onCategory,
    required this.filtered,
    required this.refresh,
    required this.open,
  });

  final MarketplaceCatalogState list;
  final TextEditingController searchController;
  final List<String> categories;
  final String? selectedCategory;
  final ValueChanged<String?> onCategory;
  final List<MarketplaceAgentSkill>? filtered;
  final VoidCallback refresh;
  final void Function(String url) open;
}

MarketplaceCatalogView useMarketplaceCatalog(
  BuildContext context,
  WidgetRef ref,
) {
  final search = useDebouncedSearch();
  final category = useState<String?>(null);
  final list = ref.watch(marketplaceAgentSkillsProvider);
  ref.listen(marketplaceAgentSkillsProvider, (previous, next) {
    if (next.error != null &&
        next.skills != null &&
        previous?.error != next.error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.t(LocaleKeys.agentSkillMarketCached))),
      );
    }
  });
  final skills = list.skills;
  final categories = {
    for (final skill in skills ?? const <MarketplaceAgentSkill>[])
      if (skill.category.isNotEmpty) skill.category,
  }.toList()..sort();
  final selected = categories.contains(category.value) ? category.value : null;

  Future<void> open(String url) async {
    try {
      if (await ref.read(marketplaceLinkLauncherProvider)(Uri.parse(url))) {
        return;
      }
      throw StateError('System browser declined the URL');
    } catch (error, stackTrace) {
      _log.error(
        'Open skill source failed',
        error: error,
        stackTrace: stackTrace,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.t(LocaleKeys.commonOpenLinkFailed))),
        );
      }
    }
  }

  return MarketplaceCatalogView(
    list: list,
    searchController: search.controller,
    categories: categories,
    selectedCategory: selected,
    onCategory: (value) => category.value = value,
    filtered: skills
        ?.where(
          (skill) =>
              (selected == null || skill.category == selected) &&
              skill.matches(search.query),
        )
        .toList(),
    refresh: () => ref.read(marketplaceAgentSkillsProvider.notifier).refresh(),
    open: open,
  );
}

/// 广场刷新按钮；刷新失败但仍有缓存时切换为警告图标并提示正在展示缓存。
class MarketplaceRefreshButton extends StatelessWidget {
  const MarketplaceRefreshButton({super.key, required this.view});

  final MarketplaceCatalogView view;

  @override
  Widget build(BuildContext context) {
    final list = view.list;
    return Tooltip(
      message: context.t(
        list.error != null && list.skills != null
            ? LocaleKeys.agentSkillMarketCached
            : LocaleKeys.commonRefresh,
      ),
      child: RevericButton.text(
        label: context.t(LocaleKeys.commonRefresh),
        icon: list.error != null
            ? RevericIcons.warning_circle
            : RevericIcons.arrow_clockwise,
        loading: list.loading,
        onPressed: list.loading ? null : view.refresh,
      ),
    );
  }
}
