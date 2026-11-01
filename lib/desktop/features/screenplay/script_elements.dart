// 职责: 剧本正文的元素排版、就地编辑控件、元素工具条与光标位置状态。
// 关联文件:
//   lib/shared/models/screenplay_editing.dart
//   lib/desktop/features/screenplay/script.dart
//   lib/desktop/features/screenplay/screenplay_text_styles.dart
//   lib/shared/models/screenplay_element.dart
//   lib/shared/utils/text_input_composing.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/screenplay.json
//   assets/translations/zh-CN/screenplay.json
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/text-input-ime.md
//   .agents/rules/performance.md

import 'package:flutter/material.dart';

import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/models/screenplay_element.dart';
import '../../../shared/theme/theme.dart';
import '../../../shared/widgets/screenplay/element_options.dart';
export '../../../shared/widgets/screenplay/text_field.dart';
export '../../../shared/widgets/screenplay/element_layout.dart';
export '../../../shared/widgets/screenplay/element_options.dart';

/// 光标停在哪一场的哪一行。
@immutable
class ScreenplayCaret {
  const ScreenplayCaret({
    required this.sceneId,
    required this.index,
    required this.type,
    this.atEnd = false,
  });

  final String sceneId;
  final int index;
  final ScreenplayElementType type;
  final bool atEnd;

  @override
  bool operator ==(Object other) =>
      other is ScreenplayCaret &&
      other.sceneId == sceneId &&
      other.index == index &&
      other.type == type &&
      other.atEnd == atEnd;

  @override
  int get hashCode => Object.hash(sceneId, index, type, atEnd);
}

/// 当前可编辑场次向工具条暴露的行为。工具条只需要「改类型」和「插一行」，
/// 不需要拿到元素列表本身，所以这里暴露的是行为而不是裸状态。
class ScreenplayElementCommands {
  const ScreenplayElementCommands({
    required this.setType,
    required this.insertAfter,
    required this.canApply,
  });

  final void Function(int index, ScreenplayElementType type) setType;
  final void Function(int index, ScreenplayElementType type, String text)
  insertAfter;

  /// 这一行能不能改成该类型。对话和括号要求前面挂着角色行，
  /// 否则 writeElements 会拒收整场，工具条得在入口就拦下来。
  final bool Function(int index, ScreenplayElementType type) canApply;
}

/// 光标位置 + 当前场次可用命令。
///
/// 单独做成 [ChangeNotifier] 是为了让工具条只订阅它：焦点在行间移动时只重建
/// 工具条那一小块，而不是整页正文。
class ScreenplayCaretController extends ChangeNotifier {
  ScreenplayCaret? _caret;
  ScreenplayElementCommands? _commands;
  bool _disposed = false;

  ScreenplayCaret? get caret => _caret;

  bool get hasCommands => _commands != null;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void focus(ScreenplayCaret caret) {
    if (_caret == caret) return;
    _caret = caret;
    notifyListeners();
  }

  /// 场次切换或元素被删掉时清位；只清属于该场的光标，避免误清别处。
  ///
  /// 通知延到帧末：清位常发生在 hook 的 cleanup 里，而 cleanup 跑在 build 阶段，
  /// 当场 notify 会变成「build 期间 markNeedsBuild」。
  void clearScene(String sceneId) {
    if (_caret?.sceneId != sceneId) return;
    _caret = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_disposed) notifyListeners();
    });
  }

  void bindCommands(ScreenplayElementCommands? commands) {
    _commands = commands;
  }

  /// 光标所在行能否改成该类型。没有光标时不预判，交给 [applyType] 空转。
  bool canApply(ScreenplayElementType type) {
    final caret = _caret;
    final commands = _commands;
    if (caret == null || commands == null) return true;
    return commands.canApply(caret.index, type);
  }

  void applyType(ScreenplayElementType type) {
    final caret = _caret;
    final commands = _commands;
    if (caret == null || commands == null || caret.type == type) return;
    if (!commands.canApply(caret.index, type)) return;
    commands.setType(caret.index, type);
    _caret = ScreenplayCaret(
      sceneId: caret.sceneId,
      index: caret.index,
      type: type,
    );
    notifyListeners();
  }

  /// Tab 轮转到下一个类型，跳过当前位置用不了的（例如没有前置角色时的对话）——
  /// 否则 Tab 停在被拦下的那一格上，看起来像失灵。
  void cycleType([bool reverse = false]) {
    final caret = _caret;
    if (caret == null) return;
    const types = screenplayBodyElementTypes;
    final start = types.indexOf(caret.type);
    for (var step = 1; step <= types.length; step += 1) {
      final next = types[(start + (reverse ? -step : step)) % types.length];
      if (next == caret.type) return;
      if (canApply(next)) {
        applyType(next);
        return;
      }
    }
  }

  void insertNext([String text = '']) {
    final caret = _caret;
    final commands = _commands;
    if (caret == null || commands == null) return;
    commands.insertAfter(
      caret.index,
      screenplayNextElementType(caret.type),
      text,
    );
  }
}

/// `.sp-eltbar` —— 元素工具条。按钮组与正文栏共用同一条居中轴线和左边距，
/// 所以「场次」按钮正好落在场次标题的正上方；快捷键提示不参与这条对齐。
class ScreenplayElementBar extends StatelessWidget {
  const ScreenplayElementBar({
    super.key,
    required this.caretController,
    required this.onPick,
  });

