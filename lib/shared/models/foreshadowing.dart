// 职责: Foreshadowing 模型导出、表单字段枚举与扩展方法
// 关联文件:
//   lib/shared/database/novel_content_database.dart

import '../../third/form/flutter_hook_form.dart';
import '../database/novel_content_database.dart';
import '../utils/utf16_safe_text.dart';

export '../database/novel_content_database.dart'
    show
        Foreshadowing,
        Foreshadowings,
        ForeshadowingsCompanion,
        foreshadowingStatusPending,
        foreshadowingStatusPlanted,
        foreshadowingStatusPayoff,
        foreshadowingStatusAbandoned,
        foreshadowingStatuses;

enum ForeshadowingEditFields implements FieldSchema {
  title(validators: [RequiredValidator()]),
  setup(initialValue: ''),
  payoff(initialValue: ''),
  status(initialValue: foreshadowingStatusPending);

  const ForeshadowingEditFields({this.validators, this.initialValue});

  final dynamic initialValue;

  @override
  final List<Validator<dynamic>>? validators;
}

extension ForeshadowingX on Foreshadowing {
  String get normalizedStatus => foreshadowingStatuses.contains(status)
      ? status
      : foreshadowingStatusPending;

  bool get isPending => normalizedStatus == foreshadowingStatusPending;

  bool get isPlanted => normalizedStatus == foreshadowingStatusPlanted;

  bool get isPayoff => normalizedStatus == foreshadowingStatusPayoff;

  bool get isAbandoned => normalizedStatus == foreshadowingStatusAbandoned;

  bool get hasSetup => setup.trim().isNotEmpty;

  bool get hasPayoff => payoff.trim().isNotEmpty;

  String get setupSummary {
    return _preview(setup);
  }

  String get payoffSummary {
    return _preview(payoff);
  }
}

String _preview(String value) {
  return truncateUtf16Safe(value.trim(), 200);
}

extension ForeshadowingListX on List<Foreshadowing> {
  List<Foreshadowing> get sorted =>
      [...this]..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

  List<Foreshadowing> get enabled =>
      where((f) => f.deletedAt == notDeletedSentinel).toList();
}
