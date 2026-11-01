// 职责: 校验剧本制作设置并从画幅和分辨率派生输出尺寸。
// 关联文件:
//   lib/shared/database/novel_content_database.dart
//   lib/shared/services/storyboard/service.dart
import '../../database/novel_content_database.dart';

abstract final class ProductionSettings {
  static const ratios = ['21:9', '16:9', '4:3', '1:1', '3:4', '9:16'];
  static const resolutions = ['480p', '720p', '1080p', '2160p'];
  static void validate(String ratio, String resolution) {
    if (!ratios.contains(ratio) || !resolutions.contains(resolution)) {
      throw const FormatException('Unsupported ratio or resolution.');
    }
  }

  static (int, int) dimensions(String ratio, String resolution) {
    validate(ratio, resolution);
    final sides = ratio.split(':').map(int.parse).toList();
    final shortSide = int.parse(resolution.substring(0, resolution.length - 1));
    int even(double value) => (value / 2).round() * 2;
    return sides[0] >= sides[1]
        ? (even(shortSide * sides[0] / sides[1]), shortSide)
        : (shortSide, even(shortSide * sides[1] / sides[0]));
  }
}

extension ScreenplayOutputSize on ScreenplayRow {
  int get width => ProductionSettings.dimensions(ratio, resolution).$1;
  int get height => ProductionSettings.dimensions(ratio, resolution).$2;
}
