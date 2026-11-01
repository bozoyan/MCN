// 职责: 按受控文件路径共享原尺寸全景纹理，在最后一个租约释放时销毁图像。
// 关联文件:
//   lib/shared/widgets/production/panorama/viewer.dart
//   lib/shared/widgets/production/panorama/capture.dart
import 'dart:ui' as ui;

class PanoramaTexture {
  PanoramaTexture._(this.path, this.image);
  final String path;
  final ui.Image image;
  bool _released = false;
  void dispose() {
    if (!_released) {
      _released = true;
      PanoramaTextures._release(path);
    }
  }
}

class _Entry {
  _Entry(this.image);
  final Future<ui.Image> image;
  int references = 0;
}

class PanoramaTextures {
  static final _entries = <String, _Entry>{};
  static int get activePaths => _entries.length;
  static Future<PanoramaTexture> acquire(String path) async {
    final entry = _entries.putIfAbsent(path, () => _Entry(_decode(path)));
    entry.references++;
    try {
      return PanoramaTexture._(path, await entry.image);
    } catch (_) {
      _release(path);
      rethrow;
    }
  }

  static void _release(String path) {
    final entry = _entries[path];
    if (entry == null) {
      return;
    }
    if (--entry.references == 0) {
      _entries.remove(path);
      entry.image.then(
        (image) => image.dispose(),
        onError: (Object _, StackTrace _) {},
      );
    }
  }

  static Future<ui.Image> _decode(String path) async {
    final buffer = await ui.ImmutableBuffer.fromFilePath(path);
    try {
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      try {
        final codec = await descriptor.instantiateCodec();
        try {
          return (await codec.getNextFrame()).image;
        } finally {
          codec.dispose();
        }
      } finally {
        descriptor.dispose();
      }
    } finally {
      buffer.dispose();
    }
  }
}

class PanoramaShader {
  static Future<ui.FragmentProgram>? _program;
  static Future<ui.FragmentProgram> program() =>
      _program ??= ui.FragmentProgram.fromAsset('shaders/equirect_view.frag');
}
