// 职责: 聊天窗口的出图对话框 — 选择模型与尺寸并编辑请求级参数,直接生成并落入当前会话。
// 关联文件:
//   lib/shared/models/image/chat_image_memory.dart
//   lib/shared/providers/ai_providers.dart
//   lib/shared/providers/settings_providers.dart
//   lib/shared/providers/novel_providers.dart
//   lib/shared/services/ai/image.dart
//   lib/shared/widgets/production/image_request_extras_panel.dart
//   lib/desktop/widgets/ai/chat/composer.dart
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/hooks.md
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../../shared/components/reveric_button.dart';
import '../../../../shared/components/reveric_dialog.dart';
import '../../../../shared/components/reveric_select.dart';
import '../../../../shared/components/reveric_text_field.dart';
import '../../../../shared/localization/app_localization.dart';
import '../../../../shared/localization/locale_keys.dart';
import '../../../../shared/logger/app_logger.dart';
import '../../../../shared/models/ai_message_block.dart';
import '../../../../shared/models/ai_provider.dart';
import '../../../../shared/models/asset_purpose.dart';
import '../../../../shared/models/image/chat_image_memory.dart';
import '../../../../shared/models/image/channels.dart';
import '../../../../shared/models/image/extras.dart';
import '../../../../shared/models/production/image_request.dart';
import '../../../../shared/providers/ai_providers.dart';
import '../../../../shared/providers/novel_providers.dart';
import '../../../../shared/providers/settings_providers.dart';
import '../../../../shared/services/ai/image.dart';
import '../../../../shared/theme/theme.dart';
import '../../../../shared/widgets/production/image_request_extras_panel.dart';

final _log = AppLogger.forModule('ChatImageDialog');

/// 聊天里手动出图:默认底座 Qwen/Qwen-Image-2.1-Turbo,可换任意已配置的
/// 图像模型;魔搭/MOSS 模型额外提供尺寸与 LoRA/参数编辑。生成结果作为图片
/// 卡片插入当前会话消息流。上次使用的模型/尺寸/参数会持久化,下次打开恢复。
Future<void> showChatImageDialog({
  required BuildContext context,
  required WidgetRef ref,
  required String novelId,
  required String? sessionId,
}) async {
  if (sessionId == null || sessionId.isEmpty) {
    return;
  }
  final memory = await _readChatImageMemory(ref);
  if (!context.mounted) {
    return;
  }
  await showRevericDialog<void>(
    context: context,
    builder: (dialogContext) {
      return _ChatImageDialog(
        novelId: novelId,
        sessionId: sessionId,
        memory: memory,
      );
    },
  );
}

Future<ChatImageMemoryData> _readChatImageMemory(WidgetRef ref) async {
  final database = ref.read(appSettingsDatabaseProvider);
  try {
    final raw = await database.appSettingsDao.get(
      ChatImageMemoryData.appSettingsKey,
    );
    if (raw == null || raw.isEmpty) {
      return ChatImageMemoryData.defaults;
    }
    return ChatImageMemoryData.decode(raw);
  } catch (error, stackTrace) {
    _log.error(
      '[DB] table=app_settings operation=SELECT '
      'id=${ChatImageMemoryData.appSettingsKey} malformed aggregate',
      error: error,
      stackTrace: stackTrace,
    );
    return ChatImageMemoryData.defaults;
  }
}

Future<void> _saveChatImageMemory(
  WidgetRef ref,
  ChatImageMemoryData memory,
) async {
  final database = ref.read(appSettingsDatabaseProvider);
  try {
    await database.appSettingsDao.set(
      key: ChatImageMemoryData.appSettingsKey,
      value: memory.encode(),
    );
  } catch (error, stackTrace) {
    _log.error(
      '[DB] table=app_settings operation=INSERT '
      'id=${ChatImageMemoryData.appSettingsKey}',
      error: error,
      stackTrace: stackTrace,
    );
  }
}

class _ChatImageDialog extends HookConsumerWidget {
  const _ChatImageDialog({
    required this.novelId,
    required this.sessionId,
    required this.memory,
  });

