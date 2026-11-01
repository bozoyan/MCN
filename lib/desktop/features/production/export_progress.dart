// 职责: 展示视频导出进度并在取消后等待复制安全停止。
// 关联文件:
//   lib/shared/services/production/export_orchestrator.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/screenplay.json
//   assets/translations/zh-CN/screenplay.json
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
// 遵循的 Rules:
//   .agents/rules/hooks.md
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import '../../../shared/components/reveric_button.dart';
import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/services/production/export_orchestrator.dart';
import '../../../shared/services/production/ffmpeg_runner.dart';

class ProductionExportProgress extends HookWidget {
  const ProductionExportProgress({
    super.key,
    required this.operation,
    required this.cancellation,
  });
  final Future<ProductionExportReport> operation;
  final MediaCancellation cancellation;
  @override
  Widget build(BuildContext context) {
    final result = useFuture(operation);
    final cancelling = useState(false);
    useEffect(() {
      if (result.hasData) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) {
            Navigator.pop(context, result.data);
          }
        });
      }
      return null;
    }, [result.data]);
    return PopScope(
      canPop: result.hasData,
      child: AlertDialog(
        title: Text(context.t(LocaleKeys.productionExport)),
        content: const SizedBox(
          height: 80,
          child: Center(child: CircularProgressIndicator()),
        ),
        actions: [
          RevericButton.text(
            label: context.t(LocaleKeys.commonCancel),
            loading: cancelling.value,
            onPressed: () async {
              cancelling.value = true;
              await cancellation.cancel();
            },
          ),
        ],
      ),
    );
  }
}
