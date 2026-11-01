// 职责: 展示单个 MCP 服务状态，并提供启停、连接、登录、编辑和删除入口。
// 关联文件:
//   lib/shared/widgets/settings/mcp/section.dart
//   lib/shared/widgets/settings/mcp/labels.dart
//   lib/shared/providers/mcp_providers.dart
//   lib/shared/services/mcp/runtime.dart
//   lib/mobile/widgets/sheet.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/settings.json
//   assets/translations/zh-CN/settings.json
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
// 遵循的 Rules:
//   .agents/rules/hooks.md
//   .agents/rules/design-system.md
//   .agents/rules/icons.md
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../../../mobile/widgets/sheet.dart';
import '../../../components/reveric_badge.dart';
import '../../../components/reveric_button.dart';
import '../../../components/reveric_context_menu.dart';
import '../../../components/reveric_icon_button.dart';
import '../../../components/reveric_switch.dart';
import '../../../components/reveric_slidable_delete.dart';
import '../../../localization/app_localization.dart';
import '../../../localization/locale_keys.dart';
import '../../../models/mcp/config.dart';
import '../../../providers/mcp_providers.dart';
import '../../../services/mcp/runtime.dart';
import '../../../services/mcp/diagnostics.dart';
import '../../../theme/theme.dart';
import '../../confirm_dialog.dart';
import 'labels.dart';

enum _InlineAction { cancelLogin, login, connect }

class McpServerRow extends HookConsumerWidget {
  const McpServerRow({super.key, required this.config, required this.onEdit});
  final McpServerConfig config;
  final VoidCallback onEdit;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final busy = useState<String?>(null);
    final feedback = useState<String?>(null);
    final service = ref.watch(mcpSettingsServiceProvider);
    final states = ref.watch(mcpConnectionStatesProvider).asData?.value;
    final status =
        states?[config.name]?.status ??
        (config.enabled
            ? McpConnectionStatus.disconnected
            : McpConnectionStatus.disabled);
    final mobile = defaultTargetPlatform == TargetPlatform.android;
    final supported = !mobile || config.connection is McpHttpConfig;
    final http = config.connection is McpHttpConfig
        ? config.connection as McpHttpConfig
        : null;
    final loggingIn =
        busy.value == 'login' || service.oauth.isLoggingIn(config.name);
    final typo = RevericTheme.typographyOf(context);
    final colors = RevericTheme.colorsOf(context);
    final idle = busy.value == null;
    final active = supported && config.enabled;
    final oauthCapable =
        active &&
        http != null &&
        (status == McpConnectionStatus.needs_auth ||
            http.authMode == McpAuthMode.oauth);
    final signedIn = http?.oauth['accessToken'] != null;
    final failureKey = mcpFailureLocaleKey(states?[config.name]?.failureKind);
    final statusKey = !supported
        ? LocaleKeys.settingsMcpDesktopOnly
        : switch (status) {
            McpConnectionStatus.disabled => LocaleKeys.settingsMcpDisabled,
            McpConnectionStatus.disconnected =>
              LocaleKeys.settingsMcpDisconnected,
            McpConnectionStatus.connecting => LocaleKeys.settingsMcpConnecting,
            McpConnectionStatus.ready => LocaleKeys.settingsMcpReady,
            McpConnectionStatus.needs_auth => LocaleKeys.settingsMcpNeedsAuth,
            McpConnectionStatus.error => failureKey,
          };
    final dotColor = !supported
        ? colors.textSubtle
        : switch (status) {
            McpConnectionStatus.ready => colors.additionBorder,
            McpConnectionStatus.connecting => colors.accentAmber,
            McpConnectionStatus.needs_auth => colors.warningText,
            McpConnectionStatus.error => colors.error,
            McpConnectionStatus.disconnected => colors.textMuted,
            McpConnectionStatus.disabled => colors.textSubtle,
          };
    // 已连接、未连接、已停用只靠状态点表达，避免每行都多一行常态文案。
    final detailKey =
        feedback.value ??
        (!supported
            ? LocaleKeys.settingsMcpDesktopOnly
            : switch (status) {
                McpConnectionStatus.connecting =>
                  LocaleKeys.settingsMcpConnecting,
                McpConnectionStatus.needs_auth =>
                  LocaleKeys.settingsMcpNeedsAuth,
                McpConnectionStatus.error => failureKey,
                _ => null,
              });
    final detailWarns =
        feedback.value != null ||
        (supported &&
            (status == McpConnectionStatus.error ||
                status == McpConnectionStatus.needs_auth));
    final inline = !active
        ? null
        : loggingIn
        ? _InlineAction.cancelLogin
        : oauthCapable && !signedIn
        ? _InlineAction.login
        : busy.value == 'connect' || status == McpConnectionStatus.error
        ? _InlineAction.connect
        : null;
    Future<void> run(String action, Future<void> Function() operation) async {
      if (busy.value != null) {
        return;
      }
      busy.value = action;
      feedback.value = null;
      try {
        await operation();
      } catch (error) {
        if (context.mounted) {
          feedback.value = mcpFailureLocaleKey(
            action == 'connect'
                ? service.runtime.states[config.name]?.failureKind
                : mcpFailureKind(error, authorization: action == 'login'),
          );
        }
      } finally {
        if (context.mounted) {
          busy.value = null;
        }
      }
    }

