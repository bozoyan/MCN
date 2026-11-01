// 职责: NovelState 模型导出与扩展方法
// 关联文件:
//   lib/shared/database/novel_content_database.dart

import '../database/novel_content_database.dart';

export '../database/novel_content_database.dart'
    show NovelState, NovelStates, NovelStatesCompanion;

extension NovelStateX on NovelState {
  bool get isIdle => status == 'idle';

  bool get isRunning => status == 'running';

  bool get isPaused => status == 'paused';

  bool get isError => status == 'error';

  bool get hasData => data != null && data!.isNotEmpty;
}