  final ScreenplayCaretController caretController;
  final ValueChanged<ScreenplayElementOption> onPick;

  /// 主区窄下来时提示会压到按钮上 —— 提示是可有可无的那一半，先撤它。
  ///
  /// 阈值按真实几何算：按钮组从居中的 720 栏左边 +72 起排，英文标签下约 480 宽，
  /// 右缘落在 `(W-720)/2 + 552`；提示英文下约 230 宽，贴右边缘。两者留 16 间隙不
  /// 相撞需要 W ≳ 880。取 960 留余量。原来的 1440 比这宽出一大截，两侧栏一展开
  /// 主区就到不了，结果是提示在常见窗口下从来不出现。
  static const double _hintBreakpoint = 960;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: RevericSpacing.x3l,
        vertical: RevericSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: colors.surfaceContainer,
        border: Border(bottom: BorderSide(color: colors.borderSubtle)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) => Stack(
          alignment: Alignment.centerRight,
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: RevericSizes.screenplayPageMaxWidth,
                ),
                child: Padding(
                  padding: const EdgeInsets.only(
                    left: RevericSpacing.editorPaddingH,
                  ),
                  child: ListenableBuilder(
                    listenable: caretController,
                    builder: (context, _) {
                      final activeType = caretController.caret?.type;
                      return Row(
                        children: [
                          for (
                            var index = 0;
                            index < screenplayElementOptions.length;
                            index += 1
                          )
                            // 按钮按自然宽度排，栏内放不下时一起收窄（对齐 mockup
                            // 里 flex item 的默认 shrink）—— 中文标签两个字，
                            // 英文的 Transition/Character 长得多，写死自然宽度
                            // 会把这一栏撑爆。
                            Flexible(
                              child: _ElementButton(
                                option: screenplayElementOptions[index],
                                shortcut: index + 1,
                                active:
                                    screenplayElementOptions[index].type !=
                                        null &&
                                    screenplayElementOptions[index].type ==
                                        activeType,
                                enabled:
                                    screenplayElementOptions[index].type ==
                                        null ||
                                    caretController.canApply(
                                      screenplayElementOptions[index].type!,
                                    ),
                                onTap: () =>
                                    onPick(screenplayElementOptions[index]),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
            if (constraints.maxWidth >= _hintBreakpoint) const _ElementHint(),
          ],
        ),
      ),
    );
  }
}

class _ElementButton extends StatefulWidget {
  const _ElementButton({
    required this.option,
    required this.shortcut,
    required this.active,
    required this.enabled,
    required this.onTap,
  });

  final ScreenplayElementOption option;
  final int shortcut;
  final bool active;
  final bool enabled;
  final VoidCallback onTap;

  @override
  State<_ElementButton> createState() => _ElementButtonState();
}

class _ElementButtonState extends State<_ElementButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final hovered = _hovered && widget.enabled;
    final foreground = !widget.enabled
        ? colors.textSubtle.withValues(alpha: 0.4)
        : widget.active
        ? colors.textPrimary
        : hovered
        ? colors.textSecondary
        : colors.textMuted;
    return MouseRegion(
      cursor: widget.enabled
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.enabled ? widget.onTap : null,
        // 快捷键收进 tooltip：常驻第三行会把整条工具条撑到正文两行高，
        // 而这一栏是编辑时一直挂在头顶的 chrome。
        child: Tooltip(
          message: screenplayElementShortcutLabel(widget.shortcut),
          waitDuration: const Duration(milliseconds: 400),
          child: Container(
            constraints: const BoxConstraints(minWidth: 56),
            padding: const EdgeInsets.symmetric(
              horizontal: RevericSpacing.sm,
              vertical: RevericSpacing.xxs,
            ),
            decoration: BoxDecoration(
              color: widget.active
                  ? colors.selected
                  : hovered
                  ? colors.hover
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(RevericRadius.large),
              border: Border.all(
                color: widget.active ? colors.borderInput : Colors.transparent,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                RevericIcon(widget.option.icon, size: 16, color: foreground),
                const SizedBox(height: 2),
                Text(
                  context.t(widget.option.labelKey),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: typo.uiTiny.copyWith(color: foreground),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ElementHint extends StatelessWidget {
  const _ElementHint();

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const _Kbd('Tab'),
        const SizedBox(width: RevericSpacing.xs),
        Text(
          context.t(LocaleKeys.screenplayElementHintTab),
          style: typo.uiTiny.copyWith(color: colors.textSubtle),
        ),
        const SizedBox(width: RevericSpacing.md),
        const _Kbd('Enter'),
        const SizedBox(width: RevericSpacing.xs),
        Text(
          context.t(LocaleKeys.screenplayElementHintEnter),
          style: typo.uiTiny.copyWith(color: colors.textSubtle),
        ),
      ],
    );
  }
}

class _Kbd extends StatelessWidget {
  const _Kbd(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(RevericRadius.small),
        border: Border.all(color: colors.borderInput),
      ),
      child: Text(
        label,
        style: typo.mono.copyWith(
          fontSize: 10,
          height: 1.2,
          fontWeight: FontWeight.w500,
          color: colors.textMuted,
        ),
      ),
    );
  }
}
