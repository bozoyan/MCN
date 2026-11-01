// 职责: 人物档案分组骨架 — 定义七个分组的唯一真源，并提供吸顶锚点栏与滚动联动控制器。
// 关联文件:
//   lib/desktop/widgets/workspace/character_profile_editor.dart
//   lib/mobile/pages/character_editor_page.dart
//   lib/shared/widgets/character/character_relations_overview.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/workspace.json
//   assets/translations/zh-CN/workspace.json
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/performance.md
//   .agents/rules/icons.md

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../localization/app_localization.dart';
import '../../localization/locale_keys.dart';
import '../../theme/theme.dart';

/// 人物档案的七个分组。桌面与移动端共用同一份顺序与文案。
enum CharacterProfileSectionId {
  identity,
  figure,
  biography,
  outward,
  psyche,
  story,
  relations,
}

class CharacterProfileSection {
  const CharacterProfileSection({
    required this.id,
    required this.titleKey,
    required this.hintKey,
    required this.icon,
  });

  final CharacterProfileSectionId id;
  final String titleKey;
  final String hintKey;
  final String icon;
}

const characterProfileSections = <CharacterProfileSection>[
  CharacterProfileSection(
    id: CharacterProfileSectionId.identity,
    titleKey: LocaleKeys.workspaceCharacterSectionIdentity,
    hintKey: LocaleKeys.workspaceCharacterSectionIdentityHint,
    icon: RevericIcons.person,
  ),
  CharacterProfileSection(
    id: CharacterProfileSectionId.figure,
    titleKey: LocaleKeys.workspaceCharacterSectionFigure,
    hintKey: LocaleKeys.workspaceCharacterSectionFigureHint,
    icon: RevericIcons.image_outlined,
  ),
  CharacterProfileSection(
    id: CharacterProfileSectionId.biography,
    titleKey: LocaleKeys.workspaceCharacterSectionBiography,
    hintKey: LocaleKeys.workspaceCharacterSectionBiographyHint,
    icon: RevericIcons.book_open,
  ),
  CharacterProfileSection(
    id: CharacterProfileSectionId.outward,
    titleKey: LocaleKeys.workspaceCharacterSectionOutward,
    hintKey: LocaleKeys.workspaceCharacterSectionOutwardHint,
    icon: RevericIcons.mask_happy_rounded,
  ),
  CharacterProfileSection(
    id: CharacterProfileSectionId.psyche,
    titleKey: LocaleKeys.workspaceCharacterSectionPsyche,
    hintKey: LocaleKeys.workspaceCharacterSectionPsycheHint,
    icon: RevericIcons.favorite,
  ),
  CharacterProfileSection(
    id: CharacterProfileSectionId.story,
    titleKey: LocaleKeys.workspaceCharacterSectionStory,
    hintKey: LocaleKeys.workspaceCharacterSectionStoryHint,
    icon: RevericIcons.water,
  ),
  CharacterProfileSection(
    id: CharacterProfileSectionId.relations,
    titleKey: LocaleKeys.workspaceCharacterSectionRelations,
    hintKey: LocaleKeys.workspaceCharacterSectionRelationsHint,
    icon: RevericIcons.account_tree,
  ),
];

/// 锚点栏与分组滚动的双向联动。
///
/// 页面持有本对象并把 [keyOf] 挂到各分组根节点上；锚点栏只订阅 [active]，
/// 滚动过程中不触发整页重建（`.agents/rules/performance.md`）。
class CharacterProfileScrollSpy {
  CharacterProfileScrollSpy({
    required this.scrollController,
    required this.stickyExtent,
  }) : active = ValueNotifier<CharacterProfileSectionId>(
         characterProfileSections.first.id,
       );

  final ScrollController scrollController;

  /// 吸顶锚点栏高度：判定「已到顶」时要把被遮住的那一条排除掉。
  final double stickyExtent;

  final ValueNotifier<CharacterProfileSectionId> active;

  final Map<CharacterProfileSectionId, GlobalKey> _keys =
      <CharacterProfileSectionId, GlobalKey>{};

  bool _jumping = false;

  GlobalKey keyOf(CharacterProfileSectionId id) {
    return _keys.putIfAbsent(id, GlobalKey.new);
  }

  void attach() => scrollController.addListener(sync);

