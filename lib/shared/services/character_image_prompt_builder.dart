// 职责: 为桌面和移动端拼接统一的人物头像、照片生成提示词。
// 关联文件:
//   lib/desktop/widgets/workspace/character_profile_editor.dart
//   lib/mobile/widgets/character_image_actions.dart

String buildCharacterAvatarPrompt({
  required String name,
  required String stylePrompt,
}) =>
    'Avatar portrait: 请为角色「$name」生成头像。\n'
    '先 Read 引用的人物资料，再调用 Run：command=character，subcommand=generate-avatar。'
    'options.character 填该人物的 ID，options.prompt 根据人物外貌设定和以下风格要求编写。'
    '如需查看命令帮助，调用 Run：command=help，subcommand=character。\n\n'
    '风格要求：\n$stylePrompt';

String buildCharacterPhotoPrompt({
  required String name,
  required String stylePrompt,
  required String? avatarAssetId,
}) {
  final reference = avatarAssetId != null && avatarAssetId.isNotEmpty
      ? '\noptions.asset_id 填「$avatarAssetId」，将角色头像作为参考图，严格参考头像中的人物外貌特征（脸型、发型、发色、眼睛等），保持角色形象一致性，确保生成的照片与头像中的是同一人物。'
      : '';
  return 'Character photo: 请为角色「$name」生成照片或插画。\n'
      '先 Read 引用的人物资料，再调用 Run：command=character，subcommand=generate-photo。'
      'options.character 填该人物的 ID，options.prompt 根据人物外貌设定和以下风格要求编写。'
      '如需查看命令帮助，调用 Run：command=help，subcommand=character。'
      '$reference\n\n风格要求：\n$stylePrompt';
}
