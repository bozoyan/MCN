// 职责: 为桌面图片节点打开主体选择，并展示主体资料、选用其共享照片。
// 关联文件:
//   lib/shared/services/production/canvas_service.dart
//   lib/desktop/features/production/node_card.dart
//   lib/shared/widgets/subject_picker.dart
//   lib/shared/widgets/entity_card.dart
//   lib/shared/services/subjects.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/screenplay.json
//   assets/translations/zh-CN/screenplay.json
//   assets/translations/en/workspace.json
//   assets/translations/zh-CN/workspace.json
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
// 遵循的 Rules:
//   .agents/rules/hooks.md
//   .agents/rules/design-system.md
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import '../../../shared/components/reveric_button.dart';
import '../../../shared/components/reveric_dialog.dart';
import '../../../shared/components/reveric_placeholder.dart';
import '../../../shared/database/novel_content_database.dart';
import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/services/production/canvas_service.dart';
import '../../../shared/theme/theme.dart';
import '../../../shared/services/subjects.dart';
import '../../../shared/widgets/entity_card.dart';
import '../../../shared/widgets/subject_photo_name.dart';
import '../../../shared/widgets/subject_picker.dart';
import 'node_card.dart';

Future<String?> pickProductionSubject(
  BuildContext context,
  ProductionCanvasService service, {
  required SubjectKind kind,
}) => showSubjectPicker(
  context,
  db: service.db,
  kind: kind,
  coverBuilder: (assetId) =>
      ProductionAssetThumb(service: service, assetId: assetId),
);

/// 打开主体资料弹窗；返回选中的照片资产 id，取消时为 null。
Future<String?> showProductionSubjectProfile(
  BuildContext context,
  ProductionCanvasService service,
  ProductionClipRow clip,
) => showRevericDialog<String>(
  context: context,
  builder: (_) => ProductionSubjectProfileDialog(service: service, clip: clip),
);

/// 主体资料：左侧完整资料，右侧照片可点选采用、可改名；窄窗口改为上下排列。
class ProductionSubjectProfileDialog extends HookWidget {
  const ProductionSubjectProfileDialog({
    super.key,
    required this.service,
    required this.clip,
  });
  final ProductionCanvasService service;
  final ProductionClipRow clip;

  static const double _width = 880;
  static const double _height = 520;
  static const double _photosWidth = 360;

  /// 低于此宽度时资料和照片上下排列。
  static const double _stackBelow = 640;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final profile = useStream(
      useMemoized(
        () =>
            watchSubjectProfile(service.db, clip.subjectKind!, clip.subjectId!),
        [service, clip.subjectKind, clip.subjectId],
      ),
    );
    final data = profile.data;

    Widget photoGrid({required bool scrollable}) {
      final photos = data!.photos;
      if (photos.isEmpty) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: RevericSpacing.x2l),
          child: RevericPlaceholder.empty(
            icon: RevericIcons.image_outlined,
            title: context.t(LocaleKeys.productionPhotosEmpty),
          ),
        );
      }
      return GridView.builder(
        shrinkWrap: !scrollable,
        padding: scrollable
            ? const EdgeInsets.only(bottom: _fadeExtent)
            : EdgeInsets.zero,
        physics: scrollable ? null : const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 168,
          childAspectRatio: 0.8,
          crossAxisSpacing: RevericSpacing.sm,
          mainAxisSpacing: RevericSpacing.sm,
        ),
        itemCount: photos.length,
        itemBuilder: (context, index) {
          final assetId = photos[index].assetId;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: SubjectPickerTile(
                  key: ValueKey('subject-photo-$assetId'),
                  selected: assetId == clip.adoptedAssetId,
                  onTap: () => Navigator.of(context).pop(assetId),
                  cover: ProductionAssetThumb(
                    service: service,
                    assetId: assetId,
                  ),
                ),
              ),
              SubjectPhotoName(
                photo: photos[index],
                onRename: (name) =>
                    service.renameSubjectPhoto(clip, assetId, name),
              ),
            ],
          );
        },
      );
    }

    Widget photosLabel() => Padding(
      padding: const EdgeInsets.only(bottom: RevericSpacing.sm),
      child: Text(
        context.t(LocaleKeys.workspaceItemPhotos),
        style: typo.uiTinySemibold.copyWith(color: colors.textMuted),
      ),
    );

    final body = profile.hasError
        ? Center(
            child: RevericPlaceholder.error(
              title: context.t(LocaleKeys.commonLoadFailed),
            ),
          )
        : data == null
        ? const Center(child: CircularProgressIndicator())
        : LayoutBuilder(
            builder: (context, box) {
              final details = subjectProfileDetails(context, data);
              if (box.maxWidth < _stackBelow) {
                return _ScrollFade(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(bottom: _fadeExtent),
                    child: EntityCard(
                      entity: data.entity,
                      surface: EntityCardSurface.plain,
                      details: details,
                      footer: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [photosLabel(), photoGrid(scrollable: false)],
                      ),
                    ),
                  ),
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: _ScrollFade(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.only(bottom: _fadeExtent),
                        child: EntityCard(
                          entity: data.entity,
                          surface: EntityCardSurface.plain,
                          details: details,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: RevericSpacing.x2l),
                  SizedBox(
                    width: _photosWidth,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        photosLabel(),
                        Expanded(
                          child: _ScrollFade(
                            child: photoGrid(scrollable: true),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          );

    return RevericDialog.panel(
      width: _width,
      title: Text(context.t(LocaleKeys.productionSubjectProfile)),
      content: SizedBox(
        width: _width,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 期望高度固定，矮窗口下按弹窗剩余空间收缩。
            Flexible(
              child: SizedBox(height: _height, child: body),
            ),
          ],
        ),
      ),
      actions: [
        RevericButton.text(
          label: context.t(LocaleKeys.commonClose),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

/// 底部渐隐区高度；滚动内容底部留同样的空白，滚到底时最后一行完整露出。
const double _fadeExtent = 20;

/// 下方还有内容时底部渐隐，提示可继续滚动；滚到底后取消渐隐。
class _ScrollFade extends HookWidget {
  const _ScrollFade({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final more = useState(false);
    bool sync(ScrollMetrics metrics, int depth) {
      if (depth == 0) {
        more.value = metrics.extentAfter > 0;
      }
      return false;
    }

    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (n) => sync(n.metrics, n.depth),
      child: NotificationListener<ScrollUpdateNotification>(
        onNotification: (n) => sync(n.metrics, n.depth),
        child: ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (bounds) => LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black,
              Colors.black,
              more.value ? Colors.transparent : Colors.black,
            ],
            stops: [
              0,
              bounds.height <= _fadeExtent
                  ? 0
                  : 1 - _fadeExtent / bounds.height,
              1,
            ],
          ).createShader(bounds),
          child: child,
        ),
      ),
    );
  }
}
