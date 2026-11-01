// 职责: 定义图像模型与渠道共用的能力、请求默认值及字段覆盖规则。
// 关联文件:
//   lib/shared/models/image/catalog.dart
//   lib/shared/models/image/channels.dart
//   lib/shared/models/model_config.dart

import '../model_config.dart';
export '../model_config.dart' show ConfigValue;

class ImageModelCapabilities {
  const ImageModelCapabilities({
    Set<String>? ratios,
    Set<String>? resolutions,
    Map<String, Map<String, String>>? sizes,
    int? minReferences,
    int? maxReferences,
    ConfigValue<int>? minPixels,
    ConfigValue<int>? maxPixels,
    ConfigValue<int>? maxEditPixels,
    ConfigValue<double>? maxAspectRatio,
  }) : _ratios = ratios,
       _resolutions = resolutions,
       _sizes = sizes,
       _minReferences = minReferences,
       _maxReferences = maxReferences,
       _minPixels = minPixels,
       _maxPixels = maxPixels,
       _maxEditPixels = maxEditPixels,
       _maxAspectRatio = maxAspectRatio;

  final Set<String>? _ratios;
  Set<String> get ratios => _ratios ?? const {'auto'};
  final Set<String>? _resolutions;
  Set<String> get resolutions => _resolutions ?? const {'auto'};
  final Map<String, Map<String, String>>? _sizes;
  Map<String, Map<String, String>> get sizes => _sizes ?? const {};
  final int? _minReferences;
  int get minReferences => _minReferences ?? 0;
  final int? _maxReferences;
  int get maxReferences => _maxReferences ?? 0;
  final ConfigValue<int>? _minPixels;
  int? get minPixels => _minPixels?.value;
  final ConfigValue<int>? _maxPixels;
  int? get maxPixels => _maxPixels?.value;
  final ConfigValue<int>? _maxEditPixels;
  int? get maxEditPixels => _maxEditPixels?.value;
  final ConfigValue<double>? _maxAspectRatio;
  double? get maxAspectRatio => _maxAspectRatio?.value;

  ImageModelCapabilities merge(ImageModelCapabilities overrides) =>
      ImageModelCapabilities(
        ratios: overrides._ratios ?? _ratios,
        resolutions: overrides._resolutions ?? _resolutions,
        sizes: overrides._sizes ?? _sizes,
        minReferences: overrides._minReferences ?? _minReferences,
        maxReferences: overrides._maxReferences ?? _maxReferences,
        minPixels: overrides._minPixels ?? _minPixels,
        maxPixels: overrides._maxPixels ?? _maxPixels,
        maxEditPixels: overrides._maxEditPixels ?? _maxEditPixels,
        maxAspectRatio: overrides._maxAspectRatio ?? _maxAspectRatio,
      );

  String? size(String ratio, String resolution) {
    if (!ratios.contains(ratio) || !resolutions.contains(resolution)) {
      throw const FormatException('Unsupported image specification');
    }
    return sizes[resolution]?[ratio];
  }

  void validateReferences(int count) {
    if (count < minReferences || count > maxReferences) {
      throw const FormatException('Unsupported image reference count');
    }
  }

  void validateSize(String? size, {int references = 0}) {
    if (size == null || size == 'auto') {
      return;
    }
    if (resolutions.contains(size)) {
      // Check a tier's pixel budget as well as explicit dimensions.
      final dimensions = sizes[size]?['1:1'];
      if (dimensions == null) {
        return;
      }
      size = dimensions;
    }
    final match = RegExp(r'^([1-9][0-9]*)x([1-9][0-9]*)$').firstMatch(size);
    if (match == null) {
      throw const FormatException('Unsupported image size');
    }
    final width = int.parse(match[1]!);
    final height = int.parse(match[2]!);
    final pixels = width * height;
    if ((minPixels != null && pixels < minPixels!) ||
        (maxPixels != null && pixels > maxPixels!) ||
        (references > 0 && maxEditPixels != null && pixels > maxEditPixels!) ||
        (maxAspectRatio != null &&
            (width / height > maxAspectRatio! ||
                height / width > maxAspectRatio!))) {
      throw const FormatException('Unsupported image dimensions');
    }
  }
}

class ImageRequestDefaults {
  const ImageRequestDefaults({
    ConfigValue<String>? size,
    ConfigValue<String>? responseFormat,
    ConfigValue<String>? outputFormat,
    ConfigValue<String>? quality,
    ConfigValue<bool>? watermark,
    ConfigValue<bool>? promptExtend,
    ConfigValue<String>? promptOptimization,
  }) : _size = size,
       _responseFormat = responseFormat,
       _outputFormat = outputFormat,
       _quality = quality,
       _watermark = watermark,
       _promptExtend = promptExtend,
       _promptOptimization = promptOptimization;

  final ConfigValue<String>? _size;
  String? get size => _size?.value;
  final ConfigValue<String>? _responseFormat;
  String? get responseFormat => _responseFormat?.value;
  final ConfigValue<String>? _outputFormat;
  String? get outputFormat => _outputFormat?.value;
  final ConfigValue<String>? _quality;
  String? get quality => _quality?.value;
  final ConfigValue<bool>? _watermark;
  bool? get watermark => _watermark?.value;
  final ConfigValue<bool>? _promptExtend;
  bool? get promptExtend => _promptExtend?.value;
  final ConfigValue<String>? _promptOptimization;
  String? get promptOptimization => _promptOptimization?.value;

  ImageRequestDefaults merge(ImageRequestDefaults overrides) =>
      ImageRequestDefaults(
        size: overrides._size ?? _size,
        responseFormat: overrides._responseFormat ?? _responseFormat,
        outputFormat: overrides._outputFormat ?? _outputFormat,
        quality: overrides._quality ?? _quality,
        watermark: overrides._watermark ?? _watermark,
        promptExtend: overrides._promptExtend ?? _promptExtend,
        promptOptimization:
            overrides._promptOptimization ?? _promptOptimization,
      );
}