  final String novelId;
  final String sessionId;
  final ChatImageMemoryData memory;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final settings = ref.watch(aiSettingsProvider);
    final options = settings.availableModelOptionsForKind(AiModelKind.image);
    final currentOption = ref.watch(
      resolvedAiModelOptionForKindProvider(kind: AiModelKind.image),
    );
    // 优先恢复上次使用的模型;没有记忆或已失效时回落默认底座
    // Qwen/Qwen-Image-2.1-Turbo,再回落当前默认与第一个。
    final rememberedOption = options
        .where((option) => option.id == memory.modelOptionId)
        .firstOrNull;
    final defaultOption =
        rememberedOption ??
        options
            .where((option) => option.model == _chatImageDefaultModelId)
            .firstOrNull ??
        currentOption ??
        options.firstOrNull;
    final selected = useState<AiModelOption?>(defaultOption);
    final size = useState<String?>(
      _restoreSize(settings, defaultOption, memory.size),
    );
    final extras = useState<ImageRequestExtras?>(memory.extras);
    final prompt = useState('');

    final protocol =
        selected.value == null
        ? null
        : settings
              .findConfigForSelection(
                providerId: selected.value!.providerId,
                model: selected.value!.model,
                kind: AiModelKind.image,
              )
              ?.typeConfig
              .imageProtocol;

    Future<void> generate() async {
      final option = selected.value;
      final promptText = prompt.value.trim();
      if (option == null || promptText.isEmpty) {
        return;
      }
      final config = settings.findConfigForSelection(
        providerId: option.providerId,
        model: option.model,
        kind: AiModelKind.image,
      );
      if (config == null) {
        return;
      }
      Navigator.of(context).pop();
      // 弹窗已销毁,后续生成直接由会话流承接;不再触碰任何已 dispose 的
      // 弹窗 hook 状态(此前在 pop 后给 generating 赋值会抛
      // "used after being disposed",把已经排程的生成一并打断)。
      await submitChatImageGeneration(
        context: context,
        ref: ref,
        novelId: novelId,
        sessionId: sessionId,
        option: option,
        prompt: promptText,
        size: size.value,
        extras: extras.value,
      );
    }

    return RevericDialog(
      title: context.t(LocaleKeys.aiImageDialogTitle),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.t(LocaleKeys.storyboardModel),
                style: typo.uiSemibold.copyWith(color: colors.textSecondary),
              ),
              const SizedBox(height: RevericSpacing.md),
              RevericSelect<AiModelOption>(
                value: selected.value,
                items: [
                  for (final option in options)
                    RevericSelectItem(
                      value: option,
                      label: option.model,
                      subtitle: option.providerId,
                    ),
                ],
                onChanged: (value) {
                  selected.value = value;
                  size.value = null;
                },
              ),
              if (protocol == ImageProtocol.modelscope_image ||
                  protocol == ImageProtocol.moss_image) ...[
                const SizedBox(height: RevericSpacing.lg),
                _ChatImageSizeSelector(
                  key: ValueKey(
                    'size_${selected.value?.providerId}_${selected.value?.model}',
                  ),
                  settings: settings,
                  providerId: selected.value?.providerId,
                  model: selected.value?.model,
                  selectedSize: size.value,
                  onChanged: (value) => size.value = value,
                ),
                const SizedBox(height: RevericSpacing.lg),
                ImageRequestExtrasPanel(
                  protocol: protocol!,
                  value: extras.value,
                  recommendedSteps: modelScopeRecommendedSteps(
                    selected.value?.model ?? '',
                  ),
                  onChanged: (value) => extras.value = value,
                ),
              ],
              const SizedBox(height: RevericSpacing.lg),
              RevericTextField(
                hintText: context.t(LocaleKeys.aiImageDialogPromptHint),
                multiline: true,
                minLines: 3,
                maxLines: 6,
                onChanged: (value) => prompt.value = value,
              ),
            ],
          ),
        ),
      ),
      width: 420,
      actions: [
        RevericButton.secondary(
          label: context.t(LocaleKeys.commonCancel),
          onPressed: () => Navigator.of(context).pop(),
        ),
        RevericButton.primary(
          label: context.t(LocaleKeys.productionImageGenerate),
          onPressed:
              selected.value != null && prompt.value.trim().isNotEmpty
              ? () {
                  generate();
                }
              : null,
        ),
      ],
    );
  }
}

/// 尺寸下拉:按选中模型的渠道能力展开 比例·档位 组合,回显当前选中尺寸。
class _ChatImageSizeSelector extends ConsumerWidget {
  const _ChatImageSizeSelector({
    super.key,
    required this.settings,
    required this.providerId,
    required this.model,
    required this.selectedSize,
    required this.onChanged,
  });

  final AiSettings settings;
  final String? providerId;
  final String? model;

