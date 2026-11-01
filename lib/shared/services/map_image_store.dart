// 职责: 地图图片文件存取 — 按 images/maps/{mapId}/map-v{n} 约定写入统一图片目录并回读
// 关联文件:
//   lib/shared/models/map_studio_models.dart
//   lib/shared/services/generate_map_orchestrator.dart
//   lib/shared/services/ai/image.dart
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 地图图像落盘。路径一律以 app 容器根为基准的相对路径存进 NovelMap.settings，
/// 读取时再解析成绝对路径。旧版本文件保留，不做删除。
class MapImageStore {
  static const _imagesRootName = 'images';
  static const _mapsDirectoryName = 'maps';

  Future<Directory> _mapsRoot() async {
    final support = await getApplicationSupportDirectory();
    return Directory(
      p.join(support.path, _imagesRootName, _mapsDirectoryName),
    ).create(recursive: true);
  }

  Directory _mapDir(Directory root, String mapId) =>
      Directory(p.join(root.path, mapId))..createSync(recursive: true);

  /// 保存地图，返回相对路径。
  Future<String> saveMap({
    required String mapId,
    required int version,
    required Uint8List bytes,
    required String mimeSubtype,
  }) {
    return _save(
      mapId: mapId,
      version: version,
      kind: 'map',
      bytes: bytes,
      mimeSubtype: mimeSubtype,
    );
  }

  Future<String> _save({
    required String mapId,
    required int version,
    required String kind,
    required Uint8List bytes,
    required String mimeSubtype,
  }) async {
    final root = await _mapsRoot();
    final dir = _mapDir(root, mapId);
    final ext = mimeSubtype.isEmpty ? 'png' : mimeSubtype;
    final file = File(p.join(dir.path, '$kind-v$version.$ext'));
    await file.writeAsBytes(bytes, flush: true);
    return p.join(
      _imagesRootName,
      _mapsDirectoryName,
      mapId,
      p.basename(file.path),
    );
  }

  Future<File> _resolve(String relativePath) async {
    final support = await getApplicationSupportDirectory();
    return File(p.join(support.path, relativePath));
  }

  /// 读取相对路径指向的图片字节；文件不存在返回 null。
  Future<Uint8List?> read(String relativePath) async {
    try {
      final file = await _resolve(relativePath);
      if (!await file.exists()) return null;
      return await file.readAsBytes();
    } on FileSystemException {
      return null;
    }
  }

  /// 相对路径对应的绝对路径（导出用）。
  Future<String?> absolutePathOf(String relativePath) async {
    final file = await _resolve(relativePath);
    return file.path;
  }
}
