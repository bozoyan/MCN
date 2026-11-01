// 职责: 剧本角色选择内容体 — 搜索、键盘选中、就地新建人物，供桌面浮层与移动 sheet 共用。
// 关联文件:
//   lib/desktop/features/screenplay/character_picker.dart
//   lib/mobile/features/screenplay/character_picker_sheet.dart
//   lib/shared/providers/novel_providers.dart
//   lib/shared/widgets/character_avatar.dart
//   lib/shared/components/reveric_search_field.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/screenplay.json
//   assets/translations/zh-CN/screenplay.json
// 遵循的 Rules:
//   .agents/rules/hooks.md
//   .agents/rules/search-debounce.md
//   .agents/rules/design-system.md
//   .agents/rules/text-input-ime.md
//   .agents/rules/i18n.md

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../components/reveric_search_field.dart';
import '../../localization/app_localization.dart';
import '../../localization/locale_keys.dart';
import '../../models/character_profile.dart';
import '../../providers/novel_providers.dart';
import '../../theme/theme.dart';
import '../character_avatar.dart';

/// 选项行高；键盘高亮滚动按这个值算，所以列表用 itemExtent 固定住。
const double _rowHeight = 40;

/// 角色选择内容体：搜索框 + 快捷键提示 + 人物列表 + 就地新建。
///
/// 只负责内容与交互，不负责弹层形态 —— 桌面挂在锚定浮层里、移动端挂在 bottom sheet 里，
/// 关闭由外壳在 [onPick] / [onSwitchToAction] / [onCancel] 里做。
class ScreenplayCharacterPickerBody extends HookConsumerWidget {
  const ScreenplayCharacterPickerBody({
    super.key,
    required this.databasePath,
    required this.onPick,
    required this.onCancel,
    this.selectedId,
    this.priorityIds = const [],
    this.onSwitchToAction,
    this.showShortcutHints = false,
    this.autofocus = true,
  });

  final String databasePath;

  /// 选中已有人物或新建成功后回调，参数是人物 id。
  final ValueChanged<String> onPick;

  final VoidCallback onCancel;

  /// 当前角色行已经绑定的人物，列表里打勾。
  final String? selectedId;

  /// 本场已经出场的人物 id，排在列表前面。
  final List<String> priorityIds;

  /// 「切换为动作」出口；为空则不渲染该提示行，也不接管 Tab。
  final VoidCallback? onSwitchToAction;

  /// 是否渲染 Tab / Enter 快捷键提示行（桌面 true、移动端 false）。
  final bool showShortcutHints;

  final bool autofocus;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final search = useDebouncedSearch();
    final controller = search.controller;
    final scrollController = useScrollController();
    final query = search.query;
    final name = controller.text.trim();
    final pending = name.toLowerCase() != query;
    final composing = controller.value.composing;
    final isComposing = composing.isValid && !composing.isCollapsed;
    // 高亮跟着查询走：改了关键词就回到第一条，否则回车会落在过滤前的旧行上。
    final highlight = useState((query: '', index: 0));
    final creating = useRef(false);

    final characters =
        ref.watch(characterProfilesProvider(databasePath)).value ??
        const <CharacterProfile>[];
    // 本场人物优先；只在防抖后的查询或人物数据变化时重新排序、过滤。
    final matches = useMemoized(() {
      final priority = priorityIds.toSet();
      final ordered = <CharacterProfile>[
        for (final character in characters)
          if (priority.contains(character.id)) character,
        for (final character in characters)
          if (!priority.contains(character.id)) character,
      ];
      return query.isEmpty
          ? ordered
          : ordered
                .where(
                  (character) => character.name.toLowerCase().contains(query),
                )
                .toList();
    }, [characters, priorityIds, query]);
    // 等查询稳定后才允许新建，名字保留用户输入的大小写。
    final canCreate =
        !pending &&
        !isComposing &&
        name.isNotEmpty &&
        !characters.any((character) => character.name.trim() == name);
    final rowCount = matches.length + (canCreate ? 1 : 0);
    final index = rowCount == 0 || highlight.value.query != query
        ? 0
        : highlight.value.index.clamp(0, rowCount - 1).toInt();

    void moveHighlight(int next) {
      highlight.value = (query: query, index: next);
    }

