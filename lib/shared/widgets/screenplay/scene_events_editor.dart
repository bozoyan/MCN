// 职责: 编辑有序场次事件，提供折叠、增删和顺序调整。
// 关联文件:
//   lib/shared/widgets/screenplay/scene_properties_form.dart
//   lib/shared/components/reveric_text_field.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/screenplay.json
//   assets/translations/zh-CN/screenplay.json
// 遵循的 Rules:
//   .agents/rules/hooks.md
//   .agents/rules/form.md
//   .agents/rules/text-input-ime.md

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import '../../components/reveric_text_field.dart';
import '../../localization/app_localization.dart';
import '../../localization/locale_keys.dart';
import '../../theme/theme.dart';

class SceneEventsEditor extends HookWidget {
  const SceneEventsEditor({
    super.key,
    required this.events,
    required this.onChanged,
  });
  final List<Map<String, dynamic>> events;
  final ValueChanged<List<Map<String, dynamic>>> onChanged;

  @override
  Widget build(BuildContext context) {
    final keys = useMemoized(
      () => [for (final _ in events) UniqueKey()],
      const [],
    );
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);

    void update(int index, Map<String, dynamic> updated) {
      final next = [...events];
      next[index] = updated;
      onChanged(next);
    }

    void move(int index, int offset) {
      final next = [...events];
      final event = next.removeAt(index);
      next.insert(index + offset, event);
      final key = keys.removeAt(index);
      keys.insert(index + offset, key);
      onChanged(next);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (events.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: RevericSpacing.md),
            child: Text(
              context.t(LocaleKeys.screenplaySceneEventsEmpty),
              style: typo.uiSmall.copyWith(color: colors.textMuted),
            ),
          ),
        for (final (index, event) in events.indexed)
          Padding(
            key: keys[index],
            padding: const EdgeInsets.only(bottom: RevericSpacing.sm),
            child: _SceneEventItem(
              index: index,
              event: event,
              isFirst: index == 0,
              isLast: index == events.length - 1,
              onChanged: (updated) => update(index, updated),
              onMoveUp: () => move(index, -1),
              onMoveDown: () => move(index, 1),
              onDelete: () {
                keys.removeAt(index);
                onChanged([...events]..removeAt(index));
              },
            ),
          ),
        OutlinedButton.icon(
          onPressed: () {
            keys.add(UniqueKey());
            onChanged([
              ...events,
              {'title': '', 'summary': ''},
            ]);
          },
          icon: const RevericIcon(RevericIcons.add, size: 16),
          label: Text(context.t(LocaleKeys.screenplaySceneEventAdd)),
        ),
      ],
    );
  }
}

class _SceneEventItem extends HookWidget {
  const _SceneEventItem({
    required this.index,
    required this.event,
    required this.isFirst,
    required this.isLast,
    required this.onChanged,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onDelete,
  });

  final int index;
  final Map<String, dynamic> event;
  final bool isFirst;
  final bool isLast;
  final ValueChanged<Map<String, dynamic>> onChanged;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);

    final titleController = useTextEditingController(
      text: event['title'] as String? ?? '',
    );
    final summaryController = useTextEditingController(
      text: event['summary'] as String? ?? '',
    );
    final stateChangeController = useTextEditingController(
      text: event['state_change'] as String? ?? '',
    );

    useEffect(() {
      final currentTitle = event['title'] as String? ?? '';
      if (titleController.text != currentTitle) {
        titleController.text = currentTitle;
      }
      final currentSummary = event['summary'] as String? ?? '';
      if (summaryController.text != currentSummary) {
        summaryController.text = currentSummary;
      }
      final currentStateChange = event['state_change'] as String? ?? '';
      if (stateChangeController.text != currentStateChange) {
        stateChangeController.text = currentStateChange;
      }
      return null;
    }, [event['title'], event['summary'], event['state_change']]);

    final title = (event['title'] as String? ?? '').trim();
    final hasTitle = title.isNotEmpty;
    final displayTitle = hasTitle
        ? title
        : context.t(
            LocaleKeys.screenplaySceneEventNumber,
            namedArgs: {'number': '${index + 1}'},
          );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceContainerHigh,
        border: Border.all(color: colors.borderInput),
        borderRadius: BorderRadius.circular(RevericRadius.large),
      ),
      child: ExpansionTile(
        initiallyExpanded: index == 0,
        maintainState: true,
        shape: const Border(),
        collapsedShape: const Border(),
        title: Text(
          displayTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: typo.uiSemibold.copyWith(
            color: hasTitle ? colors.textPrimary : colors.textMuted,
          ),
        ),
        trailing: const RevericIcon(RevericIcons.expand_more, size: 18),
        childrenPadding: const EdgeInsets.fromLTRB(
          RevericSpacing.md,
          0,
          RevericSpacing.md,
          RevericSpacing.xs,
        ),
        children: [
          RevericTextField(
            controller: titleController,
            hintText: context.t(LocaleKeys.screenplaySceneEventTitle),
            onChanged: (value) => onChanged({...event, 'title': value}),
          ),
          const SizedBox(height: RevericSpacing.sm),
          RevericTextField(
            controller: summaryController,
            multiline: true,
            minLines: 2,
            maxLines: 4,
            hintText: context.t(LocaleKeys.screenplaySceneEventSummary),
            onChanged: (value) => onChanged({...event, 'summary': value}),
          ),
          const SizedBox(height: RevericSpacing.sm),
          RevericTextField(
            controller: stateChangeController,
            multiline: true,
            minLines: 1,
            maxLines: 3,
            hintText: context.t(LocaleKeys.screenplaySceneStateChange),
            onChanged: (value) => onChanged({...event, 'state_change': value}),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              IconButton(
                tooltip: context.t(LocaleKeys.screenplayMoveUp),
                onPressed: isFirst ? null : onMoveUp,
                icon: RevericIcon(
                  RevericIcons.arrow_upward_rounded,
                  size: 18,
                  color: isFirst ? colors.textSubtle : colors.textMuted,
                ),
              ),
              IconButton(
                tooltip: context.t(LocaleKeys.screenplayMoveDown),
                onPressed: isLast ? null : onMoveDown,
                icon: RevericIcon(
                  RevericIcons.arrow_downward_rounded,
                  size: 18,
                  color: isLast ? colors.textSubtle : colors.textMuted,
                ),
              ),
              IconButton(
                tooltip: context.t(LocaleKeys.commonDelete),
                onPressed: onDelete,
                icon: RevericIcon(
                  RevericIcons.delete_outline,
                  size: 18,
                  color: colors.deletionBorder,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
