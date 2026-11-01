// 职责: 导演台 AI 识图弹窗 — 从本地上传、画布、作品场景或历史上传中选一张图，并选择插入还是覆盖导演台。
// 关联文件:
//   lib/desktop/features/production/region.dart
//   lib/desktop/features/production/node_card.dart
//   lib/shared/services/production/canvas_service.dart
//   lib/shared/services/subjects.dart
//   lib/shared/widgets/screenplay/director_workspace.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/director.json
//   assets/translations/zh-CN/director.json
//   assets/translations/en/assets.json
//   assets/translations/zh-CN/assets.json
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
// 遵循的 Rules:
//   .agents/rules/hooks.md
//   .agents/rules/design-system.md
//   .agents/rules/file-access.md
import 'dart:io';
import 'package:reveric/shared/models/asset_purpose.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import '../../../shared/components/reveric_button.dart';
import '../../../shared/components/reveric_dialog.dart';
import '../../../shared/components/reveric_segmented_control.dart';
import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/logger/app_logger.dart';
import '../../../shared/services/production/canvas_service.dart';
import '../../../shared/services/production/ffmpeg_runner.dart'
    show MediaCancellation;
import '../../../shared/services/subjects.dart';
import '../../../shared/theme/theme.dart';
import 'node_card.dart' show ProductionAssetThumb;

final _log = AppLogger.forModule('Director');

enum SceneRecognitionSource { upload, canvas, scenes, history }

typedef SceneRecognitionChoice = ({String assetId, bool overwrite});

typedef _Image = ({String assetId, String label});

Future<SceneRecognitionChoice?> showSceneRecognitionDialog(
  BuildContext context, {
  required ProductionCanvasService service,
  required String canvasId,
}) => showRevericDialog<SceneRecognitionChoice>(
  context: context,
  builder: (_) => SceneRecognitionDialog(service: service, canvasId: canvasId),
);

/// 交给聊天的识图指令；当前导演台由聊天上下文指明，这里只描述要做什么。
String sceneRecognitionPrompt({required bool overwrite}) =>
    '识别图中的场景，在当前打开的导演台中搭建站位参考：还原空间布局与关键道具、'
    '人物站位与朝向，并按画面视角添加机位。'
    '${overwrite ? '导演台已清空，按图片重新搭建。' : '保留导演台已有的全景、角色和机位，只补充图中的内容。'}';

class SceneRecognitionDialog extends HookWidget {
  const SceneRecognitionDialog({
    super.key,
    required this.service,
    required this.canvasId,
  });
  final ProductionCanvasService service;
  final String canvasId;

  static const double _width = 860;
  static const double _bodyHeight = 360;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final source = useState(SceneRecognitionSource.upload);
    final picked = useState<String?>(null);
    final overwrite = useState(false);
    void pick(String id) => picked.value = id;

