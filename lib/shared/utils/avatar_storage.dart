// 职责: 本地头像落盘 — 把用户选中的图片复制到应用支持目录，返回可持久保存的路径。
// 关联文件:
//   lib/shared/utils/storage_paths.dart
//   lib/shared/widgets/user_profile_edit_dialog.dart
//   lib/shared/hooks/use_onboarding_setup.dart
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'storage_paths.dart';

/// 把 [sourcePath] 复制到 `<appSupport>/avatars/avatar.<ext>`。
///
/// 直接存用户原文件路径的话，原图被移动/删除后头像就失效了。
/// 返回值已过 [RevericPaths.toRelative]，可直接写入设置。
Future<String> storeAvatarFile(String sourcePath) async {
  final appDir = await getApplicationSupportDirectory();
  final avatarDir = Directory(p.join(appDir.path, 'avatars'));
  if (!await avatarDir.exists()) {
    await avatarDir.create(recursive: true);
  }
  final dest = p.join(avatarDir.path, 'avatar${p.extension(sourcePath)}');
  await File(sourcePath).copy(dest);
  return RevericPaths.toRelative(dest) ?? dest;
}