    // 键盘换行时把高亮行拉回视野；列表行高固定，直接按行号算偏移。
    useEffect(() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!scrollController.hasClients) {
          return;
        }
        final position = scrollController.position;
        final top = index * _rowHeight;
        if (top < position.pixels) {
          scrollController.jumpTo(top);
        } else if (top + _rowHeight >
            position.pixels + position.viewportDimension) {
          scrollController.jumpTo(
            (top + _rowHeight - position.viewportDimension).clamp(
              0,
              position.maxScrollExtent,
            ),
          );
        }
      });
      return null;
    }, [index, scrollController]);

    Future<void> create() async {
      if (!canCreate || creating.value) {
        return;
      }
      creating.value = true;
      try {
        final id = await ref
            .read(novelContentServiceProvider(databasePath))
            .createCharacterProfile(name: name);
        if (context.mounted) {
          onPick(id);
        }
      } finally {
        creating.value = false;
      }
    }

    void activate(int target) {
      if (pending || isComposing) {
        return;
      }
      if (target < matches.length) {
        onPick(matches[target].id);
        return;
      }
      create();
    }

    KeyEventResult handleKey(FocusNode node, KeyEvent event) {
      if (event is KeyUpEvent) {
        return KeyEventResult.ignored;
      }
      // 中文输入法组词期间的回车是上屏，不是「选中」。
      final composing = controller.value.composing;
      if (composing.isValid && !composing.isCollapsed) {
        return KeyEventResult.ignored;
      }
      final key = event.logicalKey;
      // 防抖期间仍展示上次结果，但不能用回车误选旧查询的高亮项。
      if (pending &&
          (key == LogicalKeyboardKey.enter ||
              key == LogicalKeyboardKey.arrowDown ||
              key == LogicalKeyboardKey.arrowUp)) {
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowDown && rowCount > 0) {
        moveHighlight((index + 1) % rowCount);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowUp && rowCount > 0) {
        moveHighlight((index - 1 + rowCount) % rowCount);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.enter && rowCount > 0) {
        activate(index);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.escape) {
        onCancel();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.tab && onSwitchToAction != null) {
        onSwitchToAction!();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            RevericSpacing.sm,
            RevericSpacing.sm,
            RevericSpacing.sm,
            RevericSpacing.xs,
          ),
          child: Focus(
            onKeyEvent: handleKey,
            child: RevericSearchField(
              controller: controller,
              autofocus: autofocus,
              hint: context.t(LocaleKeys.commonSearchCharacters),
            ),
          ),
        ),
        if (showShortcutHints) ...[
          if (onSwitchToAction != null)
            _HintRow(
              shortcut: 'Tab',
              label: context.t(LocaleKeys.screenplaySwitchToAction),
              onTap: onSwitchToAction,
            ),
          _HintRow(
            shortcut: 'Enter',
            label: context.t(LocaleKeys.screenplayQuickCreateCharacter),
            onTap: canCreate ? create : null,
          ),
          const SizedBox(height: RevericSpacing.xs),
        ],
        Flexible(
          child: rowCount == 0
              ? Padding(
                  padding: const EdgeInsets.all(RevericSpacing.x2l),
                  child: Text(
                    context.t(LocaleKeys.commonNoResults),
                    textAlign: TextAlign.center,
                    style: typo.uiSmall.copyWith(color: colors.textMuted),
                  ),
                )
              : ListView.builder(
                  controller: scrollController,
                  shrinkWrap: true,
                  itemExtent: _rowHeight,
                  padding: const EdgeInsets.symmetric(
                    horizontal: RevericSpacing.xs,
                    vertical: RevericSpacing.xs,
                  ),
                  itemCount: rowCount,
                  itemBuilder: (context, position) => position == matches.length
                      ? _PickerRow(
                          highlighted: position == index,
                          onTap: create,
                          leading: RevericIcon(
                            RevericIcons.add,
                            size: 16,
                            color: colors.accent,
                          ),
                          label: context.t(
                            LocaleKeys.screenplayCreateCharacterNamed,
                            namedArgs: {'name': name},
                          ),
                        )
                      : _PickerRow(
                          highlighted: position == index,
                          onTap: () => activate(position),
                          leading: CharacterAvatar(
                            character: matches[position],
                            size: 24,
                            backgroundColor: colors.selected,
                            textColor: colors.accent,
                          ),
                          label: matches[position].name,
                          trailing: matches[position].id == selectedId
                              ? RevericIcon(
                                  RevericIcons.check,
                                  size: 14,
                                  color: colors.accent,
                                )
                              : null,
                        ),
                ),
        ),
      ],
    );
  }
}

/// 快捷键提示行：键帽 + 说明，点击等同按该键。
class _HintRow extends StatelessWidget {
  const _HintRow({required this.shortcut, required this.label, this.onTap});

  final String shortcut;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final enabled = onTap != null;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: RevericSpacing.lg,
          vertical: RevericSpacing.xs,
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: RevericSpacing.sm,
                vertical: RevericSpacing.xxs,
              ),
              decoration: BoxDecoration(
                color: colors.surfaceDim,
                borderRadius: BorderRadius.circular(RevericRadius.medium),
                border: Border.all(color: colors.borderSubtle),
              ),
              child: Text(
                shortcut,
                style: typo.uiTinySemibold.copyWith(
                  color: enabled ? colors.textSecondary : colors.textSubtle,
                ),
              ),
            ),
            const SizedBox(width: RevericSpacing.md),
            Expanded(
              child: Text(
                label,
                style: typo.uiSmall.copyWith(
                  color: enabled ? colors.textMuted : colors.textSubtle,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PickerRow extends StatelessWidget {
  const _PickerRow({
    required this.leading,
    required this.label,
    required this.highlighted,
    required this.onTap,
    this.trailing,
  });

  final Widget leading;
  final String label;
  final bool highlighted;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(RevericRadius.medium),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: RevericSpacing.sm),
        decoration: BoxDecoration(
          color: highlighted ? colors.selected : null,
          borderRadius: BorderRadius.circular(RevericRadius.medium),
        ),
        child: Row(
          children: [
            SizedBox(width: 24, child: Center(child: leading)),
            const SizedBox(width: RevericSpacing.md),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: typo.ui.copyWith(color: colors.textPrimary),
              ),
            ),
            // ignore: use_null_aware_elements
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}
