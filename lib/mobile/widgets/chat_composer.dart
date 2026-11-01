// 职责: 移动端聊天输入条 — 文本输入 + 附加引用/发送/停止按钮（忙碌可排队一条；已占用则只留停止）。
// 关联文件:
//   lib/mobile/pages/novel_chat_page.dart
//   lib/shared/theme/theme.dart
//   lib/shared/hooks/use_chat_composer_hint.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/mobile.json
//   assets/translations/zh-CN/mobile.json
//   assets/translations/en/ai.json
//   assets/translations/zh-CN/ai.json
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
// 遵循的 Rules:
//   .agents/rules/hooks.md
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import '../../shared/hooks/use_chat_composer_hint.dart';
import '../../shared/localization/app_localization.dart';
import '../../shared/localization/locale_keys.dart';
import '../../shared/theme/theme.dart';
import '../../shared/widgets/ai/chat/attachment_input.dart';

/// 底部输入条：统一圆角卡片 — 顶部左侧模型选择 pill、中部多行输入框、
/// 底部一行（左 附加、右 发送/停止）。
class MobileChatComposer extends HookWidget {
  const MobileChatComposer({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.isBusy,
    this.sendBlocked = false,
    this.queueOccupied = false,
    this.hasPendingHandoff = false,
    required this.onSend,
    required this.onStop,
    this.modelSelector,
    this.onAttach,
    this.onAttachFile,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isBusy;

  /// 当前模型不可用时禁用发送/排队按钮；
  /// 忙碌中的停止（取消）按钮仍可用。
  final bool sendBlocked;

  /// 已有一条待发送队列时禁止再次排队（不覆盖）。
  final bool queueOccupied;

  /// handoff 自带完整 prompt，存在时即使文本为空也允许发送。
  final bool hasPendingHandoff;

  final VoidCallback onSend;
  final VoidCallback onStop;

  /// 顶部左上角的模型 + 推理强度选择触发器（由调用方构建，通常为
  /// [MobileModelSelector.pill]）。
  final Widget? modelSelector;

  /// 打开引用资源选择器。为 null 时不显示附加按钮。
  final VoidCallback? onAttach;

  /// 选择本地 txt/md 文件并附加为内联上下文。为 null 时不显示文件按钮。
  final VoidCallback? onAttachFile;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final composerHint = useChatComposerHint(context);

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          RevericSpacing.lg,
          RevericSpacing.sm,
          RevericSpacing.lg,
          RevericSpacing.sm,
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: RevericSpacing.md,
            vertical: RevericSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: colors.surfaceContainer,
            borderRadius: BorderRadius.circular(RevericRadius.x2l),
            border: Border.all(color: colors.borderSubtle),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (modelSelector != null) ...[
                modelSelector!,
                const SizedBox(height: RevericSpacing.xs),
              ],
              ChatAttachmentInput(
                controller: controller,
                focusNode: focusNode,
                child: TextField(
                  contextMenuBuilder: chatAttachmentContextMenu,
                  controller: controller,
                  focusNode: focusNode,
                  minLines: 1,
                  maxLines: 5,
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.newline,
                  style: typo.body.copyWith(color: colors.textPrimary),
                  cursorColor: colors.accent,
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    hintText: composerHint,
                    hintStyle: typo.body.copyWith(color: colors.textMuted),
                  ),
                ),
              ),
              const SizedBox(height: RevericSpacing.xs),
              Row(
                children: [
                  if (onAttach != null)
                    _CircleButton(
                      icon: RevericIcons.add_link,
                      background: colors.surface,
                      foreground: colors.textSecondary,
                      border: colors.borderSubtle,
                      onTap: onAttach!,
                      tooltip: context.t(LocaleKeys.mobileChatReferenceTitle),
                    ),
                  if (onAttach != null && onAttachFile != null)
                    const SizedBox(width: RevericSpacing.sm),
                  if (onAttachFile != null)
                    _CircleButton(
                      icon: RevericIcons.attachment,
                      background: colors.surface,
                      foreground: colors.textSecondary,
                      border: colors.borderSubtle,
                      onTap: onAttachFile!,
                      tooltip: context.t(LocaleKeys.aiAttachFile),
                    ),
                  const Spacer(),
                  _SendControls(
                    controller: controller,
                    isBusy: isBusy,
                    sendBlocked: sendBlocked,
                    queueOccupied: queueOccupied,
                    hasPendingHandoff: hasPendingHandoff,
                    onSend: onSend,
                    onStop: onStop,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 移动端聊天输入框上方的可关闭提示卡。
class MobileChatComposerNotice extends StatelessWidget {
  const MobileChatComposerNotice({
    super.key,
    required this.message,
    required this.onDismiss,
  });

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        RevericSpacing.lg,
        0,
        RevericSpacing.lg,
        RevericSpacing.sm,
      ),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(
          horizontal: RevericSpacing.md,
          vertical: RevericSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: colors.warningBg.withValues(alpha: 0.62),
          borderRadius: BorderRadius.circular(RevericRadius.medium),
          border: Border.all(color: colors.warningText.withValues(alpha: 0.22)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: RevericIcon(
                RevericIcons.warning_circle,
                size: 16,
                color: colors.warningText,
              ),
            ),
            const SizedBox(width: RevericSpacing.sm),
            Expanded(
              child: Text(
                message,
                style: typo.uiSmall.copyWith(color: colors.warningText),
              ),
            ),
            const SizedBox(width: RevericSpacing.sm),
            IconButton(
              onPressed: onDismiss,
              tooltip: context.t(LocaleKeys.commonClose),
              icon: RevericIcon(
                RevericIcons.close_rounded,
                size: 14,
                color: colors.warningText,
              ),
              style: IconButton.styleFrom(
                minimumSize: const Size(28, 28),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                padding: EdgeInsets.zero,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 发送/停止控件：忙碌时显示停止；队列空闲且有文本或 handoff 时显示发送排队。
///
/// 用 StatefulWidget 而非监听整个 [TextEditingValue]：只在「有无文本」翻转时重建，
/// 且在 CJK 输入法合成期（composing region 非空）不重建，避免打断中文等合成输入。
class _SendControls extends StatefulWidget {
  const _SendControls({
    required this.controller,
    required this.isBusy,
    required this.sendBlocked,
    required this.queueOccupied,
    required this.hasPendingHandoff,
    required this.onSend,
    required this.onStop,
  });

  final TextEditingController controller;
  final bool isBusy;
  final bool sendBlocked;
  final bool queueOccupied;
  final bool hasPendingHandoff;
  final VoidCallback onSend;
  final VoidCallback onStop;

  @override
  State<_SendControls> createState() => _SendControlsState();
}

class _SendControlsState extends State<_SendControls> {
  late bool _hasText = widget.controller.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
  }

  @override
  void didUpdateWidget(_SendControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onChanged);
      widget.controller.addListener(_onChanged);
      _hasText = widget.controller.text.trim().isNotEmpty;
    }
  }

  void _onChanged() {
    // 合成期（CJK marked text）不触发重建，避免打断中文输入法。
    final composing = widget.controller.value.composing;
    if (composing.isValid && !composing.isCollapsed) {
      return;
    }
    final hasText = widget.controller.text.trim().isNotEmpty;
    if (hasText != _hasText) {
      setState(() => _hasText = hasText);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final hasSendableContent = _hasText || widget.hasPendingHandoff;
    // 模型不可用时禁用发送/排队；停止（取消进行中的请求）不受影响。
    if (!widget.isBusy) {
      return _CircleButton(
        icon: RevericIcons.send_rounded,
        background: colors.accent,
        foreground: colors.onAccent,
        onTap: widget.onSend,
        tooltip: context.t(LocaleKeys.mobileChatSend),
        enabled: !widget.sendBlocked && hasSendableContent,
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _CircleButton(
          icon: RevericIcons.stop_rounded,
          background: colors.surface,
          foreground: colors.textSecondary,
          border: colors.borderSubtle,
          onTap: widget.onStop,
          tooltip: context.t(LocaleKeys.mobileChatStop),
        ),
        if (hasSendableContent && !widget.queueOccupied) ...[
          const SizedBox(width: RevericSpacing.sm),
          _CircleButton(
            icon: RevericIcons.send_rounded,
            background: colors.accent,
            foreground: colors.onAccent,
            onTap: widget.onSend,
            tooltip: context.t(LocaleKeys.mobileChatSend),
            enabled: !widget.sendBlocked,
          ),
        ],
      ],
    );
  }
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({
    required this.icon,
    required this.background,
    required this.foreground,
    required this.onTap,
    required this.tooltip,
    this.border,
    this.enabled = true,
  });

  final String icon;
  final Color background;
  final Color foreground;
  final Color? border;
  final VoidCallback onTap;
  final String tooltip;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        enabled: enabled,
        label: tooltip,
        child: GestureDetector(
          onTap: enabled ? onTap : null,
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: enabled ? background : colors.surfaceContainer,
              borderRadius: BorderRadius.circular(RevericRadius.full),
              border: enabled
                  ? (border == null ? null : Border.all(color: border!))
                  : Border.all(color: colors.borderSubtle),
            ),
            alignment: Alignment.center,
            child: RevericIcon(
              icon,
              size: 20,
              color: enabled ? foreground : colors.textSubtle,
            ),
          ),
        ),
      ),
    );
  }
}
