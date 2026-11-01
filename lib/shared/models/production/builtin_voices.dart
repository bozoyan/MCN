// 职责: 登记应用随附的角色参考音频及其完整性指纹。
// 关联文件:
//   lib/shared/services/production/builtin_voice_orchestrator.dart
//   lib/desktop/features/production/builtin_voices.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/screenplay.json
//   assets/translations/zh-CN/screenplay.json
import '../../localization/locale_keys.dart';

class BuiltinVoice {
  const BuiltinVoice({
    required this.id,
    required this.nameKey,
    required this.sha256,
    required this.durationMs,
  });

  final String id;
  final String nameKey;
  final String sha256;
  final int durationMs;
  String get bundlePath => 'assets/audio/voices/$id.wav';
}

const productionBuiltinVoices = [
  BuiltinVoice(
    id: 'warm-female',
    nameKey: LocaleKeys.productionVoiceWarmFemale,
    sha256: '296177792f85601d6a978521147cf47eae135852ff531eb584335551077199ca',
    durationMs: 6400,
  ),
  BuiltinVoice(
    id: 'cool-female',
    nameKey: LocaleKeys.productionVoiceCoolFemale,
    sha256: '513cebe9f5e153e6a149fcf37ee4e11fa2a6bd7f8411da709e0a6620f28975b0',
    durationMs: 6400,
  ),
  BuiltinVoice(
    id: 'bright-girl',
    nameKey: LocaleKeys.productionVoiceBrightGirl,
    sha256: '39b723972f4bca894378c964b6abc1bb25c16f31fb5459dba8f226dd40f6efbb',
    durationMs: 6180,
  ),
  BuiltinVoice(
    id: 'clear-boy',
    nameKey: LocaleKeys.productionVoiceClearBoy,
    sha256: '33bd1799be2578f4f959b8083b86f2b0c2de122225e728be53cf31cbc42ba4ec',
    durationMs: 4517,
  ),
  BuiltinVoice(
    id: 'warm-male',
    nameKey: LocaleKeys.productionVoiceWarmMale,
    sha256: 'dcafe536a54699775dd7d95c71cd523d7fa12f9978caa3be05af2503e7143f65',
    durationMs: 6400,
  ),
  BuiltinVoice(
    id: 'deep-male',
    nameKey: LocaleKeys.productionVoiceDeepMale,
    sha256: '3ae0d192b4c4e39422c04d85b121db7a817569c75bef2b557aea13e029926d1e',
    durationMs: 6400,
  ),
  BuiltinVoice(
    id: 'weathered-elder',
    nameKey: LocaleKeys.productionVoiceWeatheredElder,
    sha256: 'a5f0ca1696f54b8a5c370d8a7470fb502a2a1c749bbbb6a32ca3619e20e60ef2',
    durationMs: 6400,
  ),
];
