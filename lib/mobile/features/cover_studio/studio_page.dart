// 职责: 移动端 AI 封面工作台页 — 持有提示词真源，编排画布、设计师抽屉与生成记录。
// 关联文件:
//   lib/shared/providers/cover_studio_providers.dart
//   lib/mobile/features/cover_studio/canvas.dart
//   lib/mobile/features/cover_studio/designer_sheet.dart
//   lib/mobile/features/cover_studio/records_sheet.dart
//   lib/shared/providers/cover_providers.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/editor.json
//   assets/translations/zh-CN/editor.json
//   assets/translations/en/workspace.json
//   assets/translations/zh-CN/workspace.json
// 遵循的 Rules:
//   .agents/rules/widget-decomposition.md
//   .agents/rules/design-system.md
//   .agents/rules/form.md
//   .agents/rules/hooks.md
//   .agents/rules/text-input-ime.md
//   .agents/rules/i18n.md

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../shared/providers/async_read.dart';
import '../../../shared/database/app_database.dart';
import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/providers/cover_providers.dart';
import '../../../shared/providers/cover_studio_providers.dart';
import '../../../shared/providers/novel_providers.dart';
import '../../../shared/services/cover_prompt_builder.dart';
import '../../../shared/theme/theme.dart';
import '../../../shared/widgets/cover_studio/sections.dart';
import '../../../third/form/flutter_hook_form.dart';
import 'canvas.dart';
import 'canvas_actions.dart';
import 'bottom_bar.dart';
import 'designer_sheet.dart';
import 'records_sheet.dart';

/// 打开封面工作台。[onApply] 收到的是图片资产 id，由调用方决定怎么落到作品上。
Future<void> openMobileCoverStudioPage(
  BuildContext context, {
  required Novel novel,
  required String? databasePath,
  required Future<void> Function(String assetId) onApply,
}) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => MobileCoverStudioPage(
        novel: novel,
        databasePath: databasePath,
        onApply: onApply,
      ),
    ),
  );
}

class MobileCoverStudioPage extends HookConsumerWidget {
  const MobileCoverStudioPage({
    super.key,
    required this.novel,
    required this.databasePath,
    required this.onApply,
  });

  final Novel novel;

  /// per-novel content DB 的路径。封面档案存在它的 novel_states 里；
  /// 内容库还没打开时为 null，此时整块档案功能收起，出图照常。
  final String? databasePath;
  final Future<void> Function(String assetId) onApply;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = RevericTheme.colorsOf(context);
    // 不给 initialValues：这个字段的真相源是下面的外部 controller。
    // listen: false —— 输入期不让 form 变更驱动整页重建（text-input-ime.md）。
    final form = useForm<CoverStudioField>(listen: false);
    // 提示词归用户：书名与署名只作为默认种子写进这段话。
    final seedPrompt = defaultCoverPrompt(
      novelTitle: novel.title,
      authorName: novel.authorName,
    );
    // controller 归页面所有：设计师在 modal sheet 里是另一条 route，闭包捕获的
    // 仍是这一个实例，所以下面两条 ref.listen 的回填对抽屉同样生效。
    final promptController = useTextEditingController(text: seedPrompt);

    final state = ref.watch(coverStudioControllerProvider(novel.id));
    final controller = ref.read(
      coverStudioControllerProvider(novel.id).notifier,
    );

    // 「新建」在记录抽屉里按下，够不着这里的提示词 controller，只能靠 draftSeq 传信。
    // 用 ref.listen 而不是 useEffect：listen 的回调在 build 之外跑，不会在构建期
    // 把 EditableText 标脏（hooks.md）。
    ref.listen(
      coverStudioControllerProvider(novel.id).select((state) => state.draftSeq),
      (previous, next) {
        if (previous == null || previous == next) {
          return;
        }
        promptController.value = TextEditingValue(
          text: seedPrompt,
          selection: TextSelection.collapsed(offset: seedPrompt.length),
        );
      },
    );
    ref.listen(
      coverStudioControllerProvider(
        novel.id,
      ).select((state) => state.promptRestore),
      (previous, next) {
        if (next == null || previous?.sequence == next.sequence) {
          return;
        }
        promptController.value = TextEditingValue(
          text: next.text,
          selection: TextSelection.collapsed(offset: next.text.length),
        );
      },
    );

    final libraryAssets =
        ref.watch(imageAssetsProvider(novel.id)).asData?.value ??
        const <AssetRow>[];
    final batches =
        ref.watch(imageBatchesProvider(novel.id)).asData?.value ??
        const <ImageBatchRow>[];
    final path = databasePath;
    final briefAsync = path == null
        ? null
        : ref.watch(coverBriefStateProvider(path));

    // 未选批次时画布空态；不自动跟最新一批。
    final currentBatch = _resolveBatch(batches, state.selectedBatchId);
    final slots = currentBatch == null
        ? const <CoverSlotView>[]
        : ref.watch(coverSlotViewsProvider(currentBatch.id, novel.id));
    final selected = _selectedSlot(slots, state.selectedOrdinal);
    final appliedAssetId = novel.coverAssetId;

    void appendPrompt(String fragment) {
      final next = appendCoverPromptFragment(promptController.text, fragment);
      if (next == promptController.text) {
        return;
      }
      promptController.value = TextEditingValue(
        text: next,
        selection: TextSelection.collapsed(offset: next.length),
      );
    }

    Future<void> generate() =>
        controller.generate(prompt: promptController.text);

