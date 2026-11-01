// 职责: 在制作工作区内切换剪辑区域并统一注册两个区域的离开保存保护。
// 关联文件:
//   lib/desktop/features/editing/region.dart
//   lib/desktop/features/production/region.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
// 遵循的 Rules:
//   .agents/rules/hooks.md
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'region.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../../shared/providers/novel_providers.dart';
import '../../../shared/services/production/editing_orchestrator.dart';
import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/widgets/screenplay/loading.dart';

class EditingShell extends HookConsumerWidget {
  const EditingShell({
    super.key,
    required this.novelId,
    required this.identity,
    required this.registerFlush,
    required this.builder,
  });
  final String novelId;
  final ({String path, String episodeId}) identity;
  final ValueChanged<Future<void> Function()?> registerFlush;
  final Widget Function(
    VoidCallback open,
    ValueChanged<Future<void> Function()?> register,
  )
  builder;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(novelContentDatabaseProvider(identity.path));
    final editing = useFuture(
      useMemoized(
        () => EpisodeEditingOrchestrator().ensureEpisodeEditing(
          db,
          identity.episodeId,
        ),
        [db, identity],
      ),
    );
    final opened = useState(false);
    final productionFlush = useRef<Future<void> Function()?>(null);
    final editingFlush = useRef<Future<void> Function()?>(null);
    final registration = useRef(registerFlush)..value = registerFlush;
    useEffect(() {
      opened.value = false;
      return null;
    }, [identity]);
    useEffect(() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          registration.value(() async {
            await editingFlush.value?.call();
            await productionFlush.value?.call();
          });
        }
      });
      return () => registration.value(null);
    }, const []);
    if (editing.hasError) {
      return Center(child: Text(context.t(LocaleKeys.commonLoadFailed)));
    }
    if (!editing.hasData) {
      return const ScreenplayLoading();
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        ExcludeFocus(
          excluding: opened.value,
          child: Offstage(
            offstage: opened.value,
            child: builder(
              () => opened.value = true,
              (flush) => productionFlush.value = flush,
            ),
          ),
        ),
        if (opened.value)
          EditingRegion(
            key: ValueKey(identity),
            novelId: novelId,
            identity: identity,
            editingId: editing.data!.editing.id,
            onClose: () => opened.value = false,
            registerFlush: (flush) => editingFlush.value = flush,
          ),
      ],
    );
  }
}
