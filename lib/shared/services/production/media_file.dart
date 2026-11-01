// 职责: 按受控相对路径读取制作媒体，不依赖资产登记记录。
// 关联文件:
//   lib/shared/services/production/library_service.dart
//   lib/shared/services/production/canvas_service.dart
//   lib/shared/services/production/import_orchestrator.dart
import 'dart:io';
import 'package:path/path.dart' as p;
import '../../models/production/media.dart';
import 'library_service.dart';
import '../storyboard/service.dart';

const productionMediaFormats = {
  '.png': ('image', 'image/png'),
  '.jpg': ('image', 'image/jpeg'),
  '.jpeg': ('image', 'image/jpeg'),
  '.webp': ('image', 'image/webp'),
  '.mp4': ('video', 'video/mp4'),
  '.mov': ('video', 'video/quicktime'),
  '.mkv': ('video', 'video/x-matroska'),
  '.webm': ('video', 'video/webm'),
  '.mp3': ('audio', 'audio/mpeg'),
  '.wav': ('audio', 'audio/wav'),
  '.m4a': ('audio', 'audio/mp4'),
  '.aac': ('audio', 'audio/aac'),
  '.flac': ('audio', 'audio/flac'),
  '.ogg': ('audio', 'audio/ogg'),
};

(String, String)? productionMediaFormat(String path) =>
    productionMediaFormats[p.posix.extension(path).toLowerCase()];

class ProductionMediaFile {
  const ProductionMediaFile(this.path, this.type, this.mimeType);
  final String path;
  final String type;
  final String mimeType;
  String get name => p.posix.basename(path);

  static Future<ProductionMediaFile> read(
    MediaLibraryService library,
    String stored, {
    String? type,
  }) async {
    final path = library.relativePath(stored);
    final format =
        productionMediaFormats[p.posix.extension(path).toLowerCase()];
    if (format == null || (type != null && format.$1 != type)) {
      throw const MediaException(MediaFailure.invalid_media);
    }
    final file = File(library.resolvePath(path));
    if (!await file.exists()) {
      throw const StoryboardException('media_missing');
    }
    final handle = await file.open();
    try {
      if (await handle.length() == 0) {
        throw const MediaException(MediaFailure.invalid_media);
      }
    } finally {
      await handle.close();
    }
    return ProductionMediaFile(path, format.$1, format.$2);
  }
}
