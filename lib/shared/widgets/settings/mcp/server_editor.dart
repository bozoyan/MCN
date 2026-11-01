// 职责: 提供 MCP 配置粘贴预览和手动编辑表单，确认保存前不连接服务。
// 关联文件:
//   lib/shared/models/mcp/config.dart
//   lib/shared/models/mcp/config_import.dart
//   lib/shared/providers/mcp_providers.dart
//   lib/shared/widgets/settings/mcp/notice.dart
//   lib/shared/widgets/settings/mcp/labels.dart
//   lib/shared/widgets/settings/leave_guard.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/settings.json
//   assets/translations/zh-CN/settings.json
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
// 遵循的 Rules:
//   .agents/rules/hooks.md
//   .agents/rules/form.md
//   .agents/rules/design-system.md
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../../components/reveric_badge.dart';
import '../../../components/reveric_button.dart';
import '../../../components/reveric_icon_button.dart';
import '../../../components/reveric_segmented_control.dart';
import '../../../components/reveric_select.dart';
import '../../../components/reveric_switch.dart';
import '../../../form/form.dart';
import '../../../localization/app_localization.dart';
import '../../../localization/locale_keys.dart';
import '../../../models/mcp/config.dart';
import '../../../models/mcp/config_import.dart';
import '../../../providers/mcp_providers.dart';
import '../../../theme/theme.dart';
import '../../unsaved_changes_dialog.dart';
import '../leave_guard.dart';
import '../settings_section_widgets.dart';
import 'labels.dart';
import 'notice.dart';

/// 移动端以全屏页编辑；桌面端由设置内容区就地替换列表，不经过此入口。
Future<void> showMcpServerEditor(
  BuildContext context, {
  McpServerConfig? config,
}) async {
  final theme = RevericTheme.of(context);
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => RevericTheme(
        data: theme,
        child: McpServerEditor(config: config, mobile: true),
      ),
    ),
  );
}

enum _Field implements FieldSchema {
  paste,
  name,
  purpose,
  transport,
  url,
  command,
  args,
  cwd,
  env,
  headers,
  auth,
  token,
  clientId,
  scopes,
  callbackPort,
  exposure,
  enabled,
  connectTimeout,
  callTimeout;

  @override
  List<Validator<dynamic>>? get validators => null;
}

class McpServerEditor extends HookConsumerWidget {
  const McpServerEditor({
    super.key,
    this.config,
    this.mobile = false,
    this.onClose,
  });
  final McpServerConfig? config;
  final bool mobile;

  /// 桌面就地编辑时返回列表；为空时关闭当前路由。
  final VoidCallback? onClose;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final saving = useState(false);
    final pasteMode = useState(config == null);
    final feedback = useState<({String key, Map<String, String>? args})?>(null);
    void notify(String key, [Map<String, String>? args]) =>
        feedback.value = (key: key, args: args);
    final preview = useState<List<McpServerConfig>?>(null);
    final leaveGuard = useRef<SettingsLeaveGuard?>(null);
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final raw = config?.toJson() ?? <String, dynamic>{};
    final oauth = raw['oauth'] as Map? ?? {};
    final form = useForm<_Field>(
      initialValues: {
        _Field.paste: '',
        _Field.name: config?.name ?? '',
        _Field.purpose: config?.description ?? '',
        _Field.transport: raw['transport'] ?? 'streamable_http',
        _Field.url: raw['url'] ?? '',
        _Field.command: raw['command'] ?? '',
        _Field.args: jsonEncode(raw['args'] ?? []),
        _Field.cwd: raw['cwd'] ?? '',
        _Field.env: jsonEncode(raw['env'] ?? {}),
        _Field.headers: jsonEncode(raw['headers'] ?? {}),
        _Field.auth: raw['authMode'] ?? 'none',
        _Field.token: raw['bearerToken'] ?? '',
        _Field.clientId: oauth['clientId'] ?? '',
        _Field.scopes: (oauth['scopes'] as List? ?? []).join(' '),
        _Field.callbackPort: '${oauth['callbackPort'] ?? ''}',
        _Field.exposure: config?.exposure.name ?? 'deferred',
        _Field.enabled: config?.enabled ?? true,
        _Field.connectTimeout: '${config?.connectTimeoutSeconds ?? 15}',
        _Field.callTimeout: '${config?.callTimeoutSeconds ?? 60}',
      },
    );
    String value(_Field field) => form.getValue<String>(field) ?? '';
    final stdio = value(_Field.transport) == 'stdio';
    final authMode = value(_Field.auth);
    void close() {
      if (onClose case final onClose?) {
        onClose();
      } else {
        Navigator.of(context).pop();
      }
    }

