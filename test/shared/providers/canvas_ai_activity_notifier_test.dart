// 职责: 画布 AI 活动广播测试 — 守住「同一帧连报多条全部送达节拍器、背压 Future 透传、只摘自己挂的节拍器」
// 关联文件:
//   lib/shared/providers/canvas_providers.dart
//   lib/shared/models/canvas_ai_activity.dart

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/models/canvas_ai_activity.dart';
import 'package:reveric/shared/providers/canvas_providers.dart';

CanvasAiActivity _addNode(String canvasId, String nodeId) {
  return CanvasAiActivity(
    canvasId: canvasId,
    kind: CanvasAiActivityKind.add_node,
    focusNodeIds: [nodeId],
  );
}

void main() {
  late ProviderContainer container;
  late CanvasAiActivityNotifier notifier;

  setUp(() {
    container = ProviderContainer();
    notifier = container.read(canvasAiActivityProvider.notifier);
  });

  tearDown(() => container.dispose());

  test('同一帧连报多条全部送达节拍器，不会只剩最后一条', () {
    final received = <String>[];
    notifier.attachPacer('c1', (activity) {
      received.add(activity.focusNodeIds.single);
      return Future<void>.value();
    });

    // 批量处理同步连报：watch state 只看得到最后一条，节拍器必须每条都收到。
    for (final id in ['n0', 'n1', 'n2']) {
      unawaited(notifier.report(_addNode('c1', id)));
    }

    expect(received, ['n0', 'n1', 'n2']);
    expect(container.read(canvasAiActivityProvider)?.focusNodeIds, ['n2']);
  });

  test('report 透传节拍器的 Future；别的画布或没挂节拍器时立即完成', () async {
    final step = Completer<void>();
    notifier.attachPacer('c1', (_) => step.future);

    var released = false;
    unawaited(
      notifier.report(_addNode('c1', 'n0')).then((_) => released = true),
    );
    await notifier.report(_addNode('c2', 'n0'));
    await Future<void>.delayed(Duration.zero);
    expect(released, isFalse);

    step.complete();
    await Future<void>.delayed(Duration.zero);
    expect(released, isTrue);
  });

  test('只摘自己挂的节拍器：新页面先挂、旧页面后卸不会误摘', () {
    final received = <String>[];
    Future<void> oldPacer(CanvasAiActivity _) {
      received.add('old');
      return Future<void>.value();
    }

    Future<void> newPacer(CanvasAiActivity _) {
      received.add('new');
      return Future<void>.value();
    }

    notifier.attachPacer('c1', oldPacer);
    notifier.attachPacer('c1', newPacer);
    notifier.detachPacer('c1', oldPacer);

    unawaited(notifier.report(_addNode('c1', 'n0')));
    expect(received, ['new']);
  });
}
