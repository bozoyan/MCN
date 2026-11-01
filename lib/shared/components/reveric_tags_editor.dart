// 职责: Reveric 通用标签编辑器 — 展示已有标签 chip、内联添加/删除，供表单复用。
//   支持可选 suggestions 参数启用 Autocomplete 下拉建议（由调用方提供）。
// 关联文件:
//   lib/shared/components/reveric_text_field.dart
//   lib/shared/theme/theme.dart
//   lib/shared/providers/dictionary_providers.dart (suggestions 数据来源，由调用方传入)
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/icons.md
//   .agents/rules/text-input-ime.md
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/theme.dart';
import 'reveric_text_field.dart';

/// 通用标签编辑：已有标签 chip + 「添加标签」内联输入。
///
/// 单个标签默认最长 4 个字符（与小说表单一致），可用 [maxLength] 放宽
/// （人物别名与称号等场景）；去重由组件在 [onChanged] 前处理。
///
/// 当 [suggestions] 非空时，输入标签会显示自动补全下拉（由调用方提供），
/// 整体 UI 形态不变（点「添加标签」→ 内联输入 → 回车/勾选/失焦提交）。
class RevericTagsEditor extends StatelessWidget {
  const RevericTagsEditor({
    super.key,
    required this.tags,
    required this.onChanged,
    required this.addLabel,
    required this.hintText,
    this.suggestions,
    this.maxLength = maxTagLength,
  });

  final List<String> tags;
  final ValueChanged<List<String>> onChanged;
  final String addLabel;
  final String hintText;

  /// 可选的标签自动补全候选（由调用方提供）。为 null 或空时维持纯自由文本输入。
  final List<String>? suggestions;

  /// 单个标签允许的最大字符数。
  final int maxLength;

  static const int maxTagLength = 4;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);

    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(RevericRadius.large),
        border: Border.all(color: colors.borderInput),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: RevericSpacing.md,
        vertical: RevericSpacing.sm,
      ),
      child: Wrap(
        spacing: RevericSpacing.sm,
        runSpacing: RevericSpacing.sm,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final tag in tags)
            _TagChip(
              label: tag,
              colors: colors,
              typo: typo,
              onDeleted: () {
                onChanged(tags.where((t) => t != tag).toList());
              },
            ),
          _AddTagChip(
            onAdd: (tag) {
              if (tags.contains(tag)) {
                return;
              }
              onChanged([...tags, tag]);
            },
            colors: colors,
            typo: typo,
            label: addLabel,
            hintText: hintText,
            suggestions: suggestions,
            maxLength: maxLength,
          ),
        ],
      ),
    );
  }
}

class _TagChip extends StatelessWidget {
  const _TagChip({
    required this.label,
    required this.colors,
    required this.typo,
    required this.onDeleted,
  });

  final String label;
  final RevericColors colors;
  final RevericTypography typo;
  final VoidCallback onDeleted;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32,
      padding: const EdgeInsets.only(
        left: RevericSpacing.md,
        right: RevericSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: colors.surfaceDim,
        borderRadius: BorderRadius.circular(RevericRadius.small),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: typo.uiSmall.copyWith(color: colors.textPrimary)),
          const SizedBox(width: RevericSpacing.xs),
          InkWell(
            onTap: onDeleted,
            borderRadius: BorderRadius.circular(RevericRadius.small),
            child: Padding(
              padding: const EdgeInsets.all(RevericSpacing.xxs),
              child: RevericIcon(
                RevericIcons.close,
                size: 14,
                color: colors.textSubtle,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AddTagChip extends StatefulWidget {
  const _AddTagChip({
    required this.onAdd,
    required this.colors,
    required this.typo,
    required this.label,
    required this.hintText,
    required this.maxLength,
    this.suggestions,
  });

  final ValueSetter<String> onAdd;
  final RevericColors colors;
  final RevericTypography typo;
  final String label;
  final String hintText;
  final int maxLength;

  /// 非空时在输入态启用 Autocomplete 下拉。
  final List<String>? suggestions;

  @override
  State<_AddTagChip> createState() => _AddTagChipState();
}

class _AddTagChipState extends State<_AddTagChip> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _isEditing = false;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_handleFocusChange);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChange);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    if (!_focusNode.hasFocus && _isEditing && !_isSubmitting) {
      _submit();
    }
  }

