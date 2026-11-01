// 职责: 保存角色共用音色的音频资产引用与名称。
// 关联文件:
//   lib/shared/database/type_converters.dart
//   lib/shared/database/novel_content_database.dart
//   lib/shared/services/production/voices.dart

class CharacterVoice {
  const CharacterVoice({required this.assetId, this.name = ''});
  final String assetId;
  final String name;

  factory CharacterVoice.fromJson(Object? value) {
    if (value is! Map ||
        value['asset_id'] is! String ||
        (value['asset_id'] as String).trim().isEmpty ||
        value['name'] is! String) {
      throw const FormatException(
        'Voice requires a nonempty asset_id and a name.',
      );
    }
    return CharacterVoice(
      assetId: value['asset_id'] as String,
      name: value['name'] as String,
    );
  }

  Map<String, dynamic> toJson() => {'asset_id': assetId, 'name': name};
  CharacterVoice copyWith({String? name}) =>
      CharacterVoice(assetId: assetId, name: name ?? this.name);

  @override
  bool operator ==(Object other) =>
      other is CharacterVoice && other.assetId == assetId && other.name == name;
  @override
  int get hashCode => Object.hash(assetId, name);
}
