// 职责: 首次启动引导的跨端状态 — 静默应用默认配置、恢复或随机生成称呼、保存资料、完成引导。
// 关联文件:
//   lib/desktop/pages/onboarding.dart
//   lib/mobile/pages/onboarding_page.dart
//   lib/shared/providers/settings_providers.dart
//   lib/shared/providers/official_skill_sync_providers.dart
//   lib/shared/services/app_initialization.dart
//   lib/shared/utils/ai_nickname.dart
// 遵循的 Rules:
//   .agents/rules/hooks.md
//   .agents/rules/state-management.md
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../providers/official_skill_sync_providers.dart';
import '../providers/novel_providers.dart';
import '../providers/settings_providers.dart';
import '../services/app_initialization.dart';
import '../utils/ai_nickname.dart';

class OnboardingSetup {
  const OnboardingSetup({
    required this.nameController,
    required this.avatarPath,
    required this.defaultsReady,
    required this.saveProfile,
    required this.complete,
  });

  /// 「AI 怎么称呼您」— 本地称呼，与账户用户名无关。
  final TextEditingController nameController;

  /// 已落盘的头像路径（相对或绝对），由调用方选图后写入。
  final ValueNotifier<String?> avatarPath;

  /// 默认主题与模型是否已应用。
  final bool defaultsReady;

  final Future<void> Function() saveProfile;

  /// 保存资料并标记引导完成；导航由调用方负责。
  final Future<void> Function() complete;
}

OnboardingSetup useOnboardingSetup(WidgetRef ref) {
  final context = useContext();
  final settingsNotifier = ref.read(appSettingsProvider.notifier);
  final settingsAsync = ref.watch(appSettingsProvider);
  final nameController = useTextEditingController();
  final avatarPath = useState<String?>(null);
  final defaultsReady = useState(false);
  final profileSeeded = useRef(false);

  // 与应用启动共用官方技能同步；多处读取只执行同一轮。
  useEffect(() {
    unawaited(
      Future<void>(() {
        ref.read(officialSkillSyncProvider);
      }),
    );
    return null;
  }, []);

  useEffect(() {
    () async {
      await settingsNotifier.applyOnboardingDefaults(
        theme: AppTheme.classic,
        themeMode: AppThemeMode.system,
      );
      defaultsReady.value = true;
    }();
    return null;
  }, []);

  // 恢复上次保存的称呼与头像（例如重置 onboarding 后再次进入）；
  // 首次打开没有称呼时随机生成一个，用户不改也能直接开始。
  useEffect(() {
    final settings = settingsAsync.asData?.value;
    if (settings == null || profileSeeded.value) {
      return null;
    }
    profileSeeded.value = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) {
        return;
      }
      if (nameController.text.isEmpty) {
        nameController.text = settings.username.isNotEmpty
            ? settings.username
            : randomAiNickname(Localizations.localeOf(context));
      }
      if (avatarPath.value == null && settings.avatarPath.isNotEmpty) {
        avatarPath.value = settings.avatarPath;
      }
    });
    return null;
  }, [settingsAsync.asData?.value]);

  Future<void> saveProfile() async {
    await settingsNotifier.setUsername(nameController.text.trim());
    final avatar = avatarPath.value;
    if (avatar != null && avatar.isNotEmpty) {
      await settingsNotifier.setAvatarPath(avatar);
    }
  }

  Future<void> complete() async {
    await saveProfile();
    await markOnboardingCompleted(ref.read(appDatabaseProvider));
  }

  return OnboardingSetup(
    nameController: nameController,
    avatarPath: avatarPath,
    defaultsReady: defaultsReady.value,
    saveProfile: saveProfile,
    complete: complete,
  );
}
