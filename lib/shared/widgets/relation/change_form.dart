// 职责: 管理关系新增、剧情变化与录入修正的独立表单会话。
// 关联文件:
//   lib/shared/services/entity_relations_service.dart
//   lib/shared/widgets/relation/providers.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/relation.json
//   assets/translations/zh-CN/relation.json
//   assets/translations/en/relation_dialog.json
//   assets/translations/zh-CN/relation_dialog.json
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
// 遵循的 Rules:
//   .agents/rules/hooks.md
//   .agents/rules/design-system.md
//   .agents/rules/state-management.md
//   .agents/rules/form.md
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../components/reveric_button.dart';
import '../../components/reveric_select.dart';
import '../../database/novel_content_database.dart';
import '../../entity_graph/providers.dart';
import '../../entity_graph/colors.dart';
import '../../entity_graph/labels.dart';
import '../../entity_graph/data.dart';
import '../../form/form.dart';
import '../../localization/app_localization.dart';
import '../../localization/locale_keys.dart';
import '../../theme/theme.dart';
import '../../utils/entity_relation_types.dart';
import '../entity_search_selector.dart';
import 'evidence.dart';
import 'providers.dart';
import 'support.dart';

enum RelationFormIntent { create, change, correct, end, restore }

class RelationFormRequest {
  const RelationFormRequest({
    required this.intent,
    this.relation,
    this.source,
    this.target,
  });
  final RelationFormIntent intent;
  final EntityRelation? relation;
  final (String, String)? source;
  final (String, String)? target;
}

String relationFormTitle(BuildContext context, RelationFormIntent intent) =>
    context.t(switch (intent) {
      RelationFormIntent.create => LocaleKeys.relationCreate,
      RelationFormIntent.change => LocaleKeys.relationRecordChange,
      RelationFormIntent.correct => LocaleKeys.relationCorrectRecord,
      RelationFormIntent.end => LocaleKeys.relationEndRelation,
      RelationFormIntent.restore => LocaleKeys.relationRestoreRelation,
    });

enum RelationFormField<T> implements FieldSchema {
  sourceType<String>(),
  sourceId<String>(),
  targetType<String>(),
  targetId<String>(),
  relationType<String>(),
  status<String>(),
  proof<String>(),
  reason<String>(),
  evidence<String>();

  const RelationFormField();
  @override
  List<Validator<dynamic>>? get validators => null;
}

class RelationChangeForm extends HookConsumerWidget {
  const RelationChangeForm({
    super.key,
    required this.databasePath,
    required this.request,
    this.onSaved,
  });
  final String databasePath;
  final RelationFormRequest request;
  final VoidCallback? onSaved;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final original = request.relation;
    final expected = useState(original);
    final busy = useState(false);
    final failure = useState<String?>(null);
    final conflict = useState(false);
    final correcting = request.intent == RelationFormIntent.correct;
    final creating = request.intent == RelationFormIntent.create;
    final initialSource =
        original?.sourceType ?? request.source?.$1 ?? 'character';
    final initialTarget =
        original?.targetType ?? request.target?.$1 ?? 'character';
    final initialStatus = switch (request.intent) {
      RelationFormIntent.end => 'ended',
      RelationFormIntent.restore => 'active',
      _ => original?.status ?? 'active',
    };
    final form = useForm<RelationFormField>(
      initialValues: {
        RelationFormField.sourceType: initialSource,
        RelationFormField.sourceId:
            original?.sourceId ?? request.source?.$2 ?? '',
        RelationFormField.targetType: initialTarget,
        RelationFormField.targetId:
            original?.targetId ?? request.target?.$2 ?? '',
        RelationFormField.relationType:
            original?.relationType ??
            validRelationTypesFor(initialSource, initialTarget).firstOrNull ??
            '',
        RelationFormField.status: initialStatus,
        RelationFormField.proof: correcting ? original?.proof ?? '' : '',
        RelationFormField.reason: '',
        RelationFormField.evidence: correcting && original != null
            ? original.chapterId != null
                  ? 'chapter:${original.chapterId}'
                  : original.sceneId != null
                  ? 'scene:${original.sceneId}'
                  : ''
            : '',
      },
      keys: [original?.id, request.intent],
    );
    String value(RelationFormField field) => form.getValue<String>(field) ?? '';
    final source = original?.sourceType ?? value(RelationFormField.sourceType);
    final target = original?.targetType ?? value(RelationFormField.targetType);
    final allowed = validRelationTypesFor(source, target);
    final service = ref.watch(entityRelationsServiceProvider(databasePath));
    final choices = ref.watch(relationEvidenceChoicesProvider(databasePath));
    final typo = RevericTheme.typographyOf(context);
    final colors = RevericTheme.colorsOf(context);
    final selectHeight = _selectHeight(context);