  void _submit() => _submitWithValue(_controller.text);

  void _submitWithValue(String text) {
    if (_isSubmitting) {
      return;
    }
    _isSubmitting = true;
    final trimmed = text.trim();
    if (trimmed.isNotEmpty && trimmed.length <= widget.maxLength) {
      widget.onAdd(trimmed);
    }
    _controller.clear();
    if (mounted) {
      setState(() => _isEditing = false);
    }
    _isSubmitting = false;
  }

  void _startEditing() {
    setState(() => _isEditing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNode.requestFocus();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isEditing) {
      final hasSuggestions =
          widget.suggestions != null && widget.suggestions!.isNotEmpty;
      // 放宽长度限制的场景（别名、称号）需要更宽的输入框，否则文字会被迫横向滚动。
      final fieldWidth = widget.maxLength > RevericTagsEditor.maxTagLength
          ? 180.0
          : 120.0;
      final field = RevericTextField(
        controller: _controller,
        focusNode: _focusNode,
        autofocus: true,
        height: RevericSizes.fieldHeightSm,
        hintText: widget.hintText,
        fillColor: widget.colors.surface,
        inputFormatters: [
          LengthLimitingTextInputFormatter(
            widget.maxLength,
            maxLengthEnforcement:
                MaxLengthEnforcement.truncateAfterCompositionEnds,
          ),
        ],
        suffixIcon: IconButton(
          icon: RevericIcon(
            RevericIcons.check,
            size: 14,
            color: widget.colors.accent,
          ),
          onPressed: _submit,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
        ),
        suffixIconConstraints: const BoxConstraints(
          minWidth: 28,
          minHeight: 28,
        ),
        onSubmitted: (_) => _submit(),
      );

      // 有候选字典时用 RawAutocomplete 包一层下拉建议；无候选时维持纯 TextField。
      // 复用同一个 _controller / _focusNode，保留失焦提交、勾选提交等现有 UX。
      if (!hasSuggestions) {
        return SizedBox(width: fieldWidth, child: field);
      }

      return SizedBox(
        width: fieldWidth,
        child: RawAutocomplete<String>(
          textEditingController: _controller,
          focusNode: _focusNode,
          optionsBuilder: (textEditingValue) {
            final query = textEditingValue.text.toLowerCase();
            if (query.isEmpty) {
              return widget.suggestions!;
            }
            return widget.suggestions!.where(
              (s) => s.toLowerCase().contains(query),
            );
          },
          optionsViewBuilder: (context, onSelected, options) {
            return _TagSuggestionsOverlay(
              options: options.toList(),
              colors: widget.colors,
              typo: widget.typo,
              onTap: (value) {
                onSelected(value);
                _submitWithValue(value);
              },
            );
          },
          fieldViewBuilder:
              (context, controller, focusNode, onFieldSubmitted) => field,
        ),
      );
    }

    return InkWell(
      onTap: _startEditing,
      borderRadius: BorderRadius.circular(RevericRadius.small),
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: RevericSpacing.md),
        decoration: BoxDecoration(
          color: widget.colors.canvas,
          borderRadius: BorderRadius.circular(RevericRadius.small),
          border: Border.all(color: widget.colors.borderSubtle),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            RevericIcon(
              RevericIcons.add,
              size: 14,
              color: widget.colors.textSubtle,
            ),
            const SizedBox(width: RevericSpacing.xxs),
            Text(
              widget.label,
              style: widget.typo.uiSmall.copyWith(
                color: widget.colors.textSubtle,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 标签自动补全下拉浮层。约束最大高度并按字典顺序展示候选。
class _TagSuggestionsOverlay extends StatelessWidget {
  const _TagSuggestionsOverlay({
    required this.options,
    required this.colors,
    required this.typo,
    required this.onTap,
  });

  final List<String> options;
  final RevericColors colors;
  final RevericTypography typo;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topLeft,
      child: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(RevericRadius.small),
        color: colors.surface,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: options.length > 5 ? 200 : options.length * 36.0 + 8,
            maxWidth: 200,
          ),
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 4),
            shrinkWrap: true,
            children: [
              for (final option in options)
                InkWell(
                  onTap: () => onTap(option),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: RevericSpacing.md,
                      vertical: 6,
                    ),
                    child: Text(
                      option,
                      style: typo.uiSmall.copyWith(color: colors.textPrimary),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