  /// 当前选中的尺寸;null 表示默认档,也用于不在支持列表时的回落显示。
  final String? selectedSize;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = providerId == null || model == null
        ? null
        : settings.findConfigForSelection(
            providerId: providerId!,
            model: model!,
            kind: AiModelKind.image,
          );
    final caps = config == null ? null : ProductionImageCapabilities(config, model!);
    if (caps == null || !caps.isSupported) {
      return const SizedBox.shrink();
    }
    final options = <(String?, String)>[
      (null, context.t(LocaleKeys.commonDefault)),
      for (final resolution in caps.resolutions)
        for (final ratio in caps.ratios)
          if (caps.size(ratio, resolution) case final size?)
            (size, '$ratio · $resolution ($size)'),
    ];
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.t(LocaleKeys.productionImageSize),
          style: typo.uiSemibold.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: RevericSpacing.md),
        RevericSelect<(String?, String)>(
          value: options.firstWhere(
            (option) => option.$1 == selectedSize,
            orElse: () => options.first,
          ),
          items: [
            for (final option in options)
              RevericSelectItem(value: option, label: option.$2),
          ],
          onChanged: (value) => onChanged(value.$1),
        ),
      ],
    );
  }
}

/// 聊天快捷出图的生成入口(出图弹窗与 `/出图` 指令共用):落占位块、保存
/// 参数记忆、生成、入库并把持久路径回写会话流。失败以图片块错误态呈现,
/// 同时在弹窗/聊天宿主仍挂载时弹一条提示。
Future<void> submitChatImageGeneration({
  required BuildContext context,
  required WidgetRef ref,
  required String novelId,
  required String sessionId,
  required AiModelOption option,
  required String prompt,
  String? size,
  ImageRequestExtras? extras,
  List<String> referencePaths = const [],
}) async {
  final config = ref.read(aiSettingsProvider).findConfigForSelection(
    providerId: option.providerId,
    model: option.model,
    kind: AiModelKind.image,
  );
  if (config == null) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.t(LocaleKeys.aiNoImageModelConfigured))),
      );
    }
    return;
  }
  final sessionNotifier = ref.read(aiChatSessionProvider(sessionId).notifier);
  final library = ref.read(imageLibraryServiceProvider);
  final blockId = 'img_manual_${DateTime.now().microsecondsSinceEpoch}';
  // 持久化本次使用的模型/尺寸/参数,下次打开对话框恢复;失败不影响生成。
  unawaited(
    _saveChatImageMemory(
      ref,
      ChatImageMemoryData(
        modelOptionId: option.id,
        size: size,
        extras: extras == null || extras.isEmpty ? null : extras,
      ),
    ),
  );
  // 先在会话流里落一个占位块,生成完成后原地改成结果。
  sessionNotifier.upsertImageBlock(
    AiImageBlock(
      id: blockId,
      prompt: prompt,
      toolName: 'GeneratePhoto',
      status: AiImageStatus.generating,
    ),
  );
  try {
    final service = AiImageGenerationService(config, model: option.model);
    // 带参考图(≤4)走编辑接口(参考图作 image_url 下发);纯文生图走生成接口。
    final result =
        referencePaths.isEmpty
        ? await service.generateImage(prompt, size: size, extras: extras)
        : await service.editImages(
          prompt,
          imageData: referencePaths,
          size: size,
          extras: extras,
        );
    final asset = await library.importGenerated(
      result,
      novelId: novelId,
      purpose: AssetPurpose.ai_chat_generated,
      prompt: prompt,
      model: option.model,
    );
    // importGenerated 的 finally 会删除 result 的临时文件,
    // 块里必须存图库资产的持久路径,否则卡片解析不到文件、图片无法显示。
    sessionNotifier.patchImageBlock(
      blockId,
      status: AiImageStatus.success,
      localFilePath: asset.path,
      assetId: asset.id,
    );
  } catch (error) {
    sessionNotifier.patchImageBlock(
      blockId,
      status: AiImageStatus.error,
      errorMessage: '$error',
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.t(LocaleKeys.productionImageGenerateFailed)),
        ),
      );
    }
  }
}

/// `/出图` 或 `/img` 指令的解析结果;size/lora 缺省时由参数记忆补齐。
class ChatImageCommand {
  const ChatImageCommand({required this.prompt, this.size, this.extras});

  /// 画面描述(已剔除指令与参数段)。
  final String prompt;
  final String? size;
  final ImageRequestExtras? extras;
}

