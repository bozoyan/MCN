// 职责: 校验并序列化统一媒体资产的版本化内容规格。
// 关联文件:
//   lib/shared/database/type_converters.dart
//   lib/shared/services/production/asset_service.dart

const fileAssetTypes = ['image', 'video', 'audio'];

sealed class AssetContent {
  const AssetContent();
  String get kind;
  Map<String, dynamic> toJson();

  factory AssetContent.fromJson(Map<String, dynamic> data) {
    if (data['version'] != 1 || !fileAssetTypes.contains(data['kind'])) {
      throw const FormatException('Unsupported asset content');
    }
    final kind = data['kind'];
    final generation = data['generation'] == null
        ? null
        : AssetGeneration.fromJson(data['generation'] as Map<String, dynamic>);
    return switch (kind) {
      'image' => ImageAssetContent(
        mimeType: data['mime_type'] as String?,
        bytes: data['bytes'] as int?,
        width: data['width'] as int?,
        height: data['height'] as int?,
        generation: generation,
      ),
      'video' => VideoAssetContent(
        mimeType: data['mime_type'] as String?,
        bytes: data['bytes'] as int?,
        width: data['width'] as int?,
        height: data['height'] as int?,
        durationMs: data['duration_ms'] as int?,
        generation: generation,
      ),
      'audio' => AudioAssetContent(
        mimeType: data['mime_type'] as String?,
        bytes: data['bytes'] as int?,
        durationMs: data['duration_ms'] as int?,
        generation: generation,
      ),
      _ => throw const FormatException('Unsupported asset content'),
    };
  }
}

class AssetGeneration {
  const AssetGeneration({this.prompt, this.model});
  final String? prompt;
  final String? model;
  factory AssetGeneration.fromJson(Map<String, dynamic> json) =>
      AssetGeneration(
        prompt: json['prompt'] as String?,
        model: json['model'] as String?,
      );
  Map<String, dynamic> toJson() => {'prompt': prompt, 'model': model};
}

sealed class MediaAssetContent extends AssetContent {
  const MediaAssetContent({this.mimeType, this.bytes, this.generation});
  final String? mimeType;
  final int? bytes;
  final AssetGeneration? generation;
  @override
  Map<String, dynamic> toJson() => {
    'version': 1,
    'kind': kind,
    'mime_type': mimeType,
    'bytes': bytes,
    if (generation != null) 'generation': generation!.toJson(),
  };
}

final class ImageAssetContent extends MediaAssetContent {
  const ImageAssetContent({
    super.mimeType,
    super.bytes,
    super.generation,
    this.width,
    this.height,
  });
  final int? width;
  final int? height;
  @override
  String get kind => 'image';
  @override
  Map<String, dynamic> toJson() => {
    ...super.toJson(),
    'width': width,
    'height': height,
  };
}

final class VideoAssetContent extends MediaAssetContent {
  const VideoAssetContent({
    super.mimeType,
    super.bytes,
    super.generation,
    this.width,
    this.height,
    this.durationMs,
  });
  final int? width;
  final int? height;
  final int? durationMs;
  @override
  String get kind => 'video';
  @override
  Map<String, dynamic> toJson() => {
    ...super.toJson(),
    'width': width,
    'height': height,
    'duration_ms': durationMs,
  };
}

final class AudioAssetContent extends MediaAssetContent {
  const AudioAssetContent({
    super.mimeType,
    super.bytes,
    super.generation,
    this.durationMs,
  });
  final int? durationMs;
  @override
  String get kind => 'audio';
  @override
  Map<String, dynamic> toJson() => {
    ...super.toJson(),
    'duration_ms': durationMs,
  };
}
