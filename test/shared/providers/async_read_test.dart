// 职责: 验证异步读取在无页面监听时持续存活，并在成功或失败后释放订阅。
// 关联文件:
//   lib/shared/providers/async_read.dart
// 遵循的 Rules:
//   .agents/rules/testing.md

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/providers/async_read.dart';

class _Resource {
  bool closed = false;
}

void main() {
  testWidgets('a widget read finishes after the initiating widget is removed', (
    tester,
  ) async {
    final values = StreamController<int>.broadcast();
    var disposed = false;
    final stream = StreamProvider.autoDispose<int>((ref) {
      ref.onDispose(() => disposed = true);
      return values.stream;
    });
    final container = ProviderContainer();
    addTearDown(() async {
      container.dispose();
      await values.close();
    });
    late Future<Object> result;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: Consumer(
          builder: (context, ref, _) {
            result = ref
                .readFuture(stream.future)
                .then<Object>(
                  (value) => value,
                  onError: (Object error) => error,
                );
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const SizedBox.shrink(),
      ),
    );
    await tester.pump();
    values.add(42);
    await tester.pump();
    expect(await result, 42);
    await tester.pump();
    expect(disposed, isTrue);
  });
  for (final fails in [false, true]) {
    test(
      'retains a resource for the entire operation (fails=$fails)',
      () async {
        final gate = Completer<void>();
        final resource = _Resource();
        final provider = Provider.autoDispose<_Resource>((ref) {
          ref.onDispose(() => resource.closed = true);
          return resource;
        });
        final container = ProviderContainer();
        addTearDown(container.dispose);
        final error = StateError('operation failed');
        final result = container
            .withProvider(provider, (value) async {
              await gate.future;
              if (value.closed) {
                throw StateError('resource was closed during operation');
              }
              if (fails) {
                throw error;
              }
              return 'done';
            })
            .then<Object>((value) => value, onError: (Object error) => error);
        await pumpEventQueue();
        gate.complete();

        expect(await result, fails ? same(error) : 'done');
        await pumpEventQueue();
        expect(resource.closed, isTrue);
      },
    );
  }
  for (final fails in [false, true]) {
    test(
      'retains an unobserved future until it settles (fails=$fails)',
      () async {
        final gate = Completer<String>();
        var disposed = false;
        final provider = FutureProvider.autoDispose<String>((ref) {
          ref.onDispose(() => disposed = true);
          return gate.future;
        });
        final container = ProviderContainer();
        addTearDown(container.dispose);
        final result = container
            .readFuture(provider.future)
            .then<Object>((value) => value, onError: (Object error) => error);
        await pumpEventQueue();
        final disposedDuringRead = disposed;
        final error = StateError('request failed');
        if (fails) {
          gate.completeError(error);
        } else {
          gate.complete('value');
        }
        expect(await result, fails ? same(error) : 'value');
        expect(disposedDuringRead, isFalse);
        await pumpEventQueue();
        expect(disposed, isTrue);
      },
    );
  }

  test('a provider command can read a disposable stream through Ref', () async {
    final gate = StreamController<int>();
    var disposed = false;
    final stream = StreamProvider.autoDispose<int>((ref) {
      ref.onDispose(() => disposed = true);
      return gate.stream;
    });
    final command = Provider(
      (ref) =>
          () => ref.readFuture(stream.future),
    );
    final container = ProviderContainer();
    addTearDown(() async {
      container.dispose();
      await gate.close();
    });

    final result = container
        .read(command)()
        .then<Object>((value) => value, onError: (Object error) => error);
    await pumpEventQueue();
    gate.add(42);
    expect(await result, 42);
    await pumpEventQueue();
    expect(disposed, isTrue);
  });
}