/// 解析聊天快捷出图指令;非指令或缺少画面描述时返回 null(消息继续走原流程)。
///
/// 语法:`/出图 <画面描述> [size=1440x816] [lora=repo[:weight]]...`;
/// lora 可重复,权重缺省 1,数值非法时回落 1,校验交给请求端。
ChatImageCommand? parseChatImageCommand(String text) {
  final trimmed = text.trim();
  final head = RegExp(r'^/(?:出图|img)(?:\s+([\s\S]+))?$').firstMatch(trimmed);
  if (head == null) {
    return null;
  }
  var body = head[1] ?? '';
  String? size;
  final sizeMatch = RegExp(r'(?:^|\s)size=(\d+x\d+)').firstMatch(body);
  if (sizeMatch != null) {
    size = sizeMatch[1];
    body = body.replaceFirst(sizeMatch.group(0)!, ' ');
  }
  final loras = <ModelScopeLora>[];
  for (final match in RegExp(r'(?:^|\s)lora=([^\s]+)').allMatches(body)) {
    body = body.replaceFirst(match.group(0)!, ' ');
    final parts = match[1]!.split(':');
    final repoId = parts.first.trim();
    if (repoId.isEmpty) {
      continue;
    }
    final weight = parts.length > 1
        ? double.tryParse(parts[1]) ?? 1.0
        : 1.0;
    loras.add(ModelScopeLora(repoId: repoId, weight: weight));
  }
  final prompt = body.trim();
  if (prompt.isEmpty) {
    return null;
  }
  return ChatImageCommand(
    prompt: prompt,
    size: size,
    extras: loras.isEmpty ? null : ImageRequestExtras(loras: loras),
  );
}

/// 执行 `/出图` 指令:模型与缺省参数来自参数记忆,指令里显式给出的
/// size/lora 优先;记忆的尺寸仍需通过渠道能力校验;参考图(≤4)走编辑接口。
Future<void> runChatImageCommand({
  required BuildContext context,
  required WidgetRef ref,
  required String novelId,
  required String sessionId,
  required ChatImageCommand command,
  List<String> referencePaths = const [],
}) async {
  final settings = ref.read(aiSettingsProvider);
  final memory = await _readChatImageMemory(ref);
  final option = resolveChatImageModel(settings, memory);
  if (option == null) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.t(LocaleKeys.aiNoImageModelConfigured))),
      );
    }
    return;
  }
  await submitChatImageGeneration(
    context: context,
    ref: ref,
    novelId: novelId,
    sessionId: sessionId,
    option: option,
    prompt: command.prompt,
    size: command.size ?? _restoreSize(settings, option, memory.size),
    extras: command.extras ?? memory.extras,
    referencePaths: referencePaths,
  );
}

/// 聊天出图的默认底座;弹窗与指令共用。
const _chatImageDefaultModelId = 'Qwen/Qwen-Image-2.1-Turbo';

/// 校验记忆的尺寸仍被该模型的渠道能力支持;不支持时回落默认(null)。
String? _restoreSize(
  AiSettings settings,
  AiModelOption? option,
  String? savedSize,
) {
  if (option == null || savedSize == null || savedSize.isEmpty) {
    return null;
  }
  final config = settings.findConfigForSelection(
    providerId: option.providerId,
    model: option.model,
    kind: AiModelKind.image,
  );
  final caps = config == null
      ? null
      : ProductionImageCapabilities(config, option.model);
  if (caps == null || !caps.isSupported) {
    return null;
  }
  for (final resolution in caps.resolutions) {
    for (final ratio in caps.ratios) {
      if (caps.size(ratio, resolution) == savedSize) {
        return savedSize;
      }
    }
  }
  return null;
}

/// 与弹窗一致的模型恢复链:记忆 → 默认底座 → 当前默认 → 第一个。
AiModelOption? resolveChatImageModel(
  AiSettings settings,
  ChatImageMemoryData memory,
) {
  final options = settings.availableModelOptionsForKind(AiModelKind.image);
  if (options.isEmpty) {
    return null;
  }
  final remembered = options
      .where((option) => option.id == memory.modelOptionId)
      .firstOrNull;
  final current = settings.findModelOptionById(
    kind: AiModelKind.image,
    optionId: settings.defaultOptionIdForKind(AiModelKind.image),
  );
  return remembered ??
      options
          .where((option) => option.model == _chatImageDefaultModelId)
          .firstOrNull ??
      current ??
      options.firstOrNull;
}
