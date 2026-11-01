// 职责: 共享内置道具 GLB 模板，统一坐标系供渲染器克隆实例。
// 关联文件:
//   lib/shared/services/director/scene_builder.dart
//   lib/shared/models/director/document.dart
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import '../../models/director/presets.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart' as v;
import '../../models/director/document.dart';

class PropModels {
  // 内置资源随应用打包且不可变；按需缓存至多 propModelAssets.length 个模板。
  // 缓存 Future 同时合并主视口、预览和导出的并发加载；场景只使用克隆实例。
  static final _bundled = <String, Future<Node>>{};

  static Future<Node> _loadBundled(String path) => _bundled.putIfAbsent(
    path,
    () => rootBundle
        .load(path)
        .then(
          (data) => _decode(
            data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          ),
        )
        .catchError((Object error, StackTrace stack) {
          _bundled.remove(path);
          Error.throwWithStackTrace(error, stack);
        }),
  );

  static Future<Map<String, Node>> load(DirectorDocument document) async {
    final models = <String, Node>{};
    for (final object in document.objects) {
      final geometry = object['geometry_key'] as String;
      final bundled = propModelAssets[geometry];
      if (bundled != null && !models.containsKey(geometry)) {
        models[geometry] = await _loadBundled(bundled);
      }
    }
    return models;
  }

  static Future<Node> _decode(Uint8List bytes) async {
    validatePropGlb(bytes);
    final model = await Node.fromGlbBytes(bytes, maxTextureSize: 2048);
    model.localTransform = v.Matrix4.identity();
    void reverse(Node node) {
      for (final primitive in node.mesh?.primitives ?? <MeshPrimitive>[]) {
        final geometry = primitive.geometry;
        // GLB 导入器返回 UnskinnedGeometry；MeshGeometry 只是其程序化子类。
        if (geometry is! UnskinnedGeometry || !geometry.isReadable) {
          throw StateError('unsupported_prop_geometry');
        }
        final mesh = geometry.extractMeshData();
        final indices = mesh.indices == null
            ? List.generate(mesh.positions.length ~/ 3, (i) => i)
            : List<int>.from(mesh.indices!);
        if (indices.length % 3 != 0) {
          throw StateError('unsupported_prop_geometry');
        }
        for (var i = 0; i < indices.length; i += 3) {
          final v = indices[i + 1];
          indices[i + 1] = indices[i + 2];
          indices[i + 2] = v;
        }
        primitive.geometry = MeshGeometry.fromArrays(
          positions: mesh.positions,
          normals: mesh.normals,
          texCoords: mesh.texCoords,
          texCoords1: mesh.texCoords1,
          colors: mesh.colors,
          tangents: mesh.tangents,
          indices: indices,
        );
      }
      node.children.forEach(reverse);
    }

    reverse(model);
    return model;
  }
}

void validatePropGlb(Uint8List bytes) {
  if (bytes.length < 20) {
    throw const FormatException('Invalid GLB');
  }
  final header = ByteData.sublistView(bytes);
  if (header.getUint32(0, Endian.little) != 0x46546c67 ||
      header.getUint32(4, Endian.little) != 2 ||
      header.getUint32(8, Endian.little) != bytes.length ||
      header.getUint32(16, Endian.little) != 0x4e4f534a) {
    throw const FormatException('Invalid GLB header');
  }
  final length = header.getUint32(12, Endian.little);
  if (20 + length > bytes.length) {
    throw const FormatException('Invalid GLB JSON');
  }
  final gltf =
      jsonDecode(utf8.decode(bytes.sublist(20, 20 + length)))
          as Map<String, dynamic>;
  for (final entry in [
    ...?gltf['buffers'] as List?,
    ...?gltf['images'] as List?,
  ]) {
    if (entry['uri'] != null) {
      throw const FormatException('Use embedded GLB buffers and textures');
    }
  }
  if ((gltf['skins'] as List?)?.isNotEmpty == true ||
      (gltf['animations'] as List?)?.isNotEmpty == true) {
    throw const FormatException('Props must use static geometry');
  }
  if ((gltf['meshes'] as List?)?.isNotEmpty != true) {
    throw const FormatException('Prop requires a mesh');
  }
}