    return RevericDialog.panel(
      width: _width,
      title: Text(context.t(LocaleKeys.directorRecognizeTitle)),
      content: SizedBox(
        width: _width,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: RevericSegmentedControl<SceneRecognitionSource>(
                segments: [
                  RevericSegment(
                    value: SceneRecognitionSource.upload,
                    label: context.t(LocaleKeys.directorRecognizeUpload),
                  ),
                  RevericSegment(
                    value: SceneRecognitionSource.canvas,
                    label: context.t(LocaleKeys.directorRecognizeCanvas),
                  ),
                  RevericSegment(
                    value: SceneRecognitionSource.scenes,
                    label: context.t(LocaleKeys.directorRecognizeScenes),
                  ),
                  RevericSegment(
                    value: SceneRecognitionSource.history,
                    label: context.t(LocaleKeys.directorRecognizeHistory),
                  ),
                ],
                selected: source.value,
                onChanged: (value) => source.value = value,
              ),
            ),
            const SizedBox(height: RevericSpacing.lg),
            SizedBox(
              height: _bodyHeight,
              child: switch (source.value) {
                SceneRecognitionSource.upload => _UploadPane(
                  service: service,
                  picked: picked.value,
                  onPicked: pick,
                ),
                SceneRecognitionSource.canvas => _CanvasImages(
                  service: service,
                  canvasId: canvasId,
                  picked: picked.value,
                  onPicked: pick,
                ),
                SceneRecognitionSource.scenes => _SceneImages(
                  service: service,
                  picked: picked.value,
                  onPicked: pick,
                ),
                SceneRecognitionSource.history => _HistoryImages(
                  service: service,
                  picked: picked.value,
                  onPicked: pick,
                ),
              },
            ),
            const SizedBox(height: RevericSpacing.x2l),
            Text(
              context.t(LocaleKeys.directorRecognizeMode),
              style: typo.uiSemibold.copyWith(color: colors.textPrimary),
            ),
            const SizedBox(height: RevericSpacing.md),
            RadioGroup<bool>(
              groupValue: overwrite.value,
              onChanged: (value) => overwrite.value = value ?? false,
              child: Row(
                children: [
                  Expanded(
                    child: _ModeCard(
                      value: false,
                      selected: !overwrite.value,
                      title: context.t(LocaleKeys.directorRecognizeInsert),
                      hint: context.t(LocaleKeys.directorRecognizeInsertHint),
                      onTap: () => overwrite.value = false,
                    ),
                  ),
                  const SizedBox(width: RevericSpacing.md),
                  Expanded(
                    child: _ModeCard(
                      value: true,
                      selected: overwrite.value,
                      title: context.t(LocaleKeys.directorRecognizeOverwrite),
                      hint: context.t(
                        LocaleKeys.directorRecognizeOverwriteHint,
                      ),
                      onTap: () => overwrite.value = true,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        RevericButton.secondary(
          label: context.t(LocaleKeys.commonCancel),
          onPressed: () => Navigator.pop(context),
        ),
        RevericButton.primary(
          key: const ValueKey('scene-recognition-confirm'),
          label: context.t(LocaleKeys.directorRecognizeConfirm),
          onPressed: picked.value == null
              ? null
              : () => Navigator.pop<SceneRecognitionChoice>(context, (
                  assetId: picked.value!,
                  overwrite: overwrite.value,
                )),
        ),
      ],
    );
  }
}

/// 本地上传：导入资产库（之后也会出现在「历史上传」里），并整张预览刚导入的图。
class _UploadPane extends HookWidget {
  const _UploadPane({
    required this.service,
    required this.picked,
    required this.onPicked,
  });
  final ProductionCanvasService service;
  final String? picked;
  final ValueChanged<String> onPicked;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final uploaded = useState<String?>(null);
    final importing = useState(false);

    Future<void> upload() async {
      importing.value = true;
      try {
        final file = await openFile(
          acceptedTypeGroups: [
            XTypeGroup(
              label: context.t(LocaleKeys.mediaImages),
              extensions: const ['png', 'jpg', 'jpeg', 'webp'],
            ),
          ],
        );
        if (file == null) {
          return;
        }
        final asset = await service.library.importFile(
          File(file.path),
          name: file.name,
          novelId: service.novelId,
          purpose: AssetPurpose.director_scene_recognition,
          cancellation: MediaCancellation(),
        );
        if (asset.type != 'image') {
          throw const FormatException('Unsupported upload type');
        }
        if (context.mounted) {
          uploaded.value = asset.id;
          onPicked(asset.id);
        }
      } catch (error, stack) {
        _log.error('recognize upload failed', error: error, stackTrace: stack);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.t(LocaleKeys.mediaImportFailed))),
          );
        }
      } finally {
        if (context.mounted) {
          importing.value = false;
        }
      }
    }

    final id = uploaded.value;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: colors.surfaceDim,
        borderRadius: BorderRadius.circular(RevericRadius.large),
        border: Border.all(
          color: id != null && picked == id
              ? colors.accent
              : colors.borderSubtle,
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (id != null)
            GestureDetector(
              onTap: () => onPicked(id),
              child: _Preview(service: service, assetId: id),
            ),
          Align(
            alignment: id == null ? Alignment.center : Alignment.bottomRight,
            child: Padding(
              padding: const EdgeInsets.all(RevericSpacing.md),
              child: RevericButton.secondary(
                key: const ValueKey('scene-recognition-upload'),
                label: context.t(LocaleKeys.commonSelectImage),
                icon: RevericIcons.upload,
                loading: importing.value,
                onPressed: importing.value ? null : upload,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 整张显示，不裁切；识图看的是全图构图。
class _Preview extends HookWidget {
  const _Preview({required this.service, required this.assetId});
  final ProductionCanvasService service;
  final String assetId;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final asset = useFuture(
      useMemoized(() => service.requireAsset(assetId, type: 'image'), [
        service,
        assetId,
      ]),
    ).data;
    if (asset == null) {
      return const SizedBox.shrink();
    }
    return Image.file(
      File(service.library.resolve(asset)),
      fit: BoxFit.contain,
      errorBuilder: (_, _, _) => Center(
        child: RevericIcon(
          RevericIcons.broken_image_outlined,
          color: colors.error,
        ),
      ),
    );
  }
}

class _CanvasImages extends HookWidget {
  const _CanvasImages({
    required this.service,
    required this.canvasId,
    required this.picked,
    required this.onPicked,
  });
  final ProductionCanvasService service;
  final String canvasId;
  final String? picked;
  final ValueChanged<String> onPicked;

  @override
  Widget build(BuildContext context) {
    final images = useFuture(
      useMemoized(
        () async => [
          for (final asset in await service.canvasImages(canvasId))
            (assetId: asset.id, label: asset.name),
        ],
        [service, canvasId],
      ),
    );
    return _ImageGrid(
      images: images.data,
      picked: picked,
      service: service,
      onPicked: onPicked,
    );
  }
}

/// 作品里带图的「场景」是地点：每张地点照片一格。
class _SceneImages extends HookWidget {
  const _SceneImages({
    required this.service,
    required this.picked,
    required this.onPicked,
  });
  final ProductionCanvasService service;
  final String? picked;
  final ValueChanged<String> onPicked;

  @override
  Widget build(BuildContext context) {
    final images = useFuture(
      useMemoized(
        () async => [
          for (final location in await loadSubjects(
            service.db,
            SubjectKind.location,
          ))
            for (final photo in location.photos)
              (
                assetId: photo.assetId,
                label: photo.name.isEmpty
                    ? location.name
                    : '${location.name} · ${photo.name}',
              ),
        ],
        [service],
      ),
    );
    return _ImageGrid(
      images: images.data,
      picked: picked,
      service: service,
      onPicked: onPicked,
    );
  }
}

class _HistoryImages extends HookWidget {
  const _HistoryImages({
    required this.service,
    required this.picked,
    required this.onPicked,
  });
  final ProductionCanvasService service;
  final String? picked;
  final ValueChanged<String> onPicked;

  @override
  Widget build(BuildContext context) {
    final images = useStream(
      useMemoized(
        () => service.library.database.assetDao
            .watchAssets(novelId: service.novelId, type: 'image')
            .map(
              (rows) => [
                for (final asset in rows)
                  if (asset.purpose ==
                      AssetPurpose.director_scene_recognition.value)
                    (assetId: asset.id, label: asset.name),
              ],
            ),
        [service],
      ),
    );
    return _ImageGrid(
      images: images.data,
      picked: picked,
      service: service,
      onPicked: onPicked,
    );
  }
}

class _ImageGrid extends StatelessWidget {
  const _ImageGrid({
    required this.images,
    required this.picked,
    required this.service,
    required this.onPicked,
  });

  /// null 表示仍在读取。
  final List<_Image>? images;
  final String? picked;
  final ProductionCanvasService service;
  final ValueChanged<String> onPicked;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final items = images;
    if (items == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (items.isEmpty) {
      return Center(
        child: Text(
          context.t(LocaleKeys.directorRecognizeEmpty),
          style: typo.ui.copyWith(color: colors.textMuted),
        ),
      );
    }
    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 5,
        mainAxisExtent: 164,
        mainAxisSpacing: RevericSpacing.md,
        crossAxisSpacing: RevericSpacing.md,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final image = items[index];
        final selected = image.assetId == picked;
        return GestureDetector(
          key: ValueKey('scene-recognition-image:${image.assetId}'),
          onTap: () => onPicked(image.assetId),
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: Container(
              padding: const EdgeInsets.fromLTRB(6, 6, 6, 8),
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(RevericRadius.large),
                border: Border.all(
                  color: selected ? colors.accent : colors.borderSubtle,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(RevericRadius.medium),
                      child: ProductionAssetThumb(
                        service: service,
                        assetId: image.assetId,
                      ),
                    ),
                  ),
                  const SizedBox(height: RevericSpacing.xs),
                  Text(
                    image.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: typo.uiSmall.copyWith(color: colors.textPrimary),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.value,
    required this.selected,
    required this.title,
    required this.hint,
    required this.onTap,
  });
  final bool value;
  final bool selected;
  final String title;
  final String hint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return Material(
      color: selected ? colors.selected : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(RevericRadius.large),
        side: BorderSide(
          color: selected ? colors.borderInput : colors.borderSubtle,
        ),
      ),
      child: InkWell(
        key: ValueKey('scene-recognition-mode:$value'),
        borderRadius: BorderRadius.circular(RevericRadius.large),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(RevericSpacing.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Radio<bool>(value: value),
              const SizedBox(width: RevericSpacing.xs),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: typo.uiSemibold.copyWith(
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: RevericSpacing.xxs),
                    Text(
                      hint,
                      style: typo.uiSmall.copyWith(color: colors.textMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