    Future<void> submit() async {
      if (busy.value || conflict.value || allowed.isEmpty) {
        return;
      }
      var valid = form.validate();
      for (final field in [
        if (creating) ...[
          RelationFormField.sourceId,
          RelationFormField.targetId,
        ],
        if (!correcting ||
            value(RelationFormField.proof) != expected.value?.proof)
          RelationFormField.proof,
        if (!creating && !correcting) RelationFormField.reason,
      ]) {
        if (value(field).trim().isEmpty) {
          form.setError(field, context.t(LocaleKeys.relationRequired));
          valid = false;
        }
      }
      if (!valid) {
        return;
      }
      busy.value = true;
      failure.value = null;
      final location = value(RelationFormField.evidence);
      final chapter = location.startsWith('chapter:')
          ? location.substring(8)
          : null;
      final scene = location.startsWith('scene:')
          ? location.substring(6)
          : null;
      try {
        if (creating) {
          await service.createRelation(
            sourceType: source,
            sourceId: value(RelationFormField.sourceId),
            targetType: target,
            targetId: value(RelationFormField.targetId),
            relationType: value(RelationFormField.relationType),
            status: value(RelationFormField.status),
            proof: value(RelationFormField.proof),
            chapterId: chapter,
            sceneId: scene,
          );
        } else if (correcting) {
          final row = expected.value!;
          await service.correctCurrentFields(
            id: row.id,
            expected: row,
            relationType:
                value(RelationFormField.relationType) == row.relationType
                ? null
                : value(RelationFormField.relationType),
            status: value(RelationFormField.status) == row.status
                ? null
                : value(RelationFormField.status),
            proof: value(RelationFormField.proof) == row.proof
                ? null
                : value(RelationFormField.proof),
            chapterId: chapter == row.chapterId
                ? const Value.absent()
                : Value(chapter),
            sceneId: scene == row.sceneId ? const Value.absent() : Value(scene),
          );
        } else {
          await service.recordChange(
            id: original!.id,
            expected: expected.value,
            relationType: value(RelationFormField.relationType),
            status: value(RelationFormField.status),
            proof: value(RelationFormField.proof),
            reason: value(RelationFormField.reason),
            chapterId: chapter,
            sceneId: scene,
          );
        }
        if (context.mounted) {
          onSaved?.call();
        }
      } catch (error) {
        if (context.mounted) {
          failure.value = relationErrorLabel(context, error);
          conflict.value = relationErrorCode(error) == 'relation_changed';
        }
      } finally {
        if (context.mounted) {
          busy.value = false;
        }
      }
    }

    final typeField = HookedFormField<RelationFormField, String>(
      key: const ValueKey('relation-type'),
      fieldHook: RelationFormField.relationType,
      notifyOnChange: true,
      builder: (selected, onChanged, _) => RevericSelect<String>(
        height: selectHeight,
        value: allowed.contains(selected) ? selected : null,
        label: context.t(LocaleKeys.relationType),
        placeholder: allowed.isEmpty
            ? context.t(LocaleKeys.relationDialogHintNoSupportedTypes)
            : null,
        items: [
          for (final type in allowed)
            RevericSelectItem(
              value: type,
              label: relationLabel(context, type, source, target),
              color: relationCategoryColor(
                relationCategory(type, sourceType: source, targetType: target),
              ),
            ),
        ],
        enabled:
            !busy.value &&
            request.intent != RelationFormIntent.end &&
            request.intent != RelationFormIntent.restore,
        onChanged: (value) => onChanged?.call(value),
      ),
    );