    Future<void> remove() async {
      if (busy.value != null) {
        return;
      }
      final confirmed = await showConfirmDialog(
        context,
        title: context.t(LocaleKeys.commonDelete),
        message: context.t(LocaleKeys.settingsMcpDeleteConfirm),
        confirmLabel: context.t(LocaleKeys.commonDelete),
        variant: ConfirmDialogVariant.warning,
      );
      if (confirmed && context.mounted) {
        final messenger = ScaffoldMessenger.of(context);
        final notice = context.t(LocaleKeys.settingsMcpRevocationFailed);
        await run('delete', () async {
          final result = await service.delete(config.name);
          if (result.remoteFailed && messenger.mounted) {
            messenger.showSnackBar(SnackBar(content: Text(notice)));
          }
        });
      }
    }

    void connect() {
      run('connect', () async {
        await service.runtime.retry(config.name);
      });
    }

    void logout() {
      run('logout', () async {
        final result = await service.logout(config.name);
        if (context.mounted && result.remoteFailed) {
          feedback.value = LocaleKeys.settingsMcpRevocationFailed;
        }
      });
    }

    final canEdit = supported && idle;
    // Android 的删除由左滑承担，菜单只放次要操作。
    List<RevericMenuItem> menuItems() => [
      RevericMenuItem(
        icon: RevericIcons.edit,
        label: context.t(LocaleKeys.commonEdit),
        enabled: canEdit,
        onTap: onEdit,
      ),
      if (active && inline != _InlineAction.connect)
        RevericMenuItem(
          icon: RevericIcons.arrow_clockwise,
          label: context.t(LocaleKeys.settingsMcpConnect),
          enabled: idle,
          onTap: connect,
        ),
      if (oauthCapable && signedIn && !loggingIn)
        RevericMenuItem(
          icon: RevericIcons.sign_out,
          label: context.t(LocaleKeys.settingsMcpLogout),
          enabled: idle,
          onTap: logout,
        ),
    ];

    void showMenuAt(Offset position) {
      showRevericContextMenu(
        context: context,
        position: position,
        entries: [
          ...menuItems(),
          const RevericMenuDivider(),
          RevericMenuItem(
            icon: RevericIcons.delete,
            iconColor: colors.warningText,
            labelColor: colors.warningText,
            label: context.t(LocaleKeys.commonDelete),
            enabled: idle,
            onTap: remove,
          ),
        ],
      );
    }

