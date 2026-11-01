// 职责: 便签原地编辑 — 标题/正文 debounce 自动保存、颜色切换、「…」菜单删除,IME 组词期不触发上层 rebuild
// 关联文件:
//   lib/desktop/features/canvas/widgets/canvas_detail_layer.dart
//   lib/desktop/features/canvas/canvas_palette.dart
//   lib/desktop/features/canvas/edit_session.dart
//   lib/desktop/features/canvas/widgets/canvas_node_color_picker.dart
//   lib/shared/components/reveric_more_menu_button.dart
//   lib/shared/utils/text_input_composing.dart
//   lib/shared/database/novel_content_database.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/zh-CN/common.json
//   assets/translations/en/common.json
//   assets/translations/en/canvas.json
//   assets/translations/zh-CN/canvas.json
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/text-input-ime.md
//   .agents/rules/hooks.md
//   .agents/rules/i18n.md

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../shared/components/reveric_context_menu.dart';
import '../../../../shared/components/reveric_more_menu_button.dart';
import '../../../../shared/components/reveric_text_field.dart';
import '../../../../shared/database/novel_content_database.dart';
import '../../../../shared/localization/app_localization.dart';
import '../../../../shared/localization/locale_keys.dart';
import '../../../../shared/theme/theme.dart';
import '../../../../shared/utils/text_input_composing.dart';
import '../canvas_palette.dart';
import '../edit_session.dart';
import 'canvas_node_color_picker.dart';

/// 便签正文写库的 debounce 时长。
const _stickySaveDebounce = Duration(milliseconds: 600);

/// 便签原地编辑器：标题、正文、颜色、删除。
///
/// 用 [StatefulWidget] + 外部 controller 而非 `lib/third/form`：便签没有校验、
/// 没有提交按钮，是「边写边存」的自动保存场景，套 form 只会多一层无用的编辑态。
/// 但 IME 规则照 `.agents/rules/text-input-ime.md` 执行：
/// - 输入期不向上层同步(否则 DB stream 回流会重建整棵子树 → 失焦)
/// - 组词期(`isTextInputComposing`)完全跳过写库，等上屏后再存
/// - 外部 DB 回流只更新没有本地改动的字段，保存失败时保留草稿
class CanvasStickyActions {
  const CanvasStickyActions({
    required this.onTitleChanged,
    required this.onContentChanged,
    required this.onColorChanged,
    required this.onDelete,
  });
  final Future<void> Function(String) onTitleChanged;
  final Future<void> Function(String) onContentChanged;
  final ValueChanged<String?> onColorChanged;
  final VoidCallback onDelete;
}

class CanvasStickyEditor extends StatefulWidget {
  const CanvasStickyEditor({
    super.key,
    required this.node,
    required this.actions,
    this.session,
  });
  final CanvasNode node;
  final CanvasStickyActions actions;
  final CanvasEditSession? session;

  @override
  State<CanvasStickyEditor> createState() => _CanvasStickyEditorState();
}

