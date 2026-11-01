// 职责: 承载剧本朗读的配置加载、音色设置与播放界面。
// 关联文件:
//   lib/desktop/features/narration/setup.dart
//   lib/desktop/features/narration/playback.dart
//   lib/shared/providers/narration.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/screenplay.json
//   assets/translations/zh-CN/screenplay.json
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
// 遵循的 Rules:
//   .agents/rules/hooks.md

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../../shared/components/reveric_button.dart';
import '../../../shared/components/reveric_dialog.dart';
import '../../../shared/components/reveric_icon_button.dart';
import '../../../shared/components/reveric_placeholder.dart';
import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/logger/app_logger.dart';
import '../../../shared/models/narration.dart';
import '../../../shared/providers/narration.dart';
import '../../../shared/theme/theme.dart';
import 'playback.dart';
import 'setup.dart';

final _log = AppLogger.forModule('Narration');

class NarrationDialog extends HookConsumerWidget {
  const NarrationDialog({
    super.key,
    required this.workId,
    required this.source,
  });
  final String workId;
  final NarrationSource source;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.watch(narrationServiceProvider);
    final revision = useState(0);
    final loaded = useFuture(
      useMemoized(() => service.load(workId), [
        service,
        workId,
        revision.value,
      ]),
    );
    final plan = useState<NarrationPlan?>(null);
    final settings = useRef<NarrationSettings?>(null);
    useEffect(() {
      if (loaded.hasError) {
        _log.error(
          'configuration load failed',
          error: loaded.error,
          stackTrace: loaded.stackTrace,
        );
      }
      return null;
    }, [loaded.error, loaded.stackTrace]);
    return RevericDialog.panel(
      width: RevericSizes.screenplayPageMaxWidth,
      title: Row(
        children: [
          Expanded(child: Text(context.t(LocaleKeys.narrationTitle))),
          RevericIconButton(
            icon: RevericIcons.close,
            tooltip: context.t(LocaleKeys.commonClose),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
      content: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.6,
        child: loaded.hasError
            ? Center(
                child: RevericPlaceholder.error(
                  title: context.t(LocaleKeys.narrationFailed),
                  action: RevericButton.secondary(
                    label: context.t(LocaleKeys.commonRetry),
                    onPressed: () => revision.value++,
                  ),
                ),
              )
            : !loaded.hasData
            ? const Center(child: CircularProgressIndicator())
            : plan.value == null
            ? NarrationSetup(
                workId: workId,
                source: source,
                initial: settings.value ?? loaded.data!,
                onStart: (next) {
                  settings.value = next.settings;
                  plan.value = next;
                },
              )
            : NarrationPlayback(
                source: source,
                plan: plan.value!,
                onBack: () => plan.value = null,
              ),
      ),
    );
  }
}
