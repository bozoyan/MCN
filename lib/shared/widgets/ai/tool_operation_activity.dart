// 职责: 在原工具组下展示待批准的审批卡与已处理运行的一行回执。
// 关联文件:
//   lib/shared/widgets/ai/chat/chat_message_view.dart
//   lib/shared/widgets/ai/tool_approval_card.dart
//   lib/shared/providers/tool_permissions.dart
//   lib/shared/services/ai/tool_operations.dart
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../models/ai_message_block.dart';
import '../../providers/tool_operations.dart';
import '../../providers/tool_permissions.dart';
import '../../services/ai/tool_operations.dart';
import '../../theme/theme.dart';
import 'tool_approval_card.dart';

/// 图片生成卡替换了原工具卡，按 `img_<callId>` 找回调用身份。
const _imageBlockPrefix = 'img_';

class ToolOperationActivity extends ConsumerWidget {
  const ToolOperationActivity({
    super.key,
    required this.sessionId,
    required this.blocks,
  });
  final String sessionId;
  final List<AiMessageBlock> blocks;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ids = {
      for (final block in blocks)
        if (block is AiToolCallBlock)
          block.callId
        else if (block is AiImageBlock &&
            block.id.startsWith(_imageBlockPrefix))
          block.id.substring(_imageBlockPrefix.length),
    };
    final registry = ref.watch(toolOperationRegistryProvider);
    final pending =
        (ref.watch(pendingToolApprovalsProvider(sessionId)).value ?? const [])
            .where(
              (request) =>
                  ids.contains(request.displayCallId ?? request.callId),
            )
            .toList();
    return StreamBuilder<ToolOperationRecord>(
      stream: registry.changes.where(
        (record) =>
            record.ownerSessionId == sessionId &&
            ids.contains(record.displayCallId ?? record.callId),
      ),
      builder: (context, _) {
        final records = <String, ToolOperationRecord>{};
        for (final block in blocks.whereType<AiToolCallBlock>()) {
          for (final snapshot
              in block.metadata?['operations'] as List? ?? const []) {
            final record = ToolOperationRecord.fromJson(
              Map<String, dynamic>.from(snapshot as Map),
            );
            records[record.runId] = record;
          }
        }
        for (final record in registry.records.values) {
          if (record.ownerSessionId == sessionId &&
              ids.contains(record.displayCallId ?? record.callId)) {
            records[record.runId] = record;
          }
        }
        final waiting = {for (final request in pending) request.approvalId};
        // 待批准的运行由审批卡代表；只有真正弹过审批的运行才出回执。
        final receipts = [
          for (final record in records.values)
            if (record.approvalRequested && !waiting.contains(record.runId))
              _receipt(context, record),
        ];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (receipts.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: RevericSpacing.sm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: receipts,
                ),
              ),
            for (final request in pending)
              ToolApprovalCard(key: ValueKey(request), request: request),
          ],
        );
      },
    );
  }

  Widget _receipt(BuildContext context, ToolOperationRecord record) {
    final view = describeToolOperation(context, (
      capability: record.capability,
      kind: record.kind,
      target: record.targetLabel ?? record.targetPath,
      status: record.status.name,
      result: record.result,
    ));
    return ToolOperationReceipt(
      key: ValueKey(record.runId),
      capability: record.capability,
      title: view.title,
      target: view.target,
      state: view.state,
      stateIcon: view.icon,
      stateColor: view.color,
    );
  }
}
