// 职责: 将选中的图片导入资产库并追加到图鉴条目的照片集。
// 关联文件:
//   lib/shared/services/novel_content.dart
//   lib/shared/services/image_library_service.dart
//   lib/mobile/widgets/compendium_photos.dart
// 遵循的 Rules:
//   .agents/rules/service-naming.md
//   .agents/rules/file-access.md
import 'image_library_service.dart';
import 'package:reveric/shared/models/asset_purpose.dart';
import 'novel_content.dart';

class ItemPhotoImportOrchestrator {
  Future<void> import({
    required NovelContentService content,
    required ImageLibraryService library,
    required String itemId,
    required List<String> paths,
  }) async {
    final novelId = await content.requireNovelId();
    for (final path in paths) {
      final asset = await library.importFile(
        path,
        novelId: novelId,
        purpose: AssetPurpose.photo,
      );
      await content.addItemPhotos(itemId, [asset.id]);
    }
  }
}
