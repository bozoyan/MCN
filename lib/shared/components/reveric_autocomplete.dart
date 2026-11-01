// 职责: 提供统一样式的单行文本自动补全，处理候选过滤、键盘选择与浮层定位。
// 关联文件:
//   lib/shared/components/reveric_text_field.dart
//   lib/shared/widgets/screenplay/time_field.dart
//   lib/shared/theme/theme.dart
// 遵循的 Rules:
//   .agents/rules/hooks.md
//   .agents/rules/text-input-ime.md
//   .agents/rules/design-system.md
//   .agents/rules/search-debounce.md

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import '../theme/theme.dart';
import 'reveric_text_field.dart';

class RevericAutocomplete extends HookWidget {
  const RevericAutocomplete({
    super.key,
    required this.controller,
    required this.suggestions,
    this.label,
    this.hintText,
    this.errorText,
  });

  /// 宿主持有输入值及其生命周期，选择候选和自由输入都写入此 controller。
  final TextEditingController controller;
  final List<String> suggestions;
  final String? label;
  final String? hintText;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final focus = useFocusNode();
    final timer = useRef<Timer?>(null);
    final pending = useRef<Completer<Iterable<String>>?>(null);
    final pendingQuery = useRef<String?>(null);
    void cancelPending() {
      timer.value?.cancel();
      if (pending.value case final request? when !request.isCompleted) {
        request.complete(const <String>[]);
      }
    }

    useEffect(() => cancelPending, const []);
    return LayoutBuilder(
      builder: (context, constraints) => RawAutocomplete<String>(
        optionsViewOpenDirection: OptionsViewOpenDirection.mostSpace,
        textEditingController: controller,
        focusNode: focus,
        optionsBuilder: (value) {
          final query = value.text.trim().toLowerCase();
          if (value.composing.isCollapsed &&
              query == pendingQuery.value &&
              pending.value != null) {
            return pending.value!.future;
          }
          cancelPending();
          pendingQuery.value = null;
          if (!value.composing.isCollapsed) {
            return const <String>[];
          }
          if (query.isEmpty ||
              suggestions.any((s) => s.toLowerCase() == query)) {
            return suggestions;
          }
          final request = Completer<Iterable<String>>();
          pending.value = request;
          pendingQuery.value = query;
          timer.value = Timer(const Duration(milliseconds: 180), () {
            request.complete(
              suggestions
                  .where((s) => s.toLowerCase().contains(query))
                  .toList(),
            );
          });
          return request.future;
        },
        fieldViewBuilder: (context, controller, focus, onSubmitted) =>
            RevericTextField(
              controller: controller,
              focusNode: focus,
              label: label,
              hintText: hintText,
              errorText: errorText,
              onSubmitted: (_) => onSubmitted(),
            ),
        optionsViewBuilder: (context, onSelected, options) =>
            _AutocompleteOptions(
              options: options.toList(),
              width: constraints.maxWidth,
              onSelected: onSelected,
            ),
      ),
    );
  }
}

class _AutocompleteOptions extends HookWidget {
  const _AutocompleteOptions({
    required this.options,
    required this.width,
    required this.onSelected,
  });
  final List<String> options;
  final double width;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final highlighted = AutocompleteHighlightedOption.of(context);
    final scroll = useScrollController();
    useEffect(() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!scroll.hasClients) {
          return;
        }
        final top = highlighted * 44.0;
        final bottom = top + 44 + RevericSpacing.xxs * 2;
        final visibleBottom = scroll.offset + scroll.position.viewportDimension;
        final target = top < scroll.offset
            ? top
            : bottom > visibleBottom
            ? bottom - scroll.position.viewportDimension
            : scroll.offset;
        scroll.jumpTo(target.clamp(0.0, scroll.position.maxScrollExtent));
      });
      return null;
    }, [highlighted, scroll]);
    return Align(
      alignment: Alignment.topLeft,
      heightFactor: 1,
      widthFactor: 1,
      child: Material(
        color: colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(RevericRadius.large),
          side: BorderSide(color: colors.borderInput),
        ),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: width,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 240),
            child: ListView.builder(
              controller: scroll,
              padding: const EdgeInsets.all(RevericSpacing.xxs),
              shrinkWrap: true,
              itemCount: options.length,
              itemExtent: 44,
              itemBuilder: (context, index) => ListTile(
                dense: true,
                minTileHeight: 44,
                selected: index == highlighted,
                selectedTileColor: colors.selected,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(RevericRadius.medium),
                ),
                title: Text(
                  options[index],
                  style: typo.ui.copyWith(color: colors.textPrimary),
                ),
                onTap: () => onSelected(options[index]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
