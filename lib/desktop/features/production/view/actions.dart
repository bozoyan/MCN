// 职责: 打开镜头与打光设置面板，按预设或全景创建图片草稿，并提供全景预览入口。
// 关联文件:
//   lib/desktop/features/production/node_bar.dart
//   lib/desktop/features/production/view/region.dart
//   lib/desktop/features/production/view/method.dart
//   lib/shared/services/production/view_derive_orchestrator.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/production.json
//   assets/translations/zh-CN/production.json
// 遵循的 Rules:
//   .agents/rules/hooks.md
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../../../shared/components/reveric_button.dart';
import '../../../../shared/components/reveric_context_menu.dart';
import '../../../../shared/database/novel_content_database.dart';
import '../../../../shared/localization/app_localization.dart';
import '../../../../shared/localization/locale_keys.dart';
import '../../../../shared/models/ai_provider.dart';
import '../../../../shared/models/production/view_presets.dart';
import '../../../../shared/models/production/panorama.dart';
import '../../../../shared/models/video/request.dart';
import '../../../../shared/providers/settings_providers.dart';
import '../../../../shared/services/production/canvas_service.dart';
import '../../../../shared/services/production/view_derive_orchestrator.dart';
import '../../../../shared/theme/theme.dart';
import '../support.dart';
import 'method.dart';
import 'models.dart';
import 'region.dart';
import '../grid/session.dart';
import '../grid/spec_picker.dart';

/// 节点工具栏「九宫格」菜单；产品设定图只在图片编辑器里提供。
const _toolbarPresets = [
  ImageGenerationMethod.expression_grid,
  ImageGenerationMethod.multi_camera_grid,
  ImageGenerationMethod.plot_grid,
  ImageGenerationMethod.face_turnaround,
  ImageGenerationMethod.character_sheet,
  ImageGenerationMethod.scene_sheet,
  ImageGenerationMethod.continuous_grid,
  ImageGenerationMethod.cinematic_light,
  ImageGenerationMethod.character_turnaround,
  ImageGenerationMethod.after_3s,
  ImageGenerationMethod.before_5s,
];

class ProductionViewActions extends HookConsumerWidget {
  const ProductionViewActions({
    super.key,
    required this.service,
    required this.node,
    required this.assetId,
    required this.onCreated,
  });
  final ProductionCanvasService service;
  final CanvasNode node;
  final String? assetId;
  final ValueChanged<CanvasNode> onCreated;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final options = ref.watch(
      availableAiModelOptionsByKindProvider(AiModelKind.image),
    );
    final preferred = ref.watch(
      resolvedAiModelOptionForKindProvider(kind: AiModelKind.image),
    );
    final providers = ref.watch(aiSettingsProvider).providers;

    final model = resolveViewModel(
      options: options,
      providers: providers,
      preferredOptionId: preferred?.id,
    );
    final asset = useFuture(
      useMemoized(
        () => service.inputAsset(
          ProductionInput.node(node.id, VideoInputRole.reference_image),
        ),
        [service, node.id, assetId],
      ),
    );
    final busy = useState(false);
    final session = ProductionViewSession.of(context);
    final reason = !asset.hasData
        ? context.t(LocaleKeys.productionViewImageRequired)
        : null;
    void createDraft(
      BuildContext context,
      ImageGenerationMethod method,
      String label,
    ) => productionRun(context, () async {
      busy.value = true;
      try {
        final created = await ViewDeriveOrchestrator().createDraft(
          service: service,
          sourceNodeId: node.id,
          method: method,
          title: '${node.title} · $label',
        );
        if (context.mounted) {
          onCreated(created);
        }
      } finally {
        if (context.mounted) {
          busy.value = false;
        }
      }
    });
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
          message: reason ?? '',
          child: Builder(
            builder: (context) => RevericButton.text(
              icon: RevericIcons.tune,
              label: context.t(LocaleKeys.productionViewViewComposition),
              size: RevericButtonSize.compact,
              onPressed: reason != null || busy.value
                  ? null
                  : () {
                      final box = context.findRenderObject()! as RenderBox;
                      showRevericContextMenu(
                        context: context,
                        position: box.localToGlobal(Offset(0, box.size.height)),
                        entries: [
                          for (final preset in [
                            ViewPreset.camera,
                            ViewPreset.light,
                          ])
                            RevericMenuItem(
                              label: context.t(
                                preset == ViewPreset.camera
                                    ? LocaleKeys.productionViewCamera
                                    : LocaleKeys.productionViewLight,
                              ),
                              enabled: model != null,
                              tooltip: model == null
                                  ? context.t(
                                      LocaleKeys
                                          .productionViewImageModelRequired,
                                    )
                                  : null,
                              onTap: () => session.value = preset,
                            ),
                          RevericMenuItem(
                            label: context.t(
                              LocaleKeys.productionViewPanoramaGenerate,
                            ),
                            onTap: () => createDraft(
                              context,
                              ImageGenerationMethod.panorama,
                              context.t(
                                LocaleKeys.productionViewPanoramaGenerate,
                              ),
                            ),
                          ),
                        ],
                      );
                    },
            ),
          ),
        ),
        Tooltip(
          message: reason ?? '',
          child: RevericButton.text(
            icon: RevericIcons.visibility_outlined,
            label: context.t(LocaleKeys.productionViewPanoramaPreview),
            size: RevericButtonSize.compact,
            onPressed: reason != null
                ? null
                : () => productionRun(context, () async {
                    session.value = null;
                    await service.setPanoramaView(
                      node.id,
                      const PanoramaView(),
                    );
                  }),
          ),
        ),
        Tooltip(
          message: reason ?? '',
          child: Builder(
            builder: (context) => RevericButton.text(
              icon: RevericIcons.space_dashboard_outlined,
              label: context.t(LocaleKeys.productionGridPresets),
              size: RevericButtonSize.compact,
              onPressed: reason != null || busy.value
                  ? null
                  : () {
                      final box = context.findRenderObject()! as RenderBox;
                      showRevericContextMenu(
                        context: context,
                        position: box.localToGlobal(Offset(0, box.size.height)),
                        entries: [
                          for (final method in _toolbarPresets)
                            RevericMenuItem(
                              icon: imagePresetIcon(method),
                              label: imagePresetLabel(context, method),
                              onTap: () => createDraft(
                                context,
                                method,
                                imagePresetLabel(context, method),
                              ),
                            ),
                        ],
                      );
                    },
            ),
          ),
        ),
        Tooltip(
          message: reason ?? '',
          child: ProductionGridSpecPicker(
            label: context.t(LocaleKeys.productionGridSplit),
            enabled: reason == null && !busy.value,
            onSelected: (spec) {
              session.value = null;
              ProductionGridSession.maybeOf(context)!.start(spec);
            },
          ),
        ),
      ],
    );
  }
}