    Future<void> readBrief() async {
      if (path == null) {
        return;
      }
      if (!context.mounted) {
        return;
      }
      final container = ProviderScope.containerOf(context, listen: false);
      await container.withProvider(
        coverBriefServiceProvider,
        (service) => service.read(
          contentDb: container.read(novelContentDatabaseProvider(path)),
          novelTitle: novel.title,
          novelDescription: novel.description,
        ),
      );
    }

    // 首次进来还没有档案时自动读一遍；之后只有作者点「重新读一遍」才重读。
    // 稿子天天在变，每次进页面重读既花钱、又会让同样的参数给出不同的调子。
    // 放在页面而不是抽屉里：作者可能一直不打开抽屉。
    final autoReadRequested = useRef(false);
    useEffect(() {
      final value = briefAsync?.asData?.value;
      if (value == null || autoReadRequested.value) {
        return null;
      }
      if (value.brief == null && !value.reading) {
        autoReadRequested.value = true;
        // 首帧之后再发起：effect 首次运行在 initHook 里，此时起一条会写 provider
        // 的异步任务会在构建途中改状态。
        WidgetsBinding.instance.addPostFrameCallback((_) => readBrief());
      }
      return null;
    }, [briefAsync]);

    _useToast(context, ref, novel.id);

    final selectedPath = ref
        .read(imageLibraryServiceProvider)
        .resolve(selected?.asset?.path);

    return Scaffold(
      backgroundColor: colors.canvas,
      appBar: AppBar(
        backgroundColor: colors.canvas,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const RevericIcon(RevericIcons.arrow_back, size: 18),
        ),
        title: Text(context.t(LocaleKeys.editorCoverStudio)),
        actions: [
          IconButton(
            onPressed: selectedPath == null
                ? null
                : () => _exportCover(context, selectedPath),
            icon: const RevericIcon(RevericIcons.download_outlined, size: 18),
          ),
          IconButton(
            key: const ValueKey('cover-studio-records'),
            onPressed: () =>
                openMobileCoverRecordsSheet(context, novelId: novel.id),
            icon: const RevericIcon(RevericIcons.history_outlined, size: 18),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: MobileCoverCanvas(
              novelId: novel.id,
              novelTitle: novel.title,
              slots: slots,
              appliedAssetId: appliedAssetId,
              onRework: (ordinal) {
                final batch = currentBatch;
                if (batch == null) {
                  return;
                }
                controller.rework(batchId: batch.id, ordinal: ordinal);
              },
            ),
          ),
          if (slots.isNotEmpty) ...[
            MobileCoverCanvasActions(
              novelId: novel.id,
              selected: selected,
              applied:
                  selected?.asset != null &&
                  selected!.asset!.id == appliedAssetId,
              onRework: (ordinal) {
                final batch = currentBatch;
                if (batch == null) {
                  return;
                }
                controller.rework(batchId: batch.id, ordinal: ordinal);
              },
              onApply: (slot) async {
                final asset = slot.asset;
                if (asset == null) {
                  return;
                }
                await onApply(asset.id);
              },
            ),
            const SizedBox(height: RevericSpacing.sm),
          ],
        ],
      ),
      bottomNavigationBar: MobileCoverStudioBottomBar(
        novelId: novel.id,
        onOpenDesigner: () => openMobileCoverDesignerSheet(
          context,
          novel: novel,
          databasePath: path,
          libraryAssets: libraryAssets,
          form: form,
          promptController: promptController,
          onGenerate: generate,
          onReadBrief: () => readBrief(),
          onAppendPrompt: appendPrompt,
        ),
        onGenerate: generate,
      ),
    );
  }

  ImageBatchRow? _resolveBatch(List<ImageBatchRow> batches, String? selected) {
    if (selected == null || batches.isEmpty) {
      return null;
    }
    for (final batch in batches) {
      if (batch.id == selected) {
        return batch;
      }
    }
    return null;
  }

  CoverSlotView? _selectedSlot(List<CoverSlotView> slots, int ordinal) {
    if (slots.isEmpty) {
      return null;
    }
    for (final slot in slots) {
      if (slot.ordinal == ordinal) {
        return slot;
      }
    }
    return slots.first;
  }
}

/// 手机上没有「另存为」对话框，导出走系统分享面板 —— 存相册、发微信都从这里分叉。
Future<void> _exportCover(BuildContext context, String sourcePath) async {
  final file = File(sourcePath);
  try {
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        fileNameOverrides: [file.uri.pathSegments.last],
      ),
    );
  } catch (error, stackTrace) {
    debugPrintStack(label: 'Failed to export cover', stackTrace: stackTrace);
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.t(LocaleKeys.workspaceCoverSaveFailed))),
    );
  }
}

/// 逐张出图、停止、重出这些动作各自弹一条短消息。
void _useToast(BuildContext context, WidgetRef ref, String novelId) {
  final toast = ref.watch(
    coverStudioControllerProvider(novelId).select((state) => state.toast),
  );
  // messenger 与文案都在 build 阶段取好：useEffect 的回调首次运行在 initHook 里，
  // 那里不能再读 InheritedWidget（Localizations / ScaffoldMessenger 都是）。
  final messenger = ScaffoldMessenger.maybeOf(context);
  final message = toast == null
      ? null
      : context.t(toast.messageKey, namedArgs: toast.args);

  useEffect(() {
    if (message == null || messenger == null) {
      return null;
    }
    // 弹条与清 toast 都要等这一帧画完：在 build/initHook 期间改 messenger 或
    // provider 状态会触发 setState during build。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      messenger.showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
      );
      ref.read(coverStudioControllerProvider(novelId).notifier).dismissToast();
    });
    return null;
  }, [toast?.id]);
}