class _CanvasStickyEditorState extends State<CanvasStickyEditor> {
  late final TextEditingController _titleController;
  late final TextEditingController _contentController;
  Timer? _titleDebounce;
  Timer? _contentDebounce;
  late String _savedTitle;
  late String _savedContent;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.node.title);
    _contentController = TextEditingController(text: widget.node.content);
    _titleController.addListener(_onTitleChanged);
    _contentController.addListener(_onContentChanged);
    _savedTitle = widget.node.title;
    _savedContent = widget.node.content;
    _register();
  }

  bool get _composing =>
      isTextInputComposing(_titleController) ||
      isTextInputComposing(_contentController);

  void _register() {
    widget.session?.register(
      this,
      CanvasEditorFlush(isComposing: () => _composing, flush: _flush),
    );
  }

  void _background(Future<void> future) {
    // 写入 callback 已反馈错误，session 保留失败；避免 timer/dispose 产生未处理 Future。
    unawaited(future.catchError((Object _) {}));
  }

  @override
  void didUpdateWidget(CanvasStickyEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session != widget.session) {
      oldWidget.session?.unregister(this);
      _register();
    }
    if (oldWidget.node.id != widget.node.id) {
      _titleDebounce?.cancel();
      _contentDebounce?.cancel();
      if (!_composing) {
        if (_titleController.text != _savedTitle) {
          _background(oldWidget.actions.onTitleChanged(_titleController.text));
        }
        if (_contentController.text != _savedContent) {
          _background(
            oldWidget.actions.onContentChanged(_contentController.text),
          );
        }
      }
      _syncing = true;
      _titleController.text = _savedTitle = widget.node.title;
      _contentController.text = _savedContent = widget.node.content;
      _syncing = false;
    } else if (!_composing) {
      _syncing = true;
      if (_titleController.text == _savedTitle) {
        _syncCleanText(_titleController, widget.node.title);
        _savedTitle = widget.node.title;
      }
      if (_contentController.text == _savedContent) {
        _syncCleanText(_contentController, widget.node.content);
        _savedContent = widget.node.content;
      }
      _syncing = false;
    }
  }

  void _syncCleanText(TextEditingController controller, String text) {
    if (controller.text == text) {
      return;
    }
    final selection = controller.selection;
    controller.value = TextEditingValue(
      text: text,
      selection: selection.isValid
          ? selection.copyWith(
              baseOffset: selection.baseOffset.clamp(0, text.length),
              extentOffset: selection.extentOffset.clamp(0, text.length),
            )
          : TextSelection.collapsed(offset: text.length),
    );
  }

  Future<void> _saveTitle() async {
    if (_composing || _titleController.text == _savedTitle) {
      return;
    }
    final value = _titleController.text;
    final id = widget.node.id;
    await widget.actions.onTitleChanged(value);
    if (mounted && widget.node.id == id) {
      _savedTitle = value;
    }
  }

  Future<void> _saveContent() async {
    if (_composing || _contentController.text == _savedContent) {
      return;
    }
    final value = _contentController.text;
    final id = widget.node.id;
    await widget.actions.onContentChanged(value);
    if (mounted && widget.node.id == id) {
      _savedContent = value;
    }
  }

  void _onTitleChanged() {
    if (!_syncing) {
      widget.session?.markEdited();
    }
    if (_syncing || _composing) {
      return;
    }
    _titleDebounce?.cancel();
    _titleDebounce = Timer(_stickySaveDebounce, () {
      if (mounted) {
        _background(_saveTitle());
      }
    });
  }

  void _onContentChanged() {
    if (!_syncing) {
      widget.session?.markEdited();
    }
    if (_syncing || _composing) {
      return;
    }
    _contentDebounce?.cancel();
    _contentDebounce = Timer(_stickySaveDebounce, () {
      if (mounted) {
        _background(_saveContent());
      }
    });
  }

  Future<void> _flush() async {
    if (_composing) {
      throw const CanvasEditSessionException('input_composing');
    }
    _titleDebounce?.cancel();
    _contentDebounce?.cancel();
    await _saveTitle();
    await _saveContent();
  }

  @override
  void dispose() {
    widget.session?.unregister(this);
    _titleDebounce?.cancel();
    _contentDebounce?.cancel();
    if (!_composing) {
      if (_titleController.text != _savedTitle) {
        _background(widget.actions.onTitleChanged(_titleController.text));
      }
      if (_contentController.text != _savedContent) {
        _background(widget.actions.onContentChanged(_contentController.text));
      }
    }
    _titleController.removeListener(_onTitleChanged);
    _contentController.removeListener(_onContentChanged);
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final activeColorKey = canvasStickyColorKeyOf(widget.node.style);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                context.t(LocaleKeys.canvasStickyLabel),
                style: typo.uiTinySemibold.copyWith(
                  color: colors.textSubtle,
                  letterSpacing: 0.6,
                ),
              ),
            ),
            RevericMoreMenuButton(
              iconSize: 16,
              entries: () => [
                RevericMenuItem(
                  icon: RevericIcons.delete_outline,
                  iconColor: colors.warningText,
                  labelColor: colors.warningText,
                  label: context.t(LocaleKeys.commonDelete),
                  onTap: () => _background(
                    _flush().then((_) => widget.actions.onDelete()),
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: RevericSpacing.xs),
        RevericTextField(
          controller: _titleController,
          height: RevericSizes.fieldHeightSm,
          style: typo.uiSmall,
          hintText: context.t(LocaleKeys.canvasStickyTitleHint),
          onTapOutside: (_) {
            if (!_composing) {
              _background(_flush());
            }
          },
        ),
        const SizedBox(height: RevericSpacing.xs),
        RevericTextField(
          controller: _contentController,
          multiline: true,
          minLines: 4,
          maxLines: 8,
          // 正文用 serif：便签写的是小说内容片段,视觉上归属稿纸而非界面。
          style: typo.bodySmall.copyWith(height: 1.7),
          hintText: context.t(LocaleKeys.canvasStickyPlaceholder),
          onTapOutside: (_) {
            if (!_composing) {
              _background(_flush());
            }
          },
        ),
        const SizedBox(height: RevericSpacing.md),
        CanvasNodeColorPicker(
          value: activeColorKey,
          onChanged: widget.actions.onColorChanged,
        ),
      ],
    );
  }
}