  void dispose() {
    scrollController.removeListener(sync);
    active.dispose();
  }

  /// 依据当前滚动位置收敛出高亮分组。
  void sync() {
    if (_jumping || !scrollController.hasClients) {
      return;
    }
    final position = scrollController.position;
    // 末尾分组永远到不了顶部，滚到底时直接收敛到最后一项。
    if (position.pixels >= position.maxScrollExtent - 8) {
      active.value = characterProfileSections.last.id;
      return;
    }
    final limit = position.pixels + stickyExtent + 1;
    var current = characterProfileSections.first.id;
    for (final section in characterProfileSections) {
      final offset = _offsetOf(section.id);
      if (offset != null && offset <= limit) {
        current = section.id;
      }
    }
    active.value = current;
  }

  Future<void> jumpTo(CharacterProfileSectionId id) async {
    final offset = _offsetOf(id);
    if (offset == null || !scrollController.hasClients) {
      return;
    }
    _jumping = true;
    active.value = id;
    try {
      await scrollController.animateTo(
        (offset - stickyExtent).clamp(
          scrollController.position.minScrollExtent,
          scrollController.position.maxScrollExtent,
        ),
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
      );
    } finally {
      _jumping = false;
    }
  }

  /// 分组顶部对齐视口顶部时所需的滚动偏移。
  double? _offsetOf(CharacterProfileSectionId id) {
    final context = _keys[id]?.currentContext;
    final box = context?.findRenderObject();
    if (box is! RenderBox || !box.attached) {
      return null;
    }
    final viewport = RenderAbstractViewport.maybeOf(box);
    if (viewport == null) {
      return null;
    }
    return viewport.getOffsetToReveal(box, 0).offset;
  }
}

/// 吸顶锚点栏高度（桌面与移动端一致，scroll spy 的判定线依赖它）。
const double characterProfileAnchorBarHeight = 44;

/// 横向锚点 chip 条：点击跳转分组，滚动时高亮跟随并自动居中当前项。
class CharacterProfileAnchorBar extends StatefulWidget {
  const CharacterProfileAnchorBar({
    super.key,
    required this.spy,
    this.counts = const <CharacterProfileSectionId, int>{},
    this.horizontalPadding = RevericSpacing.x3l,
  });

  final CharacterProfileScrollSpy spy;
  final Map<CharacterProfileSectionId, int> counts;
  final double horizontalPadding;

  @override
  State<CharacterProfileAnchorBar> createState() =>
      _CharacterProfileAnchorBarState();
}

class _CharacterProfileAnchorBarState extends State<CharacterProfileAnchorBar> {
  final ScrollController _stripController = ScrollController();
  final Map<CharacterProfileSectionId, GlobalKey> _chipKeys = {
    for (final section in characterProfileSections) section.id: GlobalKey(),
  };

  @override
  void initState() {
    super.initState();
    widget.spy.active.addListener(_centerActiveChip);
  }

