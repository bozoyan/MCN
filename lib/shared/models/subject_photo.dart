// 职责: 保存角色、地点或物品照片引用的图片资产与可选名称。
// 关联文件:
//   lib/shared/database/type_converters.dart
//   lib/shared/database/novel_content_database.dart
//   lib/shared/services/production/canvas_service.dart

class SubjectPhoto {
  const SubjectPhoto({required this.assetId, this.name = ''});

  final String assetId;
  final String name;

  /// 照片使用资产 id 引用，并保存可选显示名称。
  factory SubjectPhoto.fromJson(Object? value) {
    if (value is! Map ||
        value['asset_id'] is! String ||
        value['name'] is! String) {
      throw const FormatException('Photo requires string asset_id and name.');
    }
    return SubjectPhoto(
      assetId: value['asset_id'] as String,
      name: value['name'] as String,
    );
  }

  Map<String, dynamic> toJson() => {'asset_id': assetId, 'name': name};

  SubjectPhoto copyWith({String? assetId, String? name}) =>
      SubjectPhoto(assetId: assetId ?? this.assetId, name: name ?? this.name);

  @override
  bool operator ==(Object other) =>
      other is SubjectPhoto && other.assetId == assetId && other.name == name;

  @override
  int get hashCode => Object.hash(assetId, name);
}
