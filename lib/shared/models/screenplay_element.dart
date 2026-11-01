// 职责: 定义剧本文档元素及其字段配对约束。
// 关联文件:
//   lib/shared/database/novel_content_daos/screenplay_dao.dart
//   lib/shared/services/screenplay_service.dart
//   lib/shared/models/screenplay_element_render.dart

enum ScreenplayElementType {
  scene_heading,
  action,
  character,
  parenthetical,
  dialogue,
  transition,
  subtitle,
  note,
}

const screenplayBodyElementTypes = <ScreenplayElementType>[
  ScreenplayElementType.action,
  ScreenplayElementType.character,
  ScreenplayElementType.parenthetical,
  ScreenplayElementType.dialogue,
  ScreenplayElementType.transition,
  ScreenplayElementType.subtitle,
  ScreenplayElementType.note,
];

ScreenplayElementType screenplayElementTypeFromName(String value) {
  for (final type in ScreenplayElementType.values) {
    if (type.name == value) {
      return type;
    }
  }
  throw ArgumentError.value(
    value,
    'type',
    'Unsupported screenplay element type.',
  );
}

class ScreenplayElement {
  const ScreenplayElement({
    this.id,
    this.episodeId,
    this.sceneId,
    this.interiorExterior,
    this.locationId,
    this.timeLabel,
    required this.type,
    this.text = '',
    this.characterId,
    this.extension = '',
  });

  final String? id;
  final String? episodeId;
  final String? sceneId;
  final String? interiorExterior;
  final String? locationId;
  final String? timeLabel;

  bool get isHeading => type == ScreenplayElementType.scene_heading;
  bool get isObject => isHeading || type == ScreenplayElementType.character;
  final ScreenplayElementType type;
  final String text;
  final String? characterId;
  final String extension;

  ScreenplayElement normalized() {
    return ScreenplayElement(
      id: id?.trim().isEmpty == true ? null : id?.trim(),
      episodeId: episodeId,
      sceneId: sceneId,
      interiorExterior: interiorExterior,
      locationId: locationId,
      timeLabel: timeLabel?.trim(),
      type: type,
      text: type == ScreenplayElementType.character ? '' : text,
      characterId: characterId?.trim().isEmpty == true
          ? null
          : characterId?.trim(),
      extension: type == ScreenplayElementType.character
          ? extension.trim()
          : '',
    );
  }

  void validateShape() {
    if (isHeading) {
      if (text.isNotEmpty ||
          characterId != null ||
          extension.isNotEmpty ||
          timeLabel == null ||
          (interiorExterior != null &&
              interiorExterior != 'interior' &&
              interiorExterior != 'exterior' &&
              interiorExterior != 'interior_exterior')) {
        throw const ScreenplayElementValidationException(
          'invalid_element_fields',
          'Invalid scene heading fields.',
        );
      }
      return;
    }
    if (interiorExterior != null || locationId != null || timeLabel != null) {
      throw const ScreenplayElementValidationException(
        'invalid_element_fields',
        'Only scene headings may contain heading fields.',
      );
    }
    if (type == ScreenplayElementType.character && text.isNotEmpty) {
      throw const ScreenplayElementValidationException(
        'invalid_element_fields',
        'Character elements cannot contain text.',
      );
    }
    if (type == ScreenplayElementType.character) {
      if (characterId == null || characterId!.trim().isEmpty) {
        throw const ScreenplayElementValidationException(
          'character_id_required',
          'Character elements require character_id.',
        );
      }
      return;
    }
    if (characterId != null || extension.isNotEmpty) {
      throw const ScreenplayElementValidationException(
        'invalid_element_fields',
        'Only character elements may contain character_id or extension.',
      );
    }
  }

  ScreenplayElement copyWith({
    String? id,
    String? episodeId,
    String? sceneId,
    String? interiorExterior,
    bool clearInteriorExterior = false,
    String? locationId,
    bool clearLocationId = false,
    String? timeLabel,
    ScreenplayElementType? type,
    String? text,
    String? characterId,
    bool clearCharacterId = false,
    String? extension,
  }) {
    return ScreenplayElement(
      id: id ?? this.id,
      episodeId: episodeId ?? this.episodeId,
      sceneId: sceneId ?? this.sceneId,
      interiorExterior: clearInteriorExterior
          ? null
          : interiorExterior ?? this.interiorExterior,
      locationId: clearLocationId ? null : locationId ?? this.locationId,
      timeLabel: timeLabel ?? this.timeLabel,
      type: type ?? this.type,
      text: text ?? this.text,
      characterId: clearCharacterId ? null : characterId ?? this.characterId,
      extension: extension ?? this.extension,
    );
  }
}

class ScreenplayElementValidationException implements Exception {
  const ScreenplayElementValidationException(this.errorCode, this.message);

  final String errorCode;
  final String message;

  @override
  String toString() => '$errorCode: $message';
}

class ScreenplayElementWarning {
  const ScreenplayElementWarning({
    required this.code,
    required this.elementIndex,
    required this.message,
  });

  final String code;
  final int elementIndex;
  final String message;
}