  @override
  void didUpdateWidget(covariant CharacterProfileAnchorBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.spy, widget.spy)) {
      oldWidget.spy.active.removeListener(_centerActiveChip);
      widget.spy.active.addListener(_centerActiveChip);
    }
  }

  @override
  void dispose() {
    widget.spy.active.removeListener(_centerActiveChip);
    _stripController.dispose();
    super.dispose();
  }

  /// 当前分组的锚点始终留在可视范围内。
  ///
  /// 只滚 chip 条自己：`Scrollable.ensureVisible` 会连带滚动所有祖先 scrollable，
  /// 高亮跟随时会把整页也拖走。
  void _centerActiveChip() {
    if (!_stripController.hasClients) {
      return;
    }
    final chipBox = _chipKeys[widget.spy.active.value]?.currentContext
        ?.findRenderObject();
    final barBox = context.findRenderObject();
    if (chipBox is! RenderBox ||
        barBox is! RenderBox ||
        !chipBox.attached ||
        !barBox.attached) {
      return;
    }
    final chipLeft =
        chipBox.localToGlobal(Offset.zero, ancestor: barBox).dx +
        _stripController.offset;
    final target = chipLeft - (barBox.size.width - chipBox.size.width) / 2;
    final position = _stripController.position;
    _stripController.animateTo(
      target.clamp(position.minScrollExtent, position.maxScrollExtent),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    return Container(
      height: characterProfileAnchorBarHeight,
      decoration: BoxDecoration(
        color: colors.canvas,
        border: Border(bottom: BorderSide(color: colors.borderSubtle)),
      ),
      alignment: Alignment.centerLeft,
      child: ValueListenableBuilder<CharacterProfileSectionId>(
        valueListenable: widget.spy.active,
        builder: (context, active, _) {
          return SingleChildScrollView(
            controller: _stripController,
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: widget.horizontalPadding),
            child: Row(
              children: [
                for (final section in characterProfileSections)
                  Padding(
                    key: _chipKeys[section.id],
                    padding: const EdgeInsets.only(right: RevericSpacing.xxs),
                    child: _AnchorChip(
                      section: section,
                      selected: section.id == active,
                      count: widget.counts[section.id],
                      onTap: () => widget.spy.jumpTo(section.id),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _AnchorChip extends StatelessWidget {
  const _AnchorChip({
    required this.section,
    required this.selected,
    required this.count,
    required this.onTap,
  });

  final CharacterProfileSection section;
  final bool selected;
  final int? count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final foreground = selected ? colors.accentWarm : colors.textMuted;
    return Material(
      color: selected ? colors.selected : Colors.transparent,
      borderRadius: BorderRadius.circular(RevericRadius.pill),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(RevericRadius.pill),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: RevericSpacing.lg,
            vertical: RevericSpacing.xs,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              RevericIcon(section.icon, size: 14, color: foreground),
              const SizedBox(width: RevericSpacing.xs),
              Text(
                context.t(section.titleKey),
                style: typo.uiSmallSemibold.copyWith(color: foreground),
              ),
              if (count != null) ...[
                const SizedBox(width: RevericSpacing.xs),
                Text(
                  '$count',
                  style: typo.uiTiny.copyWith(color: colors.textSubtle),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 让锚点栏在 [CustomScrollView] 里吸顶。
class CharacterProfileAnchorHeaderDelegate
    extends SliverPersistentHeaderDelegate {
  const CharacterProfileAnchorHeaderDelegate({required this.child});

  final Widget child;

  @override
  double get minExtent => characterProfileAnchorBarHeight;

  @override
  double get maxExtent => characterProfileAnchorBarHeight;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return child;
  }

  @override
  bool shouldRebuild(
    covariant CharacterProfileAnchorHeaderDelegate oldDelegate,
  ) {
    return !identical(oldDelegate.child, child);
  }
}

/// 分组标题：图标底章 + 标题 + 说明 + 可选右侧动作。
class CharacterProfileSectionHeader extends StatelessWidget {
  const CharacterProfileSectionHeader({
    super.key,
    required this.section,
    this.action,
  });

  final CharacterProfileSection section;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return Row(
      children: [
        Container(
          width: RevericSizes.aiAvatarMd,
          height: RevericSizes.aiAvatarMd,
          decoration: BoxDecoration(
            color: colors.selected,
            borderRadius: BorderRadius.circular(RevericRadius.large),
          ),
          alignment: Alignment.center,
          child: RevericIcon(section.icon, size: 14, color: colors.accentWarm),
        ),
        const SizedBox(width: RevericSpacing.sm),
        Flexible(
          child: Text(
            context.t(section.titleKey),
            style: typo.uiSemibold.copyWith(color: colors.textPrimary),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: RevericSpacing.sm),
        Flexible(
          child: Text(
            context.t(section.hintKey),
            style: typo.uiTiny.copyWith(color: colors.textSubtle),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (action != null) ...[const Spacer(), action!],
      ],
    );
  }
}

/// 分组内的次级小标题（如「头像与照片」「性格」「情境行为」）。
class CharacterProfileSubLabel extends StatelessWidget {
  const CharacterProfileSubLabel({super.key, required this.text, this.note});

  final String text;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return Row(
      children: [
        Text(
          text,
          style: typo.uiSmallSemibold.copyWith(color: colors.textSecondary),
        ),
        if (note != null) ...[
          const SizedBox(width: RevericSpacing.sm),
          Flexible(
            child: Text(
              note!,
              style: typo.uiTiny.copyWith(color: colors.textSubtle),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ],
    );
  }
}
