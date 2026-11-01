// 职责: 装配朗读配置服务并复用用户配置的音频供应商调用。
// 关联文件:
//   lib/shared/services/screenplay/narration_service.dart
//   lib/shared/providers/production_audio.dart
//   lib/shared/providers/novel_providers.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/screenplay/narration_service.dart';
import 'novel_providers.dart';
import 'production_audio.dart';

final narrationServiceProvider = Provider<NarrationService>(
  (ref) => NarrationService(
    database: ref.watch(appDatabaseProvider),
    invoke: ref.watch(productionAudioInvokeProvider),
    query: ref.watch(productionAudioQueryProvider),
  ),
);