    // 与 RevericTextField 的标签同款，让下拉和分段选择与文本字段对齐。
    Widget label(String key) => Padding(
      padding: const EdgeInsets.only(bottom: RevericSpacing.xs),
      child: Text(
        context.t(key),
        style: typo.uiSmallSemibold.copyWith(color: colors.textSecondary),
      ),
    );
    Widget text(
      _Field field,
      String label, {
      bool multiline = false,
      bool secret = false,
      int minLines = 4,
      int maxLines = 8,
    }) => Padding(
      padding: const EdgeInsets.only(bottom: RevericSpacing.lg),
      child: HookedTextFormField<_Field>(
        fieldHook: field,
        label: context.t(label),
        multiline: multiline,
        minLines: minLines,
        maxLines: maxLines,
        obscureText: secret,
        enabled: !saving.value && !(field == _Field.name && config != null),
        onChanged: switch (field) {
          _Field.paste => (_) {
            preview.value = null;
          },
          _Field.name => (_) {
            if (form.getFieldForcedError(_Field.name) != null) {
              form.clearForcedErrors();
            }
          },
          _ => null,
        },
      ),
    );
    Widget select(_Field field, String labelKey, Map<String, String> choices) =>
        Padding(
          padding: const EdgeInsets.only(bottom: RevericSpacing.lg),
          child: HookedFormField<_Field, String>(
            fieldHook: field,
            notifyOnChange: true,
            builder: (current, onChanged, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                label(labelKey),
                RevericSelect<String>(
                  value: current,
                  enabled: !saving.value,
                  items: [
                    for (final entry in choices.entries)
                      RevericSelectItem(
                        value: entry.key,
                        label: context.t(entry.value),
                      ),
                  ],
                  onChanged: (value) => onChanged?.call(value),
                ),
              ],
            ),
          ),
        );
    Widget segments<T>({
      required List<RevericSegment<T>> items,
      required T selected,
      required ValueChanged<T> onChanged,
    }) => Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: RevericSizes.mcpEditorSegmentWidth,
        ),
        child: RevericSegmentedControl<T>(
          segments: items,
          selected: selected,
          onChanged: (value) {
            if (!saving.value) {
              onChanged(value);
            }
          },
        ),
      ),
    );
    Widget segmented(
      _Field field,
      String labelKey,
      Map<String, String> choices,
    ) => Padding(
      padding: const EdgeInsets.only(bottom: RevericSpacing.lg),
      child: HookedFormField<_Field, String>(
        fieldHook: field,
        notifyOnChange: true,
        builder: (current, onChanged, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            label(labelKey),
            segments(
              items: [
                for (final entry in choices.entries)
                  RevericSegment(
                    value: entry.key,
                    label: context.t(entry.value),
                  ),
              ],
              selected: choices.containsKey(current)
                  ? current!
                  : choices.keys.first,
              onChanged: (value) => onChanged?.call(value),
            ),
          ],
        ),
      ),
    );

    /// 返回是否已写入；粘贴模式首次保存只生成预览，不算写入。
    Future<bool> save({bool closeAfter = true}) async {
      if (!form.validate() || saving.value) {
        return false;
      }
      feedback.value = null;
      final enabled = form.getValue<bool>(_Field.enabled)!;
      try {
        List<McpServerConfig>? imports;
        McpServerConfig? next;
        if (pasteMode.value) {
          imports = parseMcpImport(value(_Field.paste), enabled: enabled);
          if (preview.value == null) {
            preview.value = imports;
            return false;
          }
        } else {
          final connection = stdio
              ? McpStdioConfig(
                  command: value(_Field.command),
                  args: (jsonDecode(value(_Field.args)) as List).cast<String>(),
                  cwd: value(_Field.cwd).isEmpty ? null : value(_Field.cwd),
                  env: Map<String, String>.from(
                    jsonDecode(value(_Field.env)) as Map,
                  ),
                )
              : McpHttpConfig(
                  url: value(_Field.url),
                  authMode: McpAuthMode.values.byName(authMode),
                  headers: Map<String, String>.from(
                    jsonDecode(value(_Field.headers)) as Map,
                  ),
                  bearerToken: value(_Field.token).isEmpty
                      ? null
                      : value(_Field.token),
                  oauth: {
                    ...Map<String, dynamic>.from(oauth)..remove('callbackPort'),
                    'clientId': value(_Field.clientId),
                    'scopes': value(
                      _Field.scopes,
                    ).split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList(),
                    if (value(_Field.callbackPort).isNotEmpty)
                      'callbackPort': int.parse(value(_Field.callbackPort)),
                  },
                );
          next = McpServerConfig(
            name: value(_Field.name),
            description: value(_Field.purpose),
            connection: connection,
            enabled: enabled,
            exposure: McpExposure.values.byName(value(_Field.exposure)),
            connectTimeoutSeconds: int.parse(value(_Field.connectTimeout)),
            callTimeoutSeconds: int.parse(value(_Field.callTimeout)),
          );
        }
        if (defaultTargetPlatform == TargetPlatform.android &&
            (imports ?? [next!]).any((s) => s.connection is McpStdioConfig)) {
          notify(LocaleKeys.settingsMcpDesktopOnly);
          return false;
        }
        final service = ref.read(mcpSettingsServiceProvider);
        saving.value = true;
        if (imports != null) {
          await service.importServers(imports);
        } else {
          await service.save(next!, create: config == null, baseline: config);
        }
        if (closeAfter && context.mounted) {
          close();
        }
        return true;
      } on McpServerNameConflict catch (conflict) {
        final (key, args) = _nameConflictMessage(conflict);
        if (pasteMode.value) {
          notify(key, args);
        } else if (context.mounted) {
          form.setError(_Field.name, context.t(key, namedArgs: args));
        }
      } on FormatException {
        notify(LocaleKeys.settingsMcpInvalid);
      } on TypeError {
        notify(LocaleKeys.settingsMcpInvalid);
      } on ArgumentError {
        notify(LocaleKeys.settingsMcpInvalid);
      } catch (_) {
        notify(LocaleKeys.commonSaveFailed);
      } finally {
        if (context.mounted) {
          saving.value = false;
        }
      }
      return false;
    }

    // 移动端全屏表单返回不做未保存拦截，只有桌面设置弹窗内需要询问。
    final leave = mobile ? null : SettingsLeaveScope.maybeOf(context);
    Future<bool> confirmLeave() async {
      if (saving.value) {
        return false;
      }
      if (!form.hasChanged) {
        return true;
      }
      final decision = await showUnsavedChangesDialog(
        context: context,
        titleKey: LocaleKeys.editorUnsavedChangesTitle,
        messageKey: LocaleKeys.editorUnsavedChangesMessage,
      );
      return switch (decision) {
        null => false,
        UnsavedChangesDecision.discard => true,
        UnsavedChangesDecision.save => await save(closeAfter: false),
      };
    }

    leaveGuard.value = confirmLeave;
    useEffect(() {
      if (leave == null) {
        return null;
      }
      Future<bool> guard() => leaveGuard.value!();
      leave.register(guard);
      return () => leave.unregister(guard);
    }, [leave]);
    Future<void> leaveToList() async {
      if (await confirmLeave() && context.mounted) {
        close();
      }
    }

    final saveLabel = context.t(LocaleKeys.commonSave);
    final saveButton = mobile
        ? RevericButton.text(
            label: saveLabel,
            onPressed: save,
            loading: saving.value,
          )
        : RevericButton.primary(
            label: saveLabel,
            onPressed: save,
            loading: saving.value,
          );
    final callbackPort = value(_Field.callbackPort);
    final callbackUrl = mobile
        ? 'ai.reveric://mcp/oauth/callback'
        : 'http://127.0.0.1:${callbackPort.isEmpty ? '<port>' : callbackPort}/mcp/oauth/callback';
    final transports = {
      'streamable_http': LocaleKeys.settingsMcpHttp,
      if (defaultTargetPlatform != TargetPlatform.android)
        'stdio': LocaleKeys.settingsMcpStdio,
    };
    final content = SingleChildScrollView(
      padding: mobile
          ? const EdgeInsets.all(RevericSpacing.x3l)
          : const EdgeInsets.fromLTRB(
              RevericSpacing.x4l,
              RevericSpacing.x3l,
              RevericSpacing.x4l,
              RevericSpacing.x4l,
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (config == null) ...[
            segments(
              items: [
                RevericSegment(
                  value: true,
                  label: context.t(LocaleKeys.settingsMcpPaste),
                ),
                RevericSegment(
                  value: false,
                  label: context.t(LocaleKeys.settingsMcpManual),
                ),
              ],
              selected: pasteMode.value,
              onChanged: (paste) => pasteMode.value = paste,
            ),
            const SizedBox(height: RevericSpacing.x3l),
          ],
          if (pasteMode.value) ...[
            text(
              _Field.paste,
              LocaleKeys.settingsMcpJson,
              multiline: true,
              minLines: 8,
              maxLines: 16,
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: RevericButton.secondary(
                label: context.t(LocaleKeys.settingsMcpParse),
                onPressed: saving.value
                    ? null
                    : () {
                        try {
                          preview.value = parseMcpImport(
                            value(_Field.paste),
                            enabled: form.getValue<bool>(_Field.enabled)!,
                          );
                          feedback.value = null;
                        } on McpServerNameConflict catch (conflict) {
                          final (key, args) = _nameConflictMessage(conflict);
                          notify(key, args);
                        } catch (_) {
                          notify(LocaleKeys.settingsMcpInvalid);
                        }
                      },
              ),
            ),
            if (preview.value case final items?) ...[
              const SizedBox(height: RevericSpacing.lg),
              _ImportPreview(items: items),
            ],
            const SizedBox(height: RevericSpacing.x2l),
          ] else ...[
            text(_Field.name, LocaleKeys.commonName),
            text(_Field.purpose, LocaleKeys.settingsMcpPurpose),
            if (transports.length > 1)
              segmented(
                _Field.transport,
                LocaleKeys.settingsMcpTransport,
                transports,
              ),
            if (stdio) ...[
              text(_Field.command, LocaleKeys.settingsMcpCommand),
              text(_Field.args, LocaleKeys.settingsMcpArgs, multiline: true),
              text(_Field.cwd, LocaleKeys.settingsMcpCwd),
              text(_Field.env, LocaleKeys.settingsMcpEnv, multiline: true),
            ] else ...[
              text(_Field.url, LocaleKeys.settingsMcpUrl),
              select(_Field.auth, LocaleKeys.settingsMcpAuth, {
                'none': LocaleKeys.settingsMcpAuthNone,
                'bearer': LocaleKeys.settingsMcpToken,
                'headers': LocaleKeys.settingsMcpHeaders,
                'oauth': LocaleKeys.settingsMcpLogin,
              }),
              if (authMode == 'bearer')
                text(_Field.token, LocaleKeys.settingsMcpToken, secret: true),
              text(
                _Field.headers,
                LocaleKeys.settingsMcpHeaders,
                multiline: true,
              ),
              if (authMode == 'oauth') ...[
                text(_Field.clientId, LocaleKeys.settingsMcpClientId),
                text(_Field.scopes, LocaleKeys.settingsMcpScopes),
                if (!mobile)
                  text(_Field.callbackPort, LocaleKeys.settingsMcpCallbackPort),
                label(LocaleKeys.settingsMcpCallback),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: RevericSpacing.md,
                    vertical: RevericSpacing.sm,
                  ),
                  decoration: BoxDecoration(
                    color: colors.surfaceDim,
                    borderRadius: BorderRadius.circular(RevericRadius.medium),
                  ),
                  child: SelectableText(
                    callbackUrl,
                    style: typo.uiSmall.copyWith(color: colors.textSecondary),
                  ),
                ),
                const SizedBox(height: RevericSpacing.lg),
              ],
            ],
            segmented(_Field.exposure, LocaleKeys.settingsMcpExposure, {
              'deferred': LocaleKeys.settingsMcpDeferred,
              'direct': LocaleKeys.settingsMcpDirect,
            }),
            if (mobile) ...[
              text(_Field.connectTimeout, LocaleKeys.settingsMcpConnectTimeout),
              text(_Field.callTimeout, LocaleKeys.settingsMcpCallTimeout),
            ] else
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: text(
                      _Field.connectTimeout,
                      LocaleKeys.settingsMcpConnectTimeout,
                    ),
                  ),
                  const SizedBox(width: RevericSpacing.lg),
                  Expanded(
                    child: text(
                      _Field.callTimeout,
                      LocaleKeys.settingsMcpCallTimeout,
                    ),
                  ),
                ],
              ),
          ],
          HookedFormField<_Field, bool>(
            fieldHook: _Field.enabled,
            builder: (enabled, onChanged, _) => Row(
              children: [
                Expanded(
                  child: Text(
                    context.t(LocaleKeys.settingsMcpEnabled),
                    style: typo.ui.copyWith(color: colors.textPrimary),
                  ),
                ),
                RevericSwitch(
                  value: enabled ?? false,
                  onChanged: saving.value ? null : onChanged,
                ),
              ],
            ),
          ),
        ],
      ),
    );
    // 提示固定在滚动区外，保存失败时不需要滚到表单底部才能看到。
    final notice = switch (feedback.value) {
      null => null,
      final message => Padding(
        padding: EdgeInsets.fromLTRB(
          mobile ? RevericSpacing.x3l : RevericSpacing.x4l,
          0,
          mobile ? RevericSpacing.x3l : RevericSpacing.x4l,
          RevericSpacing.lg,
        ),
        child: McpNotice(
          message: context.t(message.key, namedArgs: message.args),
        ),
      ),
    };
    final title = config?.name ?? context.t(LocaleKeys.commonAdd);
    if (mobile) {
      return HookedForm(
        form: form,
        child: Scaffold(
          backgroundColor: colors.canvas,
          appBar: AppBar(
            backgroundColor: colors.surfaceDim,
            elevation: 0,
            leading: RevericIconButton(
              icon: RevericIcons.arrow_back,
              tooltip: context.t(LocaleKeys.commonBack),
              onPressed: saving.value ? null : close,
            ),
            title: Text(
              config?.name ?? context.t(LocaleKeys.settingsMcp),
              style: typo.heading2.copyWith(color: colors.textPrimary),
            ),
            actions: [
              saveButton,
              const SizedBox(width: RevericSpacing.sm),
            ],
          ),
          body: SafeArea(
            top: false,
            child: Column(
              children: [
                Expanded(child: content),
                ?notice,
              ],
            ),
          ),
        ),
      );
    }
    final editor = HookedForm(
      form: form,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              RevericSpacing.lg,
              RevericSpacing.md,
              RevericSpacing.x4l,
              RevericSpacing.md,
            ),
            child: Row(
              children: [
                RevericIconButton(
                  icon: RevericIcons.arrow_back,
                  tooltip: context.t(LocaleKeys.commonBack),
                  onPressed: saving.value ? null : leaveToList,
                ),
                const SizedBox(width: RevericSpacing.xs),
                Text(
                  context.t(LocaleKeys.settingsMcp),
                  style: typo.ui.copyWith(color: colors.textMuted),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: RevericSpacing.xs,
                  ),
                  child: RevericIcon(
                    RevericIcons.keyboard_arrow_right,
                    size: RevericSizes.buttonIconSize,
                    color: colors.textSubtle,
                  ),
                ),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: typo.uiSemibold.copyWith(color: colors.textPrimary),
                  ),
                ),
                const SizedBox(width: RevericSpacing.lg),
                RevericButton.text(
                  label: context.t(LocaleKeys.commonCancel),
                  onPressed: saving.value ? null : close,
                ),
                const SizedBox(width: RevericSpacing.sm),
                saveButton,
              ],
            ),
          ),
          Divider(
            height: RevericSizes.dividerThickness,
            thickness: RevericSizes.dividerThickness,
            color: colors.borderSubtle,
          ),
          Expanded(child: content),
          ?notice,
        ],
      ),
    );
    if (onClose == null) {
      return editor;
    }
    // 编辑嵌在设置弹窗里：Esc 和点遮罩先回到列表，不直接关掉整个设置。
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          leaveToList();
        }
      },
      child: editor,
    );
  }
}

(String, Map<String, String>) _nameConflictMessage(
  McpServerNameConflict conflict,
) => conflict.name == conflict.existing
    ? (LocaleKeys.settingsMcpNameTaken, {'name': conflict.name})
    : (
        LocaleKeys.settingsMcpNameConflict,
        {'name': conflict.name, 'existing': conflict.existing},
      );

class _ImportPreview extends StatelessWidget {
  const _ImportPreview({required this.items});
  final List<McpServerConfig> items;
  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return SettingsCard(
      padding: EdgeInsets.zero,
      children: [
        for (final (index, item) in items.indexed) ...[
          if (index > 0) const SettingsRowDivider(),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: RevericSpacing.lg,
              vertical: RevericSpacing.md,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: typo.uiSemibold.copyWith(
                          color: colors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: RevericSpacing.xxs),
                      Text(
                        mcpEndpointLabel(item.connection),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: typo.uiSmall.copyWith(color: colors.textMuted),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: RevericSpacing.sm),
                RevericBadge(
                  label: context.t(mcpTransportLabelKey(item.connection)),
                  color: colors.textMuted,
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