    final statusField = HookedFormField<RelationFormField, String>(
      key: const ValueKey('relation-status'),
      fieldHook: RelationFormField.status,
      builder: (selected, onChanged, _) => RevericSelect<String>(
        height: selectHeight,
        value: selected,
        label: context.t(LocaleKeys.relationStatus),
        items: [
          for (final status in ['active', 'ended'])
            RevericSelectItem(
              value: status,
              label: relationStatusLabel(context, status),
              color: status == 'active' ? colors.accent : colors.textMuted,
            ),
        ],
        enabled:
            !busy.value &&
            request.intent != RelationFormIntent.end &&
            request.intent != RelationFormIntent.restore,
        onChanged: (value) => onChanged?.call(value),
      ),
    );

    return HookedForm<RelationFormField>(
      form: form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: SingleChildScrollView(
              key: const PageStorageKey('relation-form-scroll'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (creating) ...[
                    _EndpointFields(databasePath: databasePath, source: true),
                    const SizedBox(height: RevericSpacing.lg),
                    _EndpointFields(databasePath: databasePath, source: false),
                  ] else ...[
                    _FixedEndpoints(
                      databasePath: databasePath,
                      relation: original!,
                    ),
                    const SizedBox(height: RevericSpacing.xs),
                    Text(
                      context.t(switch (request.intent) {
                        RelationFormIntent.correct =>
                          LocaleKeys.relationCorrectHint,
                        RelationFormIntent.end => LocaleKeys.relationEndHint,
                        RelationFormIntent.restore =>
                          LocaleKeys.relationRestoreHint,
                        _ => LocaleKeys.relationChangeHint,
                      }),
                      style: typo.uiSmall.copyWith(color: colors.textMuted),
                    ),
                  ],
                  const SizedBox(height: RevericSpacing.x2l),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final horizontal =
                          constraints.maxWidth >=
                          MediaQuery.textScalerOf(context).scale(
                            RevericSizes.dialogWidth - RevericSpacing.x4l * 2,
                          );
                      return Flex(
                        direction: horizontal ? Axis.horizontal : Axis.vertical,
                        crossAxisAlignment: horizontal
                            ? CrossAxisAlignment.start
                            : CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (horizontal)
                            Expanded(flex: 2, child: typeField)
                          else
                            typeField,
                          SizedBox(
                            width: horizontal ? RevericSpacing.lg : 0,
                            height: horizontal ? 0 : RevericSpacing.lg,
                          ),
                          if (horizontal)
                            Expanded(child: statusField)
                          else
                            statusField,
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: RevericSpacing.lg),
                  if (!creating && !correcting) ...[
                    HookedTextFormField<RelationFormField>(
                      fieldHook: RelationFormField.reason,
                      fieldKey: const ValueKey('relation-reason'),
                      label: context.t(LocaleKeys.relationReason),
                      hintText: context.t(LocaleKeys.relationReasonHint),
                      enabled: !busy.value,
                    ),
                    const SizedBox(height: RevericSpacing.lg),
                  ],
                  Row(
                    children: [
                      Text(
                        context.t(LocaleKeys.relationFormProof),
                        style: typo.uiSmallSemibold.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                      const SizedBox(width: RevericSpacing.lg),
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: choices.when(
                            loading: () => const SizedBox.shrink(),
                            error: (_, _) => Text(
                              context.t(LocaleKeys.relationSaveFailed),
                              style: typo.uiTiny.copyWith(
                                color: colors.warningText,
                              ),
                            ),
                            data: (options) => _EvidenceSelect(
                              options: options,
                              enabled: !busy.value,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: RevericSpacing.xs),
                  HookedTextFormField<RelationFormField>(
                    fieldHook: RelationFormField.proof,
                    fieldKey: const ValueKey('relation-proof'),
                    hintText: context.t(LocaleKeys.relationProofHint),
                    multiline: true,
                    minLines: 3,
                    maxLines: 6,
                    enabled: !busy.value,
                  ),
                  if (failure.value != null)
                    Padding(
                      padding: const EdgeInsets.only(top: RevericSpacing.lg),
                      child: Text(
                        failure.value!,
                        key: const ValueKey('relation-form-error'),
                        style: typo.uiSmall.copyWith(color: colors.warningText),
                      ),
                    ),
                  if (conflict.value)
                    RevericButton.text(
                      label: context.t(LocaleKeys.relationRefreshCurrent),
                      onPressed: () async {
                        final latest = await service.getRelationById(
                          original!.id,
                        );
                        if (!context.mounted) {
                          return;
                        }
                        if (latest == null) {
                          failure.value = context.t(
                            LocaleKeys.relationNotFound,
                          );
                          return;
                        }
                        expected.value = latest;
                        conflict.value = false;
                        failure.value =
                            '${relationLabel(context, latest.relationType, latest.sourceType, latest.targetType)} · ${relationStatusLabel(context, latest.status)}\n${latest.proof}';
                      },
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: RevericSpacing.x2l),
          Wrap(
            spacing: RevericSpacing.sm,
            runSpacing: RevericSpacing.sm,
            alignment: WrapAlignment.end,
            children: [
              RevericButton.secondary(
                label: context.t(LocaleKeys.commonCancel),
                onPressed: busy.value
                    ? null
                    : () => Navigator.of(context).pop(),
              ),
              RevericButton.primary(
                key: const ValueKey('relation-save'),
                label: correcting
                    ? context.t(LocaleKeys.commonSave)
                    : relationFormTitle(context, request.intent),
                loading: busy.value,
                onPressed: busy.value || conflict.value || allowed.isEmpty
                    ? null
                    : submit,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

double _selectHeight(BuildContext context) => switch (Theme.of(
  context,
).platform) {
  TargetPlatform.android || TargetPlatform.iOS => RevericSizes.touchTargetSize,
  _ => RevericSizes.fieldHeight,
};

class _EvidenceSelect extends StatelessWidget {
  const _EvidenceSelect({required this.options, required this.enabled});
  final List<RelationEvidenceChoice> options;
  final bool enabled;
  @override
  Widget build(BuildContext context) {
    // 证据位置是依据的附属信息，放在依据标签行尾，宽度随选中项收缩。
    return IntrinsicWidth(
      child: HookedFormField<RelationFormField, String>(
        key: const ValueKey('relation-evidence'),
        fieldHook: RelationFormField.evidence,
        builder: (selected, onChanged, _) => RevericSelect<String>(
          compact: true,
          height: 20,
          menuWidth: 240,
          value: selected,
          items: [
            RevericSelectItem(
              value: '',
              label: context.t(LocaleKeys.relationSettingEvidence),
            ),
            if (selected != null &&
                selected.isNotEmpty &&
                !options.any((o) => o.key == selected))
              RevericSelectItem(
                value: selected,
                label: context.t(LocaleKeys.relationEvidenceDeleted),
              ),
            for (final option in options)
              RevericSelectItem(
                value: option.key,
                label: evidenceChoiceLabel(context, option),
              ),
          ],
          enabled: enabled,
          onChanged: (value) => onChanged?.call(value),
        ),
      ),
    );
  }
}

void _syncRelationType(FormFieldsController<RelationFormField> form) {
  final types = validRelationTypesFor(
    form.getValue<String>(RelationFormField.sourceType)!,
    form.getValue<String>(RelationFormField.targetType)!,
  );
  final current = form.getValue<String>(RelationFormField.relationType);
  form.updateValue(
    RelationFormField.relationType,
    types.contains(current) ? current! : types.firstOrNull ?? '',
    notify: true,
  );
}

class _EndpointFields extends HookWidget {
  const _EndpointFields({required this.databasePath, required this.source});
  final String databasePath;
  final bool source;
  @override
  Widget build(BuildContext context) {
    final form = useFormContext<RelationFormField>(context);
    final typo = RevericTheme.typographyOf(context);
    final colors = RevericTheme.colorsOf(context);
    final selectHeight = _selectHeight(context);
    final typeField = source
        ? RelationFormField.sourceType
        : RelationFormField.targetType;
    final idField = source
        ? RelationFormField.sourceId
        : RelationFormField.targetId;

    void swap() {
      final sourceType = form.getValue<String>(RelationFormField.sourceType);
      final sourceId = form.getValue<String>(RelationFormField.sourceId);
      form.updateValue(
        RelationFormField.sourceType,
        form.getValue<String>(RelationFormField.targetType),
        notify: true,
      );
      form.updateValue(
        RelationFormField.sourceId,
        form.getValue<String>(RelationFormField.targetId),
        notify: true,
      );
      form.updateValue(RelationFormField.targetType, sourceType, notify: true);
      form.updateValue(RelationFormField.targetId, sourceId, notify: true);
      _syncRelationType(form);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                context.t(
                  source
                      ? LocaleKeys.relationSource
                      : LocaleKeys.relationTarget,
                ),
                style: typo.uiSmallSemibold.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ),
            if (!source)
              Tooltip(
                message: context.t(LocaleKeys.relationSwapEndpoints),
                child: InkWell(
                  key: const ValueKey('relation-swap-endpoints'),
                  borderRadius: BorderRadius.circular(RevericRadius.small),
                  onTap: swap,
                  child: Padding(
                    padding: const EdgeInsets.all(RevericSpacing.xxs),
                    child: RevericIcon(
                      RevericIcons.swap_horiz_rounded,
                      size: 14,
                      color: colors.textMuted,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: RevericSpacing.xs),
        HookedFormField<RelationFormField, String>(
          fieldHook: idField,
          notifyOnChange: true,
          builder: (id, onChanged, error) {
            final type = form.getValue<String>(typeField) ?? 'character';
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 112,
                      child: HookedFormField<RelationFormField, String>(
                        key: ValueKey(
                          source
                              ? 'relation-source-type'
                              : 'relation-target-type',
                        ),
                        fieldHook: typeField,
                        notifyOnChange: true,
                        builder: (type, onTypeChanged, _) =>
                            RevericSelect<String>(
                              height: selectHeight,
                              menuWidth: 160,
                              value: type,
                              items: [
                                for (final t in [
                                  'character',
                                  'faction',
                                  'skill',
                                  'item',
                                  'creature',
                                ])
                                  RevericSelectItem(
                                    value: t,
                                    label: localizeEntityNodeTypeName(
                                      context,
                                      t,
                                    ),
                                  ),
                              ],
                              onChanged: (value) {
                                onTypeChanged?.call(value);
                                form.updateValue(idField, '', notify: true);
                                _syncRelationType(form);
                              },
                            ),
                      ),
                    ),
                    const SizedBox(width: RevericSpacing.sm),
                    Expanded(
                      // 选择器只在 selectedId 非空时回填名字；类型切换或交换端点后
                      // 需要按新的 type/id 重建，否则输入框会残留上一个实体的名字。
                      child: EntitySearchSelector(
                        key: ValueKey('$type:$id'),
                        databasePath: databasePath,
                        entityType: type,
                        selectedId: id ?? '',
                        height: selectHeight,
                        onChanged: (id, _) => onChanged?.call(id),
                      ),
                    ),
                  ],
                ),
                if (error != null)
                  Text(
                    error,
                    style: typo.uiSmall.copyWith(color: colors.warningText),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _FixedEndpoints extends ConsumerWidget {
  const _FixedEndpoints({required this.databasePath, required this.relation});
  final String databasePath;
  final EntityRelation relation;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    String name(String type, String id) =>
        ref
            .watch(
              entityGraphNodeDetailProvider(
                databasePath: databasePath,
                entityType: type,
                entityId: id,
              ),
            )
            .value
            ?.title ??
        context.t(LocaleKeys.commonUntitled);
    return Text(
      '${name(relation.sourceType, relation.sourceId)} ${isRelationDirected(relation.relationType) ? '→' : '↔'} ${name(relation.targetType, relation.targetId)}',
      style: RevericTheme.typographyOf(context).uiSemibold,
    );
  }
}