    void showSheet() {
      final items = menuItems();
      showMobileSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (sheetContext) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: RevericSpacing.x3l,
              ),
              child: Text(
                config.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: typo.uiSemibold.copyWith(color: colors.textPrimary),
              ),
            ),
            const SizedBox(height: RevericSpacing.sm),
            for (final item in items)
              ListTile(
                enabled: item.enabled,
                leading: RevericIcon(
                  item.icon!,
                  size: 20,
                  color: colors.textSecondary,
                ),
                title: Text(
                  item.label,
                  style: typo.ui.copyWith(color: colors.textPrimary),
                ),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  item.onTap!();
                },
              ),
          ],
        ),
      );
    }

    final description = config.description?.trim() ?? '';
    final dotSize = mobile
        ? RevericSizes.statusDotSizeMobile
        : RevericSizes.statusDotSize;
    final inlineButton = switch (inline) {
      null => null,
      _InlineAction.cancelLogin => RevericButton.text(
        label: context.t(LocaleKeys.commonCancel),
        size: RevericButtonSize.compact,
        onPressed: () {
          service.oauth.cancel(config.name);
        },
      ),
      _InlineAction.login => RevericButton.primary(
        label: context.t(LocaleKeys.settingsMcpLogin),
        size: RevericButtonSize.compact,
        onPressed: idle
            ? () => run('login', () => service.login(config.name))
            : null,
      ),
      _InlineAction.connect => RevericButton.secondary(
        label: context.t(LocaleKeys.settingsMcpConnect),
        size: RevericButtonSize.compact,
        loading: busy.value == 'connect',
        onPressed: idle ? connect : null,
      ),
    };
    final content = Padding(
      padding: EdgeInsets.symmetric(
        horizontal: RevericSpacing.lg,
        vertical: mobile ? RevericSpacing.lg : RevericSpacing.md,
      ),
      child: Row(
        children: [
          Tooltip(
            message: context.t(statusKey),
            child: Container(
              width: dotSize,
              height: dotSize,
              decoration: BoxDecoration(
                color: dotColor,
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: RevericSpacing.md),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        config.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: typo.uiSemibold.copyWith(
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(width: RevericSpacing.sm),
                    RevericBadge(
                      label: context.t(mcpTransportLabelKey(config.connection)),
                      color: colors.textMuted,
                    ),
                  ],
                ),
                const SizedBox(height: RevericSpacing.xxs),
                Text(
                  description.isEmpty
                      ? mcpEndpointLabel(config.connection)
                      : description,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: typo.uiSmall.copyWith(color: colors.textMuted),
                ),
                if (detailKey != null) ...[
                  const SizedBox(height: RevericSpacing.xxs),
                  Text(
                    context.t(detailKey),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: typo.uiSmall.copyWith(
                      color: detailWarns
                          ? colors.warningText
                          : colors.textMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (inlineButton != null) ...[
            const SizedBox(width: RevericSpacing.md),
            inlineButton,
          ],
          const SizedBox(width: RevericSpacing.sm),
          RevericSwitch(
            value: config.enabled,
            onChanged: supported && idle
                ? (enabled) => run(
                    'save',
                    () => service.save(
                      config.copyWith(enabled: enabled),
                      create: false,
                      baseline: config,
                    ),
                  )
                : null,
          ),
          if (!mobile)
            Builder(
              builder: (buttonContext) => RevericIconButton(
                icon: RevericIcons.more_horiz,
                tooltip: context.t(LocaleKeys.commonMoreActions),
                onPressed: () {
                  final box = buttonContext.findRenderObject()! as RenderBox;
                  showMenuAt(box.localToGlobal(Offset(0, box.size.height)));
                },
              ),
            ),
        ],
      ),
    );
    final tile = Material(
      // 左滑删除时操作面板在行下方，行本身必须不透明。
      color: mobile ? colors.canvas : null,
      type: mobile ? MaterialType.canvas : MaterialType.transparency,
      child: InkWell(
        onTap: canEdit ? onEdit : null,
        onLongPress: mobile && supported ? showSheet : null,
        onSecondaryTapDown: mobile
            ? null
            : (details) => showMenuAt(details.globalPosition),
        hoverColor: colors.hover,
        child: content,
      ),
    );
    return mobile
        ? RevericSlidableDelete(
            onDelete: remove,
            deleteLabel: context.t(LocaleKeys.commonDelete),
            borderRadius: BorderRadius.zero,
            childBuilder: (_, _) => tile,
          )
        : tile;
  }
}

String mcpFailureLocaleKey(McpFailureKind? kind) => switch (kind) {
  McpFailureKind.command_not_found => LocaleKeys.settingsMcpCommandMissing,
  McpFailureKind.working_directory => LocaleKeys.settingsMcpCwdMissing,
  McpFailureKind.process => LocaleKeys.settingsMcpProcessFailed,
  McpFailureKind.protocol => LocaleKeys.settingsMcpProtocolFailed,
  McpFailureKind.credentials => LocaleKeys.settingsMcpCredentialsRejected,
  McpFailureKind.oauth_client => LocaleKeys.settingsMcpClientRequired,
  McpFailureKind.oauth_callback => LocaleKeys.settingsMcpCallbackRejected,
  _ => LocaleKeys.settingsMcpError,
};
